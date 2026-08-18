#!/bin/bash
# =============================================================================
# Meridian — services/diagnostic_service.sh
# Responsabilidad: frontera canónica entre la capa de aplicación y el engine.
# Permite inicializar por separado para que la TUI pueda consultar el registry
# antes de ejecutar, sin obligar al entrypoint a saltarse la capa service.
# =============================================================================

# diagnostic_service_init <output_dir>
# Inicializa una sesión (logger, registry, reglas y aggregator).
diagnostic_service_init() {
  local output_dir="${1:-}"

  if [ -z "$output_dir" ]; then
    printf '%s\n' "[ERROR] diagnostic_service_init requiere un directorio de salida" >&2
    return 1
  fi

  if ! engine_init "$output_dir"; then
    return 1
  fi

  return 0
}

# diagnostic_service_execute [module_id...]
# Ejecuta módulos sobre una sesión ya inicializada. Sin IDs ejecuta todos.
diagnostic_service_execute() {
  if ! engine_run "$@"; then
    return 1
  fi

  return 0
}

# diagnostic_service_run <output_dir> [module_id...]
# Atajo no interactivo: inicializa, ejecuta y emite el resumen por stdout.
diagnostic_service_run() {
  local output_dir="${1:-}"
  [ $# -gt 0 ] || {
    printf '%s\n' "[ERROR] diagnostic_service_run requiere un directorio de salida" >&2
    return 1
  }
  shift

  if ! diagnostic_service_init "$output_dir"; then
    return 1
  fi

  if ! diagnostic_service_execute "$@"; then
    return 1
  fi

  diagnostic_service_get_summary
}

# diagnostic_service_get_results — Retorna todos los resultados acumulados.
diagnostic_service_get_results() {
  engine_get_results
}

# diagnostic_service_get_summary — Retorna el resumen estadístico de la sesión.
diagnostic_service_get_summary() {
  engine_get_summary
}

# diagnostic_service_get_count — Retorna el total de resultados canónicos.
# La capa aplicación no debe consultar el aggregator directamente.
diagnostic_service_get_count() {
  aggregator_count
}

# diagnostic_service_get_count_by_status <status>
# Expone métricas de sesión sin filtrar detalles internos del aggregator.
diagnostic_service_get_count_by_status() {
  local status="${1:-}"
  [ -n "$status" ] || {
    printf '%s\n' "[ERROR] diagnostic_service_get_count_by_status requiere status" >&2
    return 1
  }
  aggregator_count_by_status "$status"
}
