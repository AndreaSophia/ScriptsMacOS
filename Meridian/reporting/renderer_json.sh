#!/bin/bash
# Meridian — reporting/renderer_json.sh
# Genera JSON estricto desde DiagnosticResult v2 sin permitir que datos
# malformados rompan el reporte completo.

_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

_summary_field() {
  local summary="$1" key="$2" value
  value="$(printf '%s\n' "$summary" | tr ' ' '\n' | awk -F= -v k="$key" '$1 == k { print $2; exit }')"
  printf '%s' "$value"
}

renderer_json_generate() {
  local output_dir="$1" results_blob="$2" summary="$3"
  local outfile="${output_dir}/results.json"
  local total pass warn fail skip error worst_sev

  total="$(_summary_field "$summary" total)"
  pass="$(_summary_field "$summary" pass)"
  warn="$(_summary_field "$summary" warn)"
  fail="$(_summary_field "$summary" fail)"
  skip="$(_summary_field "$summary" skip)"
  error="$(_summary_field "$summary" error)"
  worst_sev="$(_summary_field "$summary" worst_severity)"

  # Los contadores se emiten como números JSON. Nunca insertar texto arbitrario
  # sin comillas aunque un caller entregue un summary corrupto.
  case "$total" in ''|*[!0-9]*) total=0;; esac
  case "$pass" in ''|*[!0-9]*) pass=0;; esac
  case "$warn" in ''|*[!0-9]*) warn=0;; esac
  case "$fail" in ''|*[!0-9]*) fail=0;; esac
  case "$skip" in ''|*[!0-9]*) skip=0;; esac
  case "$error" in ''|*[!0-9]*) error=0;; esac
  case "$worst_sev" in INFO|LOW|MEDIUM|HIGH|CRITICAL) ;; *) worst_sev="INFO";; esac

  local now host macos arch current_user
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  host="$(hostname -s 2>/dev/null || echo unknown)"
  macos="$(sw_vers -productVersion 2>/dev/null || echo N/A)"
  arch="$(uname -m 2>/dev/null || echo N/A)"
  current_user="${SUDO_USER:-$(whoami 2>/dev/null || echo unknown)}"

  {
    printf '{\n  "meridian_version": "%s",\n  "generated_at": "%s",\n' \
      "$(_json_escape "${MERIDIAN_VERSION:-1.0.0-mvp}")" "$(_json_escape "$now")"
    printf '  "host": {"hostname":"%s","macos_version":"%s","architecture":"%s","user":"%s"},\n' \
      "$(_json_escape "$host")" "$(_json_escape "$macos")" "$(_json_escape "$arch")" "$(_json_escape "$current_user")"
    printf '  "summary": {"total":%s,"pass":%s,"warn":%s,"fail":%s,"skip":%s,"error":%s,"worst_severity":"%s"},\n' \
      "$total" "$pass" "$warn" "$fail" "$skip" "$error" "$worst_sev"
    printf '  "results": [\n'

    local first=true line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      result_deserialize "$line"
      if ! result_validate; then
        log_warn "renderer_json" "DiagnosticResult inválido omitido del JSON"
        continue
      fi

      [ "$first" = true ] && first=false || printf ',\n'
      printf '    {"module_id":"%s","module_version":"%s","timestamp":"%s","hostname":"%s","status":"%s","severity":"%s","title":"%s","description":"%s","explanation":"%s","risk":"%s","suggested_action":"%s","repairable":%s,"repair_risk":"%s","repair_id":"%s","execution_time_ms":%s,"exit_code":%s,"raw_output":"%s","rule_triggered":"%s","evidence":"%s"}' \
        "$(_json_escape "$RESULT_MODULE_ID")" \
        "$(_json_escape "$RESULT_MODULE_VERSION")" \
        "$(_json_escape "$RESULT_TIMESTAMP")" \
        "$(_json_escape "$RESULT_HOSTNAME")" \
        "$(_json_escape "$RESULT_STATUS")" \
        "$(_json_escape "$RESULT_SEVERITY")" \
        "$(_json_escape "$RESULT_TITLE")" \
        "$(_json_escape "$RESULT_DESCRIPTION")" \
        "$(_json_escape "$RESULT_EXPLANATION")" \
        "$(_json_escape "$RESULT_RISK")" \
        "$(_json_escape "$RESULT_SUGGESTED_ACTION")" \
        "$RESULT_REPAIRABLE" \
        "$(_json_escape "$RESULT_REPAIR_RISK")" \
        "$(_json_escape "$RESULT_REPAIR_ID")" \
        "$RESULT_EXECUTION_TIME_MS" \
        "$RESULT_EXIT_CODE" \
        "$(_json_escape "$RESULT_RAW_OUTPUT")" \
        "$(_json_escape "$RESULT_RULE_TRIGGERED")" \
        "$(_json_escape "$RESULT_EVIDENCE")"
    done < <(printf '%s\n' "$results_blob")

    printf '\n  ]\n}\n'
  } > "$outfile" || {
    log_error "renderer_json" "No se pudo escribir results.json"
    return 1
  }

  log_ok "renderer_json" "results.json generado"
  printf '%s\n' "$outfile"
}
