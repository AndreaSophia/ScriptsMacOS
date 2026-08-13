#!/bin/bash
# =============================================================================
# Meridian — services/diagnostic_service.sh
# Responsabilidad: coordinar el flujo de diagnóstico completo.
# Orquesta engine_init, engine_run, y entrega resultados al reporting_service.
# No contiene lógica de módulos ni de reglas.
# =============================================================================

# =============================================================================
# diagnostic_service_run <output_dir> [module_id...]
# Ejecuta el diagnóstico completo y retorna el resumen.
# Si no se especifican módulos, ejecuta todos los disponibles.
# =============================================================================
diagnostic_service_run() {
  local output_dir="$1"
  shift
  local module_ids=("$@")

  # Inicializar el engine (carga módulos, reglas, logger)
  engine_init "$output_dir"

  # Ejecutar diagnóstico
  engine_run "${module_ids[@]}"

  # Retornar resumen
  engine_get_summary
}

# =============================================================================
# diagnostic_service_get_results — Retorna todos los resultados acumulados
# =============================================================================
diagnostic_service_get_results() {
  engine_get_results
}
