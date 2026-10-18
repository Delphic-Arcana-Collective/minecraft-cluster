{{- define "minecraft.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "minecraft.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "minecraft.labels" -}}
app.kubernetes.io/name: {{ include "minecraft.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "minecraft.selectorLabels" -}}
app.kubernetes.io/name: {{ include "minecraft.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
