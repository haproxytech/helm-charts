#!/bin/bash

set -o errexit

readonly HELM_VERSION=3.5.4
readonly CHART_RELEASER_VERSION=1.2.1

install_helm() {
    echo "Installing Helm"
    curl -sSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
    sudo mkdir -p "/usr/local/helm-v${HELM_VERSION}"
    sudo tar -xzf "helm-v${HELM_VERSION}-linux-amd64.tar.gz" -C "/usr/local/helm-v${HELM_VERSION}"
    sudo ln -s "/usr/local/helm-v${HELM_VERSION}/linux-amd64/helm" /usr/local/bin/helm
    sudo chmod +x /usr/local/helm-v${HELM_VERSION}/linux-amd64/helm
    rm -f "helm-v${HELM_VERSION}-linux-amd64.tar.gz"
}

install_cr() {
    echo "Installing Chart Releaser"
    curl -sSLO "https://github.com/helm/chart-releaser/releases/download/v${CHART_RELEASER_VERSION}/chart-releaser_${CHART_RELEASER_VERSION}_linux_amd64.tar.gz"
    sudo mkdir -p "/usr/local/chart-releaser-v${CHART_RELEASER_VERSION}"
    sudo tar -xzf "chart-releaser_${CHART_RELEASER_VERSION}_linux_amd64.tar.gz" -C "/usr/local/chart-releaser-v${CHART_RELEASER_VERSION}"
    sudo ln -s "/usr/local/chart-releaser-v${CHART_RELEASER_VERSION}/cr" /usr/local/bin/cr
    sudo chmod +x "/usr/local/chart-releaser-v${CHART_RELEASER_VERSION}/cr"
    rm -f "chart-releaser_${CHART_RELEASER_VERSION}_linux_amd64.tar.gz"
}

main() {
    install_helm
    install_cr
}

main
