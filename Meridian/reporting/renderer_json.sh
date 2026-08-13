#!/bin/bash
# =============================================================================
# Meridian — reporting/renderer_json.sh
# Responsabilidad: generar results.json en formato consumible por APIs,
# SIEM, Splunk, Workspace ONE o cualquier herramienta de ingestión.
# Stateless: recibe datos, produce un archivo.
# =============================================================================

# =============================================================================
# _json_escape <string> — Escapa caracteres especiales para JSON
# =============================================================================
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# =============================================================================
# renderer_json_generate <output_dir> <results_blob> <summary>
# =============================================================================
renderer_json_generate() {
  local output_dir="$1"
  local results_blob="$2"
  local summary="$3"
  local outfile="${output_dir}/results.json"

  # Parsear summary
  local total pass warn fail skip error worst_sev
  total="$(   echo "$summary" | grep -o 'total=[^ ]*'   | cut -d= -f2)"
  pass="$(    echo "$summary" | grep -o 'pass=[^ ]*'    | cut -d= -f2)"
  warn="$(    echo "$summary" | grep -o 'warn=[^ ]*'    | cut -d= -f2)"
  fail="$(    echo "$summary" | grep -o 'fail=[^ ]*'    | cut -d= -f2)"
  skip="$(    echo "$summary" | grep -o 'skip=[^ ]*'    | cut -d= -f2)"
  error="$(   echo "$summary" | grep -o 'error=[^ ]*'   | cut -d= -f2)"
  worst_sev="$(echo "$summary" | grep -o 'worst_severity=[^ ]*' | cut -d= -f2)"

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local hostname
  hostname="$(hostname -s 2>/dev/null || echo 'unknown')"
  local macos_ver
  macos_ver="$(sw_vers -productVersion 2>/dev/null || echo 'N/A')"
  local arch
  arch="$(uname -m 2>/dev/null || echo 'N/A')"
  local current_user
  current_user="${SUDO_USER:-$(whoami 2>/dev/null || echo 'unknown')}"

  {
    printf '{\n'
    printf '  "meridian_version": "%s",\n' "${MERIDIAN_VERSION:-1.0.0-mvp}"
    printf '  "generated_at": "%s",\n' "$ts"
    printf '  "host": {\n'
    printf '    "hostname": "%s",\n' "$(_json_escape "$hostname")"
    printf '    "macos_version": "%s",\n' "$(_json_escape "$macos_ver")"
    printf '    "architecture": "%s",\n' "$(_json_escape "$arch")"
    printf '    "user": "%s"\n' "$(_json_escape "$current_user")"
    printf '  },\n'
    printf '  "summary": {\n'
    printf '    "total": %s,\n'           "${total:-0}"
    printf '    "pass": %s,\n'            "${pass:-0}"
    printf '    "warn": %s,\n'            "${warn:-0}"
    printf '    "fail": %s,\n'            "${fail:-0}"
    printf '    "skip": %s,\n'            "${skip:-0}"
    printf '    "error": %s,\n'           "${error:-0}"
    printf '    "worst_severity": "%s"\n' "${worst_sev:-INFO}"
    printf '  },\n'
    printf '  "results": [\n'

    local first=true
    while IFS= read -r line; do
      [ -z "$line" ] && continue

      local mod_id mod_ver ts_mod hostname_mod status severity title
      local description explanation risk action repairable repair_risk
      local repair_id exec_time exit_code raw_output rule_triggered evidence

      mod_id="$(         echo "$line" | sed 's/|||//g' | awk -F'' '{print $1}')"
      mod_ver="$(        echo "$line" | sed 's/|||//g' | awk -F'' '{print $2}')"
      ts_mod="$(         echo "$line" | sed 's/|||//g' | awk -F'' '{print $3}')"
      hostname_mod="$(   echo "$line" | sed 's/|||//g' | awk -F'' '{print $4}')"
      status="$(         echo "$line" | sed 's/|||//g' | awk -F'' '{print $5}')"
      severity="$(       echo "$line" | sed 's/|||//g' | awk -F'' '{print $6}')"
      title="$(          echo "$line" | sed 's/|||//g' | awk -F'' '{print $7}')"
      description="$(    echo "$line" | sed 's/|||//g' | awk -F'' '{print $8}')"
      explanation="$(    echo "$line" | sed 's/|||//g' | awk -F'' '{print $9}')"
      risk="$(           echo "$line" | sed 's/|||//g' | awk -F'' '{print $10}')"
      action="$(         echo "$line" | sed 's/|||//g' | awk -F'' '{print $11}')"
      repairable="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $12}')"
      repair_risk="$(    echo "$line" | sed 's/|||//g' | awk -F'' '{print $13}')"
      repair_id="$(      echo "$line" | sed 's/|||//g' | awk -F'' '{print $14}')"
      exec_time="$(      echo "$line" | sed 's/|||//g' | awk -F'' '{print $15}')"
      exit_code="$(      echo "$line" | sed 's/|||//g' | awk -F'' '{print $16}')"
      raw_output="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $17}')"
      rule_triggered="$( echo "$line" | sed 's/|||//g' | awk -F'' '{print $18}')"
      evidence="$(       echo "$line" | sed 's/|||//g' | awk -F'' '{print $19}')"

      [ "$first" = "true" ] && first=false || printf ',\n'

      printf '    {\n'
      printf '      "module_id": "%s",\n'          "$(_json_escape "$mod_id")"
      printf '      "module_version": "%s",\n'     "$(_json_escape "$mod_ver")"
      printf '      "timestamp": "%s",\n'          "$(_json_escape "$ts_mod")"
      printf '      "hostname": "%s",\n'           "$(_json_escape "$hostname_mod")"
      printf '      "status": "%s",\n'             "$(_json_escape "$status")"
      printf '      "severity": "%s",\n'           "$(_json_escape "$severity")"
      printf '      "title": "%s",\n'              "$(_json_escape "$title")"
      printf '      "description": "%s",\n'        "$(_json_escape "$description")"
      printf '      "explanation": "%s",\n'        "$(_json_escape "$explanation")"
      printf '      "risk": "%s",\n'               "$(_json_escape "$risk")"
      printf '      "suggested_action": "%s",\n'   "$(_json_escape "$action")"
      printf '      "repairable": %s,\n'           "$repairable"
      printf '      "repair_risk": "%s",\n'        "$(_json_escape "$repair_risk")"
      printf '      "repair_id": "%s",\n'          "$(_json_escape "$repair_id")"
      printf '      "execution_time_ms": %s,\n'    "${exec_time:-0}"
      printf '      "exit_code": %s,\n'            "${exit_code:-0}"
      printf '      "raw_output": "%s",\n'         "$(_json_escape "$raw_output")"
      printf '      "rule_triggered": "%s",\n'     "$(_json_escape "$rule_triggered")"
      printf '      "evidence": "%s"\n'            "$(_json_escape "$evidence")"
      printf '    }'

    done < <(echo "$results_blob")

    printf '\n  ]\n'
    printf '}\n'

  } > "$outfile"

  log_ok "renderer_json" "results.json generado"
  echo "$outfile"
}
