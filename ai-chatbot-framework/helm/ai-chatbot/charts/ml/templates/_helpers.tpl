{{- define "ml.name" -}}
ml
{{- end }}

{{- define "ml.fullname" -}}
{{ .Release.Name }}-ml
{{- end }}

{{- define "ml.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}
