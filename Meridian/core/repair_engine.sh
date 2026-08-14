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
# =============================================================================

repair_engine_run() {
  local module_id="$1"
  local requested_repair_id="$2"
  local requested_repair_risk="${3:-}"
  local module_dir requires_root serialized repair_rc

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
  if [ -z "$module_dir" ] || [ ! -f "${module_dir}/repair.sh" ]; then
    log_error "repair_engine" "repair.sh no encontrado para módulo: $module_id"
    return 1
  fi

  # La autorización se deriva del resultado que realmente produjo el engine,
  # no de parámetros libres de la UI/caller. Esto evita degradar artificialmente
  # un riesgo HIGH a LOW al invocar repair_engine_run.
  if ! serialized="$(aggregator_get_by_module_id "$module_id")"; then
    log_error "repair_engine" "No existe DiagnosticResult de sesión para: $module_id"
    log_audit "repair_engine" "REPAIR_BLOCKED" "module=${module_id} reason=no_session_result"
    return 1
  fi

  result_deserialize "$serialized"
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

  _repair_show_warning "$module_id" "$RESULT_REPAIR_ID" "$RESULT_REPAIR_RISK"

  if ! _repair_confirm "$RESULT_REPAIR_RISK"; then
    log_info "repair_engine" "Reparación cancelada por el usuario: $RESULT_REPAIR_ID"
    log_audit "repair_engine" "REPAIR_CANCELLED" \
      "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK}"
    return 0
  fi

  log_audit "repair_engine" "REPAIR_STARTED" \
    "module=${module_id} repair_id=${RESULT_REPAIR_ID} risk=${RESULT_REPAIR_RISK} operator=$(privilege_get_current_user)"
  log_step "Ejecutando reparación: ${RESULT_REPAIR_ID}"

  # IModule exige entregar el contexto del DiagnosticResult por entorno.
  # Exportamos una copia explícita para que repair.sh no dependa de variables
  # globales heredadas accidentalmente por Bash.
  export MERIDIAN_MODULE_DIR="$module_dir"
  export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
  export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
  export RESULT_MODULE_ID RESULT_MODULE_VERSION RESULT_TIMESTAMP RESULT_HOSTNAME
  export RESULT_STATUS RESULT_SEVERITY RESULT_TITLE RESULT_DESCRIPTION
  export RESULT_EXPLANATION RESULT_RISK RESULT_SUGGESTED_ACTION
  export RESULT_REPAIRABLE RESULT_REPAIR_RISK RESULT_REPAIR_ID
  export RESULT_EXECUTION_TIME_MS RESULT_EXIT_CODE RESULT_RAW_OUTPUT
  export RESULT_RULE_TRIGGERED RESULT_EVIDENCE

  bash "${module_dir}/repair.sh" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
  repair_rc=$?

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

_repair_show_warning() {
  local module_id="$1"
  local repair_id="$2"
  local repair_risk="$3"
  local module_name
  module_name="$(registry_get_field "$module_id" 2)"

  printf "\n"
  printf "  \033[1;33m⚠  REPARACIÓN SOLICITADA\033[0m\n"
  printf "  ─────────────────────────────────────────\n"
  printf "  Módulo  : %s\n" "$module_name"
  printf "  Acción  : %s\n" "$repair_id"
  printf "  Riesgo  : \033[1m%s\033[0m\n" "$repair_risk"
  printf "  ─────────────────────────────────────────\n"
  printf "\n"
}

_repair_confirm() {
  local repair_risk="$1" reply

  case "$repair_risk" in
    LOW)
      printf "  Esta operación tiene riesgo BAJO. ¿Deseas continuar? (s/n): "
      read -r reply
      reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
      [ "$reply" = "s" ] || [ "$reply" = "si" ] || [ "$reply" = "sí" ]
      ;;
    MEDIUM)
      printf "  Esta operación tiene riesgo MEDIO. Escribe CONFIRMAR para proceder: "
      read -r reply
      [ "$reply" = "CONFIRMAR" ]
      ;;
    *)
      # HIGH/CRITICAL no deberían llegar aquí: privilege_check_repair los bloquea.
      return 1
      ;;
  esac
}
