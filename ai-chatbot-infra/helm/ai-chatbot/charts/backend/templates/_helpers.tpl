{{- define "backend.name" -}}
backend
{{- end }}

{{- define "backend.fullname" -}}
{{ .Release.Name }}-backend
{{- end }}

{{- define "backend.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

