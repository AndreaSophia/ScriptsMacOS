#!/bin/bash
# =============================================================================
# Meridian — core/engine.sh
# Responsabilidad: orquestador principal. Coordina carga de módulos,
# ejecución de diagnósticos, evaluación de reglas y acumulación de resultados.
#
# El engine NO sabe qué hacen los módulos.
# El engine NO sabe qué dicen las reglas.
# El engine solo coordina el flujo.
# =============================================================================

# =============================================================================
# engine_init <output_dir>
# Inicializa el engine para una sesión de diagnóstico.
# Establece rutas, carga módulos y reglas.
# =============================================================================
engine_init() {
  local output_dir="$1"

  export MERIDIAN_OUTPUT_DIR="$output_dir"
  export MERIDIAN_EVIDENCE_DIR="${output_dir}/evidencias"
  export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
  export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"

  mkdir -p "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null || {
    echo "[FATAL] No se pudo crear el directorio de salida: $output_dir" >&2
    exit 1
  }

  # Inicializar logger
  logger_init "${output_dir}/diagnostic.log"

  log_step "Inicializando Meridian v${MERIDIAN_VERSION}"
  log_info "engine" "Output: $output_dir"
  log_info "engine" "Host: $(hostname -s 2>/dev/null) | macOS: $(sw_vers -productVersion 2>/dev/null) | $(uname -m)"

  # Cargar módulos
  log_step "Cargando módulos"
  module_loader_discover "${MERIDIAN_ROOT}/modules"
  log_info "engine" "$(registry_count) módulo(s) disponible(s)"

  # Cargar reglas
  log_step "Cargando reglas"
  rule_loader_load "${MERIDIAN_ROOT}/rules/definitions"
  log_info "engine" "$(rule_loader_count) regla(s) cargada(s)"
}

# =============================================================================
# engine_run <module_id...>
# Ejecuta diagnóstico para los módulos especificados en orden.
# Si no se especifican IDs, ejecuta todos los módulos registrados.
# =============================================================================
engine_run() {
  local module_ids=("$@")

  # Si no se especificaron módulos, ejecutar todos
  if [ ${#module_ids[@]} -eq 0 ]; then
    while IFS= read -r id; do
      [ -n "$id" ] && module_ids+=("$id")
    done < <(registry_get_all_ids)
  fi

  if [ ${#module_ids[@]} -eq 0 ]; then
    log_warn "engine" "No hay módulos disponibles para ejecutar"
    return 1
  fi

  log_step "Ejecutando diagnóstico (${#module_ids[@]} módulo(s))"

  local module_id
  for module_id in "${module_ids[@]}"; do
    _engine_run_module "$module_id"
  done

  log_step "Diagnóstico completado"
  log_info "engine" "$(aggregator_summary)"
}

# =============================================================================
# _engine_run_module <module_id>
# Ejecuta un módulo individual y procesa su resultado.
# =============================================================================
_engine_run_module() {
  local module_id="$1"

  if ! registry_exists "$module_id"; then
    log_warn "engine" "Módulo no registrado: $module_id — se omite"
    return 0
  fi

  local module_name
  module_name="$(registry_get_field "$module_id" 2)"

  log_info "engine" "▷ ${module_name} (${module_id})"

  # Ejecutar el módulo — retorna una línea serializada
  local serialized
  serialized="$(module_loader_run "$module_id" "$MERIDIAN_EVIDENCE_DIR")"
  local run_rc=$?

  if [ -z "$serialized" ] || [ $run_rc -ne 0 ]; then
    log_error "engine" "Módulo '${module_id}' no produjo resultado válido"
    return 1
  fi

  # Deserializar el resultado en variables RESULT_*
  result_deserialize "$serialized"

  # Pasar por el rules engine para enriquecimiento
  rule_engine_evaluate "$module_id"

  # Acumular en el aggregator (re-serializa con posibles cambios del rules engine)
  aggregator_add

  # Log del resultado final
  local status_icon
  case "$RESULT_STATUS" in
    PASS)  status_icon="✓" ;;
    WARN)  status_icon="!" ;;
    FAIL)  status_icon="✗" ;;
    SKIP)  status_icon="–" ;;
    ERROR) status_icon="⚡" ;;
    *)     status_icon="?" ;;
  esac

  log_info "engine" \
    "  ${status_icon} ${RESULT_STATUS} [${RESULT_SEVERITY}] ${RESULT_TITLE}"

  return 0
}

# =============================================================================
# engine_get_results — Retorna todos los resultados acumulados
# =============================================================================
engine_get_results() {
  aggregator_get_all
}

# =============================================================================
# engine_get_summary — Retorna el resumen estadístico de la sesión
# =============================================================================
engine_get_summary() {
  aggregator_summary
}
