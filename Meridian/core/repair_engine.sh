#!/bin/bash
# =============================================================================
# Meridian — core/repair_engine.sh
# Ejecuta reparaciones con precheck, consentimiento, trazabilidad, validación
# posterior y rollback cuando el módulo declara que puede revertir la acción.
#
# Invariantes de seguridad:
#  - solo se repara un resultado previamente diagnosticado en esta sesión
#  - repair_id y repair_risk provienen del DiagnosticResult canónico
#  - el caller no puede degradar el riesgo declarado
#  - HIGH y CRITICAL permanecen bloqueados por privilege_manager en el MVP
#  - MERIDIAN_TEST_MODE nunca ejecuta cambios reales
#  - la confirmación humana se delega a la frontera UI canónica
#  - precheck.sh y repair.sh son archivos regulares no-symlink
#  - los workers reciben un entorno mínimo; nunca se propagan contraseñas
#  - un fallo de auditoría bloquea la mutación (fail-closed)
#  - rollback.sh es opcional y se intenta tras acción o validación fallida
# =============================================================================

_repair_audit() {
  local action="$1" detail="$2"
  if ! log_audit "repair_engine" "$action" "$detail"; then
    log_error "repair_engine" "No se pudo registrar auditoría: $action"
    return 1
  fi
  return 0
}

_repair_trusted_file() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ]
}

_repair_run_worker() {
  local worker_path="$1"

  # env -i evita que variables heredadas (incluidas credenciales) crucen la
  # frontera del worker. El módulo solo recibe contexto no secreto y rutas
  # canónicas. Las autorizaciones interactivas pertenecen a macOS, no a env.
  /usr/bin/env -i \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    MERIDIAN_ROOT="${MERIDIAN_ROOT}" \
    MERIDIAN_MODULE_DIR="${MERIDIAN_MODULE_DIR}" \
    MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR}" \
    MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE}" \
    RESULT_MODULE_ID="${RESULT_MODULE_ID}" \
    RESULT_REPAIR_ID="${RESULT_REPAIR_ID}" \
    RESULT_REPAIR_RISK="${RESULT_REPAIR_RISK}" \
    /bin/bash "$worker_path" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
}

_repair_attempt_rollback() {
  local module_id="$1" repair_id="$2" rollback_path="$3" reason="$4" rollback_rc

  if [ ! -e "$rollback_path" ]; then
    _repair_audit "ROLLBACK_UNAVAILABLE" \
      "module=${module_id} repair_id=${repair_id} reason=${reason}" || return 1
    return 1
  fi
  if ! _repair_trusted_file "$rollback_path"; then
    _repair_audit "ROLLBACK_BLOCKED" \
      "module=${module_id} repair_id=${repair_id} reason=untrusted_rollback" || return 1
    return 1
  fi

  _repair_audit "ROLLBACK_STARTED" \
    "module=${module_id} repair_id=${repair_id} reason=${reason}" || return 1
  if _repair_run_worker "$rollback_path"; then rollback_rc=0; else rollback_rc=$?; fi
  if [ "$rollback_rc" -eq 0 ]; then
    _repair_audit "ROLLBACK_COMPLETED" \
      "module=${module_id} repair_id=${repair_id} rc=0" || return 1
    return 0
  fi
  _repair_audit "ROLLBACK_FAILED" \
    "module=${module_id} repair_id=${repair_id} rc=${rollback_rc}" || return 1
  return 1
}

repair_engine_run() {
  local module_id="$1"
  local requested_repair_id="$2"
  local requested_repair_risk="${3:-}"
  local module_dir precheck_path repair_path rollback_path requires_root serialized
  local precheck_rc repair_rc module_name

  if ! registry_exists "$module_id"; then
    log_error "repair_engine" "Módulo no registrado: $module_id"
    return 1
  fi

  if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ]; then
    log_warn "repair_engine" "Reparaciones bloqueadas en MERIDIAN_TEST_MODE"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=test_mode" || return 1
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"
  precheck_path="${module_dir}/precheck.sh"
  repair_path="${module_dir}/repair.sh"
  rollback_path="${module_dir}/rollback.sh"
  if [ -z "$module_dir" ] || ! _repair_trusted_file "$precheck_path" || ! _repair_trusted_file "$repair_path"; then
    log_error "repair_engine" "precheck.sh/repair.sh no disponible o no confiable para módulo: $module_id"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=remedy_contract_invalid" || return 1
    return 1
  fi

  # Una reparación puede modificar el sistema como root. No seguimos symlinks
  # en la ruta del módulo ni en repair.sh: el ejecutable autorizado debe ser el
  # archivo regular que fue registrado dentro del árbol de Meridian.
  if [ -L "$module_dir" ]; then
    log_error "repair_engine" "Ruta de reparación no confiable para módulo: $module_id"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=repair_symlink_rejected" || return 1
    return 1
  fi

  if ! serialized="$(aggregator_get_by_module_id "$module_id")"; then
    log_error "repair_engine" "No existe DiagnosticResult de sesión para: $module_id"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=no_session_result" || return 1
    return 1
  fi

  if ! result_deserialize "$serialized"; then
    log_error "repair_engine" "Framing DiagnosticResult canónico inválido para: $module_id"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=invalid_result_framing" || return 1
    return 1
  fi
  if ! result_validate; then
    log_error "repair_engine" "DiagnosticResult canónico inválido para: $module_id"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=invalid_result" || return 1
    return 1
  fi

  if [ "$RESULT_REPAIRABLE" != "true" ] || [ -z "$RESULT_REPAIR_ID" ]; then
    log_warn "repair_engine" "El diagnóstico de '${module_id}' no declara reparación disponible"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=not_repairable" || return 1
    return 1
  fi

  if [ "$requested_repair_id" != "$RESULT_REPAIR_ID" ]; then
    log_error "repair_engine" "repair_id no coincide con el resultado diagnosticado"
    _repair_audit "REPAIR_BLOCKED" \
      "module=${module_id} requested=${requested_repair_id} expected=${RESULT_REPAIR_ID}"
    return 1
  fi

  if [ -n "$requested_repair_risk" ] && [ "$requested_repair_risk" != "$RESULT_REPAIR_RISK" ]; then
    log_error "repair_engine" "repair_risk no coincide con el resultado diagnosticado"
    _repair_audit "REPAIR_BLOCKED" \
      "module=${module_id} requested_risk=${requested_repair_risk} expected_risk=${RESULT_REPAIR_RISK}"
    return 1
  fi

  if ! privilege_check_repair "$RESULT_REPAIR_RISK"; then
    return 1
  fi

  requires_root="$(registry_get_field "$module_id" 7)"
  if ! privilege_check_module "$module_id" "$requires_root"; then
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=insufficient_privileges" || return 1
    return 1
  fi

  export MERIDIAN_MODULE_DIR="$module_dir"
  export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
  export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"

  _repair_audit "REPAIR_REQUESTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK} operator=$(privilege_get_current_user)" || return 1
  _repair_audit "PRECHECK_STARTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID}" || return 1
  if _repair_run_worker "$precheck_path"; then precheck_rc=0; else precheck_rc=$?; fi
  if [ "$precheck_rc" -ne 0 ]; then
    _repair_audit "PRECHECK_FAILED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} rc=${precheck_rc}" || return 1
    return 1
  fi
  _repair_audit "PRECHECK_PASSED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID}" || return 1

  # La confirmación debe ser exactamente la función TUI cargada por Meridian.
  # `command -v` también acepta ejecutables externos; bajo root, un PATH hostil
  # podría hacer pasar un binario llamado tui_confirm_repair por esta frontera.
  # `declare -F` es builtin de Bash 3.2 y solo reconoce funciones del shell.
  if ! declare -F tui_confirm_repair >/dev/null 2>&1; then
    log_error "repair_engine" "Frontera de confirmación no disponible"
    _repair_audit "REPAIR_BLOCKED" "module=${module_id} reason=confirmation_unavailable" || return 1
    return 1
  fi

  module_name="$(registry_get_field "$module_id" 2)"
  if ! tui_confirm_repair \
    "$module_name" \
    "$RESULT_REPAIR_ID" \
    "$RESULT_REPAIR_RISK" \
    "$RESULT_SUGGESTED_ACTION"; then
    log_info "repair_engine" "Reparación cancelada o no confirmable: $RESULT_REPAIR_ID"
    _repair_audit "REPAIR_CANCELLED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK}"
    return 0
  fi

  _repair_audit "CONSENT_GRANTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK}" || return 1
  _repair_audit "REPAIR_STARTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK} operator=$(privilege_get_current_user)" || return 1
  log_step "Ejecutando reparación: ${RESULT_REPAIR_ID}"

  # Un rc != 0 es un resultado esperado del protocolo de reparación. Se captura
  # dentro de un if para impedir que `set -e` cierre Meridian antes del audit.
  # Se usa el intérprete del sistema por ruta absoluta: una reparación root no
  # debe depender de PATH ni poder resolver un `bash` ajeno al macOS base.
  if _repair_run_worker "$repair_path"; then
    repair_rc=0
  else
    repair_rc=$?
  fi

  if [ "$repair_rc" -ne 0 ]; then
    log_error "repair_engine" "Reparación falló: ${RESULT_REPAIR_ID} (rc=${repair_rc})"
    _repair_audit "REPAIR_FAILED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} rc=${repair_rc}" || return 1
    _repair_attempt_rollback "$module_id" "$RESULT_REPAIR_ID" "$rollback_path" "action_failed" || true
    return 1
  fi

  log_ok "repair_engine" "Reparación completada: ${RESULT_REPAIR_ID}"
  _repair_audit "REPAIR_COMPLETED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} rc=0" || return 1

  if validation_engine_run "$module_id"; then
    return 0
  fi

  _repair_audit "REPAIR_VALIDATION_FAILED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID}" || return 1
  _repair_attempt_rollback "$module_id" "$RESULT_REPAIR_ID" "$rollback_path" "validation_failed" || true
  return 1
}
