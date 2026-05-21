# CircleCI → GitHub Actions Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `.circleci/` pipeline with an equivalent GitHub Actions workflow that mirrors the existing four-job DAG, relocates helper scripts to `.github/scripts/`, and collapses three CircleCI credentials onto the built-in `GITHUB_TOKEN`.

**Architecture:** Verbatim port of `install_charts.sh` / `install_tools.sh` / `release.sh` (one path edit only). New single workflow file `.github/workflows/ci.yml` with jobs `lint-scripts`, `lint-charts`, `install-charts`, `release-charts` matching CircleCI's DAG. Single atomic commit — splitting move-from-add would leave CircleCI broken between commits (it references `.circleci/install_charts.sh` etc., which would no longer exist).

**Tech Stack:** GitHub Actions YAML, bash, shellcheck, helm, chart-testing (`ct`), kind, chart-releaser (`cr`).

**Spec:** [`docs/superpowers/specs/2026-05-21-circleci-to-gha-migration-design.md`](../specs/2026-05-21-circleci-to-gha-migration-design.md)

**Verification toolset (all already installed locally):** `shellcheck` (0.11.0), `bash -n` for syntax check, `python3 -c "import yaml; yaml.safe_load(...)"` for YAML well-formedness.

**Working assumptions (verified):**
- Only one `.circleci/` self-reference exists in any script: `install_charts.sh:21` (the `ct.yaml` volume mount).
- `shellcheck -x` on all three scripts currently exits 0 — this is the baseline the moved scripts must preserve.

---

## Task 1: Create `.github/scripts/` and move the four helper files

**Files:**
- Create directory: `.github/scripts/`
- Move (via `git mv` so rename history survives):
  - `.circleci/install_charts.sh` → `.github/scripts/install_charts.sh`
  - `.circleci/install_tools.sh`  → `.github/scripts/install_tools.sh`
  - `.circleci/release.sh`        → `.github/scripts/release.sh`
  - `.circleci/ct.yaml`           → `.github/scripts/ct.yaml`

- [ ] **Step 1: Create the destination directory**

Run:
```bash
mkdir -p .github/scripts
```

- [ ] **Step 2: Move the four files**

Run:
```bash
git mv .circleci/install_charts.sh .github/scripts/install_charts.sh
git mv .circleci/install_tools.sh  .github/scripts/install_tools.sh
git mv .circleci/release.sh        .github/scripts/release.sh
git mv .circleci/ct.yaml           .github/scripts/ct.yaml
```

- [ ] **Step 3: Verify the move with git status**

Run:
```bash
git status
```

Expected — all four entries shown as renames:
```
	renamed:    .circleci/ct.yaml -> .github/scripts/ct.yaml
	renamed:    .circleci/install_charts.sh -> .github/scripts/install_charts.sh
	renamed:    .circleci/install_tools.sh -> .github/scripts/install_tools.sh
	renamed:    .circleci/release.sh -> .github/scripts/release.sh
```

If any shows as a `deleted` + `new file` pair instead of `renamed`, git's rename heuristic failed; abort and investigate (something is wrong with the move).

---

## Task 2: Update the one `.circleci/` self-reference inside `install_charts.sh`

**Files:**
- Modify: `.github/scripts/install_charts.sh:21`

The script's `create_ct_container()` function mounts `ct.yaml` from a hard-coded `$(pwd)/.circleci/ct.yaml` host path. After the move, the host path is `$(pwd)/.github/scripts/ct.yaml`.

- [ ] **Step 1: Edit the volume mount line**

In `.github/scripts/install_charts.sh`, change line 21 from:
```bash
        --volume "$(pwd)/.circleci/ct.yaml:/etc/ct/ct.yaml" \
```
to:
```bash
        --volume "$(pwd)/.github/scripts/ct.yaml:/etc/ct/ct.yaml" \
```

- [ ] **Step 2: Verify no `.circleci/` references remain anywhere in `.github/scripts/`**

Run:
```bash
grep -rn "\.circleci" .github/scripts/
```

Expected: empty output (exit 1 from grep). If any line is printed, fix it before continuing.

- [ ] **Step 3: Verify shellcheck still passes on all moved scripts**

Run:
```bash
shellcheck -x .github/scripts/install_charts.sh .github/scripts/install_tools.sh .github/scripts/release.sh && echo "OK"
```

Expected: `OK`. Must match the pre-move baseline (exit 0, no warnings).

- [ ] **Step 4: Verify bash syntax**

Run:
```bash
bash -n .github/scripts/install_charts.sh && bash -n .github/scripts/install_tools.sh && bash -n .github/scripts/release.sh && echo "OK"
```

Expected: `OK`.

---

## Task 3: Create `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

This is the new pipeline. Four jobs mirroring CircleCI's DAG, one orchestrator-level concurrency guard on the release job.

- [ ] **Step 1: Create the workflow file**

Write the following to `.github/workflows/ci.yml` verbatim:

```yaml
name: lint-test-release

on:
  push:
    branches-ignore:
      - gh-pages
  pull_request:

permissions:
  contents: read

jobs:
  lint-scripts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Shellcheck
        run: |
          shellcheck -x .github/scripts/install_charts.sh
          shellcheck -x .github/scripts/install_tools.sh
          shellcheck -x .github/scripts/release.sh

  lint-charts:
    runs-on: ubuntu-latest
    container:
      image: quay.io/helmpack/chart-testing:latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Mark workspace safe for git
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - name: ct lint
        run: ct lint --all --validate-maintainers=false --config .github/scripts/ct.yaml

  install-charts:
    needs: lint-charts
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install charts
        run: bash .github/scripts/install_charts.sh

  release-charts:
    needs:
      - lint-charts
      - install-charts
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    concurrency:
      group: release-${{ github.ref }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install tools (helm, cr)
        run: bash .github/scripts/install_tools.sh
      - name: Release
        env:
          CR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          HELM_GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_REPOSITORY_URL: https://x-access-token:${{ secrets.GITHUB_TOKEN }}@github.com/${{ github.repository }}.git
          GIT_USERNAME: github-actions[bot]
          GIT_EMAIL: 41898282+github-actions[bot]@users.noreply.github.com
        run: bash .github/scripts/release.sh
```

**Why each detail is there** (reference for the engineer; do not change without re-reading the spec):
- `branches-ignore: [gh-pages]` + no `tags` key → workflow runs on every branch push except `gh-pages`, and tag pushes do not trigger it (matches CircleCI's `tags: ignore: /.*/` on release-charts).
- `permissions: contents: read` at workflow level + per-job override → least-privilege. Only `release-charts` elevates.
- `fetch-depth: 0` everywhere that runs a script doing `git describe --tags` / `git diff <last-tag>` / `git checkout gh-pages` — without full history those operations break.
- `safe.directory "$GITHUB_WORKSPACE"` in `lint-charts` — when the container runs as a different UID than the runner-owned workspace, git refuses with "dubious ownership" otherwise. The other jobs don't use a container so they don't need this.
- `timeout-minutes: 20` on `install-charts` — mirrors CircleCI's `no_output_timeout: 20m`.
- `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` on `release-charts` — matches CircleCI's `branches: only: main`.
- `concurrency: group: release-${{ github.ref }}, cancel-in-progress: false` — the single deliberate addition on top of verbatim. CircleCI serializes workflow runs per branch implicitly; GHA does not, so this restores that property. `cancel-in-progress: false` lets an in-flight release finish before the next one starts (you do not want a half-completed `cr index` push to gh-pages).
- The five `env:` vars on the `Release` step exactly match the names `release.sh` reads internally (`CR_TOKEN`, `HELM_GH_TOKEN`, `GIT_REPOSITORY_URL`, `GIT_USERNAME`, `GIT_EMAIL`) — that is why `release.sh` does not need editing.

- [ ] **Step 2: Verify the YAML is well-formed**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('OK')"
```

Expected: `OK`.

- [ ] **Step 3: Spot-check the four expected job names exist**

Run:
```bash
python3 -c "
import yaml
data = yaml.safe_load(open('.github/workflows/ci.yml'))
print(sorted(data['jobs'].keys()))
"
```

Expected: `['install-charts', 'lint-charts', 'lint-scripts', 'release-charts']`.

- [ ] **Step 4: Spot-check the release job dependency chain**

Run:
```bash
python3 -c "
import yaml
j = yaml.safe_load(open('.github/workflows/ci.yml'))['jobs']
print('install-charts needs:', j['install-charts']['needs'])
print('release-charts needs:', j['release-charts']['needs'])
print('release-charts if:',    j['release-charts']['if'])
"
```

Expected:
```
install-charts needs: lint-charts
release-charts needs: ['lint-charts', 'install-charts']
release-charts if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

If any of these differ, the workflow does not match the spec — re-edit before continuing.

---

## Task 4: Delete `.circleci/config.yml` and the now-empty `.circleci/` directory

**Files:**
- Delete: `.circleci/config.yml`

Tasks 1–3 left only `.circleci/config.yml` behind. Deleting it in the same commit as the workflow add is essential: a state where both `.circleci/config.yml` and `.github/workflows/ci.yml` exist would double-run the pipeline on every push.

- [ ] **Step 1: Remove `.circleci/config.yml`**

Run:
```bash
git rm .circleci/config.yml
```

- [ ] **Step 2: Verify `.circleci/` directory is empty and remove it**

Run:
```bash
ls -la .circleci/ 2>/dev/null || echo "removed"
rmdir .circleci 2>/dev/null && echo "directory removed" || echo "still present"
```

Expected: either `removed` (the directory was already gone after `git rm`) or `directory removed`. If the script prints `still present`, list `.circleci/` to see what remains and remove any stragglers before continuing.

- [ ] **Step 3: Verify no stale references to `.circleci/` remain anywhere in the repo**

Run:
```bash
grep -rn "\.circleci" --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.md" . | grep -v "^./docs/superpowers/" | grep -v "^./.git/"
```

Expected: empty output (exit 1). The `grep -v ./docs/superpowers/` exclusion is because the design doc and this plan legitimately reference `.circleci/` in prose — that is historical context, not an active reference. The `./.git/` exclusion skips git's own internal files.

If anything else is printed, that's a stale reference (e.g., in README.md, in a test script, in CLAUDE.md) — investigate and either update or accept the reference depending on context.

---

## Task 5: Final pre-commit verification

**Files:** (no edits — verification only)

- [ ] **Step 1: Re-run the full local validation suite**

Run all of these in order; every one must succeed:

```bash
# 1. shellcheck on the moved scripts
shellcheck -x .github/scripts/install_charts.sh .github/scripts/install_tools.sh .github/scripts/release.sh && echo "shellcheck OK"

# 2. bash syntax check on the moved scripts
bash -n .github/scripts/install_charts.sh && bash -n .github/scripts/install_tools.sh && bash -n .github/scripts/release.sh && echo "bash -n OK"

# 3. YAML parse of the new workflow
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "workflow YAML OK"

# 4. ct.yaml still parses (it moved but didn't change)
python3 -c "import yaml; yaml.safe_load(open('.github/scripts/ct.yaml'))" && echo "ct.yaml OK"

# 5. The other workflow file is still valid (sanity check we didn't break it)
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/inactive.yml'))" && echo "inactive.yml OK"
```

Expected: each command prints its `OK` line.

- [ ] **Step 2: Confirm `git status` shows exactly the expected change set**

Run:
```bash
git status --short
```

Expected (order may differ):
```
D  .circleci/config.yml
R  .circleci/ct.yaml -> .github/scripts/ct.yaml
R  .circleci/install_charts.sh -> .github/scripts/install_charts.sh
R  .circleci/install_tools.sh -> .github/scripts/install_tools.sh
R  .circleci/release.sh -> .github/scripts/release.sh
A  .github/workflows/ci.yml
M  .github/scripts/install_charts.sh
```

(The `M` next to `install_charts.sh` represents the path edit from Task 2. If git did not split the rename and modify, you may see `R` only with no separate `M`; either layout is fine as long as the diff covers the one-line change.)

If anything else appears in `git status`, investigate before committing.

---

## Task 6: Commit the migration atomically

**Files:** all changes from Tasks 1–4

Follow the project's HAProxy commit message style (`MINOR: ci: …` prefix; DCO sign-off; see commits `aed305f`, `d6a5b2d`, `8fa5b37` for examples).

- [ ] **Step 1: Write the commit message to a temp file**

Heredocs trip on apostrophes in the body (`release.sh's …`), so write to a file and use `-F`. Run:

```bash
cat > /tmp/gha-migration-commit-msg.txt <<'EOF'
MINOR: ci: migrate pipeline from CircleCI to GitHub Actions

Replace .circleci/config.yml with .github/workflows/ci.yml that
mirrors the existing job DAG (lint-scripts, lint-charts,
install-charts, release-charts). The four helper scripts
(install_charts.sh, install_tools.sh, release.sh, ct.yaml) move from
.circleci/ to .github/scripts/, with one path edit inside
install_charts.sh to update the ct.yaml volume mount accordingly.

Auth model collapses from "SSH deploy key + CR_TOKEN PAT +
HELM_GH_TOKEN PAT" onto the built-in GITHUB_TOKEN with
contents:write + packages:write on the release job. The release
scripts themselves are unchanged: they read the same env var names
(CR_TOKEN, HELM_GH_TOKEN, GIT_REPOSITORY_URL, GIT_USERNAME,
GIT_EMAIL) which the workflow now supplies from
secrets.GITHUB_TOKEN and the github-actions[bot] identity.

One orchestrator-level addition on top of the verbatim port: the
release-charts job uses a concurrency group to serialize concurrent
runs, restoring the per-branch serialization CircleCI provided
implicitly. Required because two simultaneous "cr index + git push
gh-pages" operations could race on the index.yaml update.

Design doc:
docs/superpowers/specs/2026-05-21-circleci-to-gha-migration-design.md

Post-migration cleanup (manual, repo settings): the SSH deploy key
and the CR_TOKEN / HELM_GH_TOKEN repository secrets can be deleted
once this workflow runs green on main.
EOF
```

- [ ] **Step 2: Stage all changes and commit**

Run:
```bash
git add -A
git commit -s -F /tmp/gha-migration-commit-msg.txt
rm -f /tmp/gha-migration-commit-msg.txt
```

- [ ] **Step 3: Verify the commit**

Run:
```bash
git log -1 --stat
```

Expected: a single commit whose stat shows:
- `.circleci/config.yml` deleted
- Four files renamed under `.github/scripts/` (or shown as delete+create if git's similarity heuristic didn't detect the rename — see below)
- `.github/workflows/ci.yml` created (~80 lines)
- The one-line edit inside `install_charts.sh` reflected in the diff (may appear as a separate hunk on the rename, or — with extreme line counts — as a delete+create pair)
- `Signed-off-by: Dinko Korunic <dkorunic@haproxy.com>` in the footer
- Title: `MINOR: ci: migrate pipeline from CircleCI to GitHub Actions`

To force git's `log --stat` to display the rename even with the one-line modification, run `git log -1 --stat -M50%` (50% similarity threshold) if the default output appears to show a delete+create instead. The default threshold of 50% should already handle a one-line change in a ~150-line file, so this is a safety check, not an expected fixup.

---

## Post-implementation (out of plan scope; for the user to do manually)

These belong to the user, not the agent — they cannot be done by editing files:

1. **Push the branch and open the PR** for review.
2. **Watch the PR run**: `lint-scripts`, `lint-charts`, `install-charts` should all run on the PR (release-charts is gated to push-to-main and is correctly skipped).
3. **After merge**, the first push to `main` that bumps a `Chart.yaml` will exercise `release-charts` end-to-end. If you want to de-risk that, the design doc covers the options.
4. **Repo settings cleanup** once the GHA workflow is verified green on `main`:
   - Delete the SSH deploy key with fingerprint `7f:84:…:76` from repo Settings → Deploy keys.
   - Delete the `CR_TOKEN` and `HELM_GH_TOKEN` repository secrets from Settings → Secrets and variables → Actions.
   - Disable the CircleCI project for this repo from CircleCI's side.
