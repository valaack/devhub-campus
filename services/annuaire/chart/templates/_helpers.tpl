{{/*
  Helpers communs au chart annuaire.
  TODO étape 4 : complétez le bloc `labels` avec les 4 labels obligatoires
  cités dans le polycopié. La grille d'évaluation les vérifie.
*/}}

{{- define "annuaire.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "annuaire.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "annuaire.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "annuaire.labels" -}}
{{/* TODO : ajoutez ici :
       app.kubernetes.io/name
       app.kubernetes.io/instance
       app.kubernetes.io/part-of: devhub-campus
       app.kubernetes.io/managed-by: Helm
*/}}
{{- end -}}

{{- define "annuaire.selectorLabels" -}}
{{/* TODO : sélecteur minimal stable (name + instance, pas managed-by qui peut bouger). */}}
{{- end -}}
