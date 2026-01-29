{{- define "worker.name" -}}
worker
{{- end }}

{{- define "worker.fullname" -}}
{{ .Release.Name }}-worker
{{- end }}

{{- define "worker.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}
