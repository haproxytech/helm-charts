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

find_latest_tag() {
    if ! git describe --tags --abbrev=0 2>/dev/null; then
        git rev-list --max-parents=0 --first-parent HEAD
    fi
}

create_ct_container() {
    docker rm -f ct >/dev/null 2>&1 || true
    echo "Starting Chart Testing container"
    docker run --rm --interactive --detach --network host --name ct \
        --volume "$(pwd)/.github/scripts/ct.yaml:/etc/ct/ct.yaml" \
        --volume "$(pwd):/workdir" \
        --workdir /workdir \
        "quay.io/helmpack/chart-testing:${CT_VERSION}" \
        cat
}

cleanup() {
    echo "Removing ct container"
    docker kill ct >/dev/null 2>&1 || true
    stop_cloud_provider_kind
    if [[ "${KIND_KEEP_CLUSTER:-0}" != "1" ]]; then
        kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    fi
}

docker_exec() {
    docker exec --interactive ct "$@"
}

create_kind_cluster() {
    echo "Installing kind"
    curl -fsSLo kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
    chmod +x kind
    sudo mv kind /usr/local/bin/kind

    kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true

    echo "Creating cluster"
    kind create cluster --name "${CLUSTER_NAME}" --wait 5m -q

    echo "Copying kubeconfig to container"
    local kubeconfig
    kubeconfig="$(pwd)/kube-config"
    kind get kubeconfig --name "${CLUSTER_NAME}" > "${kubeconfig}"
    docker_exec mkdir -p /root/.kube
    docker cp "${kubeconfig}" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    docker_exec kubectl get nodes
}

install_cloud_provider_kind() {
    echo "Installing cloud-provider-kind ${CLOUD_PROVIDER_KIND_VERSION}"
    local version_no_v="${CLOUD_PROVIDER_KIND_VERSION#v}"
    local tarball="cloud-provider-kind_${version_no_v}_linux_amd64.tar.gz"
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
    echo "$!" > "${CLOUD_PROVIDER_KIND_PID_FILE}"
}

stop_cloud_provider_kind() {
    if [[ ! -f "${CLOUD_PROVIDER_KIND_PID_FILE}" ]]; then
        return
    fi
    local pid
    pid="$(cat "${CLOUD_PROVIDER_KIND_PID_FILE}")"
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
    rm -f "${CLOUD_PROVIDER_KIND_PID_FILE}"
}

install_local_path_provisioner() {
    docker_exec kubectl delete storageclass standard || true
    docker_exec kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_PROVISIONER_VERSION}/deploy/local-path-storage.yaml"
}

install_prometheus() {
    docker_exec helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    docker_exec helm install prometheus prometheus-community/kube-prometheus-stack \
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
        --timeout 120s
}

install_keda() {
    docker_exec helm repo add kedacore https://kedacore.github.io/charts
    docker_exec helm install keda kedacore/keda \
        --version "${KEDA_VERSION}" \
        --set resources.operator.requests.cpu=50m \
        --set resources.operator.requests.memory=64Mi \
        --set resources.metricServer.requests.cpu=50m \
        --set resources.metricServer.requests.memory=64Mi \
        --wait \
        --timeout 90s
}

install_charts() {
    # cloud-provider-kind installs Gateway API experimental CRDs (v1.4.0) at
    # startup, which conflict with haproxy-unified-gateway's gwapijob hook
    # (pins v1.3.0, refuses to downgrade). Scope it to kubernetes-ingress,
    # the only chart exercising Service type=LoadBalancer.
    docker_exec ct install --charts haproxy,haproxy-unified-gateway

    start_cloud_provider_kind
    docker_exec ct install --charts kubernetes-ingress
    stop_cloud_provider_kind

    echo
}

main() {
    pushd "${REPO_ROOT}" >/dev/null

    echo "Fetching tags"
    git fetch --tags

    local latest_tag
    latest_tag=$(find_latest_tag)

    local latest_tag_rev
    latest_tag_rev=$(git rev-parse --verify "${latest_tag}")
    echo "${latest_tag_rev} ${latest_tag} (latest tag)"

    local head_rev
    head_rev=$(git rev-parse --verify HEAD)
    echo "${head_rev} HEAD"

    if [[ "${latest_tag_rev}" == "${head_rev}" ]]; then
        echo "No code changes. Nothing to release."
        popd >/dev/null
        exit
    fi

    echo "Identifying changed charts since tag ${latest_tag}"

    local changed_charts=()
    readarray -t changed_charts <<< "$(git diff --find-renames --name-only "${latest_tag_rev}" | grep -E '\.ya?ml$' | awk -F/ 'NF>1 {print $1}' | sort -u)"

    if [[ -n "${changed_charts[*]}" ]]; then
        local changes_pending=no
        for chart in "${changed_charts[@]}"; do
            if [[ -f "${chart}/Chart.yaml" ]]; then
                changes_pending=yes
                break
            fi
        done

        if [[ "${changes_pending}" == "yes" ]]; then
            create_ct_container
            trap cleanup EXIT

            create_kind_cluster
            install_cloud_provider_kind
            install_local_path_provisioner
            install_prometheus
            install_keda
            install_charts
        else
            echo "Nothing to do. No chart changes detected."
        fi
    else
        echo "Nothing to do. No chart changes detected."
    fi

    popd >/dev/null
}

main
