# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Helm Chart

## Introduction

This chart bootstraps an HAProxy load balancer as deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. As opposed to [HAProxy Kubernetes Ingress Controller](https://github.com/haproxytech/helm-charts/tree/main/kubernetes-ingress) Chart, HAProxy is installed as a regular application and not as an Ingress Controller.

### Prerequisites

- Kubernetes 1.17+ (recommended 1.20+)
- Helm 3.6+ (recommended 3.7+)

## Before you begin

### Setup a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](https://kubernetes.io/docs/setup/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Add Helm chart repo

Once you have Helm installed, add the haproxytech Chart Repository as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
```

Alternatively if you want to proceed with just OCI-based repository, skip this step and follow the installation with OCI.

## Install the chart

To install the chart as _my-release_ deployment:

```console
helm install my-release haproxytech/haproxy
```

Alternatively also have OCI-based repository available for simplified access (add `--version X.Y.Z` to pin a chart version):

```console
helm install my-release oci://ghcr.io/haproxytech/helm-charts/haproxy
```

### Installing with unique name

To auto-generate resource names when installing, use the following:

```console
helm install haproxytech/haproxy \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for HAProxy (for instance to use a HAProxy Enterprise image) into a separate namespace _prod_.

**_NOTE_**: The namespace must exist; add `--create-namespace` to have Helm create it (eg. instead of `kubectl create namespace prod`)

```console
helm install my-haproxy haproxytech/haproxy  \
  --namespace prod \
  --create-namespace \
  --set image.tag=latest \
  --set image.repository=myregistry.domain.com/imagename \
  --set imageCredentials.registry=myregistry.domain.com \
  --set imageCredentials.username=MYUSERNAME \
  --set imageCredentials.password=MYPASSWORD
```

Alternatively, use a pre-configured (existing) imagePullSecret in the same namespace:

```console
helm install my-haproxy haproxytech/haproxy  \
  --namespace prod \
  --set image.tag=SOMETAG \
  --set existingImagePullSecret=name-of-existing-image-pull-secret
```

**_NOTE_**: Enterprise images using S6 overlay need default CMD arguments disabled (more about YAML configuration file for Helm can be found in a separate paragraph below):

```yaml
args:
  enabled: false
```

### Installing as DaemonSet

Default image mode is [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), but it is possible to use [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) as well:

```console
helm install my-haproxy2 haproxytech/haproxy \
  --set kind=DaemonSet
```

### Installing with Horizontal Pod Autoscaler

[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) automatically scales number of replicas in a Deployment. When autoscaling (or KEDA) is enabled the chart leaves `replicas` unset, so the HPA owns the replica count and `replicaCount` is ignored:

```console
helm install my-haproxy3 haproxytech/haproxy \
  --set kind=Deployment \
  --set autoscaling.enabled=true \
  --set autoscaling.targetCPUUtilizationPercentage=80
```

**_NOTE_**: Make sure to look into other tunable values for HPA documented in [values.yaml](values.yaml).

### Installing with service annotations

On some environments like EKS and GKE there might be a need to pass service annotations. Syntax can become a little tedious however:

```console
helm install my-haproxy4 haproxytech/haproxy \
  --set kind=DaemonSet \
  --set service.type=LoadBalancer \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="0.0.0.0/0" \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true"
```

**_NOTE_**: With helm `--set` it is needed to put quotes and escape dots in the annotation key and commas in the value string.

### Selecting a LoadBalancer implementation

When more than one load balancer controller runs in a cluster, `service.loadBalancerClass` picks which one reconciles the Service. Leaving it unset uses the cluster's default implementation:

```console
helm install my-haproxy5 haproxytech/haproxy \
  --set service.type=LoadBalancer \
  --set service.loadBalancerClass="example.com/internal-lb" \
  --set service.loadBalancerSourceRanges[0]="192.0.2.0/24"
```

**_NOTE_**: `loadBalancerClass` renders only when `service.type` is `LoadBalancer` and the cluster is Kubernetes 1.21 or newer (the field is GA as of 1.24). On older clusters it is omitted.

**_NOTE_**: `loadBalancerClass` is immutable while the Service stays type `LoadBalancer`. Kubernetes rejects a change on an existing Service, so `helm upgrade` cannot alter it in place - the Service has to be recreated.

### Using values from YAML file

As opposed to using many `--set` invocations, much simpler approach is to define value overrides in a separate YAML file and specify them when invoking Helm.
The `config` block can also support using helm templates to populate dynamic values, e.g. `{{ .Release.Name }}` or a value of your own such as `{{ .Values.global.serverTimeout }}` below.

_mylb.yaml_:

```yaml
kind: DaemonSet
global:
  serverTimeout: 60s
config: |
  global
    log stdout format raw local0
    daemon
    maxconn 1024
  defaults
    log global
    timeout client 60s
    timeout connect 60s
    timeout server {{ .Values.global.serverTimeout }}
  frontend fe_main
    bind :80
    default_backend be_main
  backend be_main
    server web1 10.0.0.1:8080 check
    server web2 {{ .Release.Name }}-web:8080 check
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
```

And invoking Helm becomes (compare to the previous example):

```console
helm install my-haproxy5 -f mylb.yaml haproxytech/haproxy
```

### Using secrets in additional volume mounts

In order to e.g. support SSL certificates, you can mount additional volumes from secrets:

_mylb.yaml_:

```yaml
service:
  type: LoadBalancer
config: |
  global
    log stdout format raw local0
    daemon
    maxconn 1024
    ssl-load-extra-del-ext
  defaults
    log global
    timeout client 60s
    timeout connect 60s
    timeout server 60s
  frontend fe_main
    mode http
    bind :80
    bind :443 ssl crt /usr/local/etc/ssl/tls.crt
    http-request redirect scheme https code 301 unless { ssl_fc }
    default_backend be_main
  backend be_main
    mode http
    server web1 10.0.0.1:8080 check
mountedSecrets:
  - volumeName: ssl-certificate
    secretName: star-example-com
    mountPath: /usr/local/etc/ssl
```

The above example assumes a TLS Secret called `star-example-com` (for example created with `kubectl create secret tls star-example-com --cert=... --key=...`), which holds the certificate in key `tls.crt` and the private key in key `tls.key`. HAProxy looks for a key that is not in the certificate file at `<file>.key`, i.e. `tls.crt.key`; `ssl-load-extra-del-ext` makes it look for `tls.key` instead, so the Secret can be mounted as is.

### Using additional volumes and volumeMounts

In order to load data from other sources (e.g. to preload something inside an init-container) you can mount additional volumes to the container:

```yaml
extraVolumes:
  - name: tls
    emptyDir: {}
  - name: tmp
    emptyDir:
      medium: Memory

extraVolumeMounts:
  - name: tls
    mountPath: /etc/tls
  - name: tmp
    mountPath: /tmp
```

### Using additional environment variables

In order to expose extra data (e.g. node and pod IP addresses) to haproxy, you can populate extra environment variables on the container:

```yaml
extraEnvs:
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
```

### Automatic configuration reloading

In some cases, configuration changes are frequent and constantly restarting HAProxy is not optimal. For those cases the HAProxy hot-reload feature
can be used.

In master-worker mode, sending a USR2 signal to the HAProxy process will trigger a configuration reload.

```yaml
config: |
  global
    log stdout format raw local0
    master-worker
    daemon
    maxconn 1024
  defaults
    log global
    timeout client 60s
    timeout connect 60s
    timeout server 60s
  frontend fe_main
    mode http
    bind :80
    default_backend be_main
  backend be_main
    mode http
    server web1 10.0.0.1:8080 check
```

Make sure you are not specifying subPath for any of your volumeMounts so that Kubernetes will automatically update the volumes created from
ConfigMaps.

And finally, use some sidecar container which will be delivering the signal to the process. The shareProcessNamespace Pod property is required
for the sidecars to be able to access other containers' processes.

```yaml
shareProcessNamespace:
  enabled: true
sidecarContainers:
  - name: reflex
    image: acim/go-reflex:1.17.3
    command: ["reflex", "-d", "fancy"]
    workingDir: /usr/local/etc/haproxy
    args:
      - -svr
      - "..data"
      - --
      - bash
      - -c
      - 'pkill -SIGUSR2 "haproxy|hapee-lb"'
    volumeMounts:
      - name: haproxy-config
        mountPath: /usr/local/etc/haproxy
    resources:
      limits:
        memory: 128Mi
      requests:
        cpu: 50m
        memory: 64Mi
```

## Installing as non-root with binding to privileged ports

To bind privileged ports such as tcp/80 and tcp/443 without root privileges (UID and GID are set to 1000 in the examples, as the HAProxy Docker image has UID/GID 1000 reserved for HAProxy), lower the start of the unprivileged port range for the pod. `net.ipv4.ip_unprivileged_port_start` is a namespaced, [safe sysctl](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/) since Kubernetes 1.22, so it can be set through `podSecurityContext` without any privileged container:

```yaml
podSecurityContext:
  sysctls:
    - name: net.ipv4.ip_unprivileged_port_start
      value: "0"
securityContext:
  enabled: true
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

With `daemonset.useHostNetwork: true` the pod shares the node's network namespace, where Kubernetes does not allow pod sysctls. The only option there is a privileged init container, and it changes the setting **for the whole node**, not just for HAProxy:

```yaml
kind: DaemonSet
containerPorts:
  http: 80
  https: 443
  stat: 1024
daemonset:
  useHostNetwork: true
  useHostPort: true
  hostPorts:
    http: 80
    https: 443
    stat: 1024
dnsPolicy: ClusterFirstWithHostNet
config: |
  global
    log stdout format raw local0
    maxconn 1024
  defaults
    log global
    timeout client 60s
    timeout connect 60s
    timeout server 60s
  frontend fe_main
    bind :80
    default_backend be_main
  backend be_main
    server web1 127.0.0.1:8080 check
securityContext:
  enabled: true
  runAsUser: 1000
  runAsGroup: 1000
initContainers:
  - name: sysctl
    image: "busybox:musl"
    command:
      - /bin/sh
      - -c
      - sysctl -w net.ipv4.ip_unprivileged_port_start=0
    securityContext:
      privileged: true
```

## Memory limits

The chart sets memory and CPU **requests** but no limits by default:

```yaml
resources:
  requests:
    cpu: 250m
    memory: 128Mi
```

A request only influences scheduling. Without a limit the container may use as
much memory as the node has, and under memory pressure the node's OOM killer
chooses which pod to evict, which may be an unrelated workload, instead of
this pod being restarted against a ceiling of its own. A limit also contains
runaway growth, such as stick tables or maps growing unchecked.

How much HAProxy needs depends entirely on its configuration: buffers,
concurrent connections, stick table size, map and ACL files, and SSL session
caches all contribute. Size a limit against your own configuration under load,
for example:

```yaml
resources:
  limits:
    memory: 256Mi
  requests:
    cpu: 250m
    memory: 128Mi
```

Note that this chart runs the `haproxytech/haproxy-alpine` image, which starts
HAProxy directly. The limit is a cap and nothing more. This differs from the
`kubernetes-ingress` and `haproxy-unified-gateway` charts, whose image derives
HAProxy's and the controller's memory budgets *from* the container limit, so
that leaving it unset changes how those processes size themselves.

## Prometheus monitoring

HAProxy has a built-in [Prometheus exporter](https://github.com/haproxy/haproxy/blob/master/addons/promex/README), which needs a frontend in `config`. The default `serviceMonitor.endpoints` scrape a Service port named `prometheus`; a `containerPorts` entry of that name creates both the container port and the Service port:

```yaml
containerPorts:
  prometheus: 8405
serviceMonitor:
  enabled: true
  extraLabels:
    release: prometheus   # match your Prometheus serviceMonitorSelector
config: |
  global
    log stdout format raw local0
    maxconn 1024
  defaults
    log global
    timeout client 60s
    timeout connect 60s
    timeout server 60s
  frontend prometheus
    mode http
    bind :8405
    http-request use-service prometheus-exporter if { path /metrics }
    no log
  frontend fe_main
    bind :80
    default_backend be_main
  backend be_main
    server web1 10.0.0.1:8080 check
```

The ServiceMonitor is only rendered when the `monitoring.coreos.com/v1` API (Prometheus Operator) is available.

## Configuration

The full set of supported values is defined in [`values.yaml`](values.yaml), which also carries inline documentation. To print the defaults of the chart version you have:

```console
helm show values haproxytech/haproxy
```

### Global

| Key | Description | Default |
|---|---|---|
| `nameOverride` / `fullnameOverride` | Replace the chart name / the full generated name of all resources. | _unset_ |
| `namespaceOverride` | Override `.Release.Namespace` for all resources (useful when this chart is a dependency). | _unset_ |
| `rbac.create` | Create the Role and RoleBinding that let the pods use the PodSecurityPolicy (only with `podSecurityPolicy.enabled` on Kubernetes &lt; 1.25). | `true` |
| `serviceAccount.create` | Create a ServiceAccount. | `true` |
| `serviceAccount.name` | ServiceAccount name (generated when empty; `default` when `serviceAccount.create` is `false`). | _unset_ |
| `serviceAccount.annotations` | ServiceAccount annotations. | `{}` |
| `serviceAccount.automountServiceAccountToken` | Mount the ServiceAccount token into the pods. | `true` |
| `podSecurityPolicy.enabled` | Create a PodSecurityPolicy (Kubernetes &lt; 1.25 only; PSP was removed in 1.25). Also needs `rbac.create`. | `false` |
| `podSecurityPolicy.annotations` / `.allowedUnsafeSysctls` | PSP annotations and allowed unsafe sysctls. | `{}` / _unset_ |

### Image and workload

| Key | Description | Default |
|---|---|---|
| `image.repository` | HAProxy image (switch to use CE/EE images). | `docker.io/haproxytech/haproxy-alpine` |
| `image.tag` | Image tag (defaults to the chart `appVersion`). | `""` |
| `image.pullPolicy` | Image pull policy. | `IfNotPresent` |
| `imageCredentials.registry` / `.username` / `.password` | Credentials for a private registry; the chart creates the pull Secret. | `null` |
| `existingImagePullSecret` | Name of an existing pull Secret to use instead. | `null` |
| `kind` | `Deployment` or `DaemonSet`. | `Deployment` |
| `replicaCount` | Replicas (Deployment only; ignored when autoscaling or KEDA is enabled). | `1` |
| `minReadySeconds` | Seconds a new pod must be ready before it counts as available. | `0` |
| `revisionHistoryLimit` | Old ReplicaSets (Deployment) or ControllerRevisions (DaemonSet) kept for rollback; unset uses the Kubernetes default of 10. | `null` |
| `strategy` | Deployment update strategy. | `{}` |
| `updateStrategy` | DaemonSet update strategy. | `RollingUpdate`, `maxUnavailable: 1` |
| `terminationGracePeriodSeconds` | Pod termination grace period. | `60` |
| `priorityClassName` | `PriorityClass` of the pods. | `""` |
| `args.enabled` | Pass command line arguments to HAProxy (disable for EE images using S6 overlay). | `true` |
| `args.defaults` | Default arguments. | `["-f", "/usr/local/etc/haproxy/haproxy.cfg"]` |
| `args.extraArgs` | Additional arguments. | `[]` |
| `checksumConfigMap.enabled` | Roll the pods when `config` changes. | `true` |
| `shareProcessNamespace.enabled` | Share the process namespace between containers (needed by reload sidecars). | `false` |
| `sidecarContainers` / `initContainers` | Extra sidecar and init containers. | `[]` |
| `lifecycle` | Container lifecycle handlers (`preStop`, `postStart`). | `{}` |
| `livenessProbe` / `readinessProbe` / `startupProbe` | Probe definitions (none by default). | `{}` |
| `deploymentAnnotations` / `deploymentLabels` | Metadata on the Deployment (not applied to the DaemonSet). | `{}` |
| `podAnnotations` / `podLabels` | Metadata on the pod template. | `{}` |

### HAProxy configuration

| Key | Description | Default |
|---|---|---|
| `config` | HAProxy configuration, passed through `tpl` (Helm templates allowed). | see `values.yaml` |
| `configMount.mountPath` / `.subPath` | Where the configuration is mounted. A `subPath` also names the configuration file (`haproxy.cfg` otherwise) and disables automatic ConfigMap updates; EE images use a different path. | `/usr/local/etc/haproxy` / `""` |
| `includes` | Extra files (maps, error pages, ...) mounted next to the configuration. | _unset_ |
| `includesMountPath` | Mount path of `includes`. | `/usr/local/etc/haproxy/includes` |
| `mountedSecrets` | Secrets to mount (`volumeName`, `secretName`, `mountPath`). | `[]` |
| `extraEnvs` / `extraEnvFrom` | Extra `env` / `envFrom` entries. | `[]` |
| `extraVolumes` / `extraVolumeMounts` | Extra volumes and mounts. | `[]` |

### Ports, security and resources

| Key | Description | Default |
|---|---|---|
| `containerPorts` | Named container ports; each also becomes a Service port. | `http: 80`, `https: 443`, `stat: 1024` |
| `rawContainerPorts` | Container ports in full Kubernetes form. | `[]` |
| `daemonset.useHostNetwork` / `.useHostPort` | DaemonSet host networking / host ports. | `false` |
| `daemonset.hostPorts` | Host ports (must match `containerPorts` with `useHostNetwork`). | `http: 80`, `https: 443`, `stat: 1024` |
| `podSecurityContext` | Pod security context (e.g. `sysctls`). | `{}` |
| `securityContext` | Container security context; rendered only with `securityContext.enabled: true`. | `{}` |
| `resources` | Requests and limits; see [Memory limits](#memory-limits). | `requests: cpu 250m, memory 128Mi` |

### Scheduling

| Key | Description | Default |
|---|---|---|
| `nodeSelector` / `tolerations` / `affinity` | Pod placement. | `{}` / `[]` / `{}` |
| `topologySpreadConstraints` | Topology spread constraints (Deployment only). | `[]` |
| `dnsPolicy` | Pod DNS policy (`ClusterFirstWithHostNet` with `useHostNetwork`). | `ClusterFirst` |
| `dnsConfig` | Pod DNS config. | `{}` |

### Service

| Key | Description | Default |
|---|---|---|
| `service.name` | Service name (defaults to the chart fullname). Renaming replaces the Service and, with `LoadBalancer`, its external address. | `""` |
| `service.type` | `ClusterIP`, `NodePort` or `LoadBalancer`. | `ClusterIP` |
| `service.clusterIP` | Pin a ClusterIP. | `""` |
| `service.loadBalancerIP` | Requested LB IP (provider-dependent). | `""` |
| `service.loadBalancerSourceRanges` | CIDR allowlist for the LB. | `[]` |
| `service.loadBalancerClass` | `LoadBalancerClass` (see [Selecting a LoadBalancer implementation](#selecting-a-loadbalancer-implementation)). | `null` |
| `service.externalIPs` | External IPs. | `[]` |
| `service.annotations` / `.labels` | Service metadata. | `{}` |
| `service.externalTrafficPolicy` / `.internalTrafficPolicy` | Traffic policies. | _unset_ |
| `service.ipFamilies` / `.ipFamilyPolicy` | Dual-stack settings. | _unset_ |
| `service.trafficDistribution` | Traffic distribution (`PreferSameZone`, `PreferSameNode`, ...); rendered only on Kubernetes 1.31+. | _unset_ |
| `service.additionalPorts` | Extra Service ports (`name: port`, targeting the container port of the same name). | `{}` |
| `service.rawAdditionalPorts` | Extra Service ports in full Kubernetes form. | `[]` |
| `service.nodePorts` | Fixed NodePorts by port name (with `type: NodePort`). | `{}` |

### Autoscaling and disruption

| Key | Description | Default |
|---|---|---|
| `autoscaling.enabled` | Create an HPA (Deployment only). | `false` |
| `autoscaling.minReplicas` / `.maxReplicas` | HPA bounds. | `1` / `7` |
| `autoscaling.targetCPUUtilizationPercentage` | CPU target. | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Memory target. | _unset_ |
| `autoscaling.additionalMetrics` / `.behavior` | Extra HPA metrics and scaling behaviour. | _unset_ |
| `keda.enabled` | Create a KEDA `ScaledObject` instead of an HPA (Deployment only). | `false` |
| `keda.minReplicas` / `.maxReplicas` | KEDA bounds. | `2` / `20` |
| `keda.pollingInterval` / `.cooldownPeriod` | KEDA timing. | `30` / `300` |
| `keda.restoreToOriginalReplicaCount` | Restore the replica count when the ScaledObject is removed. | `false` |
| `keda.fallback` / `.behavior` / `.scaledObject.annotations` | Fallback, scaling behaviour and ScaledObject annotations. | _unset_ / `{}` / `{}` |
| `keda.triggers` | KEDA triggers. | `[]` |
| `PodDisruptionBudget.enable` | Create a PodDisruptionBudget. | `false` |
| `PodDisruptionBudget.minAvailable` / `.maxUnavailable` | PDB constraint (set one). | _unset_ |

### Monitoring, Ingress and Gateway API

| Key | Description | Default |
|---|---|---|
| `serviceMonitor.enabled` | Create a ServiceMonitor (see [Prometheus monitoring](#prometheus-monitoring)). | `false` |
| `serviceMonitor.extraLabels` | Labels for the Prometheus Operator selector. | `{}` |
| `serviceMonitor.endpoints` | Scrape endpoints. | port `prometheus`, `/metrics`, `30s` |
| `ingress.enabled` | Create an Ingress for the Service. | `false` |
| `ingress.servicePort` | Service port the Ingress routes to. | `80` |
| `ingress.className` | `ingressClassName`. | `""` |
| `ingress.annotations` / `.labels` | Ingress metadata. | `{}` |
| `ingress.hosts` / `.tls` | Ingress rules and TLS. | `haproxy.domain.com` `/` / `[]` |
| `httpRoute.enabled` | Create a Gateway API HTTPRoute for the Service (needs Gateway API CRDs and a Gateway). | `false` |
| `httpRoute.servicePort` | Service port the route sends traffic to. | `80` |
| `httpRoute.parentRefs` / `.hostnames` / `.rules` | Gateways to attach to, hostnames and rules. | see `values.yaml` |
| `httpRoute.annotations` / `.labels` | HTTPRoute metadata. | `{}` |

## Upgrading the chart

To upgrade the _my-release_ deployment:

```console
helm upgrade my-release haproxytech/haproxy
```

## Uninstalling the chart

To uninstall/delete the _my-release_ deployment:

```console
helm uninstall my-release
```

## Debugging

It is possible to generate a set of YAML files for testing/debugging:

```console
helm install my-release haproxytech/haproxy \
  --debug \
  --dry-run
```

## Contributing

We welcome all contributions. Please refer to [guidelines](../CONTRIBUTING.md) on how to make a contribution.
