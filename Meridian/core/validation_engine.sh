#!/bin/bash
# Meridian — core/validation_engine.sh
# Ejecuta validate.sh después de una reparación conservando RESULT_*.
# El DiagnosticResult viaja por un archivo temporal para no mezclarse con
# cualquier salida informativa que emita validate.sh por stdout.

validation_engine_run() {
  local module_id="$1"
  local module_dir validator_path result_file stdout_file tmp_base serialized expected_version worker_rc

  if ! registry_exists "$module_id"; then
    log_error "validation_engine" "Módulo no registrado: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=not_registered"
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"
  expected_version="$(registry_get_field "$module_id" 4)"
  validator_path="${module_dir}/validate.sh"

  # La validación post-reparación es parte de la frontera de seguridad del
  # contrato IModule. Si desaparece en runtime, no podemos considerar la
  # reparación validada ni devolver éxito por omisión. Tampoco seguimos
  # symlinks: validate.sh se ejecuta dentro de un proceso privilegiado y su
  # destino no debe poder cambiar fuera del árbol registrado del módulo.
  if [ -z "$module_dir" ] || [ ! -f "$validator_path" ]; then
    log_error "validation_engine" "validate.sh no disponible para módulo: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=validator_unavailable"
    return 1
  fi

  if [ -L "$module_dir" ] || [ -L "$validator_path" ]; then
    log_error "validation_engine" "Ruta de validación no confiable para módulo: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=validator_symlink_rejected"
    return 1
  fi

  log_step "Validando resultado de reparación: ${module_id}"

  tmp_base="${TMPDIR:-/tmp}"
  result_file="$(mktemp "${tmp_base%/}/meridian_validation_result.XXXXXX")" || return 1
  stdout_file="$(mktemp "${tmp_base%/}/meridian_validation_stdout.XXXXXX")" || {
    rm -f "$result_file"
    return 1
  }

  # El worker completo es una frontera recuperable. No solo validate.sh puede
  # fallar: también pueden hacerlo la carga del modelo/logger o la serialización.
  # Ejecutarlo dentro de un `if` impide que `set -e` heredado del entrypoint
  # cierre Meridian antes de limpiar temporales y auditar el fallo real.
  #
  # Importante: Bash puede suprimir `errexit` dentro de comandos usados como
  # condición de `if`. Por eso las piezas de infraestructura críticas tienen
  # guardas explícitas y códigos propios; no confiamos en `set -e` para ellas.
  if (
    source "${MERIDIAN_ROOT}/core/result_model.sh" || exit 70
    source "${MERIDIAN_ROOT}/logging/logger.sh" || exit 71

    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="${MERIDIAN_EVIDENCE_DIR:-/tmp}"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    result_init || exit 72
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(grep '^version:' "${module_dir}/manifest.yaml" 2>/dev/null | sed 's/^version:[[:space:]]*//' | tr -d '\r\"' | head -1)"

    result_time_start || exit 73
    # El retorno de validate.sh es parte del protocolo. Se captura para poder
    # serializar un DiagnosticResult incluso cuando el validator retorna != 0.
    local validate_rc
    if source "$validator_path" >"$stdout_file" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"; then
      validate_rc=0
    else
      validate_rc=$?
    fi
    result_time_end || exit 74

    if [ "$validate_rc" -ne 0 ] && [ "${RESULT_EXIT_CODE:-0}" -eq 0 ] 2>/dev/null; then
      RESULT_EXIT_CODE="$validate_rc"
    fi

    if [ "$validate_rc" -ne 0 ] && [ "$RESULT_STATUS" = "PASS" ]; then
      RESULT_STATUS="ERROR"
      RESULT_SEVERITY="HIGH"
      RESULT_TITLE="Validación terminó con error interno"
    fi

    result_serialize > "$result_file" || exit 75
    exit 0
  ); then
    worker_rc=0
  else
    worker_rc=$?
  fi

  if [ -s "$stdout_file" ]; then
    cat "$stdout_file" >&2
  fi

  if [ "$worker_rc" -ne 0 ]; then
    rm -f "$result_file" "$stdout_file"
    log_error "validation_engine" "Falló la infraestructura de validación para ${module_id} (rc=${worker_rc})"
    log_audit "validation_engine" "VALIDATION_ERROR" \
      "module=${module_id} reason=validator_execution_failed rc=${worker_rc}"
    return 1
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

  # La validación solo puede reemplazar el estado del módulo que originó la
  # reparación. Un validate.sh defectuoso no debe poder cambiar module_id o
  # version y terminar reemplazando el resultado canónico de otro módulo.
  if [ "$RESULT_MODULE_ID" != "$module_id" ]; then
    log_error "validation_engine" "validate.sh cambió la identidad del módulo: esperado=${module_id} recibido=${RESULT_MODULE_ID}"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=identity_mismatch received_module=${RESULT_MODULE_ID}"
    return 1
  fi

  if [ -n "$expected_version" ] && [ "$RESULT_MODULE_VERSION" != "$expected_version" ]; then
    log_error "validation_engine" "validate.sh cambió la versión del módulo: esperado=${expected_version} recibido=${RESULT_MODULE_VERSION}"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=version_mismatch expected=${expected_version} received=${RESULT_MODULE_VERSION}"
    return 1
  fi

  # El aggregator representa el estado canónico actual de la sesión, no el
  # historial de cambios. Tras una reparación validada, sustituimos la
  # observación anterior por el resultado post-reparación. El historial queda
  # preservado en audit.log.
  if ! aggregator_replace_current_by_module_id; then
    log_error "validation_engine" "No se pudo actualizar el estado canónico post-reparación: $module_id"
    log_audit "validation_engine" "VALIDATION_ERROR" "module=${module_id} reason=canonical_update_failed"
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
