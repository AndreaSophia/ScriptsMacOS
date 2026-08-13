#!/bin/bash
# =============================================================================
# Meridian — core/module_loader.sh
# Responsabilidad: descubrir módulos en /modules, validar sus manifests
# y registrarlos en el module_registry.
#
# El core NUNCA tiene una lista hardcoded de módulos.
# La única forma de agregar un módulo es colocar su carpeta en /modules.
# =============================================================================

# =============================================================================
# _manifest_get <manifest_path> <key> — Lee un valor de un manifest.yaml
# Parser minimalista para YAML estructurado (formato clave: valor)
# Limitación conocida: no soporta YAML anidado. El schema del manifest
# es intencionalmente plano para compatibilidad con bash.
# =============================================================================
_manifest_get() {
  local manifest="$1"
  local key="$2"
  grep "^${key}:" "$manifest" 2>/dev/null | \
    sed "s/^${key}:[[:space:]]*//" | \
    sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | \
    tr -d '\r' | head -1
}

# =============================================================================
# _manifest_validate <manifest_path> <module_dir>
# =============================================================================
_manifest_validate() {
  local manifest="$1"
  local module_dir="$2"
  local errors=0

  for field in id name category version criticality requires_root timeout_seconds; do
    local val
    val="$(_manifest_get "$manifest" "$field")"
    if [ -z "$val" ]; then
      log_warn "module_loader" \
        "Manifest inválido en '$(basename "$module_dir")': campo '$field' faltante"
      errors=$((errors + 1))
    fi
  done

  if [ ! -f "${module_dir}/diagnose.sh" ]; then
    log_warn "module_loader" \
      "Módulo '$(basename "$module_dir")': falta diagnose.sh"
    errors=$((errors + 1))
  fi

  local repairable
  repairable="$(_manifest_get "$manifest" "repairable")"
  if [ "$repairable" = "true" ]; then
    if [ ! -f "${module_dir}/repair.sh" ]; then
      log_warn "module_loader" \
        "Módulo '$(basename "$module_dir")': manifest dice repairable=true pero falta repair.sh"
      errors=$((errors + 1))
    fi
    if [ ! -f "${module_dir}/validate.sh" ]; then
      log_warn "module_loader" \
        "Módulo '$(basename "$module_dir")': tiene repair.sh pero falta validate.sh"
      errors=$((errors + 1))
    fi
  fi

  local criticality
  criticality="$(_manifest_get "$manifest" "criticality")"
  case "$criticality" in
    low|medium|high|critical) ;;
    *)
      log_warn "module_loader" \
        "Módulo '$(basename "$module_dir")': criticality='$criticality' no válido"
      errors=$((errors + 1))
      ;;
  esac

  [ "$errors" -eq 0 ]
}

# =============================================================================
# module_loader_discover <modules_base_dir>
# =============================================================================
module_loader_discover() {
  local base_dir="$1"
  local loaded=0
  local rejected=0

  if [ ! -d "$base_dir" ]; then
    log_error "module_loader" "Directorio de módulos no encontrado: $base_dir"
    return 1
  fi

  log_info "module_loader" "Escaneando módulos en: $base_dir"

  local manifest
  while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue

    local module_dir
    module_dir="$(dirname "$manifest")"

    log_debug "module_loader" "Encontrado manifest: $manifest"

    if ! _manifest_validate "$manifest" "$module_dir"; then
      log_warn "module_loader" "Módulo rechazado: $module_dir"
      rejected=$((rejected + 1))
      continue
    fi

    local id name category version criticality requires_root timeout
    id="$(_manifest_get "$manifest" "id")"
    name="$(_manifest_get "$manifest" "name")"
    category="$(_manifest_get "$manifest" "category")"
    version="$(_manifest_get "$manifest" "version")"
    criticality="$(_manifest_get "$manifest" "criticality")"
    requires_root="$(_manifest_get "$manifest" "requires_root")"
    timeout="$(_manifest_get "$manifest" "timeout_seconds")"

    if registry_add "$id" "$name" "$category" "$version" \
                    "$criticality" "$module_dir" "$requires_root" "$timeout"; then
      log_ok "module_loader" "Módulo cargado: ${id} (${category}) v${version}"
      loaded=$((loaded + 1))
    fi

  done < <(find "$base_dir" -name "manifest.yaml" -type f 2>/dev/null | sort)

  log_info "module_loader" \
    "Carga completada: ${loaded} módulos registrados, ${rejected} rechazados"

  return 0
}

# =============================================================================
# _module_execute_isolated <module_id> <module_dir> <evidence_dir> <timeout>
#
# Ejecuta diagnose.sh como código SOURCED dentro de un subshell aislado.
# Esto es deliberado: los módulos cumplen el contrato asignando RESULT_* y
# usando `return`, por lo que ejecutarlos con `bash diagnose.sh` perdería esas
# variables al terminar el proceso hijo.
#
# El timeout es implementado con primitivas POSIX/Bash disponibles en macOS;
# no depende del comando GNU `timeout`, que no viene con macOS.
# =============================================================================
_module_execute_isolated() {
  local module_id="$1"
  local module_dir="$2"
  local evidence_dir="$3"
  local timeout_seconds="$4"

  local tmp_base="${TMPDIR:-/tmp}"
  local output_file
  output_file="$(mktemp "${tmp_base%/}/meridian_module.XXXXXX")" || return 1

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
    RESULT_MODULE_VERSION="$(_manifest_get "${module_dir}/manifest.yaml" "version")"

    result_time_start

    # source mantiene RESULT_* en este subshell y permite `return` dentro del módulo.
    # shellcheck source=/dev/null
    source "${module_dir}/diagnose.sh"
    local module_rc=$?

    result_time_end
    RESULT_EXIT_CODE="${RESULT_EXIT_CODE:-$module_rc}"

    result_serialize > "$output_file"
    exit "$module_rc"
  ) &

  local pid=$!
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ] 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
  local module_rc=$?

  cat "$output_file" 2>/dev/null
  rm -f "$output_file"
  return "$module_rc"
}

# =============================================================================
# module_loader_run <module_id> <evidence_dir>
# =============================================================================
module_loader_run() {
  local module_id="$1"
  local evidence_dir="$2"

  if ! registry_exists "$module_id"; then
    log_error "module_loader" "Módulo no registrado: $module_id"
    return 1
  fi

  local module_dir
  module_dir="$(registry_get_path "$module_id")"
  local requires_root
  requires_root="$(registry_get_field "$module_id" 7)"
  local timeout
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

  local module_evidence_dir="${evidence_dir}/${module_id}"
  mkdir -p "$module_evidence_dir" 2>/dev/null

  log_info "module_loader" "Ejecutando módulo: ${module_id} (timeout: ${timeout}s)"

  local serialized_result
  serialized_result="$(_module_execute_isolated \
    "$module_id" "$module_dir" "$module_evidence_dir" "$timeout")"
  local rc=$?

  if [ $rc -eq 124 ]; then
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

  # Si diagnose.sh terminó con error interno, conservamos su resultado para
  # evidencia pero marcamos exit_code si el módulo no lo hizo explícitamente.
  if [ $rc -ne 0 ]; then
    result_deserialize "$serialized_result"
    RESULT_STATUS="ERROR"
    [ "$RESULT_SEVERITY" = "INFO" ] && RESULT_SEVERITY="HIGH"
    RESULT_EXIT_CODE="$rc"
    [ "$RESULT_TITLE" = "Diagnóstico no completado" ] || \
      RESULT_TITLE="${RESULT_TITLE} (error interno rc=${rc})"
    result_serialize
    return 0
  fi

  printf '%s\n' "$serialized_result"
  return 0
}
