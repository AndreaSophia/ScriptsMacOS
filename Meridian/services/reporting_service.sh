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

# =============================================================================
# reporting_service_generate <output_dir> <format...>
# Genera los reportes solicitados. Formatos MVP: txt json
# Un renderer fallido no impide intentar los demás; al final se retorna error
# si al menos uno de los formatos solicitados no pudo generarse.
# =============================================================================
reporting_service_generate() {
  local output_dir="$1"
  shift
  local formats=("$@")

  REPORTING_TXT_PATH=""
  REPORTING_JSON_PATH=""

  if [ ${#formats[@]} -eq 0 ]; then
    formats=("txt" "json")
  fi

  [ -d "$output_dir" ] || mkdir -p "$output_dir" 2>/dev/null || {
    log_error "reporting_service" "No se pudo crear directorio de reportes: $output_dir"
    return 1
  }

  # Reporting consume el estado exclusivamente mediante diagnostic_service.
  # La capa service permanece como frontera canónica y evita dependencias
  # laterales directas contra engine/aggregator desde la aplicación.
  local results summary
  results="$(diagnostic_service_get_results)"
  summary="$(diagnostic_service_get_summary)"

  local fmt failures=0 generated_path
  for fmt in "${formats[@]}"; do
    case "$fmt" in
      txt)
        if generated_path="$(renderer_txt_generate "$output_dir" "$results" "$summary")"; then
          REPORTING_TXT_PATH="$generated_path"
        else
          log_error "reporting_service" "Falló renderer TXT"
          failures=$((failures + 1))
        fi
        ;;
      json)
        if generated_path="$(renderer_json_generate "$output_dir" "$results" "$summary")"; then
          REPORTING_JSON_PATH="$generated_path"
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
