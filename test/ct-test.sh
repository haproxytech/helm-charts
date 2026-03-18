#!/bin/bash
#
# Chart-testing (ct) wrapper for local development.
#
# Uses ct to lint and optionally install Helm charts, matching what
# CircleCI runs but locally against a Kind cluster.
#
# Prerequisites:
#   - ct (https://github.com/helm/chart-testing)
#   - kind (https://kind.sigs.k8s.io/) — only for install tests
#   - kubectl, helm
#
# Usage:
#   ./test/ct-test.sh                                # lint all charts
#   ./test/ct-test.sh lint                            # lint all charts
#   ./test/ct-test.sh lint haproxy-unified-gateway    # lint one chart
#   ./test/ct-test.sh install                         # install all charts (creates Kind cluster)
#   ./test/ct-test.sh install haproxy-unified-gateway # install one chart
#
# Options (env vars):
#   KIND_CLUSTER_NAME=name  Custom cluster name (default: ct-dev)
#   KIND_KEEP_CLUSTER=1     Don't delete the Kind cluster after tests
#   SKIP_KIND=1             Skip Kind cluster management (use existing kubeconfig)
#   CT_ARGS="..."           Extra arguments passed to ct (e.g. "--debug")
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CT_CONFIG="${SCRIPT_DIR}/ct.yaml"
CT_VERSION="${CT_VERSION:-v3.10.0}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-ct-dev}"
KIND_KEEP_CLUSTER="${KIND_KEEP_CLUSTER:-0}"
SKIP_KIND="${SKIP_KIND:-0}"
CT_ARGS="${CT_ARGS:-}"
KIND_CREATED=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- prerequisites ---

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "${RED}ERROR:${NC} '$1' not found in PATH" >&2
        return 1
    fi
}

# --- ct config files ---

# Download chart_schema.yaml and lintconf.yaml from the ct release matching CT_VERSION.
ensure_ct_configs() {
    local base_url="https://raw.githubusercontent.com/helm/chart-testing/${CT_VERSION}/etc"
    local files=(chart_schema.yaml lintconf.yaml)

    for f in "${files[@]}"; do
        if [ ! -f "${SCRIPT_DIR}/${f}" ]; then
            echo -e "Downloading ${f} (ct ${CT_VERSION})..."
            if ! curl -sSfL "${base_url}/${f}" -o "${SCRIPT_DIR}/${f}"; then
                echo -e "${RED}ERROR:${NC} failed to download ${f}" >&2
                exit 1
            fi
        fi
    done
}

# --- Kind cluster management ---

create_kind_cluster() {
    if [ "$SKIP_KIND" = "1" ]; then
        echo -e "${YELLOW}SKIP_KIND=1, using existing kubeconfig${NC}"
        return
    fi

    check_tool kind

    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        echo -e "Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC} already exists, reusing"
        kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" &>/dev/null || {
            echo -e "${RED}ERROR:${NC} cluster exists but is not reachable" >&2
            exit 1
        }
        kubectl config use-context "kind-${KIND_CLUSTER_NAME}" &>/dev/null || true
        return
    fi

    echo -e "Creating Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC}..."
    kind create cluster --name "${KIND_CLUSTER_NAME}" --wait 120s
    KIND_CREATED=true
    echo -e "${GREEN}Kind cluster created${NC}"
}

delete_kind_cluster() {
    if [ "$SKIP_KIND" = "1" ]; then
        return
    fi
    if [ "$KIND_KEEP_CLUSTER" = "1" ]; then
        echo -e "\n${YELLOW}KIND_KEEP_CLUSTER=1, keeping cluster '${KIND_CLUSTER_NAME}'${NC}"
        echo -e "  Delete:  kind delete cluster --name ${KIND_CLUSTER_NAME}"
        return
    fi
    if $KIND_CREATED || kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        echo -e "\nDeleting Kind cluster ${BOLD}${KIND_CLUSTER_NAME}${NC}..."
        kind delete cluster --name "${KIND_CLUSTER_NAME}"
        echo -e "${GREEN}Kind cluster deleted${NC}"
    fi
}

# --- ct commands ---

do_lint() {
    local chart_arg="$1"

    echo -e "\n${BOLD}=== ct lint ===${NC}"

    local ct_cmd=(ct lint --config "$CT_CONFIG")

    if [ -n "$chart_arg" ]; then
        ct_cmd+=(--charts "$REPO_ROOT/$chart_arg")
    else
        ct_cmd+=(--all)
    fi

    # shellcheck disable=SC2086
    "${ct_cmd[@]}" $CT_ARGS
    echo -e "${GREEN}ct lint passed${NC}"
}

do_install() {
    local chart_arg="$1"

    echo -e "\n${BOLD}=== ct install ===${NC}"

    check_tool kubectl
    check_tool helm

    create_kind_cluster
    trap delete_kind_cluster EXIT

    # Verify cluster is reachable
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}ERROR:${NC} cannot connect to Kubernetes cluster" >&2
        exit 1
    fi

    echo "Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

    local ct_cmd=(ct install --config "$CT_CONFIG")

    if [ -n "$chart_arg" ]; then
        ct_cmd+=(--charts "$REPO_ROOT/$chart_arg")
    else
        ct_cmd+=(--all)
    fi

    # shellcheck disable=SC2086
    "${ct_cmd[@]}" $CT_ARGS
    echo -e "${GREEN}ct install passed${NC}"
}

# --- main ---

main() {
    local mode="${1:-lint}"
    local chart="${2:-}"

    check_tool ct
    check_tool helm
    ensure_ct_configs

    echo -e "${BOLD}Chart Testing (ct) — local${NC}"
    echo "Repo:    $REPO_ROOT"
    echo "Config:  $CT_CONFIG"
    echo "ct:      $(ct version 2>&1 | head -1)"
    echo "Helm:    $(helm version --short 2>/dev/null)"
    echo "Mode:    $mode"
    [ -n "$chart" ] && echo "Chart:   $chart"

    cd "$REPO_ROOT"

    case "$mode" in
        lint)
            do_lint "$chart"
            ;;
        install)
            do_install "$chart"
            ;;
        all)
            do_lint "$chart"
            do_install "$chart"
            ;;
        *)
            echo -e "${RED}Unknown mode:${NC} $mode"
            echo "Usage: $0 [lint|install|all] [chart-name]"
            exit 1
            ;;
    esac
}

main "$@"
