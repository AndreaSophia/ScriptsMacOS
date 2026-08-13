#!/bin/bash
# =============================================================================
# Meridian — ui/tui/result_display.sh
# Responsabilidad: mostrar resultados de diagnóstico en consola con formato
# visual claro. No contiene lógica de negocio.
# =============================================================================

# Colores por severidad
_color_for_severity() {
  case "$1" in
    CRITICAL) printf '\033[1;31m' ;;  # rojo bold
    HIGH)     printf '\033[0;31m' ;;  # rojo
    MEDIUM)   printf '\033[0;33m' ;;  # amarillo
    LOW)      printf '\033[0;34m' ;;  # azul
    INFO)     printf '\033[0;32m' ;;  # verde
    *)        printf '\033[0;90m' ;;  # gris
  esac
}

_color_for_status() {
  case "$1" in
    PASS)  printf '\033[1;32m' ;;  # verde bold
    WARN)  printf '\033[1;33m' ;;  # amarillo bold
    FAIL)  printf '\033[1;31m' ;;  # rojo bold
    SKIP)  printf '\033[0;90m' ;;  # gris
    ERROR) printf '\033[1;35m' ;;  # magenta bold
    *)     printf '\033[0m' ;;
  esac
}

_RST='\033[0m'

# =============================================================================
# tui_display_results <results_blob>
# Muestra todos los resultados en formato de tabla visual
# =============================================================================
tui_display_results() {
  local results_blob="$1"

  printf "\n"
  tui_separator
  printf "  \033[1;37m  RESULTADOS DEL DIAGNÓSTICO\033[0m\n"
  tui_separator
  printf "\n"

  local has_results=false

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    has_results=true

    local mod_id status severity title description action repairable

    mod_id="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $1}')"
    status="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $5}')"
    severity="$(   echo "$line" | sed 's/|||//g' | awk -F'' '{print $6}')"
    title="$(      echo "$line" | sed 's/|||//g' | awk -F'' '{print $7}')"
    description="$(echo "$line" | sed 's/|||//g' | awk -F'' '{print $8}')"
    action="$(     echo "$line" | sed 's/|||//g' | awk -F'' '{print $11}')"
    repairable="$( echo "$line" | sed 's/|||//g' | awk -F'' '{print $12}')"

    local status_color sev_color icon
    status_color="$(_color_for_status "$status")"
    sev_color="$(_color_for_severity "$severity")"

    case "$status" in
      PASS)  icon="✓" ;;
      WARN)  icon="!" ;;
      FAIL)  icon="✗" ;;
      SKIP)  icon="–" ;;
      ERROR) icon="⚡" ;;
      *)     icon="?" ;;
    esac

    # Línea principal del resultado
    printf "  ${status_color}%s${_RST}  ${sev_color}[%-8s]${_RST}  \033[1m%s\033[0m\n" \
      "$icon" "$severity" "$title"
    printf "     \033[0;90m%-12s${_RST}  %s\n" "$mod_id" "$description"

    # Acción sugerida (solo si hay algo útil)
    if [ "$action" != "N/A" ] && [ -n "$action" ]; then
      printf "     \033[0;36m→ %s${_RST}\n" "$action"
    fi

    # Indicador de reparación disponible
    if [ "$repairable" = "true" ]; then
      printf "     \033[0;33m[⚙ Reparación disponible]${_RST}\n"
    fi

    printf "\n"

  done < <(echo "$results_blob")

  if [ "$has_results" = "false" ]; then
    printf "  \033[0;90mNo hay resultados para mostrar.\033[0m\n\n"
  fi
}

# =============================================================================
# tui_display_summary <summary_string>
# Muestra el resumen estadístico final
# =============================================================================
tui_display_summary() {
  local summary="$1"

  local total pass warn fail skip error worst_sev
  total="$(   echo "$summary" | grep -o 'total=[^ ]*'   | cut -d= -f2)"
  pass="$(    echo "$summary" | grep -o 'pass=[^ ]*'    | cut -d= -f2)"
  warn="$(    echo "$summary" | grep -o 'warn=[^ ]*'    | cut -d= -f2)"
  fail="$(    echo "$summary" | grep -o 'fail=[^ ]*'    | cut -d= -f2)"
  skip="$(    echo "$summary" | grep -o 'skip=[^ ]*'    | cut -d= -f2)"
  error="$(   echo "$summary" | grep -o 'error=[^ ]*'   | cut -d= -f2)"
  worst_sev="$(echo "$summary" | grep -o 'worst_severity=[^ ]*' | cut -d= -f2)"

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
  printf "  Severidad máxima   : ${worst_color}\033[1m%s\033[0m\n" "${worst_sev:-INFO}"
  printf "\n"
}

# =============================================================================
# tui_display_output_paths <output_dir> <txt_path> <json_path>
# Muestra las rutas de los archivos generados
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
