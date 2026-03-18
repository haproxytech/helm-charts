# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Unified Gateway

A Kubernetes Gateway API controller powered by HAProxy. HAProxy Unified Gateway (HUG) implements the [Gateway API](https://gateway-api.sigs.k8s.io/) specification to provide advanced traffic management capabilities.

## Introduction

This chart bootstraps a HAProxy Unified Gateway deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

### Prerequisites

- Kubernetes 1.26+
- Helm 3.6+ (recommended 3.7+)

## Before you begin

### Setting up a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](http://kubernetes.io/docs/getting-started-guides/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Adding Helm chart repo

Once you have Helm installed, add the haproxytech Chart Repository as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts

helm repo update
```

## Installing the chart

To install the chart with Helm v3 as _my-release_ deployment:

```console
helm install my-release haproxytech/haproxy-unified-gateway
```

### Installing with unique name

To auto-generate controller and its resources names when installing, use the following:

```console
helm install haproxytech/haproxy-unified-gateway \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for controller into a separate namespace _prod_.

**_NOTE_**: Helm v3 requires namespace to be precreated (eg. with `kubectl create namespace prod`)

```console
helm install my-release haproxytech/haproxy-unified-gateway  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.imagePullSecrets[0].name=my-pull-secret
```

### Using values from YAML file

As opposed to using many `--set` invocations, much simpler approach is to define value overrides in a separate YAML file and specify them when invoking Helm:

_myhug.yaml_:

```yaml
controller:
  kind: DaemonSet
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
```

And invoking Helm becomes:

```console
helm install my-release -f myhug.yaml haproxytech/haproxy-unified-gateway
```

### Installing as DaemonSet

Default controller mode is [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), but it is possible to use [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) as well:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.kind=DaemonSet
```

### Installing with host networking (DaemonSet)

When using DaemonSet mode, you can enable host networking and host ports:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.kind=DaemonSet \
  --set controller.daemonset.useHostNetwork=true \
  --set controller.dnsPolicy=ClusterFirstWithHostNet
```

### Installing with service annotations

On some environments like EKS and GKE there might be a need to pass service annotations. Syntax can become a little tedious however:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="0.0.0.0/0" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true"
```

**_NOTE_**: With helm `--set` it is needed to put quotes and escape dots in the annotation key and commas in the value string.

### Installing with Horizontal Pod Autoscaler (HPA)

[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) automatically scales number of replicas in Deployment and adjusts replica count for the controller:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.autoscaling.enabled=true
```

### Enabling Prometheus monitoring

HUG exposes two separate metrics endpoints:

- **`stat`** (port 31024) — HAProxy native metrics (`haproxy_*` prefix): connections, request rates, backend health, latency, error codes
- **`metrics`** (port 31060) — HUG controller metrics (`hug_*` prefix): event batch processing, config generation, cert/map operations, HAProxy reloads

The chart supports both [ServiceMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/user-guides/getting-started.md) and [PodMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/design.md#podmonitor) for Prometheus Operator integration. These are mutually exclusive — enable only one. By default, both endpoints are scraped.

**Note:** Requires Prometheus Operator installed in the cluster. The `monitoring.coreos.com/v1` API must be available.

#### Metrics authentication

The controller metrics endpoint (`metrics` port) supports three authentication modes via `controller.metricsAuth`:

| Mode | Default | Protocol | Description |
| --- | --- | --- | --- |
| `kube-rbac` | **yes** | HTTPS | Kubernetes TokenReview/SubjectAccessReview — Prometheus authenticates with its ServiceAccount token |
| `none` | | HTTP | No authentication |
| `basic` | | HTTPS | HTTP Basic Authentication with username/password |

#### Default setup (kube-rbac)

By default the chart uses `kube-rbac` authentication. The controller serves metrics over HTTPS and validates bearer tokens via the Kubernetes API. To set it up:

**Step 1.** Create a ClusterRole that grants access to the `/metrics` endpoint and bind it to the Prometheus ServiceAccount:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: hug-metrics-reader
rules:
  - nonResourceURLs: ["/metrics"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hug-metrics-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: hug-metrics-reader
subjects:
  - kind: ServiceAccount
    name: prometheus        # adjust to your Prometheus SA name
    namespace: monitoring   # adjust to your Prometheus namespace
```

**Step 2.** Enable the ServiceMonitor (or PodMonitor). The default endpoints are pre-configured for kube-rbac — `stat` uses plain HTTP, `metrics` uses HTTPS with the Prometheus pod's ServiceAccount token:

```yaml
controller:
  serviceMonitor:
    enabled: true
    extraLabels:
      release: prometheus   # match your Prometheus serviceMonitorSelector
```

That's it. The default `values.yaml` endpoints already include the correct HTTPS + bearer token configuration for the `metrics` port:

```yaml
# Default endpoints (already set in values.yaml):
endpoints:
  - port: stat
    path: /metrics
    scheme: http
    interval: 30s
  - port: metrics
    path: /metrics
    scheme: https
    interval: 30s
    tlsConfig:
      insecureSkipVerify: true
    bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
```

#### Using no authentication

To disable metrics authentication:

```yaml
controller:
  metricsAuth: none
  serviceMonitor:
    enabled: true
    endpoints:
      - port: stat
        path: /metrics
        scheme: http
        interval: 30s
      - port: metrics
        path: /metrics
        scheme: http
        interval: 30s
```

#### Using basic authentication

```yaml
controller:
  metricsAuth: basic
  extraArgs:
    - --metrics-basic-auth-user=prometheus
    - --metrics-basic-auth-password=secret
  serviceMonitor:
    enabled: true
    endpoints:
      - port: stat
        path: /metrics
        scheme: http
        interval: 30s
      - port: metrics
        path: /metrics
        scheme: https
        interval: 30s
        tlsConfig:
          insecureSkipVerify: true
        basicAuth:
          username:
            name: hug-metrics-basic-auth
            key: username
          password:
            name: hug-metrics-basic-auth
            key: password
```

#### Using PodMonitor instead of ServiceMonitor

PodMonitor scrapes pods directly without creating an extra metrics Service. Replace `serviceMonitor` with `podMonitor` in any of the examples above:

```yaml
controller:
  podMonitor:
    enabled: true
    extraLabels:
      release: prometheus
```

### Configuring HugConf

The chart creates a HugConf custom resource for controller configuration. You can customize logging, and optionally reference Global and Defaults custom resources:

```yaml
hugconf:
  logging:
    defaultLevel: Debug
    categoryLevelList:
      - category: "gate"
        level: "Debug"
      - category: "k8s"
        level: "Info"
  # Reference a Global CR for HAProxy global section customization
  globalRef:
    group: gate.v3.haproxy.org
    kind: Global
    name: global
  # Reference a Defaults CR for HAProxy defaults section customization
  defaultsRef:
    group: gate.v3.haproxy.org
    kind: Defaults
    name: haproxytech
```

The Global and Defaults CRDs are automatically installed by the CRD job. When a `globalRef` or `defaultsRef` is set, the controller uses the referenced CR to configure the HAProxy global/defaults sections. When removed, built-in defaults are restored.

### Adding extra ports

By default the chart exposes four container ports: `http` (31080), `https` (31443), `stat` (31024) and `metrics` (31060). Additional ports can be added in two places:

1. **`controller.containerPort`** — exposes the port on the container (pod spec)
2. **`controller.service.extraPorts`** — exposes the port on the Service

#### Using `--set` flags

To add a container port only (e.g. for a sidecar or internal use):

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.containerPort.custom=8080
```

To also expose it on the Service:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.containerPort.custom=8080 \
  --set controller.service.extraPorts[0].name=custom \
  --set controller.service.extraPorts[0].port=8080 \
  --set controller.service.extraPorts[0].targetPort=8080 \
  --set controller.service.extraPorts[0].protocol=TCP
```

#### Using a values file

For multiple extra ports, a values file is cleaner:

```yaml
controller:
  containerPort:
    http: 31080
    https: 31443
    stat: 31024
    custom: 8080
    grpc: 9090
  service:
    extraPorts:
      - name: custom
        port: 8080
        targetPort: 8080
        protocol: TCP
      - name: grpc
        port: 9090
        targetPort: 9090
        protocol: TCP
```

#### DaemonSet with host ports

For DaemonSet mode with host ports, also add matching entries in `controller.daemonset.hostPorts`:

```yaml
controller:
  kind: DaemonSet
  containerPort:
    http: 31080
    https: 31443
    stat: 31024
    custom: 8080
  daemonset:
    useHostPort: true
    hostPorts:
      http: 80
      https: 443
      stat: 1024
      custom: 8080
  service:
    extraPorts:
      - name: custom
        port: 8080
        targetPort: 8080
        protocol: TCP
```

### Passing extra arguments

Additional controller flags can be passed via `extraArgs`:

```yaml
controller:
  extraArgs:
    - --controller-name=gate.haproxy.org/hug
    - --namespaces=default,production
    - --leader-election-enabled
```

#### Available controller flags

| Flag | Default | Description |
| --- | --- | --- |
| `--controller-name` | `gate.haproxy.org/hug` | `spec.controllerName` GatewayClass selector |
| `--namespaces` | | Comma-separated list of namespaces to monitor |
| `--ipv4-bind-address` | | IPv4 address to bind to |
| `--ipv6-bind-address` | | IPv6 address to bind to |
| `--disable-ipv4` | `false` | Disable IPv4 support |
| `--disable-ipv6` | `false` | Disable IPv6 support |
| `--stats-port` | `1024` | Port for HAProxy stats |
| `--controller-port` | `31060` | Port for controller metrics (prometheus) |
| `--log-type` | `json` | Log output type (`text` or `json`) |
| `--sync-period` | `0` | Period at which the controller computes HAProxy configuration (e.g. `5s`, `1m`) |
| `--startup-sync-period` | `0` | Startup period for HAProxy config computation |
| `--cache-resync-period` | `0` | Controller-runtime manager cache SyncPeriod (defaults to 10 hours if not set) |
| `--leader-election-enabled` | `false` | Enable leader election |
| `--add-stats-port` | `true` | Add stats port bind to existing stats frontend |
| `--metrics-auth` | `none` | Metrics endpoint auth mode: `none`, `kube-rbac`, `basic` |
| `--metrics-basic-auth-user` | | Basic auth username (when `--metrics-auth=basic`) |
| `--metrics-basic-auth-password` | | Basic auth password (when `--metrics-auth=basic`) |

**Note:** The `--hugconf-crd` flag is set automatically by the chart via the `hugconfCrd` helper. The `--job-check-crd` and `--job-gwapi` flags are used internally by the CRD/Gateway API installation jobs.

### Installing with KEDA autoscaling

[KEDA](https://keda.sh/) provides event-driven autoscaling. It is mutually exclusive with HPA — when KEDA is enabled, HPA is automatically disabled even if `autoscaling.enabled` is set to `true`.

```yaml
controller:
  keda:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    pollingInterval: 30
    cooldownPeriod: 300
    restoreToOriginalReplicaCount: false
    scaledObject:
      annotations: {}
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://<prometheus-host>:9090
          metricName: haproxy_process_idle_time_percent
          threshold: '50'
          query: avg(100-avg_over_time(haproxy_process_idle_time_percent{job="haproxy-unified-gateway"}[2m]))
```

Optional advanced configuration:

```yaml
controller:
  keda:
    enabled: true
    # ...triggers, minReplicas, maxReplicas...
    fallback:
      failureThreshold: 3
      replicas: 5
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Pods
              value: 1
              periodSeconds: 300
```

### Disabling CRD/Gateway API installation jobs

By default, the chart includes Helm hook jobs that install HUG CRDs and Gateway API CRDs. To disable them:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set crdjob.enabled=false \
  --set gwapijob.enabled=false
```

## Upgrading the chart

To upgrade the _my-release_ deployment:

```console
helm upgrade my-release haproxytech/haproxy-unified-gateway
```

## Uninstalling the chart

To uninstall/delete the _my-release_ deployment:

```console
helm delete my-release
```

## Debugging

It is possible to generate a set of YAML files for testing/debugging:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --debug \
  --dry-run
```

## Contributing

We welcome all contributions. Please refer to [guidelines](../CONTRIBUTING.md) on how to make a contribution.
