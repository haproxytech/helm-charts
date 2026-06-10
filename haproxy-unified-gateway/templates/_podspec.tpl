{{/*
Copyright 2026 HAProxy Technologies LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{/*
Render the contents of spec.template.spec for the controller pod across
the two deployment shapes (Deployment, DaemonSet).

Call with:
  {{- include "haproxy-unified-gateway.podSpec" (dict "Root" . "Mode" "Deployment") | nindent 6 }}

Mode values: "Deployment" | "DaemonSet".

Mode-driven behaviour:
  - Host-port wiring (hostNetwork, per-port hostPort/hostIP) is sourced from
    controller.daemonset.* for DaemonSet only; Deployment renders none of it.
*/}}
{{- define "haproxy-unified-gateway.podSpec" -}}
{{- $root := .Root -}}
{{- $ctlr := $root.Values.controller -}}
{{- $useHostNetwork := false -}}
{{- $useHostPort := false -}}
{{- $hostPorts := dict -}}
{{- $hostIP := "" -}}
{{- if eq .Mode "DaemonSet" -}}
{{-   $useHostNetwork = $ctlr.daemonset.useHostNetwork -}}
{{-   $useHostPort = $ctlr.daemonset.useHostPort -}}
{{-   $hostPorts = $ctlr.daemonset.hostPorts -}}
{{-   $hostIP = $ctlr.daemonset.hostIP -}}
{{- end -}}
serviceAccountName: {{ include "haproxy-unified-gateway.serviceAccountName" $root }}
{{- with $ctlr.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $podSecurityContext := dict -}}
{{- if $ctlr.unprivileged -}}
{{-   $podSecurityContext = dict "runAsNonRoot" true "runAsUser" 1000 "runAsGroup" 1000 -}}
{{- end -}}
{{- with $ctlr.podSecurityContext -}}
{{-   $podSecurityContext = mergeOverwrite $podSecurityContext (deepCopy .) -}}
{{- end -}}
{{- with $podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- if $useHostNetwork }}
hostNetwork: true
{{- end }}
{{- with $ctlr.dnsPolicy }}
dnsPolicy: {{ . }}
{{- end }}
{{- with $ctlr.dnsConfig }}
dnsConfig:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.initContainers }}
initContainers:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: {{ include "haproxy-unified-gateway.name" $root }}
    image: {{ include "haproxy-unified-gateway.image" $root }}
    imagePullPolicy: {{ $ctlr.image.pullPolicy }}
    args:
      {{- if or $root.Values.hugconf.create $ctlr.hugconfCrd }}
      - --hugconf-crd={{ include "haproxy-unified-gateway.hugconfCrd" $root }}
      {{- end }}
      {{- with $ctlr.metricsAuth }}
      - --metrics-auth={{ . }}
      {{- end }}
      {{- range $ctlr.extraArgs }}
      - {{ . }}
      {{- end }}
    ports:
      {{- range $key, $value := $ctlr.containerPort }}
      - name: {{ $key }}
        containerPort: {{ $value }}
        protocol: TCP
        {{- if and $useHostPort (index $hostPorts $key) }}
        hostPort: {{ index $hostPorts $key }}
        {{- end }}
        {{- if $hostIP }}
        hostIP: {{ $hostIP }}
        {{- end }}
      {{- end }}
    env:
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_IP
        valueFrom:
          fieldRef:
            fieldPath: status.podIP
      {{- with $ctlr.extraEnvs }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- with $ctlr.livenessProbe }}
    livenessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $ctlr.readinessProbe }}
    readinessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $ctlr.startupProbe }}
    startupProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $ctlr.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if $ctlr.unprivileged }}
    securityContext:
      allowPrivilegeEscalation: {{ $ctlr.allowPrivilegeEscalation }}
      capabilities:
        drop:
          - ALL
        add:
          - NET_BIND_SERVICE
      {{- with $ctlr.seccompProfile }}
      seccompProfile:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- with $ctlr.extraVolumeMounts }}
    volumeMounts:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- with $ctlr.extraContainers }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- with $ctlr.extraVolumes }}
volumes:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
