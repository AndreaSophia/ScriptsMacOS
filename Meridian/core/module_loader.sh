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
    sed 's/^["\x27]//' | sed 's/["\x27]$//' | \
    tr -d '\r' | head -1
}

# =============================================================================
# _manifest_validate <manifest_path> <module_dir>
# Valida que el manifest contiene todos los campos obligatorios y que
# los archivos requeridos existen en el directorio del módulo.
# Retorna 0 si es válido, 1 si no (con mensajes de error en stderr)
# =============================================================================
_manifest_validate() {
  local manifest="$1"
  local module_dir="$2"
  local errors=0

  # Campos obligatorios del manifest
  for field in id name category version criticality requires_root timeout_seconds; do
    local val
    val="$(_manifest_get "$manifest" "$field")"
    if [ -z "$val" ]; then
      log_warn "module_loader" \
        "Manifest inválido en '$(basename "$module_dir")': campo '$field' faltante"
      errors=$((errors + 1))
    fi
  done

  # Archivo diagnose.sh debe existir
  if [ ! -f "${module_dir}/diagnose.sh" ]; then
    log_warn "module_loader" \
      "Módulo '$(basename "$module_dir")': falta diagnose.sh"
    errors=$((errors + 1))
  fi

  # Si repairable no está implícito, verificar consistencia
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

  # Validar enum criticality
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

  return $errors
}

# =============================================================================
# module_loader_discover <modules_base_dir>
# Escanea el directorio base buscando manifests y registra los módulos válidos.
# Retorna el número de módulos registrados correctamente.
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

  # Buscar todos los manifest.yaml recursivamente
  local manifest
  while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue

    local module_dir
    module_dir="$(dirname "$manifest")"

    log_debug "module_loader" "Encontrado manifest: $manifest"

    # Validar el manifest
    if ! _manifest_validate "$manifest" "$module_dir"; then
      log_warn "module_loader" "Módulo rechazado: $module_dir"
      rejected=$((rejected + 1))
      continue
    fi

    # Extraer campos del manifest
    local id name category version criticality requires_root timeout
    id="$(_manifest_get "$manifest" "id")"
    name="$(_manifest_get "$manifest" "name")"
    category="$(_manifest_get "$manifest" "category")"
    version="$(_manifest_get "$manifest" "version")"
    criticality="$(_manifest_get "$manifest" "criticality")"
    requires_root="$(_manifest_get "$manifest" "requires_root")"
    timeout="$(_manifest_get "$manifest" "timeout_seconds")"

    # Registrar en el registry
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
# module_loader_run <module_id> <evidence_dir>
# Ejecuta el diagnose.sh de un módulo en un subshell aislado.
# El subshell previene que las variables del módulo contaminen el engine.
# Retorna el resultado serializado en stdout, rc en $?
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

  # Verificar privilegios
  if ! privilege_check_module "$module_id" "$requires_root"; then
    # Construir un resultado SKIP para el módulo
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

  # Crear directorio de evidencia para el módulo
  local module_evidence_dir="${evidence_dir}/${module_id}"
  mkdir -p "$module_evidence_dir" 2>/dev/null

  log_info "module_loader" "Ejecutando módulo: ${module_id} (timeout: ${timeout}s)"

  # Ejecutar en subshell para aislamiento de variables
  # El subshell hereda las funciones del core via source, pero sus variables
  # no afectan al shell padre.
  local serialized_result
  serialized_result="$(
    # Importar solo las dependencias necesarias dentro del subshell
    # shellcheck source=/dev/null
    source "${MERIDIAN_CORE_DIR}/result_model.sh"
    # shellcheck source=/dev/null
    source "${MERIDIAN_LOGGING_DIR}/logger.sh"

    # Variables de entorno para el módulo
    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="$module_evidence_dir"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(grep "^version:" "${module_dir}/manifest.yaml" 2>/dev/null | \
      sed 's/^version:[[:space:]]*//' | head -1)"

    result_time_start

    # Ejecutar diagnose.sh con timeout
    # shellcheck source=/dev/null
    timeout "$timeout" bash "${module_dir}/diagnose.sh" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
    local rc=$?

    result_time_end

    if [ $rc -eq 124 ]; then
      RESULT_STATUS="ERROR"
      RESULT_SEVERITY="HIGH"
      RESULT_TITLE="Módulo excedió el tiempo máximo de ejecución"
      RESULT_DESCRIPTION="El diagnóstico no completó en ${timeout} segundos."
      RESULT_EXPLANATION="Posible bloqueo esperando recursos del sistema o red."
      RESULT_RISK="El estado del módulo es desconocido."
      RESULT_SUGGESTED_ACTION="Reintentar con conectividad de red disponible."
      RESULT_REPAIRABLE="false"
      RESULT_REPAIR_RISK="NONE"
      RESULT_EXIT_CODE="124"
    elif [ $rc -ne 0 ]; then
      RESULT_EXIT_CODE="$rc"
      # Si el módulo falló pero no configuró STATUS, marcar como ERROR
      if [ "$RESULT_STATUS" = "ERROR" ] && [ "$RESULT_TITLE" = "Diagnóstico no completado" ]; then
        RESULT_TITLE="Error interno del módulo"
        RESULT_DESCRIPTION="El módulo terminó con rc=${rc}."
      fi
    fi

    result_serialize
  )"

  local run_rc=$?

  if [ -z "$serialized_result" ]; then
    log_error "module_loader" \
      "Módulo '${module_id}' no produjo resultado — revisar diagnose.sh"
    return 1
  fi

  echo "$serialized_result"
  return $run_rc
}
