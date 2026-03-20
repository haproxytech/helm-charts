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
Expand the name of the chart.
*/}}
{{- define "haproxy-unified-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "haproxy-unified-gateway.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "haproxy-unified-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace to use.
*/}}
{{- define "haproxy-unified-gateway.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "haproxy-unified-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "haproxy-unified-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Helm chart metadata labels.
*/}}
{{- define "haproxy-unified-gateway.helmChartLabels" -}}
helm.sh/chart: {{ include "haproxy-unified-gateway.chart" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common labels (selector + chart metadata).
*/}}
{{- define "haproxy-unified-gateway.labels" -}}
{{ include "haproxy-unified-gateway.selectorLabels" . }}
{{ include "haproxy-unified-gateway.helmChartLabels" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "haproxy-unified-gateway.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "haproxy-unified-gateway.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Controller image.
*/}}
{{- define "haproxy-unified-gateway.image" -}}
{{- $tag := default .Chart.AppVersion .Values.controller.image.tag -}}
{{- printf "%s:%s" .Values.controller.image.repository $tag }}
{{- end }}

{{/*
CRD Job ServiceAccount/RBAC name.
*/}}
{{- define "haproxy-unified-gateway.crdjob.saName" -}}
{{- printf "%s-crdjob" (include "haproxy-unified-gateway.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Metrics Service name.
*/}}
{{- define "haproxy-unified-gateway.metricsServiceName" -}}
{{- printf "%s-metrics" (include "haproxy-unified-gateway.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
HugConf cleanup Job name.
*/}}
{{- define "haproxy-unified-gateway.hugconfCleanup.fullname" -}}
{{- printf "%s-hugconf-cleanup" (include "haproxy-unified-gateway.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
CRD Job labels.
*/}}
{{- define "haproxy-unified-gateway.crdjobLabels" -}}
{{ include "haproxy-unified-gateway.helmChartLabels" . }}
app.kubernetes.io/name: {{ include "haproxy-unified-gateway.name" . }}-crdjob
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CRD Job fullname (includes revision for uniqueness).
*/}}
{{- define "haproxy-unified-gateway.crdjob.fullname" -}}
{{- printf "%s-crdjob-%d" (include "haproxy-unified-gateway.fullname" .) .Release.Revision | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Gateway API Job labels.
*/}}
{{- define "haproxy-unified-gateway.gwapijobLabels" -}}
{{ include "haproxy-unified-gateway.helmChartLabels" . }}
app.kubernetes.io/name: {{ include "haproxy-unified-gateway.name" . }}-gwapijob
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Gateway API Job fullname (includes revision for uniqueness).
*/}}
{{- define "haproxy-unified-gateway.gwapijob.fullname" -}}
{{- printf "%s-gwapijob-%d" (include "haproxy-unified-gateway.fullname" .) .Release.Revision | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ServiceMonitor name.
*/}}
{{- define "haproxy-unified-gateway.serviceMonitorName" -}}
{{- default (include "haproxy-unified-gateway.fullname" .) .Values.controller.serviceMonitor.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
PodMonitor name.
*/}}
{{- define "haproxy-unified-gateway.podMonitorName" -}}
{{- default (include "haproxy-unified-gateway.fullname" .) .Values.controller.podMonitor.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
HugConf CRD reference path (namespace/name).
*/}}
{{- define "haproxy-unified-gateway.hugconfCrd" -}}
{{- if .Values.controller.hugconfCrd }}
{{- .Values.controller.hugconfCrd }}
{{- else }}
{{- printf "%s/%s" (include "haproxy-unified-gateway.namespace" .) .Values.hugconf.name }}
{{- end }}
{{- end }}
