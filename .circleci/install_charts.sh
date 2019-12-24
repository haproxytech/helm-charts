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
    docker_exec ct install --all
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
        exit
    fi

    mkdir -p "${PACKAGE_PATH}"

    echo "Identifying changed charts since tag ${latest_tag}"

    local changed_charts=()
    readarray -t changed_charts <<< "$(git diff --find-renames --name-only "${latest_tag_rev}" | grep '\.yaml$' | cut -d '/' -f 1 | sort -u)"

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
            install_local_path_provisioner
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
