#!/bin/bash
# =============================================================================
# Meridian — services/reporting_service.sh
# Responsabilidad: coordinar la generación de reportes.
# Delega a cada renderer. No contiene lógica de formato.
# =============================================================================

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

  if [ ${#formats[@]} -eq 0 ]; then
    formats=("txt" "json")
  fi

  [ -d "$output_dir" ] || mkdir -p "$output_dir" 2>/dev/null || {
    log_error "reporting_service" "No se pudo crear directorio de reportes: $output_dir"
    return 1
  }

  local results summary
  results="$(diagnostic_service_get_results)"
  summary="$(engine_get_summary)"

  local fmt failures=0
  for fmt in "${formats[@]}"; do
    case "$fmt" in
      txt)
        if ! renderer_txt_generate "$output_dir" "$results" "$summary"; then
          log_error "reporting_service" "Falló renderer TXT"
          failures=$((failures + 1))
        fi
        ;;
      json)
        if ! renderer_json_generate "$output_dir" "$results" "$summary"; then
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
