#!/bin/bash
# Meridian — core/validation_engine.sh
# Ejecuta validate.sh después de una reparación conservando RESULT_*.
# El DiagnosticResult viaja por un archivo temporal para no mezclarse con
# cualquier salida informativa que emita validate.sh por stdout.

validation_engine_run() {
  local module_id="$1"
  local module_dir result_file stdout_file tmp_base serialized

  if ! registry_exists "$module_id"; then
    log_error "validation_engine" "Módulo no registrado: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=not_registered"
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"

  # La validación post-reparación es parte de la frontera de seguridad del
  # contrato IModule. Si desaparece en runtime, no podemos considerar la
  # reparación validada ni devolver éxito por omisión.
  if [ -z "$module_dir" ] || [ ! -f "${module_dir}/validate.sh" ]; then
    log_error "validation_engine" "validate.sh no disponible para módulo: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=validator_unavailable"
    return 1
  fi

  log_step "Validando resultado de reparación: ${module_id}"

  tmp_base="${TMPDIR:-/tmp}"
  result_file="$(mktemp "${tmp_base%/}/meridian_validation_result.XXXXXX")" || return 1
  stdout_file="$(mktemp "${tmp_base%/}/meridian_validation_stdout.XXXXXX")" || {
    rm -f "$result_file"
    return 1
  }

  (
    source "${MERIDIAN_ROOT}/core/result_model.sh"
    source "${MERIDIAN_ROOT}/logging/logger.sh"

    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(grep '^version:' "${module_dir}/manifest.yaml" 2>/dev/null | sed 's/^version:[[:space:]]*//' | tr -d '\r\"' | head -1)"

    result_time_start
    # `set -e` viene heredado del entrypoint. El retorno de validate.sh es parte
    # del protocolo, no una razón para terminar el proceso antes de serializar.
    local validate_rc
    if source "${module_dir}/validate.sh" >"$stdout_file" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"; then
      validate_rc=0
    else
      validate_rc=$?
    fi
    result_time_end

    if [ "$validate_rc" -ne 0 ] && [ "${RESULT_EXIT_CODE:-0}" -eq 0 ] 2>/dev/null; then
      RESULT_EXIT_CODE="$validate_rc"
    fi

    if [ "$validate_rc" -ne 0 ] && [ "$RESULT_STATUS" = "PASS" ]; then
      RESULT_STATUS="ERROR"
      RESULT_SEVERITY="HIGH"
      RESULT_TITLE="Validación terminó con error interno"
    fi

    result_serialize > "$result_file"
    exit 0
  )

  if [ -s "$stdout_file" ]; then
    cat "$stdout_file" >&2
  fi

  serialized="$(cat "$result_file" 2>/dev/null)"
  rm -f "$result_file" "$stdout_file"

  if [ -z "$serialized" ]; then
    log_error "validation_engine" "validate.sh no produjo resultado"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=no_output"
    return 1
  fi

  if ! result_deserialize "$serialized"; then
    log_error "validation_engine" "validate.sh produjo framing DiagnosticResult inválido para: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=invalid_framing"
    return 1
  fi

  if ! result_validate; then
    log_error "validation_engine" "validate.sh produjo un DiagnosticResult inválido para: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=invalid_result"
    return 1
  fi

  if [ "$RESULT_STATUS" = "PASS" ]; then
    log_ok "validation_engine" "Validación exitosa: ${module_id} → ${RESULT_STATUS}"
    log_audit "validation_engine" "VALIDATION_PASSED" "module=${module_id} status=${RESULT_STATUS}"
    return 0
  fi

  log_warn "validation_engine" "Reparación completada pero estado sigue siendo: ${RESULT_STATUS} — ${RESULT_TITLE}"
  log_audit "validation_engine" "VALIDATION_FAILED" "module=${module_id} status=${RESULT_STATUS} title=${RESULT_TITLE}"
  return 1
}
