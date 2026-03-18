#!/bin/bash
#
# Local Helm chart testing script.
# Runs lint and template rendering for each ci/ values file.
#
# Usage:
#   ./test/local-test.sh                           # test all charts
#   ./test/local-test.sh haproxy-unified-gateway   # test only HUG
#   ./test/local-test.sh kubernetes-ingress        # test only ingress
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILED=$((FAILED + 1)); FAILURES+=("$1"); }
log_skip() { echo -e "  ${YELLOW}SKIP${NC} $1"; SKIPPED=$((SKIPPED + 1)); }
log_section() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

# Determine which charts to test
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

# 1. helm lint with default values
test_lint() {
    local chart="$1"
    local label="$chart: helm lint (defaults)"

    if helm lint "$REPO_ROOT/$chart" --quiet 2>/dev/null; then
        log_pass "$label"
    else
        log_fail "$label"
    fi
}

# 2. helm template with default values
test_template_defaults() {
    local chart="$1"
    local label="$chart: helm template (defaults)"

    if helm template test-release "$REPO_ROOT/$chart" >/dev/null 2>&1; then
        log_pass "$label"
    else
        log_fail "$label"
    fi
}

# 3. helm lint + template for each ci/ values file
test_ci_values() {
    local chart="$1"
    local ci_dir="$REPO_ROOT/$chart/ci"

    if [ ! -d "$ci_dir" ]; then
        log_skip "$chart: no ci/ directory"
        return
    fi

    local count=0
    for values_file in "$ci_dir"/*.yaml "$ci_dir"/*.yml; do
        [ -f "$values_file" ] || continue
        count=$((count + 1))

        local fname
        fname="$(basename "$values_file")"

        # lint
        local lint_label="$chart: lint ci/$fname"
        if helm lint "$REPO_ROOT/$chart" -f "$values_file" --quiet 2>/dev/null; then
            log_pass "$lint_label"
        else
            log_fail "$lint_label"
        fi

        # template
        local tmpl_label="$chart: template ci/$fname"
        local output
        if output=$(helm template test-release "$REPO_ROOT/$chart" -f "$values_file" 2>&1); then
            log_pass "$tmpl_label"
        else
            log_fail "$tmpl_label"
            echo "$output" | head -5 | sed 's/^/    /'
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_skip "$chart: ci/ directory is empty"
    fi
}

# 4. Check Chart.yaml required fields
test_chart_metadata() {
    local chart="$1"
    local chart_yaml="$REPO_ROOT/$chart/Chart.yaml"
    local label="$chart: Chart.yaml metadata"

    local ok=true
    for field in name version appVersion description; do
        if ! grep -q "^${field}:" "$chart_yaml"; then
            echo -e "  ${RED}FAIL${NC} $chart: Chart.yaml missing '$field'"
            FAILED=$((FAILED + 1))
            FAILURES+=("$chart: Chart.yaml missing '$field'")
            ok=false
        fi
    done

    if $ok; then
        log_pass "$label"
    fi
}

# 5. Verify template renders different output for Deployment vs DaemonSet (if applicable)
test_kind_switch() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    # Only test if chart has both Deployment and DaemonSet templates
    if ! grep -q 'kind: Deployment' "$values_yaml" 2>/dev/null; then
        return
    fi
    if [ ! -f "$REPO_ROOT/$chart/templates/controller-daemonset.yaml" ]; then
        return
    fi

    local label="$chart: Deployment vs DaemonSet renders differently"

    local deploy_out daemon_out
    deploy_out=$(helm template test-release "$REPO_ROOT/$chart" --set controller.kind=Deployment 2>&1)
    daemon_out=$(helm template test-release "$REPO_ROOT/$chart" --set controller.kind=DaemonSet 2>&1)

    if [ $? -ne 0 ]; then
        log_fail "$label (DaemonSet template failed)"
        return
    fi

    if echo "$deploy_out" | grep -q 'kind: Deployment' && echo "$daemon_out" | grep -q 'kind: DaemonSet'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi
}

# 6. Verify HugConf cleanup hook renders correctly
test_hugconf_cleanup() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'hugconf:' "$values_yaml" 2>/dev/null; then
        return
    fi

    # Cleanup resources should render when hugconf.create=true (default)
    local label="$chart: HugConf cleanup hook renders when hugconf.create=true"
    local output
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set hugconf.create=true 2>&1)
    if echo "$output" | grep -q 'hugconf-cleanup' && echo "$output" | grep -q '"helm.sh/hook": pre-delete'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # Cleanup resources should NOT render when hugconf.create=false
    label="$chart: HugConf cleanup hook skipped when hugconf.create=false"
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set hugconf.create=false 2>&1)
    if echo "$output" | grep -q 'hugconf-cleanup'; then
        log_fail "$label"
    else
        log_pass "$label"
    fi

    # Verify the cleanup Job uses the correct HugConf name
    label="$chart: HugConf cleanup Job targets correct resource name"
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set hugconf.create=true \
        --set hugconf.name=my-custom-hugconf 2>&1)
    if echo "$output" | grep -q 'hugconfs/my-custom-hugconf'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi
}

# 7. Verify controller metrics port and metricsAuth flag render correctly
test_metrics_port() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"

    if ! grep -q 'metricsAuth:' "$values_yaml" 2>/dev/null; then
        return
    fi

    # Verify metrics container port renders
    local label="$chart: metrics container port (31060) renders"
    local output
    output=$(helm template test-release "$REPO_ROOT/$chart" 2>&1)
    if echo "$output" | grep -q 'containerPort: 31060'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # Verify --metrics-auth=kube-rbac is the default arg
    label="$chart: --metrics-auth=kube-rbac in default args"
    if echo "$output" | grep -q '\-\-metrics-auth=kube-rbac'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # Verify metricsAuth=none omits kube-rbac and sets none
    label="$chart: --metrics-auth=none when metricsAuth=none"
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set controller.metricsAuth=none 2>&1)
    if echo "$output" | grep -q '\-\-metrics-auth=none' && \
       ! echo "$output" | grep -q '\-\-metrics-auth=kube-rbac'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # Verify metrics Service includes both stat and metrics ports when ServiceMonitor is enabled
    label="$chart: metrics Service has stat and metrics ports"
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set controller.serviceMonitor.enabled=true \
        --api-versions monitoring.coreos.com/v1 2>&1)
    if echo "$output" | grep -A1 'name: stat' | grep -q 'port: 31024' && \
       echo "$output" | grep -A1 'name: metrics' | grep -q 'port: 31060'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # Verify DaemonSet also gets the metrics port and --metrics-auth flag
    if [ -f "$REPO_ROOT/$chart/templates/controller-daemonset.yaml" ]; then
        label="$chart: DaemonSet renders metrics port and --metrics-auth"
        output=$(helm template test-release "$REPO_ROOT/$chart" \
            --set controller.kind=DaemonSet 2>&1)
        if echo "$output" | grep -q 'containerPort: 31060' && \
           echo "$output" | grep -q '\-\-metrics-auth=kube-rbac'; then
            log_pass "$label"
        else
            log_fail "$label"
        fi
    fi
}

# 8. Verify ServiceMonitor/PodMonitor render correctly when API is available
test_monitoring() {
    local chart="$1"
    local values_yaml="$REPO_ROOT/$chart/values.yaml"
    local tmpl_dir="$REPO_ROOT/$chart/templates"

    if ! grep -q 'serviceMonitor:' "$values_yaml" 2>/dev/null; then
        return
    fi

    # Determine the values path for serviceMonitor.enabled
    # Some charts use controller.serviceMonitor.enabled, others use serviceMonitor.enabled
    local sm_set="controller.serviceMonitor.enabled=true"
    if grep -q '^serviceMonitor:' "$values_yaml" 2>/dev/null; then
        sm_set="serviceMonitor.enabled=true"
    fi

    # ServiceMonitor: should render when API version is available
    local label="$chart: ServiceMonitor renders with monitoring.coreos.com/v1 API"
    local output
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set "$sm_set" \
        --api-versions monitoring.coreos.com/v1 2>&1)
    if echo "$output" | grep -q 'kind: ServiceMonitor'; then
        log_pass "$label"
    else
        log_fail "$label"
    fi

    # ServiceMonitor: should NOT render without the API
    label="$chart: ServiceMonitor skipped without monitoring.coreos.com/v1 API"
    output=$(helm template test-release "$REPO_ROOT/$chart" \
        --set "$sm_set" 2>&1)
    if echo "$output" | grep -q 'kind: ServiceMonitor'; then
        log_fail "$label"
    else
        log_pass "$label"
    fi

    # Metrics service: only test if chart has a metrics service template
    if ls "$tmpl_dir"/*service-metrics* &>/dev/null; then
        label="$chart: metrics Service created with ServiceMonitor"
        output=$(helm template test-release "$REPO_ROOT/$chart" \
            --set "$sm_set" \
            --api-versions monitoring.coreos.com/v1 2>&1)
        if echo "$output" | grep -q 'name: test-release.*-metrics'; then
            log_pass "$label"
        else
            log_fail "$label"
        fi
    fi

    # PodMonitor: only test if chart has a podmonitor template
    if ls "$tmpl_dir"/*podmonitor* &>/dev/null; then
        local pm_set="controller.podMonitor.enabled=true"
        if grep -q '^podMonitor:' "$values_yaml" 2>/dev/null; then
            pm_set="podMonitor.enabled=true"
        fi

        label="$chart: PodMonitor renders with monitoring.coreos.com/v1 API"
        output=$(helm template test-release "$REPO_ROOT/$chart" \
            --set "$pm_set" \
            --api-versions monitoring.coreos.com/v1 2>&1)
        if echo "$output" | grep -q 'kind: PodMonitor'; then
            log_pass "$label"
        else
            log_fail "$label"
        fi

        # PodMonitor: should NOT create metrics service
        label="$chart: no metrics Service with PodMonitor only"
        output=$(helm template test-release "$REPO_ROOT/$chart" \
            --set "$pm_set" \
            --api-versions monitoring.coreos.com/v1 2>&1)
        if echo "$output" | grep -q 'name: test-release.*-metrics'; then
            log_fail "$label"
        else
            log_pass "$label"
        fi
    fi
}

main() {
    local filter="${1:-}"

    echo -e "${BOLD}Helm Chart Local Test${NC}"
    echo "Repo: $REPO_ROOT"
    echo "Helm: $(helm version --short 2>/dev/null)"

    local charts
    read -ra charts <<< "$(find_charts "$filter")"
    echo "Charts: ${charts[*]}"

    for chart in "${charts[@]}"; do
        log_section "$chart"

        test_chart_metadata "$chart"
        test_lint "$chart"
        test_template_defaults "$chart"
        test_kind_switch "$chart"
        test_hugconf_cleanup "$chart"
        test_metrics_port "$chart"
        test_monitoring "$chart"
        test_ci_values "$chart"
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

    echo -e "\n${GREEN}All tests passed.${NC}"
}

main "$@"
