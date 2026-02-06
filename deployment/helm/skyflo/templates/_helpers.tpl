{{/*
Expand the name of the chart.
*/}}
{{- define "skyflo.name" -}}
{{- $g := index .Values "global" -}}
{{- if $g }}{{ default .Chart.Name $g.nameOverride | trunc 63 | trimSuffix "-" }}{{- else }}{{ .Chart.Name | trunc 63 | trimSuffix "-" }}{{- end }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "skyflo.fullname" -}}
{{- $g := index .Values "global" -}}
{{- if $g.fullnameOverride }}
{{- $g.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "skyflo.name" . }}
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
{{- define "skyflo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "skyflo.labels" -}}
helm.sh/chart: {{ include "skyflo.chart" . }}
{{ include "skyflo.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "skyflo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skyflo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Effective app version (for ConfigMap and image tags). From global.version.
*/}}
{{- define "skyflo.version" -}}
{{- $g := index .Values "global" -}}
{{- if $g }}{{ $g.version | default .Chart.AppVersion | default "v0.5.0" }}{{- else }}{{ .Chart.AppVersion | default "v0.5.0" }}{{- end }}
{{- end }}

{{/*
Namespace for resources (e.g. when creating namespace or in docs). From global.namespace.
*/}}
{{- define "skyflo.namespace" -}}
{{- $g := index .Values "global" -}}
{{- if $g }}{{ $g.namespace | default .Release.Namespace | default "skyflo-ai" }}{{- else }}{{ .Release.Namespace | default "skyflo-ai" }}{{- end }}
{{- end }}

{{/*
Engine service URL for UI API_URL config.
*/}}
{{- define "skyflo.engineUrl" -}}
http://{{ include "skyflo.fullname" . }}-engine:8080/api/v1
{{- end }}
