#!/bin/bash
#
# Merge a bot appVersion pull request and push the matching chart version
# bump to main. Run from the repository root with a checkout of main, never
# of the pull request head.
#
# Environment:
#   REPO      owner/name of this repository
#   SHA       head commit of the workflow run that just passed CI
#   BOT       login the pull request must be authored by
#   CHARTS    alternation of chart directories this may act on
#   GH_TOKEN  token used for the GitHub API and the release dispatch

set -o errexit
set -o nounset
set -o pipefail

readonly REPO="${REPO:?REPO is required}"
readonly SHA="${SHA:?SHA is required}"
readonly BOT="${BOT:?BOT is required}"
readonly CHARTS="${CHARTS:?CHARTS is required}"

# Read a field out of a Chart.yaml as it exists on origin/main right now.
main_chart_field() {
    local chart="$1" field="$2"
    git show "origin/main:${chart}/Chart.yaml" | awk -v f="^${field}:" '$0 ~ f {print $2; exit}'
}

# The merge API returning does not mean the ref is visible yet, so poll for it
# instead of failing on propagation lag.
wait_for_merge() {
    local chart="$1" want="$2" attempt landed
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        git fetch origin main
        landed=$(main_chart_field "${chart}" appVersion)
        if [[ "${landed}" == "${want}" ]]; then
            return 0
        fi
        echo "waiting for the merge to appear on main (attempt ${attempt}, saw ${landed})"
        sleep 5
    done
    return 1
}

# Push to main, rebasing onto whatever landed meanwhile. Jobs for different
# pull requests are not serialised with each other, so a rejected push is
# expected rather than exceptional.
push_to_main() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if git push origin HEAD:main; then
            return 0
        fi
        echo "push rejected (attempt ${attempt}), rebasing onto origin/main"
        git fetch origin main
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
    local pr author head files chart new old ver v

    pr=$(gh api "repos/${REPO}/commits/${SHA}/pulls" \
        --jq '[.[] | select(.state == "open" and .base.ref == "main")][0].number // empty')
    [[ -n "${pr}" ]] || { echo "no open pull request for ${SHA}"; return 0; }

    author=$(gh pr view "${pr}" --repo "${REPO}" --json author --jq '.author.login')
    head=$(gh pr view "${pr}" --repo "${REPO}" --json headRefOid --jq '.headRefOid')
    [[ "${author}" == "${BOT}" ]] || { echo "pull request #${pr} is from ${author}, not ${BOT}"; return 0; }
    [[ "${head}" == "${SHA}" ]] || { echo "pull request #${pr} moved past the tested commit"; return 0; }

    # Must touch exactly one supported Chart.yaml and nothing else, so this
    # never auto-merges template or script changes.
    files=$(gh pr diff "${pr}" --repo "${REPO}" --name-only)
    chart=$(printf '%s\n' "${files}" | sed -nE "s%^(${CHARTS})/Chart.yaml\$%\1%p")
    if [[ "$(printf '%s\n' "${files}" | wc -l)" -ne 1 ]] || [[ -z "${chart}" ]]; then
        echo "pull request #${pr} does not change exactly one supported Chart.yaml:"
        printf '%s\n' "${files}"
        return 0
    fi

    new=$(gh api "repos/${REPO}/contents/${chart}/Chart.yaml?ref=${SHA}" \
        -H "Accept: application/vnd.github.raw" \
        | awk '/^appVersion:/ {print $2; exit}')

    # Read the current appVersion from origin/main rather than from the
    # checkout this job started with: the bot opens duplicate pull requests
    # for the same appVersion, and a stale value here would merge one of them
    # as an empty commit and publish a chart release that differs from its
    # predecessor only in the version string.
    git fetch origin main
    old=$(main_chart_field "${chart}" appVersion)

    # ${new} comes from a fork and both reach arithmetic expansion below.
    for v in "${old}" "${new}"; do
        [[ ${v} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "malformed version: ${v}"; return 1; }
    done

    echo "pull request #${pr}: ${chart} appVersion ${old} -> ${new}"
    if [[ "${new}" == "${old}" ]] ||
        [[ "$(printf '%s\n%s\n' "${old}" "${new}" | sort -V | tail -1)" != "${new}" ]]; then
        echo "main already carries ${old}, leaving pull request #${pr} alone"
        return 0
    fi

    gh pr merge "${pr}" --repo "${REPO}" --squash --match-head-commit "${SHA}" \
        --subject "MINOR: ${chart}: update appVersion to ${new} (#${pr})"

    wait_for_merge "${chart}" "${new}" || { echo "merge of #${pr} did not appear on main"; return 1; }
    git checkout -B main origin/main

    ver=$(main_chart_field "${chart}" version)
    [[ ${ver} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "malformed version: ${ver}"; return 1; }

    local omaj omin nmaj nmin vmaj vmin vpat bump sev
    IFS=. read -r omaj omin _ <<<"${old}"
    IFS=. read -r nmaj nmin _ <<<"${new}"
    IFS=. read -r vmaj vmin vpat <<<"${ver}"
    if [[ "${nmaj}" != "${omaj}" ]]; then
        bump="$((vmaj + 1)).0.0"
        sev=MAJOR
    elif [[ "${nmin}" != "${omin}" ]]; then
        bump="${vmaj}.$((vmin + 1)).0"
        sev=MAJOR
    else
        bump="${vmaj}.${vmin}.$((vpat + 1))"
        sev=MINOR
    fi
    echo "chart version: ${ver} -> ${bump} (RELEASE/${sev})"

    sed -i "s|^version: .*|version: ${bump}|" "${chart}/Chart.yaml"

    # A GITHUB_TOKEN push does not trigger ci.yml, so lint here instead.
    helm lint "${chart}/"

    # Reuse the chart's own changelog entries for the commit body, the way the
    # hand-written release commits do.
    local changes
    changes=$(awk '
        /^  artifacthub.io\/changes: \|-?$/ { f = 1; next }
        f && /^    - / { sub(/^    /, ""); print; next }
        f { exit }
    ' "${chart}/Chart.yaml")

    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    printf '%s\n\n%s\n%s\n' \
        "RELEASE/${sev}: ${chart}: Tag release ${bump}" \
        "Changes in ${chart}:" \
        "${changes}" \
        | git commit -s -a -F -
    push_to_main

    # A GITHUB_TOKEN push starts no workflow, so ci.yml's release-charts job
    # never runs. workflow_dispatch is exempt from that recursion guard.
    gh workflow run release.yml --ref main
}

main
