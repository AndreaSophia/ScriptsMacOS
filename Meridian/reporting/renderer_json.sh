#!/bin/bash
# Meridian — reporting/renderer_json.sh

_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

renderer_json_generate() {
  local output_dir="$1" results_blob="$2" summary="$3"
  local outfile="${output_dir}/results.json"
  local total pass warn fail skip error worst_sev
  total="$(echo "$summary"|grep -o 'total=[^ ]*'|cut -d= -f2)"
  pass="$(echo "$summary"|grep -o 'pass=[^ ]*'|cut -d= -f2)"
  warn="$(echo "$summary"|grep -o 'warn=[^ ]*'|cut -d= -f2)"
  fail="$(echo "$summary"|grep -o 'fail=[^ ]*'|cut -d= -f2)"
  skip="$(echo "$summary"|grep -o 'skip=[^ ]*'|cut -d= -f2)"
  error="$(echo "$summary"|grep -o 'error=[^ ]*'|cut -d= -f2)"
  worst_sev="$(echo "$summary"|grep -o 'worst_severity=[^ ]*'|cut -d= -f2)"

  local now host macos arch current_user
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; host="$(hostname -s 2>/dev/null || echo unknown)"
  macos="$(sw_vers -productVersion 2>/dev/null || echo N/A)"; arch="$(uname -m 2>/dev/null || echo N/A)"
  current_user="${SUDO_USER:-$(whoami 2>/dev/null || echo unknown)}"

  {
    printf '{\n  "meridian_version": "%s",\n  "generated_at": "%s",\n' "${MERIDIAN_VERSION:-1.0.0-mvp}" "$now"
    printf '  "host": {"hostname":"%s","macos_version":"%s","architecture":"%s","user":"%s"},\n' "$(_json_escape "$host")" "$(_json_escape "$macos")" "$(_json_escape "$arch")" "$(_json_escape "$current_user")"
    printf '  "summary": {"total":%s,"pass":%s,"warn":%s,"fail":%s,"skip":%s,"error":%s,"worst_severity":"%s"},\n' "${total:-0}" "${pass:-0}" "${warn:-0}" "${fail:-0}" "${skip:-0}" "${error:-0}" "${worst_sev:-INFO}"
    printf '  "results": [\n'
    local first=true line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      result_deserialize "$line"
      [ "$first" = true ] && first=false || printf ',\n'
      printf '    {"module_id":"%s","module_version":"%s","timestamp":"%s","hostname":"%s","status":"%s","severity":"%s","title":"%s","description":"%s","explanation":"%s","risk":"%s","suggested_action":"%s","repairable":%s,"repair_risk":"%s","repair_id":"%s","execution_time_ms":%s,"exit_code":%s,"raw_output":"%s","rule_triggered":"%s","evidence":"%s"}' \
        "$(_json_escape "$RESULT_MODULE_ID")" "$(_json_escape "$RESULT_MODULE_VERSION")" "$(_json_escape "$RESULT_TIMESTAMP")" "$(_json_escape "$RESULT_HOSTNAME")" "$(_json_escape "$RESULT_STATUS")" "$(_json_escape "$RESULT_SEVERITY")" "$(_json_escape "$RESULT_TITLE")" "$(_json_escape "$RESULT_DESCRIPTION")" "$(_json_escape "$RESULT_EXPLANATION")" "$(_json_escape "$RESULT_RISK")" "$(_json_escape "$RESULT_SUGGESTED_ACTION")" "${RESULT_REPAIRABLE:-false}" "$(_json_escape "$RESULT_REPAIR_RISK")" "$(_json_escape "$RESULT_REPAIR_ID")" "${RESULT_EXECUTION_TIME_MS:-0}" "${RESULT_EXIT_CODE:-0}" "$(_json_escape "$RESULT_RAW_OUTPUT")" "$(_json_escape "$RESULT_RULE_TRIGGERED")" "$(_json_escape "$RESULT_EVIDENCE")"
    done < <(printf '%s\n' "$results_blob")
    printf '\n  ]\n}\n'
  } > "$outfile"
  log_ok "renderer_json" "results.json generado"
  echo "$outfile"
}
