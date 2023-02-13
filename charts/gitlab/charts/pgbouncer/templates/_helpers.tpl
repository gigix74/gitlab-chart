{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "pgbouncer.fullname" -}}
{{- $name := .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pgbouncer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "pgbouncer.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "pgbouncer.chart" . }}
{{- if .Values.podLabels }}
{{ toYaml .Values.podLabels }}
{{- end }}
{{ include "pgbouncer.selectorLabels" . }}
{{- end }}


{{/*
Selector labels
*/}}
{{- define "pgbouncer.selectorLabels" -}}
app: {{ include "pgbouncer.fullname" . }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Get the pgbouncer config file name.
*/}}
{{- define "pgbouncer.configFile" -}}
{{- printf "%s-config-file" (include "pgbouncer.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Get the pgbouncer userlist file name.
*/}}
{{- define "pgbouncer.userlistFile" -}}
{{- printf "%s-userlist" (include "pgbouncer.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
