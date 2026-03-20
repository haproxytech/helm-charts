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

- **Chart version**: follows its own semver (currently 1.49.x)
- **Image**: `haproxytech/kubernetes-ingress`
- **Supports**: Deployment + DaemonSet modes, IngressClass, Gateway API, HPA, KEDA, ServiceMonitor/PodMonitor, PDB, proxy service (fetch sync mode), ConfigMap-based HAProxy config, publish-service, default TLS cert generation
- **Templates**: 25 files in `templates/`
- **CI tests**: 38 test value files in `ci/`
- **Kubernetes**: >=1.23
- **Maintainer**: Dinko Korunic

## haproxy-unified-gateway Chart

- **Chart version**: 0.1.0 (appVersion 0.9.1)
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
| `controller-service.yaml` | NodePort Service (HTTP 31080, HTTPS 31443, Stats 31024) |
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

Source code lives at: `/home/zlatko/src/gitlab.int.haproxy.com/zbratkovic/unified-k8s-gateway`

Key paths in source:
- `cmd/controller/main.go` - controller entry point
- `hug/configuration/configuration.go` - CLI flags definition
- `build/Dockerfile` - container image build
- `api/definition/` - CRD definitions
- `example/dev-init/` - example Gateway/HTTPRoute manifests
- `documentation/metrics*.md` - metrics documentation

### HUG Controller Flags

All flags (for `extraArgs`):

| Flag | Default | Description |
|---|---|---|
| `--hugconf-crd` | | `namespace/name` of the HugConf CRD |
| `--controller-name` | `gate.haproxy.org/hug` | `spec.controllerName` GatewayClass selector |
| `--ipv4-bind-address` | | IPv4 address to bind to |
| `--ipv6-bind-address` | | IPv6 address to bind to |
| `--log-type` | `json` | Log output type (`text` or `json`) |
| `--job-gwapi` | | Install Gateway API experimental CRDs for given version (e.g. `1.3.0`) and exit |
| `--namespaces` | | Comma-separated list of namespaces to monitor |
| `--stats-port` | `1024` | Port for HAProxy stats |
| `--controller-port` | `31060` | Port for controller metrics (prometheus) |
| `--sync-period` | `0` | Period for HAProxy config computation (e.g. `5s`, `1m`) |
| `--startup-sync-period` | `0` | Startup period for HAProxy config computation |
| `--cache-resync-period` | `0` | Controller-runtime manager cache SyncPeriod (default: 10 hours) |
| `--add-stats-port` | `true` | Add stats port bind to existing stats frontend |
| `--force-restart-haproxy` | `false` | Force HAProxy restart at controller startup |
| `--leader-election-enabled` | `false` | Enable leader election |
| `--with-s6-overlay` | `false` | Use s6 overlay to start/stop/restart HAProxy |
| `--with-pebble` | `false` | Use pebble to start/stop/restart HAProxy |
| `--disable-ipv4` | `false` | Disable IPv4 support |
| `--disable-ipv6` | `false` | Disable IPv6 support |
| `--job-check-crd` | `false` | Run CRD refresh job and exit |
| `-e` / `--external` | `false` | Use as external controller (out of k8s cluster) |
| `--external-config-dir` | | Path to HAProxy configuration directory |
| `--external-haproxy-binary` | | Path to HAProxy binary |
| `--external-runtime-dir` | | Path to HAProxy runtime directory |
| `--external-state-dir` | | Path to HAProxy state directory |
| `--external-aux-dir` | | Path to HAProxy aux directory |
| `--metrics-auth` | `none` | Metrics endpoint auth mode: `none`, `kube-rbac`, `basic` |
| `--metrics-basic-auth-user` | | Basic auth username (when `--metrics-auth=basic`) |
| `--metrics-basic-auth-password` | | Basic auth password (when `--metrics-auth=basic`) |
| `-t` | `false` | Simulate running HAProxy (test mode) |

Note: The HUG binary default for `--metrics-auth` is `none`, but the Helm chart overrides this to `kube-rbac` via `controller.metricsAuth`.

## CI Values Files

23 test value files in `haproxy-unified-gateway/ci/`:
- 8 DaemonSet variants (default, customnodeport, extraargs, extraenvs, extraports, hostport, serviceannotation, strategy)
- 15 Deployment variants (default, customnodeport, disabled-jobs, extraargs, extraenvs, extraports, hpa, hugconf, keda, keda-advanced, metrics-none, pdb, podmonitor, servicemonitor, strategy)

Naming convention: `<mode>-<feature>-values.yaml`

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
