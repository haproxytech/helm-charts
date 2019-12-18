# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Kubernetes Ingress Controller

An ingress controller is a Kubernetes resource that routes traffic from outside your cluster to services within the cluster. HAProxy Kubernetes Ingress Controller uses ConfigMap to store the haproxy configuration.

Detailed documentation can be found within the [Official Documentation](https://www.haproxy.com/documentation/hapee/2-0r1/traffic-management/kubernetes-ingress-controller/).

Additional configuration details can be found in [annotation reference](https://github.com/haproxytech/kubernetes-ingress/tree/master/documentation) and in image [arguments reference](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/controller.md).

## Introduction

This chart bootstraps an HAProxy kubernetes-ingress deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

  - Kubernetes 1.12+
  - Helm 2.9+

## Installing the chart

To install the chart with Helm v3 as *my-release* deployment:

```console
helm install my-release haproxytech/kubernetes-ingress
```

***NOTE***: To install the chart with Helm v2 (legacy Helm) the syntax requires adding deployment name to `--name` parameter:

```console
helm install haproxytech/kubernetes-ingress \
  --name my-release
```

### Installing with unique name

To auto-generate controller and its resources names when installing, use the following:

```console
helm install haproxytech/kubernetes-ingress \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for controller into a separate namespace *prod*.

***NOTE***: Helm v3 requires namespace to be precreated (eg. with ```kubectl create namespace prod```)

```console
helm install my-ingress haproxytech/kubernetes-ingress  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.imageCredentials.registry=myregistry.domain.com \
  --set controller.imageCredentials.username=MYUSERNAME \
  --set controller.imageCredentials.password=MYPASSWORD
```

### Installing as DaemonSet

Default controller mode is [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), but it is possible to use [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) as well:

```console
helm install my-ingress2 haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet
```

### Installing in multi-ingress environment

It is also possible to set controller ingress class to be used in [multi-ingress environments](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/#using-multiple-ingress-controllers):

```console
helm install my-ingress3 haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet \
  --set controller.ingressClass=haproxy
```

***NOTE***: make sure your Ingress routes have corresponding `ingress.class: haproxy` annotation.

## Upgrading the chart

To upgrade the *my-release* deployment:

```console
helm upgrade my-release haproxytech/kubernetes-ingress
```

## Uninstalling the chart

To uninstall/delete the *my-release* deployment:

```console
helm delete kubernetes-ingress
```

## Debugging

It is possible to generate a set of YAML files for testing/debugging:

```console
helm install my-release haproxytech/kubernetes-ingress \
  --debug \
  --dry-run
```

## Contributing

We welcome all contributions. Please refer to [guidelines](../CONTRIBUTING.md) on how to make a contribution.