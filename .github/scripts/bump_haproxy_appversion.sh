#!/bin/bash
#
# Bump haproxy/Chart.yaml to the newest haproxy-alpine release and push it to
# main. Run from the repository root with a checkout of main.
#
# Environment:
#   CHART     path to the chart's Chart.yaml
#   IMAGE     Docker Hub repository to watch
#   GH_TOKEN  token used to dispatch the release workflow

set -o errexit
set -o nounset
set -o pipefail

readonly CHART="${CHART:?CHART is required}"
readonly IMAGE="${IMAGE:?IMAGE is required}"

# Push to main, rebasing onto whatever landed meanwhile. Two workflows push
# here and they are not serialised, so a rejected push is expected rather than
# exceptional.
push_to_main() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if git push origin HEAD:main; then
            return 0
        fi
        echo "push rejected (attempt ${attempt}), rebasing onto origin/main"
        # A transient failure here must cost one attempt, not the whole run.
        git fetch origin main || { sleep 5; continue; }
        if ! git rebase origin/main; then
            git rebase --abort || true
            echo "rebase onto origin/main conflicted, leaving main untouched"
            return 1
        fi
        sleep 5
    done
    echo "could not push to main after 5 attempts"
    return 1
}

main() {
    local cur ver latest new v

    cur=$(awk '/^appVersion:/ {print $2; exit}' "${CHART}")
    ver=$(awk '/^version:/ {print $2; exit}' "${CHART}")

    # Only plain X.Y.Z release tags: skips -dev, -rc, s6-* and friends. A
    # Docker Hub hiccup or an empty match must leave ${latest} empty for the
    # guard below rather than abort through pipefail.
    latest=$(curl -fsSL "https://hub.docker.com/v2/repositories/${IMAGE}/tags?page_size=100&ordering=last_updated" \
        | jq -r '.results[].name' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -1) || true

    # Both reach arithmetic expansion below, which evaluates its operand as a
    # bash expression, so never use them unvalidated.
    for v in "${cur}" "${ver}"; do
        [[ ${v} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "malformed version in ${CHART}: ${v}"; return 1; }
    done

    echo "current appVersion: ${cur}, latest release tag: ${latest}"
    if [[ -z "${latest}" ]] || [[ "${latest}" == "${cur}" ]] ||
        [[ "$(printf '%s\n%s\n' "${cur}" "${latest}" | sort -V | tail -1)" != "${latest}" ]]; then
        echo "nothing to do"
        return 0
    fi

    local cmaj cmin lmaj lmin vmaj vmin vpat
    IFS=. read -r cmaj cmin _ <<<"${cur}"
    IFS=. read -r lmaj lmin _ <<<"${latest}"
    IFS=. read -r vmaj vmin vpat <<<"${ver}"
    if [[ "${lmaj}" != "${cmaj}" ]]; then
        new="$((vmaj + 1)).0.0"
    elif [[ "${lmin}" != "${cmin}" ]]; then
        new="${vmaj}.$((vmin + 1)).0"
    else
        new="${vmaj}.${vmin}.$((vpat + 1))"
    fi
    echo "chart version: ${ver} -> ${new}"

    sed -i \
        -e "s|^version: .*|version: ${new}|" \
        -e "s|^appVersion: .*|appVersion: ${latest}|" \
        -e "s|\(${IMAGE}\):.*|\1:${latest}|" \
        "${CHART}"

    # Replace the artifacthub changes list with this single change. Both | and
    # |- block scalars are in use across the charts.
    awk -v v="${latest}" '
        /^  artifacthub.io\/changes: \|-?$/ { print; print "    - Update base image to HAProxy " v; drop = 1; next }
        drop && /^    - / { next }
        { drop = 0; print }
    ' "${CHART}" >"${CHART}.new" && mv "${CHART}.new" "${CHART}"

    # Nothing else validates this push: GITHUB_TOKEN commits do not trigger
    # ci.yml, so lint the chart here instead.
    helm lint "$(dirname "${CHART}")/"

    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git commit -s -a -m "MINOR: haproxy: update appVersion to ${latest}"
    push_to_main

    # A GITHUB_TOKEN push starts no workflow, so ci.yml's release-charts job
    # never runs. workflow_dispatch is exempt from that recursion guard.
    gh workflow run release.yml --ref main
}

main
