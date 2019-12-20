#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

readonly CT_VERSION=v3.0.0-beta.1
readonly KIND_VERSION=v0.6.1
readonly CLUSTER_NAME=chart-testing

create_ct_container() {
    echo "Starting Chart Testing container"
    docker run --rm --interactive --detach --network host --name ct \
        --volume "$(pwd)/.circleci/ct.yaml:/etc/ct/ct.yaml" \
        --volume "$(pwd):/workdir" \
        --workdir /workdir \
        "quay.io/helmpack/chart-testing:${CT_VERSION}" \
        cat
}

cleanup() {
    echo "Removing ct container"
    docker kill ct >/dev/null 2>&1 || true
}

docker_exec() {
    docker exec --interactive --tty ct "$@"
}

create_kind_cluster() {
    echo "Installing kind"
    curl -sSLo kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
    chmod +x kind
    sudo mv kind /usr/local/bin/kind

    echo "Creating cluster"
    kind create cluster --name "${CLUSTER_NAME}" --wait 5m

    echo "Copying kubeconfig to container"
    local kubeconfig
    kubeconfig="$(kind get kubeconfig-path --name "${CLUSTER_NAME}")"
    docker_exec mkdir -p /root/.kube
    docker cp "${kubeconfig}" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    docker_exec kubectl get nodes
}

install_local_path_provisioner() {
    docker_exec kubectl delete storageclass standard
    docker_exec kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml"
}

install_charts() {
    docker_exec ct install
    echo
}

main() {
    create_ct_container
    trap cleanup EXIT

    echo "Testing for chart repo changes"
    local changed
    changed=$(docker_exec ct list-changed | grep -v "is not a valid chart directory")
    if [[ -z "${changed}" ]]; then
        echo "No chart changes detected"
        return
    fi

    create_kind_cluster
    install_local_path_provisioner
    install_charts
}

main
