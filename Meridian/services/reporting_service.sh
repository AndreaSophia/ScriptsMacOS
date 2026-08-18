#!/bin/bash
# =============================================================================
# Meridian — services/reporting_service.sh
# Responsabilidad: coordinar la generación de reportes.
# Delega a cada renderer. No contiene lógica de formato.
# =============================================================================

# Rutas producidas por la última generación. Se exponen como estado del servicio
# para que el entrypoint no tenga que conocer nombres internos de renderers.
REPORTING_TXT_PATH=""
REPORTING_JSON_PATH=""

# Herramientas de filesystem usadas en una frontera que puede correr como root.
# No se resuelven mediante PATH: reporting no debe permitir que el entorno elija
# qué binario crea directorios durante una sesión privilegiada.
_REPORTING_MKDIR="/bin/mkdir"

_reporting_require_system_tools() {
  [ -x "$_REPORTING_MKDIR" ] || {
    log_error "reporting_service" "Herramienta requerida no disponible: $_REPORTING_MKDIR"
    return 1
  }
  return 0
}

# =============================================================================
# _reporting_validate_output_path <output_dir> <path>
# Un renderer solo puede publicar un artefacto regular creado dentro del
# directorio de reportes de la sesión. Rechazamos rutas inexistentes, symlinks y
# paths externos para que rc=0 no se convierta en una afirmación falsa de éxito.
# =============================================================================
_reporting_validate_output_path() {
  local output_dir="${1:-}"
  local candidate="${2:-}"
  local output_real candidate_parent candidate_parent_real

  [ -n "$output_dir" ] && [ -n "$candidate" ] || return 1
  [ -d "$output_dir" ] || return 1
  [ ! -L "$output_dir" ] || return 1
  [ -f "$candidate" ] || return 1
  [ ! -L "$candidate" ] || return 1

  # Evitamos dirname(1) para que la validación de una ruta publicada no dependa
  # de PATH. El renderer debe devolver una ruta con componente de directorio.
  case "$candidate" in
    */*) candidate_parent="${candidate%/*}" ;;
    *) return 1 ;;
  esac
  [ -n "$candidate_parent" ] || candidate_parent="/"

  output_real="$(cd "$output_dir" 2>/dev/null && pwd -P)" || return 1
  candidate_parent_real="$(cd "$candidate_parent" 2>/dev/null && pwd -P)" || return 1

  [ "$candidate_parent_real" = "$output_real" ]
}

# =============================================================================
# reporting_service_generate <output_dir> <format...>
# Genera los reportes solicitados. Formatos MVP: txt json
# Un renderer fallido no impide intentar los demás; al final se retorna error
# si al menos uno de los formatos solicitados no pudo generarse.
# =============================================================================
reporting_service_generate() {
  local output_dir="${1:-}"
  [ $# -gt 0 ] || {
    log_error "reporting_service" "reporting_service_generate requiere directorio de salida"
    return 1
  }
  shift
  local formats=("$@")

  REPORTING_TXT_PATH=""
  REPORTING_JSON_PATH=""

  if [ -z "$output_dir" ]; then
    log_error "reporting_service" "Directorio de reportes vacío"
    return 1
  fi

  if ! _reporting_require_system_tools; then
    return 1
  fi

  if [ ${#formats[@]} -eq 0 ]; then
    formats=("txt" "json")
  fi

  if [ -L "$output_dir" ]; then
    log_error "reporting_service" "Directorio de reportes no puede ser symlink: $output_dir"
    return 1
  fi

  [ -d "$output_dir" ] || "$_REPORTING_MKDIR" -p "$output_dir" 2>/dev/null || {
    log_error "reporting_service" "No se pudo crear directorio de reportes: $output_dir"
    return 1
  }

  # Reporting consume el estado exclusivamente mediante diagnostic_service.
  # La capa service permanece como frontera canónica y evita dependencias
  # laterales directas contra engine/aggregator desde la aplicación.
  #
  # No confiamos en `set -e` para propagar estas lecturas: una sesión sin
  # resultados o un service defectuoso debe producir un error explícito y
  # determinista, no una salida parcial dependiente del contexto del caller.
  local results summary
  if ! results="$(diagnostic_service_get_results)"; then
    log_error "reporting_service" "No se pudieron obtener resultados de la sesión"
    return 1
  fi
  if [ -z "$results" ]; then
    log_error "reporting_service" "La sesión no contiene resultados para reportar"
    return 1
  fi
  if ! summary="$(diagnostic_service_get_summary)"; then
    log_error "reporting_service" "No se pudo obtener el resumen de la sesión"
    return 1
  fi
  if [ -z "$summary" ]; then
    log_error "reporting_service" "Resumen de sesión vacío"
    return 1
  fi

  local fmt failures=0 generated_path
  for fmt in "${formats[@]}"; do
    generated_path=""
    case "$fmt" in
      txt)
        if generated_path="$(renderer_txt_generate "$output_dir" "$results" "$summary")"; then
          if _reporting_validate_output_path "$output_dir" "$generated_path"; then
            REPORTING_TXT_PATH="$generated_path"
          else
            log_error "reporting_service" "Renderer TXT retornó éxito sin un artefacto válido dentro del directorio de sesión"
            failures=$((failures + 1))
          fi
        else
          log_error "reporting_service" "Falló renderer TXT"
          failures=$((failures + 1))
        fi
        ;;
      json)
        if generated_path="$(renderer_json_generate "$output_dir" "$results" "$summary")"; then
          if _reporting_validate_output_path "$output_dir" "$generated_path"; then
            REPORTING_JSON_PATH="$generated_path"
          else
            log_error "reporting_service" "Renderer JSON retornó éxito sin un artefacto válido dentro del directorio de sesión"
            failures=$((failures + 1))
          fi
        else
          log_error "reporting_service" "Falló renderer JSON"
          failures=$((failures + 1))
        fi
        ;;
      *)
        log_warn "reporting_service" "Formato desconocido: $fmt — ignorado"
        failures=$((failures + 1))
        ;;
    esac
  done

  [ "$failures" -eq 0 ]
}

reporting_service_get_txt_path() {
  printf '%s\n' "$REPORTING_TXT_PATH"
}

reporting_service_get_json_path() {
  printf '%s\n' "$REPORTING_JSON_PATH"
}
