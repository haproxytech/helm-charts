# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Helm Charts

![GitHub](https://img.shields.io/github/license/haproxytech/helm-charts)
[![CI](https://github.com/haproxytech/helm-charts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/haproxytech/helm-charts/actions/workflows/ci.yml)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/haproxytech)](https://artifacthub.io/packages/search?repo=haproxytech)
[![CNTi essential: kubernetes-ingress](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/haproxytech/helm-charts/badges/kubernetes-ingress/cnti-badge.json)](https://github.com/haproxytech/helm-charts/actions/workflows/cnti.yml)

Official [HAProxy Technologies](https://www.haproxy.com/) Helm charts for running [HAProxy](https://github.com/haproxy/haproxy) on [Kubernetes](https://kubernetes.io/): as a plain load balancer, as an Ingress controller, or as a Gateway API controller.

## Charts

| Chart | Deploys | Kubernetes | Latest |
|---|---|---|---|
| [`kubernetes-ingress`](kubernetes-ingress/README.md) | [HAProxy Kubernetes Ingress Controller](https://github.com/haproxytech/kubernetes-ingress): Ingress, IngressClass and Gateway API support | 1.23+ | [![kubernetes-ingress](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fartifacthub.io%2Fapi%2Fv1%2Fpackages%2Fhelm%2Fhaproxytech%2Fkubernetes-ingress&query=%24.version&label=chart)](https://artifacthub.io/packages/helm/haproxytech/kubernetes-ingress) |
| [`haproxy-unified-gateway`](haproxy-unified-gateway/README.md) | [HAProxy Unified Gateway](https://github.com/haproxytech/haproxy-unified-gateway): a Kubernetes Gateway API controller | 1.26+ | [![haproxy-unified-gateway](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fartifacthub.io%2Fapi%2Fv1%2Fpackages%2Fhelm%2Fhaproxytech%2Fhaproxy-unified-gateway&query=%24.version&label=chart)](https://artifacthub.io/packages/helm/haproxytech/haproxy-unified-gateway) |
| [`haproxy`](haproxy/README.md) | [HAProxy](https://www.haproxy.org/) as a workload, configured from `values.yaml`; no controller | 1.17+ | [![haproxy](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fartifacthub.io%2Fapi%2Fv1%2Fpackages%2Fhelm%2Fhaproxytech%2Fhaproxy&query=%24.version&label=chart)](https://artifacthub.io/packages/helm/haproxytech/haproxy) |

Each chart's `README.md` lists its configuration options and installation examples.

## Prerequisites

- A Kubernetes cluster at the version the chart needs (see the table). For a local one, [kind](https://kind.sigs.k8s.io/) or [minikube](https://minikube.sigs.k8s.io/) will do; otherwise see [Getting started](https://kubernetes.io/docs/setup/).
- [Helm](https://helm.sh/docs/intro/install/) 3.8 or newer (needed for OCI registries).

## Installing

Charts are published to a Helm repository and, as OCI artifacts, to the GitHub Container Registry. Use either.

### Helm repository

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
helm search repo haproxytech/
helm install my-release haproxytech/<chart>
```

### OCI registry

```console
helm install my-release oci://ghcr.io/haproxytech/helm-charts/<chart>
```

Pin a release with `--version <version>`. The charts are also listed on [Artifact Hub](https://artifacthub.io/packages/search?repo=haproxytech).

## Changelogs

Chart changes are listed on Artifact Hub:
[kubernetes-ingress](https://artifacthub.io/packages/helm/haproxytech/kubernetes-ingress?modal=changelog),
[haproxy-unified-gateway](https://artifacthub.io/packages/helm/haproxytech/haproxy-unified-gateway?modal=changelog),
[haproxy](https://artifacthub.io/packages/helm/haproxytech/haproxy?modal=changelog).

Release notes for the software the charts deploy:
[HAProxy Kubernetes Ingress Controller](https://github.com/haproxytech/kubernetes-ingress/releases),
[HAProxy Unified Gateway](https://github.com/haproxytech/haproxy-unified-gateway/releases),
[HAProxy](https://github.com/haproxy/haproxy/blob/master/CHANGELOG).

## Contributing

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). In short: sign off every commit (`git commit -s`), bump the chart version in `Chart.yaml` for any chart change, and send changes to different charts as separate pull requests. [test/README.md](test/README.md) explains how to lint and test charts locally, with or without a cluster.

## License

[Apache License 2.0](LICENSE)
