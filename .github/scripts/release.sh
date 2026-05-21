#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

: "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"
: "${GIT_REPOSITORY_URL:?Environment variable GIT_REPOSITORY_URL must be set}"
: "${GIT_USERNAME:?Environment variable GIT_USERNAME must be set}"
: "${GIT_EMAIL:?Environment variable GIT_EMAIL must be set}"
: "${HELM_GH_TOKEN:?Environment variable HELM_GH_TOKEN must be set}"

readonly OWNER=haproxytech
readonly GIT_REPO=helm-charts
readonly PACKAGE_PATH=.deploy
readonly CHARTS_URL=https://haproxytech.github.io/helm-charts
readonly REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"

package_chart() {
    local chart="$1"
    helm dependency build "${chart}"
    helm package "${chart}" --destination "${PACKAGE_PATH}"
}

release_charts() {
    echo "Upload Helm chart packages to GitHub"
    # --skip-existing makes the batch idempotent: a chart whose tag already
    # has a GitHub release (re-package without version bump) no longer aborts
    # the upload of unrelated charts queued behind it.
    cr upload -o "${OWNER}" -r "${GIT_REPO}" -p "${PACKAGE_PATH}" --skip-existing

    echo "Upload Helm chart packages to GHCR OCI"
    printf '%s' "${HELM_GH_TOKEN}" | helm registry login ghcr.io --username "${OWNER}" --password-stdin

    shopt -s nullglob
    local tarballs=("${PACKAGE_PATH}"/*.tgz)
    shopt -u nullglob

    for chart in "${tarballs[@]}"; do
        helm push "${chart}" "oci://ghcr.io/${OWNER}/${GIT_REPO}"
    done
}

update_index() {
    echo "Generating Helm chart index"
    git config user.email "${GIT_EMAIL}"
    git config user.name "${GIT_USERNAME}"

    local original_ref
    original_ref=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse HEAD)
    # shellcheck disable=SC2064 # expand original_ref now, not at trap-fire time
    trap "git checkout '${original_ref}' >/dev/null 2>&1 || true" RETURN
    git checkout gh-pages

    cr index -i index.yaml -o "${OWNER}" -r "${GIT_REPO}" -c "${CHARTS_URL}" -p "${PACKAGE_PATH}"

    git add index.yaml
    if git diff --quiet --cached; then
        echo "No index.yaml changes to publish."
        return
    fi
    git commit --message="Update index.yaml" --signoff
    git push "${GIT_REPOSITORY_URL}" gh-pages
}

main() {
    pushd "${REPO_ROOT}" >/dev/null || exit 1

    echo "Fetching tags"
    git fetch --tags

    mkdir -p "${PACKAGE_PATH}"

    # Detect releasable charts by comparing each chart's `version:` field
    # against the existence of a `<chart>-<version>` tag. Diffing Chart.yaml
    # against the most recent tag in DAG (any chart) over-triggers: cosmetic
    # edits (e.g. removing `engine: gotpl`) without a version bump still
    # appear in the diff, then cr upload fails with 422 already_exists.
    local chart_yaml chart current_version tag release_pending=no
    shopt -s nullglob
    for chart_yaml in */Chart.yaml; do
        chart="${chart_yaml%/Chart.yaml}"
        current_version=$(awk '$1=="version:"{print $2; exit}' "${chart_yaml}")
        if [[ -z "${current_version}" ]]; then
            echo "Skipping ${chart}: could not read version from Chart.yaml"
            continue
        fi
        tag="${chart}-${current_version}"
        if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
            echo "Skipping ${chart}: tag ${tag} already exists"
            continue
        fi
        release_pending=yes
        echo "Packaging chart ${chart} (version ${current_version})"
        package_chart "${chart}"
    done
    shopt -u nullglob

    if [[ "${release_pending}" == "yes" ]]; then
        release_charts
        update_index
    else
        echo "Nothing to do. No chart version bumps detected."
    fi

    popd >/dev/null || exit 1
}

main
