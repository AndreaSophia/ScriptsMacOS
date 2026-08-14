#!/bin/bash
# Meridian — core/validation_engine.sh
# Ejecuta validate.sh después de una reparación conservando RESULT_*.

validation_engine_run() {
  local module_id="$1"
  local module_dir serialized validate_rc

  module_dir="$(registry_get_path "$module_id")"

  if [ ! -f "${module_dir}/validate.sh" ]; then
    log_warn "validation_engine" "validate.sh no encontrado para módulo: $module_id — no se puede validar"
    return 0
  fi

  log_step "Validando resultado de reparación: ${module_id}"

  serialized="$(
    source "${MERIDIAN_ROOT}/core/result_model.sh"
    source "${MERIDIAN_ROOT}/logging/logger.sh"

    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(grep '^version:' "${module_dir}/manifest.yaml" 2>/dev/null | sed 's/^version:[[:space:]]*//' | tr -d '\r"' | head -1)"

    result_time_start
    # validate.sh usa el mismo contrato que diagnose.sh: asigna RESULT_* y puede usar return.
    source "${module_dir}/validate.sh" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
    validate_rc=$?
    result_time_end
    RESULT_EXIT_CODE="${RESULT_EXIT_CODE:-$validate_rc}"

    if [ "$validate_rc" -ne 0 ] && [ "$RESULT_STATUS" = "PASS" ]; then
      RESULT_STATUS="ERROR"
      RESULT_SEVERITY="HIGH"
      RESULT_TITLE="Validación terminó con error interno"
      RESULT_EXIT_CODE="$validate_rc"
    fi

    result_serialize
  )"

  if [ -z "$serialized" ]; then
    log_error "validation_engine" "validate.sh no produjo resultado"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=no_output"
    return 1
  fi

  result_deserialize "$serialized"

  if [ "$RESULT_STATUS" = "PASS" ]; then
    log_ok "validation_engine" "Validación exitosa: ${module_id} → ${RESULT_STATUS}"
    log_audit "validation_engine" "VALIDATION_PASSED" "module=${module_id} status=${RESULT_STATUS}"
    return 0
  fi

  log_warn "validation_engine" "Reparación completada pero estado sigue siendo: ${RESULT_STATUS} — ${RESULT_TITLE}"
  log_audit "validation_engine" "VALIDATION_FAILED" "module=${module_id} status=${RESULT_STATUS} title=${RESULT_TITLE}"
  return 1
}
