{{- define "frontend.name" -}}
frontend
{{- end }}

{{- define "frontend.fullname" -}}
{{ .Release.Name }}-frontend
{{- end }}

{{- define "frontend.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}
