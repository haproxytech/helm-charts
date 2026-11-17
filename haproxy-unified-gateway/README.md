# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Unified Gateway

A Kubernetes Gateway API controller powered by HAProxy. HAProxy Unified Gateway (HUG) implements the [Gateway API](https://gateway-api.sigs.k8s.io/) specification to provide advanced traffic management capabilities.

Detailed documentation can be found within the [Official Documentation](https://www.haproxy.com/documentation/haproxy-unified-gateway/).

## Introduction

This chart bootstraps a HAProxy Unified Gateway deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

### Prerequisites

- Kubernetes 1.26+
- Helm 3.6+ (recommended 3.7+)

## Before you begin

### Setting up a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](https://kubernetes.io/docs/setup/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Adding Helm chart repo

Once you have Helm installed, add the haproxytech Chart Repository as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts

helm repo update
```

## Installing the chart

To install the chart as _my-release_ deployment:

```console
helm install my-release haproxytech/haproxy-unified-gateway
```

The chart installs the HUG and Gateway API CRDs through hook Jobs (see [CRD and Gateway API installation jobs](#crd-and-gateway-api-installation-jobs)), so no separate CRD step is needed. See also the official [installation guide](https://www.haproxy.com/documentation/haproxy-unified-gateway/installation/on-premises/).

### Routing the first request

The controller serves Gateways whose GatewayClass has `controllerName: gate.haproxy.org/hug`. A minimal setup sending all traffic of an HTTP listener to a Service `echo`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: hug
spec:
  controllerName: gate.haproxy.org/hug
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw
spec:
  gatewayClassName: hug
  listeners:
    - name: http
      port: 31090
      protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: echo
spec:
  parentRefs:
    - name: gw
  rules:
    - backendRefs:
        - name: echo
          port: 8080
```

For each listener the controller adds a port named `<protocol>-<port>` (here `http-31090`) to the chart's Service, so the route is reachable at `my-release-haproxy-unified-gateway:31090` inside the cluster, or through the NodePort the controller allocates for it.

### Installing with unique name

To auto-generate controller and its resources names when installing, use the following:

```console
helm install haproxytech/haproxy-unified-gateway \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for controller into a separate namespace _prod_.

**_NOTE_**: The namespace must exist; add `--create-namespace` to have Helm create it (eg. instead of `kubectl create namespace prod`)

```console
helm install my-release haproxytech/haproxy-unified-gateway  \
  --namespace prod \
  --create-namespace \
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

When using DaemonSet mode, you can enable host networking (for host ports instead, see [DaemonSet with host ports](#daemonset-with-host-ports)):

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
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true"
```

**_NOTE_**: With helm `--set` it is needed to put quotes and escape dots in the annotation key and commas in the value string. Use `--set-string` for values such as `true` or numbers, which `--set` turns into a boolean or integer that Kubernetes rejects as an annotation value.

### Installing with LoadBalancer IP

When using a LoadBalancer service type, you can request a specific IP address (provider-dependent):

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP="203.0.113.10"
```

Or using a values file:

```yaml
controller:
  service:
    type: LoadBalancer
    loadBalancerIP: "203.0.113.10"
```

**_NOTE_**: Not all cloud providers support this field. Refer to your cloud provider's documentation for LoadBalancer IP allocation.

**_NOTE_**: `loadBalancerIP` is deprecated as of Kubernetes 1.24 in favour of provider-specific annotations. To select a particular load balancer implementation, prefer `loadBalancerClass` below.

### Selecting a LoadBalancer implementation

When more than one load balancer controller runs in a cluster, `loadBalancerClass` picks which one reconciles the Service. Leaving it unset uses the cluster's default implementation. Available since chart `1.2.0`.

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerClass="example.com/internal-lb"
```

Or using a values file, together with a source IP allowlist:

```yaml
controller:
  service:
    type: LoadBalancer
    loadBalancerClass: example.com/internal-lb
    loadBalancerSourceRanges:
      - 192.0.2.0/24
      - 198.51.100.0/24
```

| Key | Description | Default |
|---|---|---|
| `controller.service.loadBalancerIP` | Requested LB IP (provider-dependent, deprecated since Kubernetes 1.24). | `""` |
| `controller.service.loadBalancerSourceRanges` | CIDR allowlist for the LB. | `[]` |
| `controller.service.loadBalancerClass` | `LoadBalancerClass` selecting the LB implementation. | `null` |

All three fields render only when `controller.service.type` is `LoadBalancer`.

**_NOTE_**: `loadBalancerClass` is immutable while the Service stays type `LoadBalancer`. Kubernetes rejects a change on an existing Service, so `helm upgrade` cannot alter it in place - the Service has to be recreated (for example by deleting it and re-running the upgrade).

**_NOTE_**: `loadBalancerSourceRanges` is only enforced by providers that implement it; check your provider's documentation before relying on it as a security control.

### Installing with Horizontal Pod Autoscaler (HPA)

[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) automatically scales number of replicas in Deployment and adjusts replica count for the controller:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set controller.autoscaling.enabled=true
```

### Enabling Prometheus monitoring

HUG exposes two separate metrics endpoints:

- **`stat`** (port 31024) — HAProxy native metrics (`haproxy_*` prefix): connections, request rates, backend health, latency, error codes ([reference](https://www.haproxy.com/documentation/haproxy-unified-gateway/administration/prometheus-metrics/haproxy-stats-metrics/))
- **`metrics`** (port 31060) — HUG controller metrics (`hug_*` prefix): event batch processing, config generation, cert/map operations, HAProxy reloads ([reference](https://www.haproxy.com/documentation/haproxy-unified-gateway/administration/prometheus-metrics/controller-metrics/))

The chart supports both [ServiceMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/getting-started/introduction.md) and [PodMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/getting-started/design.md#podmonitor) for Prometheus Operator integration. These are mutually exclusive — enable only one (the chart fails at render when both are enabled). The default ServiceMonitor endpoints scrape both; the default PodMonitor endpoints scrape only `stat` (see [below](#using-podmonitor-instead-of-servicemonitor)). Enabling the ServiceMonitor also creates a ClusterIP metrics Service (`<fullname>-metrics`) exposing `stat` and `metrics`; it requires `controller.service.enabled`.

**Note:** HAProxy serves the `stat` endpoint only once the controller has programmed its first Gateway; until then that scrape target is down. The chart passes `--stats-port` from `controller.containerPort.stat`, so change the port there rather than through `extraArgs`.

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

**Step 2.** Enable the ServiceMonitor. The default endpoints are pre-configured for kube-rbac — `stat` uses plain HTTP, `metrics` uses HTTPS with the Prometheus pod's ServiceAccount token:

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

The Secret `hug-metrics-basic-auth` (keys `username` and `password`) is not created by the chart; create it in the release namespace first.

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

To keep the password out of the pod arguments, the controller also reads the credentials from the `METRICS_BASIC_AUTH_USER` and `METRICS_BASIC_AUTH_PASSWORD` environment variables; set them from the same Secret instead of the two `extraArgs`:

```yaml
controller:
  extraEnvs:
    - name: METRICS_BASIC_AUTH_USER
      valueFrom:
        secretKeyRef:
          name: hug-metrics-basic-auth
          key: username
    - name: METRICS_BASIC_AUTH_PASSWORD
      valueFrom:
        secretKeyRef:
          name: hug-metrics-basic-auth
          key: password
```

#### Using PodMonitor instead of ServiceMonitor

PodMonitor scrapes pods directly without creating an extra metrics Service. A PodMonitor has no `bearerTokenFile`, so it cannot use the Prometheus ServiceAccount token the way the kube-rbac ServiceMonitor does, and its default endpoints therefore scrape only `stat`:

```yaml
controller:
  podMonitor:
    enabled: true
    extraLabels:
      release: prometheus
```

To also scrape the controller `metrics` endpoint with a PodMonitor, use `metricsAuth: none` or `basic` and put the endpoints of the corresponding example above under `podMonitor` instead of `serviceMonitor`. For kube-rbac, use the ServiceMonitor.

### Configuring HugConf

The chart creates a HugConf custom resource for controller configuration (a `post-install` / `pre-upgrade` hook that runs after the CRD job) and passes it to the controller as `--hugconf-crd=<namespace>/<hugconf.name>`. You can customize logging, and optionally reference Global and Defaults custom resources:

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

The Global and Defaults CRDs are automatically installed by the CRD job. When a `globalRef` or `defaultsRef` is set, the controller uses the referenced CR to configure the HAProxy global/defaults sections. When removed, built-in defaults are restored. The fields, log categories and levels are described in the official [HugConf](https://www.haproxy.com/documentation/haproxy-unified-gateway/configuration-reference/hugconf-crd/), [Global](https://www.haproxy.com/documentation/haproxy-unified-gateway/configuration-reference/global-crd/) and [Defaults](https://www.haproxy.com/documentation/haproxy-unified-gateway/configuration-reference/defaults-crd/) references.

To manage the HugConf yourself, set `hugconf.create=false` and point `controller.hugconfCrd` at it (`namespace/name`); with both unset the controller gets no `--hugconf-crd` flag.

### Adding extra ports

By default the chart exposes four container ports: `http` (31080), `https` (31443), `stat` (31024) and `metrics` (31060). Additional ports can be added in two places:

1. **`controller.containerPort`** — exposes the port on the container (pod spec)
2. **`controller.service.extraPorts`** — exposes the port on the Service

> **Gateway listener ports do not go here.** For every Gateway listener (for example HTTP, HTTPS or TCP), the controller adds a Service port named `<protocol>-<port>` with `targetPort` equal to the listener port and allocates its own NodePort. In `kubectl get svc`, `31090:30941/TCP` means service port 31090 and NodePort 30941; it is not a container port. Listing the same port in `extraPorts` makes `helm upgrade` fail under server-side apply with `conflict with "hug" ... .spec.ports[port=31090,protocol="TCP"].name`. No `containerPort` entry is needed either, because HAProxy listens on the listener port whether or not it is declared in the pod spec. Use these options only for ports that are not Gateway listeners.

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

Flags of the HUG 1.1.1 controller (`/usr/local/sbin/hug --help`, see also [controller options](https://github.com/haproxytech/haproxy-unified-gateway/blob/v1.1.1/documentation/controller-options.md)):

| Flag | Default | Description |
| --- | --- | --- |
| `--controller-name` | `gate.haproxy.org/hug` | `spec.controllerName` GatewayClass selector |
| `--gateway-ns-name` | | Only watch the Gateway with this `namespace/name`; otherwise all Gateways |
| `--hug-service-label` | `app.kubernetes.io/name:haproxy-unified-gateway` | `key:value` label identifying the HUG Service the controller adds listener ports to |
| `--namespaces` | | Comma-separated list of namespaces to monitor |
| `--ipv4-bind-address` | | IPv4 address to bind to |
| `--ipv6-bind-address` | | IPv6 address to bind to |
| `--disable-ipv4` | `false` | Disable IPv4 support |
| `--disable-ipv6` | `false` | Disable IPv6 support |
| `--accept-proxy` | `false` | Set `accept-proxy` on the Gateway listener binds, for a load balancer in front that sends the PROXY protocol header |
| `--stats-port` | `1024` | Port for HAProxy stats. **Set by the chart** from `controller.containerPort.stat` (`31024`) |
| `--controller-port` | `31060` | Port for controller metrics (prometheus) |
| `--add-stats-port` | `true` | Add stats port bind to existing stats frontend |
| `--log-type` | `json` | Log output type (`text` or `json`) |
| `--sync-period` | `0` | Period at which the controller computes HAProxy configuration (e.g. `5s`, `1m`) |
| `--startup-sync-period` | `0` | Startup period for HAProxy config computation |
| `--cache-resync-period` | `0` | Controller-runtime manager cache SyncPeriod (defaults to 10 hours if not set) |
| `--leader-election-enabled` | `false` | Enable leader election |
| `--force-restart-haproxy` | `false` | Force an HAProxy restart at controller startup |
| `--gwapi-compat` | `false` | Gateway API compatibility: a matched HTTPRoute rule that cannot forward (no or invalid backendRefs) responds 500 instead of 404 (also enabled by the `GWAPI_COMPAT` env var) |
| `--metrics-auth` | `none` | Metrics endpoint auth mode: `none`, `kube-rbac`, `basic`. **Set by the chart** from `controller.metricsAuth` (`kube-rbac`) |
| `--metrics-basic-auth-user` | | Basic auth username (when `--metrics-auth=basic`) |
| `--metrics-basic-auth-password` | | Basic auth password (when `--metrics-auth=basic`) |
| `--enable-ingress` | `false` | Enable Kubernetes Ingress support, see [Kubernetes Ingress support](#kubernetes-ingress-support) |
| `--ingress-class` | | IngressClass controller suffix this instance handles (empty matches controller `haproxy.org/ingress-controller`) |
| `--empty-ingress-class` | `false` | With `--ingress-class`, also handle Ingresses that have no `ingressClassName` |
| `--disable-ingress-status-update` | `false` | Do not write `status.loadBalancer` back onto managed Ingresses |
| `--http-ingress-frontend-port` / `--https-ingress-frontend-port` | | Ports of the HTTP / HTTPS frontends dedicated to Ingress |

**Note:** `--hugconf-crd`, `--metrics-auth` and `--stats-port` are set by the chart (from `controller.hugconfCrd` or the chart's HugConf, `controller.metricsAuth` and `controller.containerPort.stat`); do not repeat them in `extraArgs`. The `--job-check-crd` and `--job-gwapi` flags are used internally by the CRD/Gateway API installation jobs.

### Kubernetes Ingress support

The controller can also serve Kubernetes Ingress resources, translating them onto a synthetic Gateway. It is disabled by default; enable it with:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set 'controller.extraArgs={--enable-ingress}'
```

The chart's ClusterRole already grants the access it needs (Ingresses, IngressClasses and Ingress status, since chart `1.3.5`). Without `--ingress-class`, the controller handles IngressClasses with `controller: haproxy.org/ingress-controller`:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: haproxy
spec:
  controller: haproxy.org/ingress-controller
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo
spec:
  ingressClassName: haproxy
  rules:
    - host: echo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echo
                port:
                  number: 8080
```

As with Gateway listeners, the controller adds the Ingress frontend port to the chart's Service (as `http-<port>`) and writes the address into the Ingress `status.loadBalancer`.

### Installing with KEDA autoscaling

[KEDA](https://keda.sh/) provides event-driven autoscaling. It is mutually exclusive with HPA — when KEDA is enabled, HPA is automatically disabled even if `autoscaling.enabled` is set to `true`. The ScaledObject is only created with `controller.kind: Deployment`, and `controller.keda.triggers` must not be empty (the chart fails at render otherwise).

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

### CRD and Gateway API installation jobs

By default, the chart runs two `post-install` / `pre-upgrade` hook Jobs: `crdjob` installs and upgrades the HUG CRDs (`gate.v3.haproxy.org`), and `gwapijob` installs the Gateway API CRDs of version `gwapijob.version`. On the very first install the controller starts before these Jobs have run, so it logs `if kind is a CRD, it should be installed before calling Start` errors for a few seconds until the CRDs exist; this is expected and it recovers on its own.

**_NOTE_**: `gwapijob.version` defaults to the Gateway API version the controller release (`appVersion`) supports, and each HUG release accepts only specific versions. Any other value fails the Job, and with it `helm install`, with `unsupported Gateway API version "vX.Y.Z", supported: [...]`. The chart's default controller (HUG 1.1.1) accepts only Gateway API `1.7.0`. Only change it together with `controller.image.tag`.

To disable the Jobs, for example when the CRDs are managed separately:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --set crdjob.enabled=false \
  --set gwapijob.enabled=false
```

## Configuration

The full set of supported values is defined in [`values.yaml`](values.yaml), which also carries inline documentation. To print the defaults of the chart version you have:

```console
helm show values haproxytech/haproxy-unified-gateway
```

### Global

| Key | Description | Default |
|---|---|---|
| `rbac.create` | Create the controller ClusterRole and ClusterRoleBinding. | `true` |
| `namespace.create` | Create the `namespaceOverride` namespace (do **not** combine with `helm install --create-namespace`). Requires `namespaceOverride`; the release namespace (`helm install -n`) must already exist, as Helm stores the release there. | `false` |
| `namespaceOverride` | Override `.Release.Namespace` for all resources (umbrella/combined charts, `namespace.create`). | _unset_ |
| `nameOverride` / `fullnameOverride` | Replace the chart name / the full generated name of all resources. `nameOverride` also changes the `app.kubernetes.io/name` label that the controller's `--hug-service-label` matches by default, so pass `--hug-service-label=app.kubernetes.io/name:<nameOverride>` in `controller.extraArgs` with it. | _unset_ |
| `serviceAccount.create` | Create the controller ServiceAccount. | `true` |
| `serviceAccount.name` | ServiceAccount name (generated when empty). | `""` |
| `serviceAccount.annotations` | ServiceAccount annotations. | `{}` |

### Controller

| Key | Description | Default |
|---|---|---|
| `controller.kind` | `Deployment` or `DaemonSet`. | `Deployment` |
| `controller.replicaCount` | Replicas (Deployment only; not rendered with `autoscaling.enabled`, and overridden by KEDA's HPA). | `1` |
| `controller.image.repository` / `.tag` / `.pullPolicy` | Controller image (`tag` defaults to the chart `appVersion`). | `docker.io/haproxytech/haproxy-unified-gateway` / `""` / `IfNotPresent` |
| `controller.imagePullSecrets` | Pull Secrets for the controller and Job pods. | `[]` |
| `controller.hugconfCrd` | HugConf reference (`namespace/name`) passed as `--hugconf-crd`; empty uses the chart's HugConf, `<namespace>/<hugconf.name>` (no flag at all when `hugconf.create` is also `false`). | `""` |
| `controller.metricsAuth` | Metrics endpoint auth: `none`, `kube-rbac` or `basic`. | `kube-rbac` |
| `controller.extraArgs` | Extra controller flags, see [Available controller flags](#available-controller-flags). | `[]` |
| `controller.containerPort` | Container ports; `stat` is also passed as `--stats-port`. | `http: 31080`, `https: 31443`, `stat: 31024`, `metrics: 31060` |
| `controller.resources` | Requests and limits, see [Memory limits and sizing](#memory-limits-and-sizing). | `requests: cpu 250m, memory 2048Mi`, `limits.memory: 2560Mi` |
| `controller.unprivileged` | Run as non-root (UID/GID 1000), dropping all capabilities except `NET_BIND_SERVICE`. When `false`, no container security context is rendered. | `true` |
| `controller.allowPrivilegeEscalation` | Container `allowPrivilegeEscalation` (only with `unprivileged`). | `false` |
| `controller.seccompProfile` | Seccomp profile (only with `unprivileged`; `{}` disables it). | `type: RuntimeDefault` |
| `controller.podSecurityContext` | Pod security context, merged over the non-root defaults. | `{}` |
| `controller.livenessProbe` / `.readinessProbe` / `.startupProbe` | Probe definitions, rendered as given. The chart sets no probes by default. | `{}` |
| `controller.strategy` | Deployment `strategy`, or DaemonSet `updateStrategy` with `kind: DaemonSet`. | `type: RollingUpdate` |
| `controller.priorityClassName` | `PriorityClass` of the pods. | `""` |
| `controller.nodeSelector` / `.tolerations` / `.affinity` | Pod placement. | `{}` / `[]` / `{}` |
| `controller.topologySpreadConstraints` | Topology spread constraints. | `[]` |
| `controller.dnsPolicy` / `.dnsConfig` | Pod DNS policy (`ClusterFirstWithHostNet` with host networking) and config. | `""` / `{}` |
| `controller.extraEnvs` | Extra `env` entries. | `[]` |
| `controller.extraVolumes` / `.extraVolumeMounts` | Extra volumes and mounts. | `[]` |
| `controller.initContainers` / `.extraContainers` | Extra init and sidecar containers. | `[]` |
| `controller.podAnnotations` / `.podLabels` | Metadata on the pod template. | `{}` |
| `controller.extraLabels` | Extra labels on the Deployment/DaemonSet. | `{}` |
| `controller.daemonset.useHostNetwork` / `.useHostPort` | DaemonSet host networking / host ports. | `false` |
| `controller.daemonset.hostIP` | Host IP to bind host ports to. | `null` |
| `controller.daemonset.hostPorts` | Host ports by container port name. | `http: 80`, `https: 443`, `stat: 1024`, `metrics: 31060` |

### Service

| Key | Description | Default |
|---|---|---|
| `controller.service.enabled` | Render the Service the controller adds listener ports to. | `true` |
| `controller.service.type` | `ClusterIP`, `NodePort` or `LoadBalancer`. | `NodePort` |
| `controller.service.annotations` / `.labels` | Service metadata. | `{}` |
| `controller.service.externalTrafficPolicy` | `Cluster` or `Local`. | `""` |
| `controller.service.loadBalancerIP` / `.loadBalancerSourceRanges` / `.loadBalancerClass` | LoadBalancer settings, see [Selecting a LoadBalancer implementation](#selecting-a-loadbalancer-implementation). | `""` / `[]` / `null` |
| `controller.service.stat.port` / `.targetPort` / `.nodePort` | Stats Service port. | `31024` / `31024` / `""` |
| `controller.service.extraPorts` | Extra Service ports; never Gateway listener ports, see [Adding extra ports](#adding-extra-ports). | `[]` |
| `controller.service.controller-metrics.port` / `.targetPort` | Controller metrics port on the metrics Service. | `31060` / `31060` |
| `controller.service.metrics.type` / `.annotations` / `.labels` | Metrics Service with the `stat` and `metrics` ports (created with `serviceMonitor.enabled` and `service.enabled`). | `ClusterIP` / `{}` / `{}` |

### Monitoring, autoscaling and disruption

| Key | Description | Default |
|---|---|---|
| `controller.serviceMonitor.enabled` | Create a ServiceMonitor and the metrics Service. | `false` |
| `controller.podMonitor.enabled` | Create a PodMonitor (mutually exclusive with `serviceMonitor`). | `false` |
| `controller.serviceMonitor.extraLabels` / `controller.podMonitor.extraLabels` | Labels for the Prometheus Operator selector. | `{}` |
| `controller.serviceMonitor.nameOverride` / `controller.podMonitor.nameOverride` | Name of the ServiceMonitor / PodMonitor (defaults to the full generated name). | _unset_ |
| `controller.serviceMonitor.endpoints` | Scrape endpoints: `stat` over HTTP, `metrics` over HTTPS with the Prometheus ServiceAccount token (kube-rbac). | see `values.yaml` |
| `controller.podMonitor.endpoints` | Scrape endpoints: `stat` only (a PodMonitor cannot send the kube-rbac token). | `stat`, `/metrics`, `30s` |
| `controller.autoscaling.enabled` | Create an HPA (not with KEDA). | `false` |
| `controller.autoscaling.minReplicas` / `.maxReplicas` | HPA bounds. | `1` / `10` |
| `controller.autoscaling.targetCPUUtilizationPercentage` | CPU target, measured against `resources.requests.cpu`. | `80` |
| `controller.autoscaling.targetMemoryUtilizationPercentage` | Memory target. | _unset_ |
| `controller.keda.enabled` | Create a KEDA ScaledObject (Deployment only). | `false` |
| `controller.keda.minReplicas` / `.maxReplicas` | KEDA bounds. | `2` / `20` |
| `controller.keda.pollingInterval` / `.cooldownPeriod` | KEDA timing. | `30` / `300` |
| `controller.keda.restoreToOriginalReplicaCount` | Restore the replica count when the ScaledObject is removed. | `false` |
| `controller.keda.fallback` / `.horizontalPodAutoscalerConfig` / `.scaledObject.annotations` | Fallback, HPA config and ScaledObject annotations. | _unset_ / `{}` / `{}` |
| `controller.keda.triggers` | KEDA triggers (required with `keda.enabled`). | `[]` |
| `controller.podDisruptionBudget.enabled` | Create a PodDisruptionBudget (`minAvailable: 1` unless set). | `false` |
| `controller.podDisruptionBudget.minAvailable` / `.maxUnavailable` | PDB constraint (`maxUnavailable` wins when both are set). | _unset_ |

### HugConf

| Key | Description | Default |
|---|---|---|
| `hugconf.create` | Create the HugConf custom resource (`post-install` / `pre-upgrade` hook) and the `pre-delete` Job that removes it on uninstall. | `true` |
| `hugconf.name` | HugConf name. | `hugconf` |
| `hugconf.logging.defaultLevel` | Default log level. | `Info` |
| `hugconf.logging.categoryLevelList` | Per-category log levels (`k8s` and `batch` at `Error`). | see `values.yaml` |
| `hugconf.globalRef` / `hugconf.defaultsRef` | References to Global / Defaults custom resources, see [Configuring HugConf](#configuring-hugconf). | `{}` |

### CRD and Gateway API jobs

| Key | Description | Default |
|---|---|---|
| `crdjob.enabled` / `gwapijob.enabled` | Run the HUG CRD / Gateway API CRD Job. | `true` |
| `gwapijob.version` | Gateway API version to install; must be one the controller release supports. | `1.7.0` |
| `crdjob.ttlSecondsAfterFinished` / `gwapijob.ttlSecondsAfterFinished` | Seconds before a finished Job is removed. | `60` |
| `crdjob.resources` / `gwapijob.resources` | Job container resources. | `{}` |
| `crdjob.image` / `gwapijob.image` | Image override (`repository`, `tag`); defaults to the controller image. `tag` is used only with `repository` and defaults to the chart `appVersion`. | `{}` |
| `crdjob.podAnnotations` / `gwapijob.podAnnotations` | Annotations on the Job and its pod. | `{}` |
| `crdjob.nodeSelector` / `.tolerations` / `.affinity` (same for `gwapijob`) | Job pod placement. | `{}` / `[]` / `{}` |

## Memory limits and sizing

The controller image runs HAProxy and the controller under a supervisor that
sizes both from **the memory available to the container**: HAProxy is given
about 66% of it, and the controller's `GOMEMLIMIT` about 33%. The memory limit
is therefore not only a cap, it is the input to that calculation.

The chart ships a limit for that reason:

```yaml
controller:
  resources:
    limits:
      memory: 2560Mi
    requests:
      cpu: 250m
      memory: 2048Mi
```

which gives HAProxy roughly 1.7 GB and the controller roughly 850 MB.

No CPU *limit* is set, so the container is never throttled, but a
`requests.cpu` of `250m` is kept: a CPU request is a scheduling floor rather
than a cap, and the HPA measures `targetCPUUtilizationPercentage` against it,
so without it the chart's default CPU-based autoscaling has no utilisation
figure to read.

With `controller.kind: DaemonSet` the memory request is reserved on **every
node** the DaemonSet covers, so budget accordingly on large clusters.

If you remove the limit, the memory available to the container becomes the
node's total memory, and every replica sizes itself to the whole node no
matter how small its request is. The controller's garbage collector then
reclaims far later than the workload warrants, and with no pod-level ceiling
the node's OOM killer chooses a victim under pressure, possibly an unrelated
workload, instead of this pod being restarted against its own limit. The chart
prints a warning after install when that is the case.

There is no single correct value, since a small Gateway configuration and one
with large maps or many routes have very different needs. Size the limit for
your configuration. Setting `controller.resources` replaces the whole block,
so a limit you set yourself always wins.

The CRD and Gateway API Jobs (`crdjob.resources`, `gwapijob.resources`) are
unset by default. They are short-lived and only install CRDs, but they run the
same image, so set limits on them too if your policy requires every container
to have one.

## Upgrading the chart

To upgrade the _my-release_ deployment:

```console
helm upgrade my-release haproxytech/haproxy-unified-gateway
```

## Uninstalling the chart

To uninstall/delete the _my-release_ deployment:

```console
helm uninstall my-release
```

With `hugconf.create` (the default), a pre-delete hook Job removes the chart's HugConf first. The HUG and Gateway API CRDs installed by the Jobs are kept, so other Gateway API controllers and your Gateways, Routes and HUG custom resources survive; delete the CRDs by hand to remove them and every resource of those kinds.

## Debugging

It is possible to generate a set of YAML files for testing/debugging:

```console
helm install my-release haproxytech/haproxy-unified-gateway \
  --debug \
  --dry-run
```

## Contributing

We welcome all contributions. Please refer to [guidelines](../CONTRIBUTING.md) on how to make a contribution.
