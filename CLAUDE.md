# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Linting and Template Validation (no cluster needed)

```bash
# Test all charts
./test/local-test.sh

# Test a single chart
./test/local-test.sh haproxy-unified-gateway
./test/local-test.sh kubernetes-ingress

# Helm lint a chart directly
helm lint kubernetes-ingress/
helm lint haproxy-unified-gateway/ -f haproxy-unified-gateway/ci/deployment-default-values.yaml

# Render templates to stdout
helm template test-release kubernetes-ingress/
helm template test-release haproxy-unified-gateway/ --set controller.kind=DaemonSet
helm template test-release haproxy-unified-gateway/ --api-versions monitoring.coreos.com/v1
```

### Chart-testing (ct) — matches CircleCI

```bash
# Lint all charts
./test/ct-test.sh lint

# Lint a single chart
./test/ct-test.sh lint haproxy-unified-gateway

# Install (creates a Kind cluster automatically)
./test/ct-test.sh install haproxy-unified-gateway

# Keep the Kind cluster after install tests
KIND_KEEP_CLUSTER=1 ./test/ct-test.sh install
```

### Integration Tests (real Kind cluster)

```bash
# Test all charts
./test/integration-test.sh

# Test a single chart
./test/integration-test.sh haproxy-unified-gateway

# Run a specific test scenario (defaults, daemonset, hpa, pdb, metrics-port, monitoring, hugconf-cleanup, ci)
TEST_FILTER=monitoring ./test/integration-test.sh haproxy-unified-gateway

# Keep namespaces after failure for debugging
KEEP_NS=1 ./test/integration-test.sh
```

## Contribution Requirements

- All commits require a `Signed-off-by` line (DCO): `git commit -s -m "message"`
- Any change to a chart requires a chart **version bump** in `Chart.yaml` following semver
- Submit changes to multiple charts in **separate PRs**

## Project Structure

This repo contains Helm charts for HAProxy products:

- `kubernetes-ingress/` - HAProxy Kubernetes Ingress Controller chart (mature, feature-rich)
- `haproxy/` - HAProxy community chart
- `haproxy-unified-gateway/` - HAProxy Unified Gateway (HUG) chart

## kubernetes-ingress Chart

- **Chart version**: see `kubernetes-ingress/Chart.yaml` (`version` + `appVersion`); follows its own semver
- **Image**: `haproxytech/kubernetes-ingress`
- **Supports**: Deployment + DaemonSet modes, IngressClass, Gateway API, HPA, KEDA, ServiceMonitor/PodMonitor, PDB, proxy service (fetch sync mode), ConfigMap-based HAProxy config, publish-service, default TLS cert generation
- **Templates**: see `kubernetes-ingress/templates/`
- **CI tests**: see `kubernetes-ingress/ci/`
- **Kubernetes**: >=1.23
- **Maintainer**: Dinko Korunic

## haproxy Chart

Community HAProxy chart (not a controller — just runs HAProxy as a workload).
- **Chart**: see `haproxy/Chart.yaml`
- **Kubernetes**: >=1.17 (oldest of the three charts; widest compatibility surface)
- **Templates**: Deployment + DaemonSet, ConfigMap-based config, optional HPA/KEDA, optional Ingress + HTTPRoute, PSP, ServiceMonitor
- **CI tests**: `haproxy/ci/`
- No CRDs, no controller logic — config is purely declarative via `values.yaml` → `configmap.yaml`

## haproxy-unified-gateway Chart

- **Chart version**: see `haproxy-unified-gateway/Chart.yaml` (`version` + `appVersion`)
- **Image**: `haproxytech/haproxy-unified-gateway`
- **Purpose**: Kubernetes Gateway API controller powered by HAProxy
- **Kubernetes**: >=1.26
- **Binary**: `/usr/local/sbin/hug` inside the container
- **Entry point**: `/start.sh`
- **Key flag**: `--hugconf-crd=<namespace>/<name>` for HugConf CRD reference

### Templates

| Template | Purpose |
|---|---|
| `_helpers.tpl` | Name, labels, image, serviceAccount, hugconfCrd, serviceMonitorName, podMonitorName helpers |
| `controller-deployment.yaml` | Deployment (when controller.kind=Deployment) |
| `controller-daemonset.yaml` | DaemonSet with hostNetwork/hostPort support (when controller.kind=DaemonSet) |
| `controller-service.yaml` | NodePort Service (stats port only; HTTP/HTTPS listener ports are added per Gateway by the controller — see PR #354) |
| `controller-serviceaccount.yaml` | ServiceAccount |
| `clusterrole.yaml` | RBAC: Gateway API resources, HUG CRDs (gate.v3.haproxy.org incl. globals/defaults), core K8s resources, auth/authz for kube-rbac metrics |
| `clusterrolebinding.yaml` | ClusterRoleBinding |
| `controller-hugconf.yaml` | HugConf CR (logging, globalRef, defaultsRef configuration) — post-install hook (weight 5) |
| `controller-hugconf-cleanup.yaml` | Pre-delete hook Job that deletes the HugConf CR on `helm uninstall` |
| `controller-crdjob.yaml` | Helm hook Job: installs HUG CRDs (`--job-check-crd`) — post-install hook (weight 0) |
| `controller-crdjob-rbac.yaml` | SA + ClusterRole + Binding for CRD/GWAPI jobs |
| `controller-gwapijob.yaml` | Helm hook Job: installs Gateway API CRDs (`--job-gwapi=VERSION`) |
| `controller-hpa.yaml` | HPA (disabled by default, mutually exclusive with KEDA) |
| `controller-keda.yaml` | KEDA ScaledObject (disabled by default, Deployment only) |
| `controller-servicemonitor.yaml` | ServiceMonitor for Prometheus Operator (disabled by default, gated behind `.Capabilities.APIVersions`) |
| `controller-podmonitor.yaml` | PodMonitor for Prometheus Operator (disabled by default, gated behind `.Capabilities.APIVersions`) |
| `controller-service-metrics.yaml` | ClusterIP metrics Service with stat + metrics ports (created when serviceMonitor is enabled) |
| `controller-poddisruptionbudget.yaml` | PDB (disabled by default) |
| `controller-podsecuritypolicy.yaml` | PSP (disabled by default, K8s <1.25 only) |
| `controller-role.yaml` | Role for PSP usage |
| `controller-rolebinding.yaml` | RoleBinding for PSP Role |
| `namespace.yaml` | Optional namespace creation (pre-install hook) |
| `NOTES.txt` | Post-install instructions |

### Values Structure

- `rbac.create` - RBAC resources
- `namespace.create` - optional namespace
- `serviceAccount` - create, name, annotations
- `controller` - kind (Deployment/DaemonSet), image, replicaCount, hugconfCrd, metricsAuth, extraArgs, containerPort, resources, securityContext, probes, scheduling (nodeSelector/tolerations/affinity/topologySpreadConstraints), extraEnvs/Volumes/Containers, daemonset (useHostNetwork/useHostPort/hostPorts/hostIP), service config (incl. metrics service), serviceMonitor, podMonitor, autoscaling, keda (ScaledObject), PDB
- `hugconf` - create, name, logging (defaultLevel, categoryLevelList), globalRef, defaultsRef
- `crdjob` - enabled, podAnnotations, ttl, scheduling, resources, image override
- `gwapijob` - enabled, version (Gateway API CRD version), same options as crdjob

### Metrics

HUG exposes two separate metrics endpoints:

| Port | Name | Source | Default |
|---|---|---|---|
| 31024 | `stat` | HAProxy stats (via `--stats-port`) | Always exposed |
| 31060 | `metrics` | Controller metrics (via `--controller-port`) | Always exposed |

- `controller.metricsAuth` controls `--metrics-auth` flag; default is `kube-rbac`
- Supported values: `none`, `kube-rbac`, `basic`
- When `kube-rbac`: controller serves HTTPS, validates bearer tokens via TokenReview API
- When `none`: plain HTTP, no authentication
- ClusterRole includes `tokenreviews` and `subjectaccessreviews` for kube-rbac auth
- The metrics Service (`controller-service-metrics.yaml`) exposes both `stat` and `metrics` ports, created only when ServiceMonitor is enabled

### What HUG chart intentionally does NOT have (compared to kubernetes-ingress)

- No IngressClass
- No ConfigMap-based HAProxy configuration
- No proxy service / fetch sync mode
- No publish-service
- No default TLS cert generation

### HUG Source Project

Source repo: `gitlab.int.haproxy.com/zbratkovic/unified-k8s-gateway` (internal). When you have a local clone, the useful paths are:
- `cmd/controller/main.go` – controller entry point
- `hug/configuration/configuration.go` – CLI flags definition
- `api/definition/` – CRD definitions
- `documentation/metrics*.md` – metrics documentation

### HUG Controller Flags

Canonical flag list: `hug/configuration/configuration.go` in the HUG source (binary `--help` is also reliable).

Flags the chart treats specially (rest can be passed via `controller.extraArgs`):

| Flag | How the chart sets it | Notes |
|---|---|---|
| `--hugconf-crd` | Always, from `controller.hugconfCrd` or default `<release>-hugconf` | Required for the controller to find its HugConf CR |
| `--metrics-auth` | From `controller.metricsAuth` (default `kube-rbac`) | **Chart overrides the binary default of `none`** — kube-rbac wires TokenReview/SubjectAccessReview into the ClusterRole |
| `--stats-port` / `--controller-port` | Hard-coded ports 1024 / 31060 in the Service/probes | Changing requires aligning Service ports too |
| `--job-check-crd` / `--job-gwapi` | Set by the CRD/Gateway-API hook jobs only | Not for the controller process |

## CI Values Files

Naming convention: `<mode>-<feature>-values.yaml` under `haproxy-unified-gateway/ci/` (and analogous for `kubernetes-ingress/ci/`, `haproxy/ci/`). Every file there is exercised by both `local-test.sh` and `integration-test.sh`'s `ci` scenario.

## Testing

Three test scripts in `test/`:

| Script | Purpose |
|---|---|
| `test/local-test.sh` | Offline lint + template validation (no cluster needed) |
| `test/integration-test.sh` | Deploy to a real Kind cluster and verify resources |
| `test/ct-test.sh` | Wrapper around `ct` (chart-testing), matches CircleCI pipeline |

### local-test.sh

Tests: Chart.yaml metadata, helm lint, helm template, Deployment vs DaemonSet switching, HugConf cleanup hooks, metrics port rendering + `--metrics-auth` flag, ServiceMonitor/PodMonitor rendering, all ci/ values files.

### integration-test.sh

Tests on a real Kind cluster: default install, DaemonSet mode, HPA, PDB, metrics port (container port 31060, `--metrics-auth=kube-rbac` arg), ServiceMonitor/PodMonitor with metrics Service port verification, HugConf cleanup on uninstall, all ci/ values files.

`TEST_FILTER` values: `defaults`, `daemonset`, `hpa`, `pdb`, `metrics-port`, `monitoring`, `hugconf-cleanup`, `ci`

`CI_FILTER=<glob>` (used together with `TEST_FILTER=ci`) narrows ci/ tests to value files matching a glob, e.g. `TEST_FILTER=ci CI_FILTER='deployment-*' ./test/integration-test.sh haproxy-unified-gateway`.

### ct-test.sh

Runs `ct lint` and `ct install` locally, same as CircleCI. Auto-downloads `chart_schema.yaml` and `lintconf.yaml` from the ct release on first run (files are gitignored).

Modes: `lint`, `install`, `all`

### CircleCI Pipeline

`.circleci/config.yml` workflow: `lint-scripts` (shellcheck) -> `lint-charts` (ct lint) -> `install-charts` (ct install on Kind) -> `release-charts` (helm package + push to GitHub Releases, GHCR OCI, update gh-pages index).

## Conventions

- Template names prefixed with `controller-` for controller-specific resources
- All templates use `include "<chart>.fullname"` for resource naming
- All templates use `include "<chart>.namespace"` for namespace
- Helm hooks used for CRD installation jobs (post-install, pre-upgrade)
- ArgoCD hook annotations included alongside Helm hooks
- HugConf CR is a post-install hook (weight 5) that runs after the CRD job (weight 0)
- HugConf cleanup is a pre-delete hook Job
- Security context: non-root (UID 1000), CAP_NET_BIND_SERVICE, seccomp RuntimeDefault
- ServiceMonitor/PodMonitor gated behind `.Capabilities.APIVersions "monitoring.coreos.com/v1"`
