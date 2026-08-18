#!/bin/bash
# =============================================================================
# Meridian — ui/tui/result_display.sh
# Responsabilidad: mostrar resultados de diagnóstico en consola con formato
# visual claro. No contiene lógica de negocio.
#
# DiagnosticResult v2 se consume exclusivamente mediante result_deserialize;
# la UI no conoce ni interpreta el formato interno de serialización.
# =============================================================================

_color_for_severity() {
  case "$1" in
    CRITICAL) printf '\033[1;31m' ;;
    HIGH)     printf '\033[0;31m' ;;
    MEDIUM)   printf '\033[0;33m' ;;
    LOW)      printf '\033[0;34m' ;;
    INFO)     printf '\033[0;32m' ;;
    *)        printf '\033[0;90m' ;;
  esac
}

_color_for_status() {
  case "$1" in
    PASS)  printf '\033[1;32m' ;;
    WARN)  printf '\033[1;33m' ;;
    FAIL)  printf '\033[1;31m' ;;
    SKIP)  printf '\033[0;90m' ;;
    ERROR) printf '\033[1;35m' ;;
    *)     printf '\033[0m' ;;
  esac
}

_RST='\033[0m'

# Lee una clave del resumen canónico (key=value separados por espacios) sin
# depender de grep/cut. Siempre retorna 0 para que una clave ausente no active
# `set -e` desde la capa de presentación.
_summary_get() {
  local summary="$1" key="$2" token
  for token in $summary; do
    case "$token" in
      "${key}="*)
        printf '%s\n' "${token#*=}"
        return 0
        ;;
    esac
  done
  printf '%s\n' ""
  return 0
}

# =============================================================================
# tui_display_results <results_blob>
# =============================================================================
tui_display_results() {
  local results_blob="$1"

  printf "\n"
  tui_separator
  printf "  \033[1;37m  RESULTADOS DEL DIAGNÓSTICO\033[0m\n"
  tui_separator
  printf "\n"

  local has_results=false
  local line

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Nunca validar estado residual. Si el framing no puede deserializarse,
    # la línea se rechaza antes de consultar RESULT_*.
    if ! result_deserialize "$line"; then
      printf "  \033[1;35m⚡\033[0m  \033[0;90mResultado inválido omitido por la UI.\033[0m\n\n"
      continue
    fi
    if ! result_validate >/dev/null 2>&1; then
      printf "  \033[1;35m⚡\033[0m  \033[0;90mResultado inválido omitido por la UI.\033[0m\n\n"
      continue
    fi

    has_results=true

    local status_color sev_color icon
    status_color="$(_color_for_status "$RESULT_STATUS")"
    sev_color="$(_color_for_severity "$RESULT_SEVERITY")"

    case "$RESULT_STATUS" in
      PASS)  icon="✓" ;;
      WARN)  icon="!" ;;
      FAIL)  icon="✗" ;;
      SKIP)  icon="–" ;;
      ERROR) icon="⚡" ;;
      *)     icon="?" ;;
    esac

    printf "  ${status_color}%s${_RST}  ${sev_color}[%-8s]${_RST}  \033[1m%s\033[0m\n" \
      "$icon" "$RESULT_SEVERITY" "$RESULT_TITLE"
    printf "     \033[0;90m%-12s${_RST}  %s\n" \
      "$RESULT_MODULE_ID" "$RESULT_DESCRIPTION"

    if [ "$RESULT_SUGGESTED_ACTION" != "N/A" ] && \
       [ -n "$RESULT_SUGGESTED_ACTION" ]; then
      printf "     \033[0;36m→ %s${_RST}\n" "$RESULT_SUGGESTED_ACTION"
    fi

    if [ "$RESULT_REPAIRABLE" = "true" ]; then
      printf "     \033[0;33m[⚙ Reparación disponible · riesgo %s]${_RST}\n" \
        "$RESULT_REPAIR_RISK"
    fi

    printf "\n"
  done <<EOF_RESULTS
$results_blob
EOF_RESULTS

  if [ "$has_results" = "false" ]; then
    printf "  \033[0;90mNo hay resultados para mostrar.\033[0m\n\n"
  fi
}

# =============================================================================
# tui_display_summary <summary_string>
# =============================================================================
tui_display_summary() {
  local summary="$1"

  local total pass warn fail skip error worst_sev
  total="$(_summary_get "$summary" total)"
  pass="$(_summary_get "$summary" pass)"
  warn="$(_summary_get "$summary" warn)"
  fail="$(_summary_get "$summary" fail)"
  skip="$(_summary_get "$summary" skip)"
  error="$(_summary_get "$summary" error)"
  worst_sev="$(_summary_get "$summary" worst_severity)"

  # La TUI es presentación, no fuente de verdad. Un resumen incompleto se
  # representa con defaults seguros en vez de abortar toda la sesión.
  case "$worst_sev" in
    CRITICAL|HIGH|MEDIUM|LOW|INFO) ;;
    *) worst_sev="INFO" ;;
  esac

  local worst_color
  worst_color="$(_color_for_severity "$worst_sev")"

  printf "\n"
  tui_separator
  printf "  \033[1;37m  RESUMEN\033[0m\n"
  tui_separator
  printf "\n"
  printf "  Módulos ejecutados : \033[1m%s\033[0m\n" "${total:-0}"
  printf "  \033[1;32m✓ Pasaron\033[0m           : %s\n" "${pass:-0}"
  printf "  \033[1;33m! Advertencias\033[0m      : %s\n" "${warn:-0}"
  printf "  \033[1;31m✗ Fallaron\033[0m          : %s\n" "${fail:-0}"
  printf "  \033[0;90m– Omitidos\033[0m          : %s\n" "${skip:-0}"
  printf "  \033[1;35m⚡ Errores\033[0m           : %s\n" "${error:-0}"
  printf "  Severidad máxima   : ${worst_color}\033[1m%s\033[0m\n" "$worst_sev"
  printf "\n"
}

# =============================================================================
# tui_display_output_paths <output_dir> <txt_path> <json_path>
# =============================================================================
tui_display_output_paths() {
  local output_dir="$1"
  local txt_path="$2"
  local json_path="$3"

  tui_separator
  printf "  \033[0;90mCarpeta    : %s\033[0m\n" "$output_dir"
  [ -n "$txt_path" ]  && printf "  \033[0;90mReporte TXT: %s\033[0m\n" "$txt_path"
  [ -n "$json_path" ] && printf "  \033[0;90mReporte JSON: %s\033[0m\n" "$json_path"
  tui_separator
  printf "\n"
}
