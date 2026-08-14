#!/bin/bash
# =============================================================================
# Meridian — core/module_loader.sh
# Descubre módulos, valida manifests y ejecuta diagnósticos en aislamiento.
# Compatible con Bash 3.2/macOS sin dependencias GNU.
# =============================================================================

_manifest_get() {
  local manifest="$1" key="$2"
  grep "^${key}:" "$manifest" 2>/dev/null | \
    sed "s/^${key}:[[:space:]]*//" | \
    sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | \
    tr -d '\r' | head -1
}

_manifest_validate() {
  local manifest="$1" module_dir="$2" errors=0 field val

  for field in id name category version criticality requires_root timeout_seconds; do
    val="$(_manifest_get "$manifest" "$field")"
    if [ -z "$val" ]; then
      log_warn "module_loader" "Manifest inválido en '$(basename "$module_dir")': campo '$field' faltante"
      errors=$((errors + 1))
    fi
  done

  if [ ! -f "${module_dir}/diagnose.sh" ]; then
    log_warn "module_loader" "Módulo '$(basename "$module_dir")': falta diagnose.sh"
    errors=$((errors + 1))
  fi

  local repairable
  repairable="$(_manifest_get "$manifest" repairable)"
  if [ "$repairable" = "true" ]; then
    if [ ! -f "${module_dir}/repair.sh" ]; then
      log_warn "module_loader" "Módulo '$(basename "$module_dir")': manifest dice repairable=true pero falta repair.sh"
      errors=$((errors + 1))
    fi
    if [ ! -f "${module_dir}/validate.sh" ]; then
      log_warn "module_loader" "Módulo '$(basename "$module_dir")': tiene repair.sh pero falta validate.sh"
      errors=$((errors + 1))
    fi
  fi

  local criticality requires_root timeout
  criticality="$(_manifest_get "$manifest" criticality)"
  case "$criticality" in low|medium|high|critical) ;; *)
    log_warn "module_loader" "Módulo '$(basename "$module_dir")': criticality='$criticality' no válido"
    errors=$((errors + 1));;
  esac

  requires_root="$(_manifest_get "$manifest" requires_root)"
  case "$requires_root" in true|false) ;; *)
    log_warn "module_loader" "Módulo '$(basename "$module_dir")': requires_root='$requires_root' no válido"
    errors=$((errors + 1));;
  esac

  timeout="$(_manifest_get "$manifest" timeout_seconds)"
  printf '%s\n' "$timeout" | grep -qE '^[1-9][0-9]*$' || {
    log_warn "module_loader" "Módulo '$(basename "$module_dir")': timeout_seconds='$timeout' no válido"
    errors=$((errors + 1))
  }

  [ "$errors" -eq 0 ]
}

module_loader_discover() {
  local base_dir="$1" loaded=0 rejected=0 manifest module_dir
  local id name category version criticality requires_root timeout

  if [ ! -d "$base_dir" ]; then
    log_error "module_loader" "Directorio de módulos no encontrado: $base_dir"
    return 1
  fi

  log_info "module_loader" "Escaneando módulos en: $base_dir"

  while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue
    module_dir="$(dirname "$manifest")"

    if ! _manifest_validate "$manifest" "$module_dir"; then
      log_warn "module_loader" "Módulo rechazado: $module_dir"
      rejected=$((rejected + 1))
      continue
    fi

    id="$(_manifest_get "$manifest" id)"
    name="$(_manifest_get "$manifest" name)"
    category="$(_manifest_get "$manifest" category)"
    version="$(_manifest_get "$manifest" version)"
    criticality="$(_manifest_get "$manifest" criticality)"
    requires_root="$(_manifest_get "$manifest" requires_root)"
    timeout="$(_manifest_get "$manifest" timeout_seconds)"

    if registry_add "$id" "$name" "$category" "$version" "$criticality" "$module_dir" "$requires_root" "$timeout"; then
      log_ok "module_loader" "Módulo cargado: ${id} (${category}) v${version}"
      loaded=$((loaded + 1))
    fi
  done < <(find "$base_dir" -name manifest.yaml -type f 2>/dev/null | sort)

  log_info "module_loader" "Carga completada: ${loaded} módulos registrados, ${rejected} rechazados"
  return 0
}

# Ejecuta diagnose.sh como source dentro de un subshell. El canal de datos
# (DiagnosticResult) viaja por un archivo separado de stdout, para que cualquier
# printf/echo del módulo no pueda corromper la serialización.
_module_execute_isolated() {
  local module_id="$1" module_dir="$2" evidence_dir="$3" timeout_seconds="$4"
  local tmp_base="${TMPDIR:-/tmp}" result_file stdout_file

  result_file="$(mktemp "${tmp_base%/}/meridian_module_result.XXXXXX")" || return 1
  stdout_file="$(mktemp "${tmp_base%/}/meridian_module_stdout.XXXXXX")" || {
    rm -f "$result_file"
    return 1
  }

  (
    source "${MERIDIAN_CORE_DIR}/result_model.sh"
    source "${MERIDIAN_LOGGING_DIR}/logger.sh"

    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="$evidence_dir"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(_manifest_get "${module_dir}/manifest.yaml" version)"

    result_time_start
    source "${module_dir}/diagnose.sh" >"$stdout_file" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
    local module_rc=$?
    result_time_end

    if [ "$module_rc" -ne 0 ] && [ "${RESULT_EXIT_CODE:-0}" -eq 0 ] 2>/dev/null; then
      RESULT_EXIT_CODE="$module_rc"
    fi

    result_serialize > "$result_file"
    exit "$module_rc"
  ) &

  local pid=$! elapsed=0 module_rc
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ] 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      [ -s "$stdout_file" ] && cat "$stdout_file" >&2
      rm -f "$result_file" "$stdout_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
  module_rc=$?

  [ -s "$stdout_file" ] && cat "$stdout_file" >&2
  cat "$result_file" 2>/dev/null
  rm -f "$result_file" "$stdout_file"
  return "$module_rc"
}

module_loader_run() {
  local module_id="$1" evidence_dir="$2"
  local module_dir requires_root timeout module_evidence_dir serialized_result rc

  if ! registry_exists "$module_id"; then
    log_error "module_loader" "Módulo no registrado: $module_id"
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"
  requires_root="$(registry_get_field "$module_id" 7)"
  timeout="$(registry_get_field "$module_id" 8)"
  timeout="${timeout:-30}"

  if ! privilege_check_module "$module_id" "$requires_root"; then
    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
    RESULT_STATUS="SKIP"
    RESULT_SEVERITY="INFO"
    RESULT_TITLE="Módulo omitido por privilegios insuficientes"
    RESULT_DESCRIPTION="El módulo requiere root y el diagnóstico no corre como root."
    RESULT_EXPLANATION="Ejecutar con sudo para obtener este diagnóstico."
    RESULT_RISK="N/A"
    RESULT_SUGGESTED_ACTION="sudo meridian"
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXECUTION_TIME_MS="0"
    RESULT_EXIT_CODE="0"
    result_serialize
    return 0
  fi

  module_evidence_dir="${evidence_dir}/${module_id}"
  mkdir -p "$module_evidence_dir" 2>/dev/null
  log_info "module_loader" "Ejecutando módulo: ${module_id} (timeout: ${timeout}s)"

  serialized_result="$(_module_execute_isolated "$module_id" "$module_dir" "$module_evidence_dir" "$timeout")"
  rc=$?

  if [ "$rc" -eq 124 ]; then
    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="Módulo excedió el tiempo máximo de ejecución"
    RESULT_DESCRIPTION="El diagnóstico no completó en ${timeout} segundos."
    RESULT_EXPLANATION="Posible bloqueo esperando recursos del sistema o red."
    RESULT_RISK="El estado del módulo es desconocido."
    RESULT_SUGGESTED_ACTION="Reintentar y revisar diagnostic.log."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="124"
    RESULT_RAW_OUTPUT=""
    result_serialize
    return 0
  fi

  if [ -z "$serialized_result" ]; then
    log_error "module_loader" "Módulo '${module_id}' no produjo DiagnosticResult"
    return 1
  fi

  result_deserialize "$serialized_result"
  if ! result_validate; then
    log_error "module_loader" "Módulo '${module_id}' produjo un DiagnosticResult inválido"
    return 1
  fi

  if [ "$rc" -ne 0 ]; then
    RESULT_STATUS="ERROR"
    [ "$RESULT_SEVERITY" = "INFO" ] && RESULT_SEVERITY="HIGH"
    RESULT_EXIT_CODE="$rc"
    if [ "$RESULT_TITLE" = "Diagnóstico no completado" ]; then
      RESULT_TITLE="Error interno del módulo"
    else
      RESULT_TITLE="${RESULT_TITLE} (error interno rc=${rc})"
    fi
    result_serialize
    return 0
  fi

  printf '%s\n' "$serialized_result"
  return 0
}
