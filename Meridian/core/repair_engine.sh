#!/bin/bash
# =============================================================================
# Meridian — core/repair_engine.sh
# Ejecuta reparaciones con confirmación, trazabilidad y validación posterior.
#
# Invariantes de seguridad:
#  - solo se repara un resultado previamente diagnosticado en esta sesión
#  - repair_id y repair_risk provienen del DiagnosticResult canónico
#  - el caller no puede degradar el riesgo declarado
#  - HIGH y CRITICAL permanecen bloqueados por privilege_manager en el MVP
#  - MERIDIAN_TEST_MODE nunca ejecuta cambios reales
#  - la confirmación humana se delega a la frontera UI canónica
#  - repair.sh debe ser un archivo regular no-symlink ejecutado por /bin/bash
# =============================================================================

repair_engine_run() {
  local module_id="$1"
  local requested_repair_id="$2"
  local requested_repair_risk="${3:-}"
  local module_dir repair_path requires_root serialized repair_rc module_name

  if ! registry_exists "$module_id"; then
    log_error "repair_engine" "Módulo no registrado: $module_id"
    return 1
  fi

  if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ]; then
    log_warn "repair_engine" "Reparaciones bloqueadas en MERIDIAN_TEST_MODE"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=test_mode"
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"
  repair_path="${module_dir}/repair.sh"
  if [ -z "$module_dir" ] || [ ! -f "$repair_path" ]; then
    log_error "repair_engine" "repair.sh no encontrado para módulo: $module_id"
    return 1
  fi

  # Una reparación puede modificar el sistema como root. No seguimos symlinks
  # en la ruta del módulo ni en repair.sh: el ejecutable autorizado debe ser el
  # archivo regular que fue registrado dentro del árbol de Meridian.
  if [ -L "$module_dir" ] || [ -L "$repair_path" ]; then
    log_error "repair_engine" "Ruta de reparación no confiable para módulo: $module_id"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=repair_symlink_rejected"
    return 1
  fi

  if ! serialized="$(aggregator_get_by_module_id "$module_id")"; then
    log_error "repair_engine" "No existe DiagnosticResult de sesión para: $module_id"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=no_session_result"
    return 1
  fi

  if ! result_deserialize "$serialized"; then
    log_error "repair_engine" "Framing DiagnosticResult canónico inválido para: $module_id"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=invalid_result_framing"
    return 1
  fi
  if ! result_validate; then
    log_error "repair_engine" "DiagnosticResult canónico inválido para: $module_id"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=invalid_result"
    return 1
  fi

  if [ "$RESULT_REPAIRABLE" != "true" ] || [ -z "$RESULT_REPAIR_ID" ]; then
    log_warn "repair_engine" "El diagnóstico de '${module_id}' no declara reparación disponible"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=not_repairable"
    return 1
  fi

  if [ "$requested_repair_id" != "$RESULT_REPAIR_ID" ]; then
    log_error "repair_engine" "repair_id no coincide con el resultado diagnosticado"
    log_audit "repair_engine" "REPAIR_BLOCKED" \
      "module=${module_id} requested=${requested_repair_id} expected=${RESULT_REPAIR_ID}"
    return 1
  fi

  if [ -n "$requested_repair_risk" ] && [ "$requested_repair_risk" != "$RESULT_REPAIR_RISK" ]; then
    log_error "repair_engine" "repair_risk no coincide con el resultado diagnosticado"
    log_audit "repair_engine" "REPAIR_BLOCKED" \
      "module=${module_id} requested_risk=${requested_repair_risk} expected_risk=${RESULT_REPAIR_RISK}"
    return 1
  fi

  if ! privilege_check_repair "$RESULT_REPAIR_RISK"; then
    return 1
  fi

  requires_root="$(registry_get_field "$module_id" 7)"
  if ! privilege_check_module "$module_id" "$requires_root"; then
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=insufficient_privileges"
    return 1
  fi

  # El core no implementa su propia semántica de confirmación. Si la frontera
  # UI no fue cargada, la reparación falla de forma segura en vez de improvisar.
  if ! command -v tui_confirm_repair >/dev/null 2>&1; then
    log_error "repair_engine" "Frontera de confirmación no disponible"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=confirmation_unavailable"
    return 1
  fi

  module_name="$(registry_get_field "$module_id" 2)"
  if ! tui_confirm_repair \
    "$module_name" \
    "$RESULT_REPAIR_ID" \
    "$RESULT_REPAIR_RISK" \
    "$RESULT_SUGGESTED_ACTION"; then
    log_info "repair_engine" "Reparación cancelada o no confirmable: $RESULT_REPAIR_ID"
    log_audit "repair_engine" "REPAIR_CANCELLED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK}"
    return 0
  fi

  log_audit "repair_engine" "REPAIR_STARTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK} operator=$(privilege_get_current_user)"
  log_step "Ejecutando reparación: ${RESULT_REPAIR_ID}"

  export MERIDIAN_MODULE_DIR="$module_dir"
  export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
  export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
  export RESULT_MODULE_ID RESULT_MODULE_VERSION RESULT_TIMESTAMP RESULT_HOSTNAME
  export RESULT_STATUS RESULT_SEVERITY RESULT_TITLE RESULT_DESCRIPTION
  export RESULT_EXPLANATION RESULT_RISK RESULT_SUGGESTED_ACTION
  export RESULT_REPAIRABLE RESULT_REPAIR_RISK RESULT_REPAIR_ID
  export RESULT_EXECUTION_TIME_MS RESULT_EXIT_CODE RESULT_RAW_OUTPUT
  export RESULT_RULE_TRIGGERED RESULT_EVIDENCE

  # Un rc != 0 es un resultado esperado del protocolo de reparación. Se captura
  # dentro de un if para impedir que `set -e` cierre Meridian antes del audit.
  # Se usa el intérprete del sistema por ruta absoluta: una reparación root no
  # debe depender de PATH ni poder resolver un `bash` ajeno al macOS base.
  if /bin/bash "$repair_path" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"; then
    repair_rc=0
  else
    repair_rc=$?
  fi

  if [ "$repair_rc" -ne 0 ]; then
    log_error "repair_engine" "Reparación falló: ${RESULT_REPAIR_ID} (rc=${repair_rc})"
    log_audit "repair_engine" "REPAIR_FAILED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} rc=${repair_rc}"
    return 1
  fi

  log_ok "repair_engine" "Reparación completada: ${RESULT_REPAIR_ID}"
  log_audit "repair_engine" "REPAIR_COMPLETED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} rc=0"

  validation_engine_run "$module_id"
}
