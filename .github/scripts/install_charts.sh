#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

readonly CT_VERSION=v3.14.0
readonly KIND_VERSION=v0.31.0
readonly CLOUD_PROVIDER_KIND_VERSION=v0.10.0
readonly LOCAL_PATH_PROVISIONER_VERSION=v0.0.36
readonly KUBE_PROMETHEUS_STACK_VERSION=85.2.0
readonly KEDA_VERSION=2.19.0
readonly CLUSTER_NAME=chart-testing
readonly REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
readonly CLOUD_PROVIDER_KIND_PID_FILE=/tmp/cloud-provider-kind.pid
readonly CLOUD_PROVIDER_KIND_LOG=/tmp/cloud-provider-kind.log

# Charts that exercise Service type=LoadBalancer and therefore need
# cloud-provider-kind running during `ct install`. Kept separate from other
# charts because cloud-provider-kind installs Gateway API experimental CRDs
# (v1.4.0) at startup, which conflict with haproxy-unified-gateway's gwapijob
# hook (pins v1.3.0, refuses to downgrade).
readonly LB_CHARTS=(kubernetes-ingress)

is_lb_chart() {
    local chart="$1"
    local c
    for c in "${LB_CHARTS[@]}"; do
        [[ "${c}" == "${chart}" ]] && return 0
    done
    return 1
}

join_csv() {
    # local IFS=, makes "$*" expand the positional args as a comma-joined string.
    local IFS=,
    echo "$*"
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        *) echo "Unsupported architecture: ${arch}" >&2; return 1 ;;
    esac
}

find_latest_tag() {
    if ! git describe --tags --abbrev=0 2>/dev/null; then
        # -n 1 limits to one rev so we never return a list when the repo has
        # multiple unrelated root commits.
        git rev-list --max-parents=0 --first-parent -n 1 HEAD
    fi
}

determine_baseline() {
    # On PR builds, diff against the PR's target branch so chart selection
    # tracks the PR's own changes only — not everything since the last release.
    # On push/tag builds (GITHUB_BASE_REF unset), fall back to the latest tag.
    if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
        local base="origin/${GITHUB_BASE_REF}"
        if ! git rev-parse --verify "${base}" >/dev/null 2>&1; then
            echo "Fetching base ref ${GITHUB_BASE_REF}" >&2
            git fetch --no-tags origin \
                "${GITHUB_BASE_REF}:refs/remotes/origin/${GITHUB_BASE_REF}" >/dev/null
        fi
        echo "${base}"
    else
        find_latest_tag
    fi
}

create_ct_container() {
    docker rm -f ct >/dev/null 2>&1 || true
    echo "Starting Chart Testing container"
    docker run --rm --interactive --detach --network host --name ct \
        --volume "${REPO_ROOT}/.github/scripts/ct.yaml:/etc/ct/ct.yaml" \
        --volume "${REPO_ROOT}:/workdir" \
        --workdir /workdir \
        "quay.io/helmpack/chart-testing:${CT_VERSION}" \
        cat
}

cleanup() {
    echo "Cleaning up"
    docker kill ct >/dev/null 2>&1 || true
    stop_cloud_provider_kind
    # `kind` may not be on PATH yet if cleanup fires before create_kind_cluster
    # has finished installing it.
    if [[ "${KIND_KEEP_CLUSTER:-0}" != "1" ]] && command -v kind >/dev/null 2>&1; then
        kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    fi
    popd >/dev/null 2>&1 || true
}

docker_exec() {
    docker exec --interactive ct "$@"
}

create_kind_cluster() {
    local arch
    arch=$(detect_arch)

    echo "Installing kind ${KIND_VERSION} (linux/${arch})"
    curl -fsSLo kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${arch}"
    chmod +x kind
    sudo mv kind /usr/local/bin/kind

    kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true

    echo "Creating cluster"
    kind create cluster --name "${CLUSTER_NAME}" --wait 5m -q

    echo "Copying kubeconfig to container"
    local kubeconfig="${REPO_ROOT}/kube-config"
    kind get kubeconfig --name "${CLUSTER_NAME}" > "${kubeconfig}"
    docker_exec mkdir -p /root/.kube
    docker cp "${kubeconfig}" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    docker_exec kubectl get nodes
}

install_cloud_provider_kind() {
    local arch
    arch=$(detect_arch)

    echo "Installing cloud-provider-kind ${CLOUD_PROVIDER_KIND_VERSION} (linux/${arch})"
    local version_no_v="${CLOUD_PROVIDER_KIND_VERSION#v}"
    local tarball="cloud-provider-kind_${version_no_v}_linux_${arch}.tar.gz"
    curl -fsSLO "https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/${CLOUD_PROVIDER_KIND_VERSION}/${tarball}"
    sudo mkdir -p "/usr/local/cloud-provider-kind-${CLOUD_PROVIDER_KIND_VERSION}"
    sudo tar -xzf "${tarball}" -C "/usr/local/cloud-provider-kind-${CLOUD_PROVIDER_KIND_VERSION}"
    sudo ln -sf "/usr/local/cloud-provider-kind-${CLOUD_PROVIDER_KIND_VERSION}/cloud-provider-kind" /usr/local/bin/cloud-provider-kind
    sudo chmod +x "/usr/local/cloud-provider-kind-${CLOUD_PROVIDER_KIND_VERSION}/cloud-provider-kind"
    rm -f "${tarball}"
}

start_cloud_provider_kind() {
    echo "Starting cloud-provider-kind in background"
    nohup cloud-provider-kind >"${CLOUD_PROVIDER_KIND_LOG}" 2>&1 &
    local pid="$!"
    echo "${pid}" > "${CLOUD_PROVIDER_KIND_PID_FILE}"

    # Brief grace period so cloud-provider-kind can wire up its informers
    # before the first LoadBalancer Service is created.
    sleep 3
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
        echo "cloud-provider-kind exited during startup; see ${CLOUD_PROVIDER_KIND_LOG}" >&2
        return 1
    fi
}

stop_cloud_provider_kind() {
    if [[ ! -f "${CLOUD_PROVIDER_KIND_PID_FILE}" ]]; then
        return
    fi
    local pid
    pid="$(cat "${CLOUD_PROVIDER_KIND_PID_FILE}")"
    if [[ -z "${pid}" ]]; then
        rm -f "${CLOUD_PROVIDER_KIND_PID_FILE}"
        return
    fi
    # Verify the PID still belongs to cloud-provider-kind before signaling.
    # PIDs can be reused — a stale PID file from a cancelled prior run could
    # otherwise point at an unrelated process. Use `args=` not `comm=`:
    # Linux truncates comm to 15 chars, shorter than "cloud-provider-kind".
    local cmd=""
    if kill -0 "${pid}" >/dev/null 2>&1; then
        cmd=$(ps -o args= -p "${pid}" 2>/dev/null || true)
    fi
    if [[ "${cmd}" == *cloud-provider-kind* ]]; then
        echo "Stopping cloud-provider-kind (pid ${pid})"
        # SIGTERM lets cloud-provider-kind reap the docker containers it spawned
        # for LoadBalancer Services; SIGKILL would orphan them.
        if kill -TERM "${pid}" >/dev/null 2>&1; then
            local _
            for _ in {1..10}; do
                kill -0 "${pid}" >/dev/null 2>&1 || break
                sleep 1
            done
            kill -KILL "${pid}" >/dev/null 2>&1 || true
        fi
    fi
    rm -f "${CLOUD_PROVIDER_KIND_PID_FILE}"
}

install_local_path_provisioner() {
    docker_exec kubectl delete storageclass standard || true
    docker_exec kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_PROVISIONER_VERSION}/deploy/local-path-storage.yaml"
}

install_prometheus() {
    docker_exec helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    docker_exec helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
        --set grafana.enabled=false \
        --set alertmanager.enabled=false \
        --set nodeExporter.enabled=false \
        --set kubeStateMetrics.enabled=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=1h \
        --set prometheus.prometheusSpec.resources.requests.cpu=100m \
        --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
        --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
        --wait \
        --timeout 300s
}

install_keda() {
    docker_exec helm repo add kedacore https://kedacore.github.io/charts
    docker_exec helm upgrade --install keda kedacore/keda \
        --version "${KEDA_VERSION}" \
        --set resources.operator.requests.cpu=50m \
        --set resources.operator.requests.memory=64Mi \
        --set resources.metricServer.requests.cpu=50m \
        --set resources.metricServer.requests.memory=64Mi \
        --wait \
        --timeout 180s
}

install_charts() {
    local no_lb_csv="$1"
    local lb_csv="$2"

    if [[ -n "${no_lb_csv}" ]]; then
        echo "Installing charts: ${no_lb_csv}"
        docker_exec ct install --charts "${no_lb_csv}"
    fi

    if [[ -n "${lb_csv}" ]]; then
        echo "Installing LoadBalancer charts (cloud-provider-kind): ${lb_csv}"
        start_cloud_provider_kind
        docker_exec ct install --charts "${lb_csv}"
        stop_cloud_provider_kind
    fi

    echo
}

main() {
    pushd "${REPO_ROOT}" >/dev/null
    trap cleanup EXIT

    # Reap any stale cloud-provider-kind left behind by a cancelled prior run
    # on a self-hosted runner. No-op on ephemeral GitHub-hosted runners.
    stop_cloud_provider_kind

    echo "Fetching tags"
    git fetch --tags

    local baseline
    baseline=$(determine_baseline)

    local baseline_rev
    baseline_rev=$(git rev-parse --verify "${baseline}")
    echo "${baseline_rev} ${baseline} (baseline)"

    local head_rev
    head_rev=$(git rev-parse --verify HEAD)
    echo "${head_rev} HEAD"

    if [[ "${baseline_rev}" == "${head_rev}" ]]; then
        echo "No code changes since baseline. Nothing to test."
        return
    fi

    echo "Identifying changed charts since ${baseline}"

    local changed_paths=()
    readarray -t changed_paths <<< "$(git diff --find-renames --name-only "${baseline_rev}" "${head_rev}" | awk -F/ 'NF>1 {print $1}' | sort -u)"

    local charts_to_install=()
    local path
    for path in "${changed_paths[@]}"; do
        [[ -z "${path}" ]] && continue
        if [[ -f "${path}/Chart.yaml" ]]; then
            charts_to_install+=("${path}")
        fi
    done

    if (( ${#charts_to_install[@]} == 0 )); then
        echo "Nothing to do. No chart changes detected."
        return
    fi

    echo "Changed charts: ${charts_to_install[*]}"

    local lb=() no_lb=()
    local chart
    for chart in "${charts_to_install[@]}"; do
        if is_lb_chart "${chart}"; then
            lb+=("${chart}")
        else
            no_lb+=("${chart}")
        fi
    done

    local no_lb_csv="" lb_csv=""
    (( ${#no_lb[@]} > 0 )) && no_lb_csv=$(join_csv "${no_lb[@]}")
    (( ${#lb[@]} > 0 )) && lb_csv=$(join_csv "${lb[@]}")

    create_ct_container
    create_kind_cluster
    if [[ -n "${lb_csv}" ]]; then
        install_cloud_provider_kind
    fi
    install_local_path_provisioner
    install_prometheus
    install_keda
    install_charts "${no_lb_csv}" "${lb_csv}"
}

main
