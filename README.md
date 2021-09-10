# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Helm Charts

![GitHub](https://img.shields.io/github/license/haproxytech/helm-charts)
[![CircleCI](https://circleci.com/gh/haproxytech/helm-charts/tree/main.svg?style=svg)](https://circleci.com/gh/haproxytech/helm-charts/tree/main)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/haproxytech)](https://artifacthub.io/packages/search?repo=haproxytech)

This repository hosts official [HAProxy Technologies](https://www.haproxy.com/) Helm Charts for deploying on [Kubernetes](https://kubernetes.io/).

## Before you begin

### Setup a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](http://kubernetes.io/docs/getting-started-guides/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Add Helm chart repo

Once you have Helm installed, add the repo as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
```

HAProxy Helm charts can be also found on [ArtifactHub](https://artifacthub.io/packages/search?repo=haproxytech).

## Search and install charts

```console
helm search repo haproxytech/
helm install my-release haproxytech/<chart>
```

**_NOTE_**: For instructions on how to install a chart follow instructions in its `README.md`.

## Contributing

We welcome all contributions. Please refer to [guidelines](CONTRIBUTING.md) on how to make a contribution.
