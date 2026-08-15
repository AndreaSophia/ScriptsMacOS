#!/bin/bash
# Meridian — core/engine.sh
engine_init() {
  local output_dir="$1"

  if [ -z "$output_dir" ]; then
    printf '%s\n' "[FATAL] engine_init requiere un directorio de salida" >&2
    return 1
  fi

  export MERIDIAN_OUTPUT_DIR="$output_dir"
  export MERIDIAN_EVIDENCE_DIR="${output_dir}/evidencias"
  export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
  export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"

  if ! mkdir -p "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null; then
    printf '%s\n' "[FATAL] No se pudo crear el directorio de salida: $output_dir" >&2
    return 1
  fi

  registry_reset
  aggregator_reset

  if ! logger_init "${output_dir}/diagnostic.log"; then
    printf '%s\n' "[FATAL] No se pudo inicializar el logger de sesión" >&2
    return 1
  fi

  log_step "Inicializando Meridian v${MERIDIAN_VERSION}"

  log_step "Cargando módulos"
  if ! module_loader_discover "${MERIDIAN_ROOT}/modules"; then
    log_error "engine" "No se pudo completar el descubrimiento de módulos"
    return 1
  fi

  if [ "$(registry_count)" -eq 0 ]; then
    log_error "engine" "No se registraron módulos válidos"
    return 1
  fi

  log_step "Cargando reglas"
  if ! rule_loader_load "${MERIDIAN_ROOT}/rules/definitions"; then
    log_error "engine" "No se pudo completar la carga de reglas"
    return 1
  fi

  return 0
}

engine_run() {
  local module_ids=("$@") id failures=0
  if [ ${#module_ids[@]} -eq 0 ]; then
    while IFS= read -r id; do [ -n "$id" ] && module_ids+=("$id"); done < <(registry_get_all_ids)
  fi
  [ ${#module_ids[@]} -gt 0 ] || { log_warn "engine" "No hay módulos disponibles"; return 1; }

  for id in "${module_ids[@]}"; do
    if ! _engine_run_module "$id"; then
      failures=$((failures + 1))
      log_error "engine" "Fallo interno procesando módulo: $id"
    fi
  done

  [ "$failures" -eq 0 ] || log_warn "engine" "La sesión completó con ${failures} fallo(s) internos de módulo"
  return 0
}

_engine_add_internal_error() {
  local module_id="$1" title="$2" description="$3"
  result_init
  RESULT_MODULE_ID="$module_id"
  RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="$title"
  RESULT_DESCRIPTION="$description"
  RESULT_EXPLANATION="Meridian no pudo obtener o procesar un DiagnosticResult válido para este módulo."
  RESULT_RISK="El estado real del componente permanece desconocido."
  RESULT_SUGGESTED_ACTION="Revisar diagnostic.log y la evidencia del módulo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  aggregator_add
}

_engine_run_module() {
  local module_id="$1" module_name serialized run_rc status_icon
  registry_exists "$module_id" || { log_warn "engine" "Módulo no registrado: $module_id"; return 0; }
  module_name="$(registry_get_field "$module_id" 2)"
  log_info "engine" "▷ ${module_name} (${module_id})"

  local tmp_base="${TMPDIR:-/tmp}" capture
  capture="$(mktemp "${tmp_base%/}/meridian_engine.XXXXXX")" || return 1

  if module_loader_run "$module_id" "$MERIDIAN_EVIDENCE_DIR" >"$capture"; then
    run_rc=0
  else
    run_rc=$?
  fi

  serialized="$(tail -n 1 "$capture" 2>/dev/null)"
  if [ "$(wc -l < "$capture" | tr -d ' ')" -gt 1 ]; then sed '$d' "$capture" >&2; fi
  rm -f "$capture"

  if [ -z "$serialized" ] || [ "$run_rc" -ne 0 ]; then
    log_error "engine" "Módulo '${module_id}' no produjo resultado válido"
    if ! _engine_add_internal_error "$module_id" \
      "Error interno ejecutando el módulo" \
      "El loader terminó con rc=${run_rc} o sin un DiagnosticResult utilizable."; then
      return 1
    fi
    return 0
  fi

  # No evaluar reglas ni mutar el aggregator si el framing v2 está corrupto.
  # result_deserialize valida que existan exactamente los 19 campos canónicos.
  if ! result_deserialize "$serialized"; then
    log_error "engine" "Módulo '${module_id}' produjo framing DiagnosticResult inválido"
    if ! _engine_add_internal_error "$module_id" \
      "DiagnosticResult con framing inválido" \
      "El resultado serializado no cumple el formato canónico v2."; then
      return 1
    fi
    return 0
  fi

  rule_engine_evaluate "$module_id"
  if ! aggregator_add; then
    log_error "engine" "Resultado de '${module_id}' rechazado por aggregator"
    if ! _engine_add_internal_error "$module_id" \
      "DiagnosticResult rechazado por el aggregator" \
      "El resultado del módulo no pudo incorporarse a la sesión."; then
      return 1
    fi
    return 0
  fi

  case "$RESULT_STATUS" in PASS) status_icon="✓";; WARN) status_icon="!";; FAIL) status_icon="✗";; SKIP) status_icon="–";; ERROR) status_icon="⚡";; *) status_icon="?";; esac
  log_info "engine" "  ${status_icon} ${RESULT_STATUS} [${RESULT_SEVERITY}] ${RESULT_TITLE}"
  return 0
}

engine_get_results() { aggregator_get_all; }
engine_get_summary() { aggregator_summary; }
