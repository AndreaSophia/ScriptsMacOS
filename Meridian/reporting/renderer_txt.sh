#!/bin/bash
# Meridian — reporting/renderer_txt.sh

renderer_txt_generate() {
  local output_dir="$1" results_blob="$2" summary="$3"
  local outfile="${output_dir}/Executive_Report.txt"
  local total pass warn fail skip error worst_sev
  total="$(echo "$summary"|grep -o 'total=[^ ]*'|cut -d= -f2)"; pass="$(echo "$summary"|grep -o 'pass=[^ ]*'|cut -d= -f2)"
  warn="$(echo "$summary"|grep -o 'warn=[^ ]*'|cut -d= -f2)"; fail="$(echo "$summary"|grep -o 'fail=[^ ]*'|cut -d= -f2)"
  skip="$(echo "$summary"|grep -o 'skip=[^ ]*'|cut -d= -f2)"; error="$(echo "$summary"|grep -o 'error=[^ ]*'|cut -d= -f2)"
  worst_sev="$(echo "$summary"|grep -o 'worst_severity=[^ ]*'|cut -d= -f2)"
  {
    printf '=============================================================\n  Meridian — Executive Report\n=============================================================\n\n'
    printf '  RESUMEN: total=%s pass=%s warn=%s fail=%s skip=%s error=%s\n  Severidad máxima: %s\n\n' "${total:-0}" "${pass:-0}" "${warn:-0}" "${fail:-0}" "${skip:-0}" "${error:-0}" "${worst_sev:-INFO}"
    printf '-------------------------------------------------------------\n  RESULTADOS POR MÓDULO\n-------------------------------------------------------------\n\n'
    local line icon
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      result_deserialize "$line"
      case "$RESULT_STATUS" in PASS) icon='✓';; WARN) icon='!';; FAIL) icon='✗';; SKIP) icon='–';; ERROR) icon='⚡';; *) icon='?';; esac
      printf '  %s [%s] %s\n' "$icon" "$RESULT_SEVERITY" "$RESULT_TITLE"
      printf '  Módulo     : %s\n  Estado     : %s\n  Descripción: %s\n' "$RESULT_MODULE_ID" "$RESULT_STATUS" "$RESULT_DESCRIPTION"
      [ "$RESULT_EXPLANATION" != N/A ] && [ -n "$RESULT_EXPLANATION" ] && printf '  Explicación: %s\n' "$RESULT_EXPLANATION"
      [ "$RESULT_RISK" != N/A ] && [ -n "$RESULT_RISK" ] && printf '  Riesgo     : %s\n' "$RESULT_RISK"
      [ "$RESULT_SUGGESTED_ACTION" != N/A ] && [ -n "$RESULT_SUGGESTED_ACTION" ] && printf '  Acción     : %s\n' "$RESULT_SUGGESTED_ACTION"
      [ "$RESULT_REPAIRABLE" = true ] && printf '  Reparable  : Sí (riesgo: %s)\n' "$RESULT_REPAIR_RISK"
      [ -n "$RESULT_RULE_TRIGGERED" ] && printf '  Regla      : %s\n' "$RESULT_RULE_TRIGGERED"
      printf '  Tiempo     : %sms\n\n' "${RESULT_EXECUTION_TIME_MS:-0}"
    done < <(printf '%s\n' "$results_blob")
    printf '=============================================================\n'
  } > "$outfile"
  log_ok "renderer_txt" "Executive_Report.txt generado"
  echo "$outfile"
}
