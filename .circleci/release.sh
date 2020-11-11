#!/bin/bash

set -o nounset

: "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"
: "${GIT_REPOSITORY_URL:?Environment variable GIT_REPOSITORY_URL must be set}"
: "${GIT_USERNAME:?Environment variable GIT_USERNAME must be set}"
: "${GIT_EMAIL:?Environment variable GIT_EMAIL must be set}"

readonly OWNER=haproxytech
readonly GIT_REPO=helm-charts
readonly PACKAGE_PATH=.deploy
readonly CHARTS_URL=https://haproxytech.github.io/helm-charts
readonly REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"

find_latest_tag() {
    if ! git describe --tags --abbrev=0 2>/dev/null; then
        git rev-list --max-parents=0 --first-parent HEAD
    fi
}

package_chart() {
    local chart="$1"
    helm dependency build "${chart}"
    helm package "${chart}" --destination "${PACKAGE_PATH}"
}

release_charts() {
    echo "Upload Helm chart packages"
    cr upload -o "${OWNER}" -r "${GIT_REPO}" -p "${PACKAGE_PATH}"
}

update_index() {
    echo "Generating Helm chart index"
    git config user.email "${GIT_EMAIL}"
    git config user.name "${GIT_USERNAME}"
    git checkout gh-pages

    cr index -i index.yaml -o "${OWNER}" -r "${GIT_REPO}" -c "${CHARTS_URL}" -p "${PACKAGE_PATH}"

    git add index.yaml
    git commit --message="Update index.yaml" --signoff
    git push "${GIT_REPOSITORY_URL}" gh-pages
}

main() {
    pushd "${REPO_ROOT}" >/dev/null || exit 1

    echo "Fetching tags"
    git fetch --tags

    local latest_tag
    latest_tag=$(find_latest_tag)

    local latest_tag_rev
    latest_tag_rev=$(git rev-parse --verify "${latest_tag}")
    echo "${latest_tag_rev} ${latest_tag} (latest tag)"

    local head_rev
    head_rev=$(git rev-parse --verify HEAD)
    echo "${head_rev} HEAD"

    if [[ "${latest_tag_rev}" == "${head_rev}" ]]; then
        echo "No code changes. Nothing to release."
        exit
    fi

    mkdir -p "${PACKAGE_PATH}"

    echo "Identifying changed charts since tag ${latest_tag}"

    local changed_charts=()
    readarray -t changed_charts <<< "$(git diff --find-renames --name-only "${latest_tag_rev}" | grep '\.yaml$' | cut -d '/' -f 1 | sort -u)"

    if [[ -n "${changed_charts[*]}" ]]; then
        local release_pending=no
        for chart in "${changed_charts[@]}"; do
            if [[ -f "${chart}/Chart.yaml" ]]; then
                release_pending=yes
                echo "Packaging chart ${chart}"
                package_chart "${chart}"
            fi
        done

        if [[ "${release_pending}" == "yes" ]]; then
            release_charts
            update_index
        else
            echo "Nothing to do. No chart changes detected."
        fi
    else
        echo "Nothing to do. No chart changes detected."
    fi

    popd >/dev/null || exit 1
}

main
