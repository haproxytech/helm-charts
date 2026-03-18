# Helm Chart Testing

Three test scripts are provided:

1. **`local-test.sh`** — Offline lint + template validation (no cluster needed)
2. **`integration-test.sh`** — Deploy to a real Kind cluster and verify resources
3. **`ct-test.sh`** — Wrapper around [chart-testing](https://github.com/helm/chart-testing) (`ct`), matching what CircleCI runs

## 1. Offline Tests (`local-test.sh`)

Runs `helm lint` and `helm template` — no cluster required.

### Prerequisites

- [Helm](https://helm.sh/docs/intro/install/) v3.x

### Usage

```bash
# Test all charts
./test/local-test.sh

# Test a specific chart
./test/local-test.sh haproxy-unified-gateway
./test/local-test.sh kubernetes-ingress
```

### What It Tests

| Test | Description |
|------|-------------|
| **Chart.yaml metadata** | Verifies required fields (`name`, `version`, `appVersion`, `description`) |
| **helm lint (defaults)** | Runs `helm lint` with default values |
| **helm template (defaults)** | Renders templates and checks for errors |
| **Deployment vs DaemonSet** | Confirms charts that support `controller.kind` render the correct resource type |
| **HugConf cleanup hook** | Verifies cleanup hook renders/skips based on `hugconf.create` and targets correct name |
| **Metrics port** | Verifies metrics container port (31060) renders, `--metrics-auth` flag is correct for both `kube-rbac` (default) and `none`, metrics Service has both `stat` and `metrics` ports |
| **ServiceMonitor/PodMonitor** | Renders with `monitoring.coreos.com/v1` API, skipped without it, metrics Service only with ServiceMonitor |
| **CI values (lint + template)** | Lint and template for every `ci/*.yaml` file |

---

## 2. Integration Tests (`integration-test.sh`)

Installs charts into a real Kubernetes cluster, waits for pods to become Ready,
verifies key resources exist, then cleans up.

By default the script creates a [Kind](https://kind.sigs.k8s.io/) cluster named
`dev-helm-charts`, runs all tests, and deletes the cluster when done.

### Prerequisites

- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Helm](https://helm.sh/docs/intro/install/) v3.x
- `kubectl`

### Usage

```bash
# Test all charts (creates + destroys Kind cluster automatically)
./test/integration-test.sh

# Test a specific chart
./test/integration-test.sh haproxy-unified-gateway
./test/integration-test.sh kubernetes-ingress
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TIMEOUT` | `120` | Max seconds to wait for pods per install |
| `KEEP_NS` | `0` | Set to `1` to keep test namespaces after run (for debugging) |
| `CI_FILTER` | _(empty)_ | Glob pattern to filter `ci/` values files (e.g. `deployment-*`) |
| `TEST_FILTER` | _(empty)_ | Run only a specific test: `defaults`, `daemonset`, `hpa`, `pdb`, `metrics-port`, `monitoring`, `hugconf-cleanup`, `ci` |
| `KIND_KEEP_CLUSTER` | `0` | Set to `1` to keep the Kind cluster after tests finish |
| `KIND_CLUSTER_NAME` | `dev-helm-charts` | Custom Kind cluster name |
| `SKIP_KIND` | `0` | Set to `1` to skip Kind management and use your existing kubeconfig |

### Examples

```bash
# Run tests and keep the Kind cluster for manual inspection afterwards
KIND_KEEP_CLUSTER=1 ./test/integration-test.sh haproxy-unified-gateway

# Re-run tests against the cluster you kept (reuses existing cluster)
./test/integration-test.sh haproxy-unified-gateway

# Delete the cluster manually when done
kind delete cluster --name dev-helm-charts

# Use your own cluster instead of Kind
SKIP_KIND=1 ./test/integration-test.sh haproxy-unified-gateway

# Longer timeout for slow clusters
TIMEOUT=300 ./test/integration-test.sh haproxy-unified-gateway

# Only run deployment-related ci/ test cases
CI_FILTER="deployment-*" ./test/integration-test.sh haproxy-unified-gateway

# Run only the monitoring test (ServiceMonitor/PodMonitor)
TEST_FILTER=monitoring ./test/integration-test.sh haproxy-unified-gateway

# Run only the metrics port test
TEST_FILTER=metrics-port ./test/integration-test.sh haproxy-unified-gateway

# Run only the HugConf cleanup test
TEST_FILTER=hugconf-cleanup ./test/integration-test.sh haproxy-unified-gateway

# Run only the defaults test
TEST_FILTER=defaults ./test/integration-test.sh haproxy-unified-gateway

# Keep namespaces after the run for manual inspection
KEEP_NS=1 ./test/integration-test.sh haproxy-unified-gateway

# Then clean up manually when done
kubectl get ns | grep '^it-' | awk '{print $1}' | xargs kubectl delete ns
```

### What It Tests

For each chart, the script runs these phases:

| Test | Description |
|------|-------------|
| **Install (defaults)** | `helm install` with default values, wait for pods, verify resources |
| **Install (DaemonSet)** | Same but with `controller.kind=DaemonSet` (if chart supports it) |
| **Install (HPA)** | Enables HPA, verifies HPA resource is created |
| **Install (PDB)** | Enables PDB, verifies PDB resource is created |
| **Metrics port** | Verifies controller pod has metrics container port 31060, `--metrics-auth=kube-rbac` arg, and main Service has stat port |
| **Install (monitoring)** | Installs Prometheus Operator CRDs, verifies ServiceMonitor/PodMonitor/metrics Service with both stat + metrics ports |
| **HugConf cleanup** | Verifies HugConf CR is deleted after `helm uninstall` |
| **Install ci/ values** | Installs with each `ci/*.yaml` file, waits for pods |

Each test:
1. Creates an isolated namespace (`it-<chart>-<suffix>-<timestamp>`)
2. Runs `helm install --wait`
3. Verifies pods reach Running/Completed state
4. On failure: dumps pod status, events, and container logs
5. Runs `helm uninstall` and deletes the namespace

### On Failure

When a test fails, the script automatically prints:
- Pod status (`kubectl get pods -o wide`)
- Recent events (`kubectl get events`)
- Container logs from unhealthy pods (last 20 lines)

---

## 3. Chart Testing (`ct-test.sh`)

Wrapper around [chart-testing](https://github.com/helm/chart-testing) (`ct`) — the same
tool CircleCI uses. Runs `ct lint` and `ct install` locally so you can validate before pushing.

### Prerequisites

- [ct](https://github.com/helm/chart-testing#installation) v3.x
- [yamale](https://github.com/23andMe/Yamale) (`pipx install yamale`)
- [yamllint](https://github.com/adrienverber/yamllint) (`pipx install yamllint`)
- [Helm](https://helm.sh/docs/intro/install/) v3.x
- [Kind](https://kind.sigs.k8s.io/) — only for `install` mode
- `kubectl` — only for `install` mode

### ct Usage

```bash
# Lint all charts
./test/ct-test.sh lint

# Lint a specific chart
./test/ct-test.sh lint haproxy-unified-gateway

# Install all charts on a Kind cluster (creates + destroys automatically)
./test/ct-test.sh install

# Install a specific chart
./test/ct-test.sh install haproxy-unified-gateway

# Lint + install in one go
./test/ct-test.sh all haproxy-unified-gateway
```

### ct Environment Variables

| Variable            | Default   | Description                                                      |
| ------------------- | --------- | ---------------------------------------------------------------- |
| `KIND_CLUSTER_NAME` | `ct-dev`  | Kind cluster name                                                |
| `KIND_KEEP_CLUSTER` | `0`       | Set to `1` to keep the Kind cluster after tests                  |
| `SKIP_KIND`         | `0`       | Set to `1` to skip Kind management and use existing kubeconfig   |
| `CT_ARGS`           | _(empty)_ | Extra arguments passed to `ct` (e.g. `--debug`)                  |

### ct Examples

```bash
# Lint with debug output
CT_ARGS="--debug" ./test/ct-test.sh lint haproxy-unified-gateway

# Install and keep cluster for inspection
KIND_KEEP_CLUSTER=1 ./test/ct-test.sh install haproxy-unified-gateway

# Use an existing cluster
SKIP_KIND=1 ./test/ct-test.sh install haproxy-unified-gateway

# Delete the cluster manually when done
kind delete cluster --name ct-dev
```

### CircleCI Compatibility

The CircleCI pipeline (`.circleci/config.yml`) runs:

1. `ct lint --all` — validates Chart.yaml schema, runs `helm lint` with each `ci/*.yaml` file
2. `ct install --all` — installs each chart with each `ci/*.yaml` file on a Kind cluster

`ct-test.sh` runs the exact same commands locally using the config in `test/ct.yaml`,
so if it passes locally it will pass in CI.

---

## CI Values Files

Both scripts use the `ci/` values files in each chart directory. These are the same
files used by [chart-testing](https://github.com/helm/chart-testing) (`ct`) in CircleCI.

Naming convention:
```
<mode>-<feature>-values.yaml
```

Examples:
- `deployment-default-values.yaml` — Deployment with defaults
- `daemonset-hostport-values.yaml` — DaemonSet with host port mapping
- `deployment-hpa-values.yaml` — Deployment with HPA enabled

## Adding New Test Cases

1. Create a new values file in `<chart>/ci/` following the naming convention.
2. Validate offline:

   ```bash
   ./test/local-test.sh <chart-name>
   ```

3. Verify ct lint passes (matches CircleCI):

   ```bash
   ./test/ct-test.sh lint <chart-name>
   ```

4. Deploy to a cluster:

   ```bash
   CI_FILTER="<your-new-file>" ./test/integration-test.sh <chart-name>
   ```

5. The file is automatically picked up by all three scripts and CircleCI's `ct lint`.
