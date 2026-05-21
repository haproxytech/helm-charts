# CircleCI → GitHub Actions migration

Status: approved design, ready for implementation
Date: 2026-05-21
Owner: Dinko Korunic <dkorunic@haproxy.com>

## Goal

Replace the `.circleci/` pipeline with an equivalent GitHub Actions
workflow. The intent is a **verbatim port** — preserve the existing
behavior of `install_charts.sh` and `release.sh` so the migration
introduces no functional changes to lint, test, or release. The
refactor is limited to (1) the orchestrator (CircleCI YAML → GHA
YAML), (2) the location of the helper scripts, and (3) the auth model
(SSH key + two PATs → built-in `GITHUB_TOKEN`).

One deliberate addition on top of the verbatim port: the
`release-charts` job uses a GHA `concurrency:` group to serialize
concurrent runs of the release path. CircleCI did not need this
because it inherently serialized workflow runs of the same branch;
GHA does not, so the guard restores that property explicitly. The
release scripts themselves remain unchanged.

## Non-goals

- Replacing `cr` / `helm` with `helm/chart-releaser-action` or
  `helm/chart-testing-action`. Those would be a larger refactor and
  are out of scope here.
- Changing what gets released, how charts are detected as changed,
  which artifacts are produced (GH Releases, GHCR OCI, gh-pages
  `index.yaml`), or the chart-testing scenarios.
- Adding new pipeline stages (security scans, scheduled runs,
  matrix-test across kind versions, etc.).
- Touching `.github/workflows/inactive.yml` (the existing stale-issue
  closer).

## File layout

### Added

- `.github/workflows/ci.yml` — the migrated pipeline. Single workflow
  file, four jobs, mirrors `.circleci/config.yml` 1:1.

### Moved (from `.circleci/` → `.github/scripts/`)

| Old path | New path | Internal edits |
|---|---|---|
| `.circleci/install_charts.sh` | `.github/scripts/install_charts.sh` | One line: the `docker run --volume "$(pwd)/.circleci/ct.yaml:/etc/ct/ct.yaml"` call updates its host path to `$(pwd)/.github/scripts/ct.yaml`. |
| `.circleci/install_tools.sh` | `.github/scripts/install_tools.sh` | unchanged |
| `.circleci/release.sh` | `.github/scripts/release.sh` | unchanged — auth env vars are supplied by the workflow, not by the script |
| `.circleci/ct.yaml` | `.github/scripts/ct.yaml` | unchanged |

All other script internals (Kind setup, kube-prometheus-stack/KEDA
install, changed-chart detection, `cr upload` / `helm push` / gh-pages
index) stay byte-identical.

### Deleted

- `.circleci/config.yml`
- `.circleci/` directory in its entirety (every file under it has
  moved by the time the directory is removed)

### Untouched

- `.github/workflows/inactive.yml`

## Workflow structure

### Triggers

```yaml
on:
  push:
    branches-ignore: [gh-pages]
  pull_request:
```

Mirrors CircleCI's `ignore: gh-pages` filter on every job. **Tag
pushes do not trigger the workflow** — when a `push` event filter
lists `branches` or `branches-ignore` without a `tags`/`tags-ignore`
counterpart, GHA evaluates the push only against the branch filter
and silently drops tag pushes. This matches CircleCI's
`tags: ignore: /.*/` on the release job.

### Default permissions

```yaml
permissions:
  contents: read
```

Each job inherits read-only unless it explicitly elevates. Only
`release-charts` elevates.

### Job DAG

Identical to CircleCI:

```
lint-scripts ── (independent)
lint-charts ──┬── install-charts ──┐
              └────────────────────┴── release-charts (push-to-main only)
```

`lint-scripts` and `lint-charts` run in parallel. `install-charts`
depends only on `lint-charts` (not `lint-scripts`). `release-charts`
depends on both `lint-charts` and `install-charts` AND is gated by
`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`.

### Job specs

#### `lint-scripts`

```yaml
runs-on: ubuntu-latest
steps:
  - actions/checkout@v4
  - run: |
      shellcheck -x .github/scripts/install_charts.sh
      shellcheck -x .github/scripts/install_tools.sh
      shellcheck -x .github/scripts/release.sh
```

No container needed: `ubuntu-latest` ships shellcheck preinstalled.
CircleCI used `koalaman/shellcheck-alpine` only to obtain the binary.

#### `lint-charts`

```yaml
runs-on: ubuntu-latest
container:
  image: quay.io/helmpack/chart-testing:latest
steps:
  - actions/checkout@v4 with fetch-depth: 0
  - run: ct lint --all --validate-maintainers=false --config .github/scripts/ct.yaml
```

`fetch-depth: 0` gives `ct` access to full history. Container is the
same image CircleCI used.

#### `install-charts`

```yaml
needs: lint-charts
runs-on: ubuntu-latest
timeout-minutes: 20
steps:
  - actions/checkout@v4 with fetch-depth: 0
  - run: bash .github/scripts/install_charts.sh
```

`ubuntu-latest` already provides Docker, helm, and kubectl
preinstalled, so the script's existing `kind` self-install and its
`docker run` of the chart-testing container work unchanged.
`fetch-depth: 0` is required so the script's `git fetch --tags` and
`git diff` against the last tag have full history. The 20-minute
timeout mirrors CircleCI's `no_output_timeout: 20m`.

#### `release-charts`

```yaml
needs: [lint-charts, install-charts]
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
runs-on: ubuntu-latest
permissions:
  contents: write
  packages: write
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
steps:
  - actions/checkout@v4 with fetch-depth: 0
  - run: bash .github/scripts/install_tools.sh
  - name: Release
    env:
      CR_TOKEN:           ${{ secrets.GITHUB_TOKEN }}
      HELM_GH_TOKEN:      ${{ secrets.GITHUB_TOKEN }}
      GIT_REPOSITORY_URL: https://x-access-token:${{ secrets.GITHUB_TOKEN }}@github.com/${{ github.repository }}.git
      GIT_USERNAME:       github-actions[bot]
      GIT_EMAIL:          41898282+github-actions[bot]@users.noreply.github.com
    run: bash .github/scripts/release.sh
```

Concurrency group ensures two simultaneous pushes to `main` can't
race the same gh-pages update; `cancel-in-progress: false` means an
in-flight release is allowed to finish before the next one starts.

## Auth model

All three CircleCI credentials are replaced by the built-in
`GITHUB_TOKEN`:

| CircleCI credential | Used for | GHA replacement |
|---|---|---|
| SSH deploy key (fingerprint `7f:84:…:76`) | `git push gh-pages` | Token-embedded HTTPS URL: `https://x-access-token:$GITHUB_TOKEN@github.com/$REPO.git` — requires `contents: write` |
| `CR_TOKEN` PAT | `cr upload` creates GH Releases | `CR_TOKEN=${{ secrets.GITHUB_TOKEN }}` — requires `contents: write` |
| `HELM_GH_TOKEN` PAT | `helm registry login ghcr.io` for OCI push | `HELM_GH_TOKEN=${{ secrets.GITHUB_TOKEN }}` — requires `packages: write` |

`release.sh` consumes each via the same env-var names it already
reads, so the script itself doesn't change. The gh-pages commit is
attributed to `github-actions[bot]` (the GHA convention), matching
how every other GHA-managed commit looks.

Post-migration cleanup: the SSH deploy key in repo settings, and the
`CR_TOKEN` / `HELM_GH_TOKEN` repository secrets, can all be deleted
once the new workflow runs green on `main` — nothing references them.

## Risks and how they're handled

| Risk | Mitigation |
|---|---|
| `cr upload` / `helm push` behave differently against `GITHUB_TOKEN` than against the existing PATs | Both tools accept GHA's token without modification (`cr` reads `CR_TOKEN` env, `helm registry login` reads stdin). The first release push will validate this end-to-end. |
| `git push` to `gh-pages` over HTTPS fails when invoked from inside a workflow because of branch-protection rules | `contents: write` permission combined with the `github-actions[bot]` identity is the documented pattern. If branch protection on `gh-pages` blocks bot pushes, add the bot to the allow-list in repo settings. |
| First push to GHCR creates a package that's private by default and not linked to the repo | This is a one-time org/package settings toggle; same behavior CircleCI users see. Not a recurring issue. |
| Tag pushes accidentally trigger the workflow | Trigger uses `branches-ignore` with no `tags` filter → tag pushes are silently dropped by GHA. Verified design. |
| The `actions/checkout@v4` default of fetch-depth=1 breaks `release.sh`'s `git describe --tags` | Every job that runs a script doing git-history work checks out with `fetch-depth: 0`. |
| Docker-in-docker on `ubuntu-latest` for `install_charts.sh` fails | `ubuntu-latest` runners are full VMs with Docker preinstalled and unrestricted. CircleCI's `machine: true` was the same thing. The script's `docker run --network host` pattern works on Linux Docker. |

## Testing the migration

The PR that introduces these files should be testable end-to-end:

1. **lint-scripts** — runs on the PR; verifies the moved scripts
   still pass shellcheck at their new paths.
2. **lint-charts** — runs on the PR; verifies `ct lint --all` works
   under the GHA-hosted container with the new config path.
3. **install-charts** — runs on the PR; verifies Kind +
   kube-prometheus-stack + KEDA + `ct install --all` all complete on
   an `ubuntu-latest` runner.
4. **release-charts** — does NOT run on the PR (it's gated on `push`
   to `main`). After the migration PR merges, the first push to
   `main` that also bumps a `Chart.yaml` version will be the first
   real exercise of this path. Until then, `release.sh`'s
   "Nothing to do. No chart changes detected." short-circuit means
   pushes to `main` with no chart changes do nothing — same behavior
   as today on CircleCI.

The CircleCI pipeline is deleted in the same PR (the `.circleci/`
directory is removed). The two systems do not need to run in
parallel: lint and install are exercised on the migration PR itself,
and the release path is no more risky to migrate cold than it is to
run twice.

## Out of scope (already addressed by other commits)

- Aligning `test/integration-test.sh` and `test/ct-test.sh` with
  `.circleci/install_charts.sh`'s Prometheus/KEDA install method —
  done in `d6a5b2d`.
- Updating the HUG KEDA ci/ values files to point at the
  kube-prometheus-stack service DNS — done in `8fa5b37`.
- Dropping the `deployment-serviceaccountexisting` ci/ values file —
  done in `811cc03`.
