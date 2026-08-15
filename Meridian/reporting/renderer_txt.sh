#!/bin/bash
# Meridian — reporting/renderer_txt.sh

_txt_summary_field() {
  local summary="$1" key="$2" value
  value="$(printf '%s\n' "$summary" | tr ' ' '\n' | awk -F= -v k="$key" '$1 == k { print $2; exit }')"
  printf '%s' "$value"
}

renderer_txt_generate() {
  local output_dir="$1" results_blob="$2" summary="$3"
  local outfile="${output_dir}/Executive_Report.txt"
  local total pass warn fail skip error worst_sev

  total="$(_txt_summary_field "$summary" total)"
  pass="$(_txt_summary_field "$summary" pass)"
  warn="$(_txt_summary_field "$summary" warn)"
  fail="$(_txt_summary_field "$summary" fail)"
  skip="$(_txt_summary_field "$summary" skip)"
  error="$(_txt_summary_field "$summary" error)"
  worst_sev="$(_txt_summary_field "$summary" worst_severity)"

  case "$total" in ''|*[!0-9]*) total=0;; esac
  case "$pass" in ''|*[!0-9]*) pass=0;; esac
  case "$warn" in ''|*[!0-9]*) warn=0;; esac
  case "$fail" in ''|*[!0-9]*) fail=0;; esac
  case "$skip" in ''|*[!0-9]*) skip=0;; esac
  case "$error" in ''|*[!0-9]*) error=0;; esac
  case "$worst_sev" in INFO|LOW|MEDIUM|HIGH|CRITICAL) ;; *) worst_sev="INFO";; esac

  {
    printf '=============================================================\n  Meridian — Executive Report\n=============================================================\n\n'
    printf '  RESUMEN: total=%s pass=%s warn=%s fail=%s skip=%s error=%s\n  Severidad máxima: %s\n\n' \
      "$total" "$pass" "$warn" "$fail" "$skip" "$error" "$worst_sev"
    printf '%s\n' '-------------------------------------------------------------' '  RESULTADOS POR MÓDULO' '-------------------------------------------------------------' ''

    local line icon
    while IFS= read -r line; do
      [ -z "$line" ] && continue

      if ! result_deserialize "$line" || ! result_validate; then
        log_warn "renderer_txt" "DiagnosticResult inválido omitido del TXT"
        continue
      fi

      case "$RESULT_STATUS" in
        PASS) icon='✓';;
        WARN) icon='!';;
        FAIL) icon='✗';;
        SKIP) icon='–';;
        ERROR) icon='⚡';;
        *) icon='?';;
      esac

      printf '  %s [%s] %s\n' "$icon" "$RESULT_SEVERITY" "$RESULT_TITLE"
      printf '  Módulo     : %s\n  Estado     : %s\n  Descripción: %s\n' \
        "$RESULT_MODULE_ID" "$RESULT_STATUS" "$RESULT_DESCRIPTION"
      [ "$RESULT_EXPLANATION" != N/A ] && [ -n "$RESULT_EXPLANATION" ] && printf '  Explicación: %s\n' "$RESULT_EXPLANATION"
      [ "$RESULT_RISK" != N/A ] && [ -n "$RESULT_RISK" ] && printf '  Riesgo     : %s\n' "$RESULT_RISK"
      [ "$RESULT_SUGGESTED_ACTION" != N/A ] && [ -n "$RESULT_SUGGESTED_ACTION" ] && printf '  Acción     : %s\n' "$RESULT_SUGGESTED_ACTION"
      [ "$RESULT_REPAIRABLE" = true ] && printf '  Reparable  : Sí (riesgo: %s)\n' "$RESULT_REPAIR_RISK"
      [ -n "$RESULT_RULE_TRIGGERED" ] && printf '  Regla      : %s\n' "$RESULT_RULE_TRIGGERED"
      printf '  Tiempo     : %sms\n\n' "${RESULT_EXECUTION_TIME_MS:-0}"
    done < <(printf '%s\n' "$results_blob")

    printf '=============================================================\n'
  } > "$outfile" || {
    log_error "renderer_txt" "No se pudo escribir Executive_Report.txt"
    return 1
  }

  log_ok "renderer_txt" "Executive_Report.txt generado"
  printf '%s\n' "$outfile"
}
