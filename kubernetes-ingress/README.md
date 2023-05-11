# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Kubernetes Ingress Controller

An ingress controller is a Kubernetes resource that routes traffic from outside your cluster to services within the cluster. HAProxy Kubernetes Ingress Controller uses ConfigMap to store the haproxy configuration.

Detailed documentation can be found within the [Official Documentation](https://www.haproxy.com/documentation/kubernetes/latest/).

Additional configuration details can be found in [annotation reference](https://github.com/haproxytech/kubernetes-ingress/tree/master/documentation) and in image [arguments reference](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/controller.md).

## Introduction

This chart bootstraps an HAProxy kubernetes-ingress deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

### Prerequisites

- Kubernetes 1.22+ (recommended 1.24+)
- Helm 3.6+ (recommended 3.7+)

## Before you begin

### Setting up a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](http://kubernetes.io/docs/getting-started-guides/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Adding Helm chart repo

Once you have Helm installed, add the repo as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts

helm repo update
```

## Installing the chart

To install the chart with Helm v3 as _my-release_ deployment:

```console
helm install my-release haproxytech/kubernetes-ingress
```

**_NOTE_**: To install the chart with Helm v2 (legacy Helm) the syntax requires adding deployment name to `--name` parameter:

```console
helm install haproxytech/kubernetes-ingress \
  --name my-release
```

By default Helm chart will install several [custom resource definitions](https://github.com/haproxytech/helm-charts/tree/main/kubernetes-ingress/crds) in the cluster if they are missing.

### Installing with unique name

To auto-generate controller and its resources names when installing, use the following:

```console
helm install haproxytech/kubernetes-ingress \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for controller into a separate namespace _prod_.

**_NOTE_**: Helm v3 requires namespace to be precreated (eg. with `kubectl create namespace prod`)

```console
helm install my-ingress haproxytech/kubernetes-ingress  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.imageCredentials.registry=myregistry.domain.com \
  --set controller.imageCredentials.username=MYUSERNAME \
  --set controller.imageCredentials.password=MYPASSWORD
```

Alternatively, use a pre-configured (existing) imagePullSecret in the same namespace:

```console
helm install my-ingress haproxytech/kubernetes-ingress  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.existingImagePullSecret name-of-existing-image-pull-secret
```

### Using values from YAML file

As opposed to using many `--set` invocations, much simpler approach is to define value overrides in a separate YAML file and specify them when invoking Helm:

_mylb.yaml_:

```yaml
controller:
  kind: DaemonSet
  ingressClass: haproxy
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
```

And invoking Helm becomes (compare to the previous example):

```console
helm install my-ingress -f mylb.yml haproxytech/kubernetes-ingress
```

A typical YAML file for TCP services looks like (provided that configmap "[default/tcp](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/controller.md)" was created) :

```yaml
controller:
  service:
    tcpPorts:
      - name: mysql
        port: 3306
        targetPort: 3306
  extraArgs:
    - --configmap-tcp-services=default/tcp
```

### Installing as DaemonSet

Default controller mode is [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), but it is possible to use [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) as well:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet
```

### Installing in multi-ingress environment

It is also possible to set controller ingress class to be used in [multi-ingress environments](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/#using-multiple-ingress-controllers):

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet \
  --set controller.ingressClass=haproxy
```

**_NOTE_**: make sure your Ingress routes have corresponding `ingress.class: haproxy` annotation.

### Installing Gateway API support

[Gateway API support](https://gateway-api.sigs.k8s.io/) can be installed and used wth controller. Supported features can seen in [Ingress Controller documentation](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/gateway-api.md)

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.gatewayControllerName=haproxy.org/gateway-controller
```

**_NOTE_**: Gateway API is not part of the default k8s API so it needs to be installed.

### Installing with service annotations

On some environments like EKS and GKE there might be a need to pass service annotations. Syntax can become a little tedious however:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet \
  --set controller.ingressClass=haproxy \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="0.0.0.0/0" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true"
```

**_NOTE_**: With helm `--set` it is needed to put quotes and escape dots in the annotation key and commas in the value string.

### Installing with Horizontal Pod Autoscaler (HPA)

[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) automatically scales number of replicas in Deployment or Replication Controller and adjusts replica count for the controller:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.autoscaling.enabled=true
```

### Installing the ServiceMonitor

If you're using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), you can automatically install the `ServiceMonitor` definition in order to automate the scraping options according to your needs.

```console
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.serviceMonitor.enabled=true
```

### Installing with Kubernetes Event-driven Autoscaling (KEDA)

[KEDA](https://keda.sh/docs/2.3/concepts/scaling-deployments/) is an improved scaling solution built on top of HPA which allows autoscaling criteria based on information from any event source including Prometheus metrics collected from HAProxy native Prometheus Exporter.

To enable KEDA, you will also need to install Prometheus Operator and ServiceMonitor enabled (serverAddress has to match `prometheus-kube-prometheus-prometheus` service IP):

_mykeda.yaml_:

```yaml
controller:
  kind: Deployment
  serviceMonitor:
    enabled: true
  keda:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://10.96.206.247:9090
          metricName: haproxy_frontend_current_sessions
          threshold: "100"
          query: sum(rate(haproxy_frontend_current_sessions{proxy="http"}[2m]))
```

Note: Other options to trigger scaling can be found in Prometheus [native exporter documentation](https://github.com/haproxy/haproxy/blob/master/addons/promex/README), but some ideas are:

- `haproxy_process_idle_time_percent`
- `haproxy_frontend_current_sessions`
- `haproxy_backend_current_queue`

And to install:

```console
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts

helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

kubectl create namespace keda
helm install keda kedacore/keda --namespace keda

helm install mytest haproxytech/kubernetes-ingress -f mykeda.yaml
```

## Upgrading the chart

To upgrade the _my-release_ deployment:

```console
helm upgrade my-release haproxytech/kubernetes-ingress
```

By default Helm [does not upgrade](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) CRDs during an upgrade, so before doing an upgrade it is mandatory to upgrade CRDs to the latest version by hand **before** doing a Helm chart upgrade.

```console
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_defaults.yaml
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_globals.yaml
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_backends.yaml
```

## Uninstalling the chart

To uninstall/delete the _my-release_ deployment:

```console
helm delete my-release
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
