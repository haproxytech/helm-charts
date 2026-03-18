#!/bin/bash
#
# Integration test: deploy Helm chart(s) to a real Kubernetes cluster.
#
# By default, creates a Kind cluster named "dev-helm-charts", runs the tests,
# and deletes the cluster when done. Set KIND_KEEP_CLUSTER=1 to keep it.
#
# Prerequisites:
#   - kind (https://kind.sigs.k8s.io/)
#   - kubectl
#   - Helm v3.x
#
# Usage:
#   ./test/integration-test.sh                           # test all charts
#   ./test/integration-test.sh haproxy-unified-gateway   # test only HUG
#   ./test/integration-test.sh kubernetes-ingress        # test only ingress
#
# Options (env vars):
#   TIMEOUT=120             Max seconds to wait for pods (default: 120)
#   KEEP_NS=1               Don't delete test namespaces on success (for debugging)
#   CI_FILTER=<glob>        Only test ci/ files matching pattern (e.g. "deployment-*")
#   TEST_FILTER=<name>      Run only a specific test (defaults, daemonset, hpa, pdb, monitoring, ci)
#   KIND_KEEP_CLUSTER=1     Don't delete the Kind cluster after tests
#   KIND_CLUSTER_NAME=name  Custom cluster name (default: dev-helm-charts)
#   SKIP_KIND=1             Skip Kind cluster creation (use existing kubeconfig)
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMEOUT="${TIMEOUT:-120}"
KEEP_NS="${KEEP_NS:-0}"
CI_FILTER="${CI_FILTER:-}"
KIND_KEEP_CLUSTER="${KIND_KEEP_CLUSTER:-0}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-dev-helm-charts}"
SKIP_KIND="${SKIP_KIND:-0}"
TEST_FILTER="${TEST_FILTER:-}"
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()
NAMESPACES=()
KIND_CREATED=false
KEDA_CRDS_INSTALLED=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log_pass()    { echo -e "  ${GREEN}PASS${NC} $1"; PASSED=$((PASSED + 1)); }
log_fail()    { echo -e "  ${RED}FAIL${NC} $1"; FAILED=$((FAILED + 1)); FAILURES+=("$1"); }
log_skip()    { echo -e "  ${YELLOW}SKIP${NC} $1"; SKIPPED=$((SKIPPED + 1)); }
log_section() { echo -e "\n${BOLD}=== $1 ===${NC}"; }
log_info()    { echo -e "  ${YELLOW}INFO${NC} $1"; }

# --- Kind cluster management ---

create_kind_cluster() {
    if [ "$SKIP_KIND" = "1" ]; then
        echo -e "${YELLOW}SKIP_KIND=1, using existing kubeconfig${NC}"
        return
    fi

    if ! command -v kind &>/dev/null; then
        echo -e "${RED}ERROR:${NC} 'kind' not found in PATH" >&2
        echo "Install it: https://kind.sigs.k8s.io/docs/user/quick-start/#installation" >&2
        exit 1
    fi

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        echo -e "Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC} already exists, reusing it"
        kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" &>/dev/null || {
            echo -e "${RED}ERROR:${NC} cluster exists but is not reachable" >&2
            exit 1
        }
        export KUBECONFIG
        KUBECONFIG=$(kind get kubeconfig-path --name="${KIND_CLUSTER_NAME}" 2>/dev/null || echo "")
        kubectl config use-context "kind-${KIND_CLUSTER_NAME}" &>/dev/null || true
        return
    fi

    echo -e "Creating Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC}..."
    kind create cluster \
        --name "${KIND_CLUSTER_NAME}" \
        --wait 120s
    KIND_CREATED=true
    echo -e "${GREEN}Kind cluster created${NC}"
}

delete_kind_cluster() {
    if [ "$SKIP_KIND" = "1" ]; then
        return
    fi

    if [ "$KIND_KEEP_CLUSTER" = "1" ]; then
        echo -e "\n${YELLOW}KIND_KEEP_CLUSTER=1, keeping cluster '${KIND_CLUSTER_NAME}'${NC}"
        echo -e "  To use:  kubectl --context kind-${KIND_CLUSTER_NAME} ..."
        echo -e "  Delete:  kind delete cluster --name ${KIND_CLUSTER_NAME}"
        return
    fi

    if $KIND_CREATED || kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        echo -e "\nDeleting Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC}..."
        kind delete cluster --name "${KIND_CLUSTER_NAME}"
        echo -e "${GREEN}Kind cluster deleted${NC}"
    fi
}

# --- helpers ---

check_prerequisites() {
    local ok=true
    for cmd in kubectl helm; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}ERROR:${NC} '$cmd' not found in PATH" >&2
            ok=false
        fi
    done
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}ERROR:${NC} cannot connect to Kubernetes cluster" >&2
        ok=false
    fi
    if ! $ok; then
        exit 1
    fi
}

find_charts() {
    local filter="${1:-}"
    local charts=()
    for dir in "$REPO_ROOT"/*/; do
        [ -f "$dir/Chart.yaml" ] || continue
        local name
        name="$(basename "$dir")"
        if [ -n "$filter" ] && [ "$name" != "$filter" ]; then
            continue
        fi
        charts+=("$name")
    done
    if [ ${#charts[@]} -eq 0 ]; then
        echo "No charts found${filter:+ matching '$filter'}." >&2
        exit 1
    fi
    echo "${charts[@]}"
}

# Generate a unique namespace for a test run
make_ns() {
    local chart="$1"
    local suffix="$2"
    # namespace max 63 chars; keep it short
    local ns="it-${chart}-${suffix}-$(date +%s)"
    ns="${ns:0:63}"
    echo "$ns"
}

create_ns() {
    local ns="$1"
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    NAMESPACES+=("$ns")
}

delete_ns() {
    local ns="$1"
    if [ "$KEEP_NS" = "1" ]; then
        log_info "KEEP_NS=1, not deleting namespace $ns"
        return
    fi
    kubectl delete namespace "$ns" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}

# Wait for all pods in a namespace to be Ready (or Completed for Jobs)
wait_for_pods() {
    local ns="$1"
    local deadline=$((SECONDS + TIMEOUT))

    while [ $SECONDS -lt $deadline ]; do
        local not_ready=0
        local pod_lines
        pod_lines=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null || true)

        if [ -z "$pod_lines" ]; then
            # No pods yet, keep waiting
            sleep 2
            continue
        fi

        while IFS= read -r line; do
            local status
            status=$(echo "$line" | awk '{print $3}')
            case "$status" in
                Running|Completed|Succeeded)
                    # Check if Running pods have all containers ready
                    if [ "$status" = "Running" ]; then
                        local ready_col
                        ready_col=$(echo "$line" | awk '{print $2}')
                        local ready_count="${ready_col%/*}"
                        local total_count="${ready_col#*/}"
                        if [ "$ready_count" != "$total_count" ]; then
                            not_ready=$((not_ready + 1))
                        fi
                    fi
                    ;;
                Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName)
                    # Terminal failure
                    return 1
                    ;;
                *)
                    not_ready=$((not_ready + 1))
                    ;;
            esac
        done <<< "$pod_lines"

        if [ "$not_ready" -eq 0 ]; then
            return 0
        fi
        sleep 3
    done
    return 1  # timeout
}

# Collect debug info on failure
dump_debug() {
    local ns="$1"
    echo -e "    ${YELLOW}--- debug info (ns: $ns) ---${NC}"
    echo "    Pods:"
    kubectl get pods -n "$ns" -o wide 2>/dev/null | sed 's/^/      /'
    echo "    Events (last 10):"
    kubectl get events -n "$ns" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 | sed 's/^/      /'

    # Show logs from non-ready pods
    local pods
    pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '$3 !~ /Running|Completed|Succeeded/ {print $1}')
    if [ -z "$pods" ]; then
        # Also grab CrashLoopBackOff pods that show as "Running"
        pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]!=a[2]) print $1}')
    fi
    for pod in $pods; do
        echo "    Logs ($pod):"
        kubectl logs -n "$ns" "$pod" --all-containers --tail=20 2>/dev/null | sed 's/^/      /' || true
    done
    echo -e "    ${YELLOW}--- end debug ---${NC}"
}

# --- test functions ---

# Return chart-specific helm args needed for test installs.
# Some charts need overrides to install cleanly on a fresh cluster.
chart_test_args() {
    local chart="$1"
    case "$chart" in
        haproxy-unified-gateway)
            # No special overrides needed: the HugConf CR is a post-install hook
            # (weight 5) that runs after the CRD job (weight 0), avoiding the
            # chicken-and-egg validation problem.
            ;;
    esac
}

# Install chart with given values, wait for pods, verify resources, then clean up.
install_and_verify() {
    local chart="$1"
    local label="$2"
    local ns="$3"
    shift 3
    # Remaining args are passed to helm install
    local helm_args=("$@")
    # Add chart-specific test overrides
    local extra_args
    extra_args=$(chart_test_args "$chart")
    if [ -n "$extra_args" ]; then
        # shellcheck disable=SC2206
        helm_args+=($extra_args)
    fi

    create_ns "$ns"

    # Install
    if ! helm install "test-${chart}" "$REPO_ROOT/$chart" \
        --namespace "$ns" \
        --wait --timeout "${TIMEOUT}s" \
        "${helm_args[@]}" 2>&1 | sed 's/^/    /'; then
        log_fail "$label (helm install failed)"
        dump_debug "$ns"
        delete_ns "$ns"
        return
    fi

    # Wait for pods to be ready (belt-and-suspenders on top of --wait)
    if ! wait_for_pods "$ns"; then
        log_fail "$label (pods not ready within ${TIMEOUT}s)"
        dump_debug "$ns"
        helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
        delete_ns "$ns"
        return
    fi

    # Basic resource verification
    local ok=true

    # Check that we have at least one Running or Completed pod
    local running
    running=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -cE 'Running|Completed|Succeeded' || true)
    if [ "$running" -eq 0 ]; then
        echo -e "    ${RED}No running pods found${NC}"
        ok=false
    fi

    # Verify ServiceAccount exists
    if kubectl get serviceaccount -n "$ns" -l "app.kubernetes.io/instance=test-${chart}" --no-headers 2>/dev/null | grep -q .; then
        : # ok
    else
        # Some charts may not label SA; check by name
        if ! kubectl get serviceaccount -n "$ns" 2>/dev/null | grep -q "test-${chart}\|${chart}"; then
            echo -e "    ${YELLOW}ServiceAccount not found (may be expected)${NC}"
        fi
    fi

    # Verify Service exists (if applicable)
    local svc_count
    svc_count=$(kubectl get svc -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [ "$svc_count" -gt 0 ]; then
        : # ok
    fi

    if $ok; then
        log_pass "$label"
    else
        log_fail "$label"
        dump_debug "$ns"
    fi

    # Cleanup
    helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
    delete_ns "$ns"
}

# Test: default values install
test_install_defaults() {
    local chart="$1"
    local label="$chart: install (defaults)"
    local ns
    ns=$(make_ns "$chart" "defaults")

    install_and_verify "$chart" "$label" "$ns"
}

# Install KEDA CRDs if not already installed.
# Required for ci/ values files that enable KEDA ScaledObject.
ensure_keda_crds() {
    if $KEDA_CRDS_INSTALLED; then
        return 0
    fi

    local keda_crd_url="https://github.com/kedacore/keda/releases/download/v2.16.1/keda-2.16.1-crds.yaml"
    if kubectl apply --server-side -f "$keda_crd_url" >/dev/null 2>&1; then
        KEDA_CRDS_INSTALLED=true
        log_info "Installed KEDA CRDs (ScaledObject, ScaledJob, TriggerAuthentication)"
        return 0
    else
        return 1
    fi
}

# Test: install with each ci/ values file
test_install_ci_values() {
    local chart="$1"
    local ci_dir="$REPO_ROOT/$chart/ci"

    if [ ! -d "$ci_dir" ]; then
        log_skip "$chart: no ci/ directory"
        return
    fi

    local count=0
    for values_file in "$ci_dir"/*.yaml "$ci_dir"/*.yml; do
        [ -f "$values_file" ] || continue

        local fname
        fname="$(basename "$values_file")"

        # Apply CI_FILTER if set
        if [ -n "$CI_FILTER" ]; then
            # shellcheck disable=SC2254
            case "$fname" in
                $CI_FILTER) ;;
                *) continue ;;
            esac
        fi

        count=$((count + 1))

        # Install KEDA CRDs if this values file enables KEDA
        if [[ "$fname" == *keda* ]]; then
            if ! ensure_keda_crds; then
                log_skip "$chart: install ci/$fname - could not install KEDA CRDs"
                continue
            fi
        fi

        local label="$chart: install ci/$fname"
        local suffix="${fname%.yaml}"
        suffix="${suffix%.yml}"
        suffix="${suffix%-values}"
        local ns
        ns=$(make_ns "$chart" "$suffix")

        install_and_verify "$chart" "$label" "$ns" -f "$values_file"
    done

    if [ "$count" -eq 0 ]; then
        log_skip "$chart: ci/ directory is empty${CI_FILTER:+ (or no match for '$CI_FILTER')}"
    fi
}

# Test: Deployment vs DaemonSet mode (if chart supports it)
test_install_daemonset() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'kind: Deployment' "$values_yaml" 2>/dev/null; then
        return
    fi
    if [ ! -f "$REPO_ROOT/$chart/templates/controller-daemonset.yaml" ]; then
        return
    fi

    local label="$chart: install (DaemonSet mode)"
    local ns
    ns=$(make_ns "$chart" "daemonset")

    install_and_verify "$chart" "$label" "$ns" --set controller.kind=DaemonSet
}

# Test: verify HPA creates when enabled (if chart supports it)
test_install_hpa() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'autoscaling:' "$values_yaml" 2>/dev/null; then
        return
    fi

    local label="$chart: install (HPA enabled)"
    local ns
    ns=$(make_ns "$chart" "hpa")

    install_and_verify "$chart" "$label" "$ns" \
        --set controller.autoscaling.enabled=true \
        --set controller.autoscaling.minReplicas=1 \
        --set controller.autoscaling.maxReplicas=3 \
        --set controller.autoscaling.targetCPUUtilizationPercentage=80
}

# Test: verify PDB creates when enabled (if chart supports it)
test_install_pdb() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'podDisruptionBudget:' "$values_yaml" 2>/dev/null; then
        return
    fi

    local label="$chart: install (PDB enabled)"
    local ns
    ns=$(make_ns "$chart" "pdb")

    install_and_verify "$chart" "$label" "$ns" \
        --set controller.replicaCount=2 \
        --set controller.podDisruptionBudget.enabled=true \
        --set controller.podDisruptionBudget.minAvailable=1
}

# Test: verify metrics port is exposed and metricsAuth flag is passed
test_install_metrics_port() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'metricsAuth:' "$values_yaml" 2>/dev/null; then
        return
    fi

    local label="$chart: install (metrics port exposed)"
    local ns
    ns=$(make_ns "$chart" "metrics")

    create_ns "$ns"

    local extra_args
    extra_args=$(chart_test_args "$chart")
    # shellcheck disable=SC2086
    if ! helm install "test-${chart}" "$REPO_ROOT/$chart" \
        --namespace "$ns" \
        --wait --timeout "${TIMEOUT}s" \
        $extra_args 2>&1 | sed 's/^/    /'; then
        log_fail "$label (helm install failed)"
        dump_debug "$ns"
        delete_ns "$ns"
        return
    fi

    if ! wait_for_pods "$ns"; then
        log_fail "$label (pods not ready within ${TIMEOUT}s)"
        dump_debug "$ns"
        helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
        delete_ns "$ns"
        return
    fi

    # Verify the controller pod has the metrics container port (31060)
    local ports_label="$chart: controller pod has metrics port 31060"
    if kubectl get pods -n "$ns" -o jsonpath='{.items[*].spec.containers[*].ports[*].containerPort}' 2>/dev/null | tr ' ' '\n' | grep -q '31060'; then
        log_pass "$ports_label"
    else
        log_fail "$ports_label"
    fi

    # Verify --metrics-auth=kube-rbac is in the container args
    local args_label="$chart: controller pod has --metrics-auth=kube-rbac arg"
    if kubectl get pods -n "$ns" -o jsonpath='{.items[*].spec.containers[*].args[*]}' 2>/dev/null | grep -q 'metrics-auth=kube-rbac'; then
        log_pass "$args_label"
    else
        log_fail "$args_label"
    fi

    # Verify the main Service has the stat port (it should NOT have metrics — that's only on the metrics Service)
    local svc_label="$chart: main Service has stat port"
    if kubectl get svc -n "$ns" "test-${chart}" -o jsonpath='{.spec.ports[*].name}' 2>/dev/null | grep -q 'stat'; then
        log_pass "$svc_label"
    else
        log_fail "$svc_label"
    fi

    helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
    delete_ns "$ns"
}

# Test: verify ServiceMonitor/PodMonitor install (if chart supports it)
# Installs Prometheus Operator CRDs so the monitoring.coreos.com/v1 API is available,
# then verifies the resources are created.
test_install_monitoring() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'serviceMonitor:' "$values_yaml" 2>/dev/null; then
        return
    fi

    # Install Prometheus Operator CRDs so the API is available
    local prom_crds_installed=false
    local prom_crd_url="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/jsonnet/prometheus-operator/podmonitors-crd.json"
    local sm_crd_url="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/jsonnet/prometheus-operator/servicemonitors-crd.json"

    # Try to apply the CRDs; if curl/URLs fail, skip
    if kubectl apply -f "$sm_crd_url" >/dev/null 2>&1 && \
       kubectl apply -f "$prom_crd_url" >/dev/null 2>&1; then
        prom_crds_installed=true
        log_info "Installed Prometheus Operator CRDs (ServiceMonitor, PodMonitor)"
    else
        log_skip "$chart: install (ServiceMonitor) - could not install Prometheus Operator CRDs"
        log_skip "$chart: install (PodMonitor) - could not install Prometheus Operator CRDs"
        return
    fi

    # ServiceMonitor test
    local label="$chart: install (ServiceMonitor enabled)"
    local ns
    ns=$(make_ns "$chart" "svcmon")
    create_ns "$ns"

    local extra_args
    extra_args=$(chart_test_args "$chart")
    # shellcheck disable=SC2086
    if helm install "test-${chart}" "$REPO_ROOT/$chart" \
        --namespace "$ns" \
        --wait --timeout "${TIMEOUT}s" \
        --set controller.serviceMonitor.enabled=true \
        $extra_args 2>&1 | sed 's/^/    /'; then

        # Verify ServiceMonitor exists
        if kubectl get servicemonitor -n "$ns" --no-headers 2>/dev/null | grep -q .; then
            log_pass "$label"
        else
            log_fail "$label (ServiceMonitor resource not found)"
        fi

        # Verify metrics Service exists
        local metrics_label="$chart: install (metrics Service created)"
        if kubectl get svc -n "$ns" --no-headers 2>/dev/null | grep -q metrics; then
            log_pass "$metrics_label"
        else
            log_fail "$metrics_label"
        fi

        # Verify metrics Service exposes both stat and metrics ports
        local ports_label="$chart: install (metrics Service has stat + metrics ports)"
        local svc_ports
        svc_ports=$(kubectl get svc -n "$ns" -l "app.kubernetes.io/instance=test-${chart}" -o jsonpath='{.items[*].spec.ports[*].name}' 2>/dev/null || true)
        if echo "$svc_ports" | grep -q 'stat' && echo "$svc_ports" | grep -q 'metrics'; then
            log_pass "$ports_label"
        else
            log_fail "$ports_label"
        fi
    else
        log_fail "$label (helm install failed)"
        dump_debug "$ns"
    fi

    helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
    delete_ns "$ns"

    # PodMonitor test
    label="$chart: install (PodMonitor enabled)"
    ns=$(make_ns "$chart" "podmon")
    create_ns "$ns"

    # shellcheck disable=SC2086
    if helm install "test-${chart}" "$REPO_ROOT/$chart" \
        --namespace "$ns" \
        --wait --timeout "${TIMEOUT}s" \
        --set controller.podMonitor.enabled=true \
        $extra_args 2>&1 | sed 's/^/    /'; then

        # Verify PodMonitor exists
        if kubectl get podmonitor -n "$ns" --no-headers 2>/dev/null | grep -q .; then
            log_pass "$label"
        else
            log_fail "$label (PodMonitor resource not found)"
        fi

        # Verify no metrics Service (PodMonitor shouldn't create one)
        local no_metrics_label="$chart: install (no metrics Service with PodMonitor)"
        if kubectl get svc -n "$ns" --no-headers 2>/dev/null | grep -q metrics; then
            log_fail "$no_metrics_label"
        else
            log_pass "$no_metrics_label"
        fi
    else
        log_fail "$label (helm install failed)"
        dump_debug "$ns"
    fi

    helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
    delete_ns "$ns"
}

# Test: verify HugConf is deleted after helm uninstall
test_hugconf_cleanup() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'hugconf:' "$values_yaml" 2>/dev/null; then
        return
    fi

    local label="$chart: HugConf deleted on uninstall"
    local ns
    ns=$(make_ns "$chart" "hugconf-cleanup")

    create_ns "$ns"

    local extra_args
    extra_args=$(chart_test_args "$chart")
    # shellcheck disable=SC2086
    if ! helm install "test-${chart}" "$REPO_ROOT/$chart" \
        --namespace "$ns" \
        --wait --timeout "${TIMEOUT}s" \
        $extra_args 2>&1 | sed 's/^/    /'; then
        log_fail "$label (helm install failed)"
        dump_debug "$ns"
        delete_ns "$ns"
        return
    fi

    if ! wait_for_pods "$ns"; then
        log_fail "$label (pods not ready within ${TIMEOUT}s)"
        dump_debug "$ns"
        helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
        delete_ns "$ns"
        return
    fi

    # Verify HugConf exists before uninstall
    if ! kubectl get hugconfs.gate.v3.haproxy.org -n "$ns" --no-headers 2>/dev/null | grep -q .; then
        log_fail "$label (HugConf not found after install)"
        helm uninstall "test-${chart}" -n "$ns" --wait 2>/dev/null || true
        delete_ns "$ns"
        return
    fi

    # Uninstall and verify HugConf is cleaned up
    if ! helm uninstall "test-${chart}" -n "$ns" --wait --timeout "${TIMEOUT}s" 2>&1 | sed 's/^/    /'; then
        log_fail "$label (helm uninstall failed)"
        delete_ns "$ns"
        return
    fi

    # Check that HugConf is gone
    if kubectl get hugconfs.gate.v3.haproxy.org -n "$ns" --no-headers 2>/dev/null | grep -q .; then
        log_fail "$label (HugConf still exists after uninstall)"
    else
        log_pass "$label"
    fi

    delete_ns "$ns"
}

# --- cleanup trap ---

cleanup() {
    if [ "$KEEP_NS" = "1" ]; then
        if [ ${#NAMESPACES[@]} -gt 0 ]; then
            echo -e "\n${YELLOW}KEEP_NS=1, these namespaces were left:${NC}"
            printf '  %s\n' "${NAMESPACES[@]}"
        fi
    else
        # In case of early exit, clean up any remaining namespaces
        for ns in "${NAMESPACES[@]}"; do
            kubectl delete namespace "$ns" --wait=false --ignore-not-found >/dev/null 2>&1 || true
        done
    fi

    delete_kind_cluster
}
trap cleanup EXIT

# --- main ---

main() {
    local filter="${1:-}"

    echo -e "${BOLD}Helm Chart Integration Test${NC}"
    echo "Repo:       $REPO_ROOT"
    echo "Helm:       $(helm version --short 2>/dev/null)"
    echo "Timeout:    ${TIMEOUT}s per install"
    [ -n "$CI_FILTER" ] && echo "CI filter:  $CI_FILTER"
    [ -n "$TEST_FILTER" ] && echo "Test:       $TEST_FILTER"

    # Create or reuse Kind cluster
    create_kind_cluster

    check_prerequisites

    echo "Cluster:    $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo "K8s server: $(kubectl version 2>/dev/null | grep 'Server Version' | head -1 || true)"

    local charts
    read -ra charts <<< "$(find_charts "$filter")"
    echo "Charts:     ${charts[*]}"

    for chart in "${charts[@]}"; do
        log_section "$chart"

        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "defaults" ];        then test_install_defaults "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "daemonset" ];      then test_install_daemonset "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "hpa" ];            then test_install_hpa "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "pdb" ];            then test_install_pdb "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "metrics-port" ];   then test_install_metrics_port "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "monitoring" ];     then test_install_monitoring "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "hugconf-cleanup" ]; then test_hugconf_cleanup "$chart"; fi
        if [ -z "$TEST_FILTER" ] || [ "$TEST_FILTER" = "ci" ];             then test_install_ci_values "$chart"; fi
    done

    # Summary
    log_section "Summary"
    echo -e "  ${GREEN}Passed:${NC}  $PASSED"
    echo -e "  ${RED}Failed:${NC}  $FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"

    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo -e "\n${RED}Failures:${NC}"
        for f in "${FAILURES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi

    echo -e "\n${GREEN}All integration tests passed.${NC}"
}

main "$@"
