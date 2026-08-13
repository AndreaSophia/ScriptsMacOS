#!/bin/bash
# =============================================================================
# Meridian — services/reporting_service.sh
# Responsabilidad: coordinar la generación de reportes.
# Delega a cada renderer. No contiene lógica de formato.
# =============================================================================

# =============================================================================
# reporting_service_generate <output_dir> <format...>
# Genera los reportes solicitados. Formatos MVP: txt json
# =============================================================================
reporting_service_generate() {
  local output_dir="$1"
  shift
  local formats=("$@")

  # Default: txt y json si no se especifica
  if [ ${#formats[@]} -eq 0 ]; then
    formats=("txt" "json")
  fi

  local results
  results="$(diagnostic_service_get_results)"

  local summary
  summary="$(engine_get_summary)"

  local fmt
  for fmt in "${formats[@]}"; do
    case "$fmt" in
      txt)
        renderer_txt_generate \
          "$output_dir" "$results" "$summary"
        ;;
      json)
        renderer_json_generate \
          "$output_dir" "$results" "$summary"
        ;;
      *)
        log_warn "reporting_service" "Formato desconocido: $fmt — ignorado"
        ;;
    esac
  done
}
