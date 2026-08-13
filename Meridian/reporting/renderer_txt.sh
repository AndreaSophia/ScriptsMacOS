#!/bin/bash
# =============================================================================
# Meridian — reporting/renderer_txt.sh
# Responsabilidad: generar Executive_Report.txt a partir de DiagnosticResult[].
# Stateless: recibe datos, produce un archivo. Sin efectos secundarios.
# =============================================================================

# =============================================================================
# renderer_txt_generate <output_dir> <results_blob> <summary>
# =============================================================================
renderer_txt_generate() {
  local output_dir="$1"
  local results_blob="$2"
  local summary="$3"
  local outfile="${output_dir}/Executive_Report.txt"

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
    printf '=============================================================\n'
    printf '  Meridian — Executive Report\n'
    printf '  %s  |  v%s\n' "${MERIDIAN_ORG:-Apple Platform Team}" "${MERIDIAN_VERSION:-1.0.0-mvp}"
    printf '=============================================================\n\n'
    printf '  Generado  : %s\n'   "$ts"
    printf '  Hostname  : %s\n'   "$hostname"
    printf '  macOS     : %s (%s)\n' "$macos_ver" "$arch"
    printf '  Usuario   : %s\n\n' "$current_user"

    printf '-------------------------------------------------------------\n'
    printf '  RESUMEN\n'
    printf '-------------------------------------------------------------\n'
    printf '  Total módulos   : %s\n'   "${total:-0}"
    printf '  ✓ Pasaron        : %s\n'  "${pass:-0}"
    printf '  ! Advertencias   : %s\n'  "${warn:-0}"
    printf '  ✗ Fallaron       : %s\n'  "${fail:-0}"
    printf '  – Omitidos       : %s\n'  "${skip:-0}"
    printf '  ⚡ Errores        : %s\n'  "${error:-0}"
    printf '  Severidad máxima : %s\n\n' "${worst_sev:-INFO}"

    printf '-------------------------------------------------------------\n'
    printf '  RESULTADOS POR MÓDULO\n'
    printf '-------------------------------------------------------------\n\n'

    # Campos por posición en la serialización (separador |||, 3 pipes = 1 delimitador)
    # Posiciones: 1=id 4=ver 7=ts 10=host 13=status 16=sev 19=title 22=desc
    #             25=expl 28=risk 31=action 34=repair 37=rep_risk 40=rep_id
    #             43=time 46=exit 49=raw 52=rule 55=evidence
    while IFS= read -r line; do
      [ -z "$line" ] && continue

      local mod_id status severity title description explanation risk action
      local repairable repair_risk exec_time rule_triggered

      mod_id="$(        echo "$line" | sed 's/|||//g' | awk -F'' '{print $1}')"
      status="$(        echo "$line" | sed 's/|||//g' | awk -F'' '{print $5}')"
      severity="$(      echo "$line" | sed 's/|||//g' | awk -F'' '{print $6}')"
      title="$(         echo "$line" | sed 's/|||//g' | awk -F'' '{print $7}')"
      description="$(   echo "$line" | sed 's/|||//g' | awk -F'' '{print $8}')"
      explanation="$(   echo "$line" | sed 's/|||//g' | awk -F'' '{print $9}')"
      risk="$(          echo "$line" | sed 's/|||//g' | awk -F'' '{print $10}')"
      action="$(        echo "$line" | sed 's/|||//g' | awk -F'' '{print $11}')"
      repairable="$(    echo "$line" | sed 's/|||//g' | awk -F'' '{print $12}')"
      repair_risk="$(   echo "$line" | sed 's/|||//g' | awk -F'' '{print $13}')"
      exec_time="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $15}')"
      rule_triggered="$(echo "$line" | sed 's/|||//g' | awk -F'' '{print $18}')"

      # Icono de estado
      local icon
      case "$status" in
        PASS)  icon="✓" ;;
        WARN)  icon="!" ;;
        FAIL)  icon="✗" ;;
        SKIP)  icon="–" ;;
        ERROR) icon="⚡" ;;
        *)     icon="?" ;;
      esac

      printf '  %s [%s] %s\n' "$icon" "$severity" "$title"
      printf '  Módulo     : %s\n' "$mod_id"
      printf '  Estado     : %s\n' "$status"
      printf '  Descripción: %s\n' "$description"
      [ "$explanation" != "N/A" ] && [ -n "$explanation" ] && \
        printf '  Explicación: %s\n' "$explanation"
      [ "$risk" != "N/A" ] && [ -n "$risk" ] && \
        printf '  Riesgo     : %s\n' "$risk"
      [ "$action" != "N/A" ] && [ -n "$action" ] && \
        printf '  Acción     : %s\n' "$action"
      [ "$repairable" = "true" ] && \
        printf '  Reparable  : Sí (riesgo: %s)\n' "$repair_risk"
      [ -n "$rule_triggered" ] && \
        printf '  Regla      : %s\n' "$rule_triggered"
      printf '  Tiempo     : %sms\n' "${exec_time:-0}"
      printf '\n'

    done < <(echo "$results_blob")

    printf '-------------------------------------------------------------\n'
    printf '  EVIDENCIAS\n'
    printf '-------------------------------------------------------------\n'
    printf '  Directorio: %s\n\n' "$output_dir"
    find "$output_dir/evidencias" -type f 2>/dev/null | sort | \
      while IFS= read -r f; do
        printf '  %s\n' "${f#$output_dir/}"
      done

    printf '\n=============================================================\n'
    printf '  Meridian v%s — %s\n' \
      "${MERIDIAN_VERSION:-1.0.0-mvp}" \
      "${MERIDIAN_ORG:-Apple Platform Team}"
    printf '=============================================================\n'

  } > "$outfile"

  log_ok "renderer_txt" "Executive_Report.txt generado"
  echo "$outfile"
}
