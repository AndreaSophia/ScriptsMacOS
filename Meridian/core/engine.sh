#!/bin/bash
# Meridian — core/engine.sh
engine_init() {
  local output_dir="$1"
  export MERIDIAN_OUTPUT_DIR="$output_dir"
  export MERIDIAN_EVIDENCE_DIR="${output_dir}/evidencias"
  export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
  export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"
  mkdir -p "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null || { echo "[FATAL] No se pudo crear: $output_dir" >&2; exit 1; }
  logger_init "${output_dir}/diagnostic.log"
  log_step "Inicializando Meridian v${MERIDIAN_VERSION}"
  log_step "Cargando módulos"; module_loader_discover "${MERIDIAN_ROOT}/modules"
  log_step "Cargando reglas"; rule_loader_load "${MERIDIAN_ROOT}/rules/definitions"
}

engine_run() {
  local module_ids=("$@") id
  if [ ${#module_ids[@]} -eq 0 ]; then
    while IFS= read -r id; do [ -n "$id" ] && module_ids+=("$id"); done < <(registry_get_all_ids)
  fi
  [ ${#module_ids[@]} -gt 0 ] || { log_warn "engine" "No hay módulos disponibles"; return 1; }
  for id in "${module_ids[@]}"; do _engine_run_module "$id"; done
}

_engine_run_module() {
  local module_id="$1" module_name serialized run_rc status_icon
  registry_exists "$module_id" || { log_warn "engine" "Módulo no registrado: $module_id"; return 0; }
  module_name="$(registry_get_field "$module_id" 2)"
  log_info "engine" "▷ ${module_name} (${module_id})"

  # module_loader emits user-facing logs on stdout. Capture only the final
  # DiagnosticResult line; forward preceding lines to stderr for visibility.
  local tmp_base="${TMPDIR:-/tmp}" capture
  capture="$(mktemp "${tmp_base%/}/meridian_engine.XXXXXX")" || return 1
  module_loader_run "$module_id" "$MERIDIAN_EVIDENCE_DIR" >"$capture"
  run_rc=$?
  serialized="$(tail -n 1 "$capture")"
  if [ "$(wc -l < "$capture" | tr -d ' ')" -gt 1 ]; then sed '$d' "$capture" >&2; fi
  rm -f "$capture"

  if [ -z "$serialized" ] || [ $run_rc -ne 0 ]; then
    log_error "engine" "Módulo '${module_id}' no produjo resultado válido"
    return 1
  fi
  result_deserialize "$serialized"
  rule_engine_evaluate "$module_id"
  if ! aggregator_add; then
    log_error "engine" "Resultado de '${module_id}' rechazado por aggregator"
    return 1
  fi
  case "$RESULT_STATUS" in PASS) status_icon="✓";; WARN) status_icon="!";; FAIL) status_icon="✗";; SKIP) status_icon="–";; ERROR) status_icon="⚡";; *) status_icon="?";; esac
  log_info "engine" "  ${status_icon} ${RESULT_STATUS} [${RESULT_SEVERITY}] ${RESULT_TITLE}"
}

engine_get_results() { aggregator_get_all; }
engine_get_summary() { aggregator_summary; }
