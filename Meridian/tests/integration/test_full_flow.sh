#!/bin/bash
# =============================================================================
# Meridian — tests/integration/test_full_flow.sh
# Flujo completo en modo test usando el contrato DiagnosticResult v2.
# =============================================================================

set -uo pipefail

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
_pass=0; _fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" "$desc" "$expected" "$actual" >&2
    _fail=$((_fail+1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     archivo no encontrado: %s\n" "$desc" "$path" >&2
    _fail=$((_fail+1))
  fi
}

assert_file_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if grep -q "$needle" "$filepath" 2>/dev/null; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     '%s' no encontrado en %s\n" "$desc" "$needle" "$(basename "$filepath")" >&2
    _fail=$((_fail+1))
  fi
}

_find_result() {
  local wanted="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    result_deserialize "$line"
    if [ "$RESULT_MODULE_ID" = "$wanted" ]; then
      printf '%s\n' "$line"
      return 0
    fi
  done < <(aggregator_get_all)
  return 1
}

printf "\n\033[1mtest_full_flow.sh — Integración completa (modo test)\033[0m\n\n"

OUTPUT_DIR="$(mktemp -d)"
trap "rm -rf '$OUTPUT_DIR'" EXIT

export MERIDIAN_TEST_MODE=1
export MERIDIAN_DEBUG=0
export MERIDIAN_VERSION="1.0.0-mvp"
export MERIDIAN_ORG="Apple Platform Team"
export MERIDIAN_FIXTURE_DIR="${MERIDIAN_ROOT}/tests/fixtures"

printf "  Cargando core...\n"
source "${MERIDIAN_ROOT}/logging/logger.sh"
source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/core/module_registry.sh"
source "${MERIDIAN_ROOT}/core/result_aggregator.sh"
source "${MERIDIAN_ROOT}/core/privilege_manager.sh"
source "${MERIDIAN_ROOT}/core/module_loader.sh"
source "${MERIDIAN_ROOT}/rules/rule_loader.sh"
source "${MERIDIAN_ROOT}/rules/rule_engine.sh"
source "${MERIDIAN_ROOT}/core/repair_engine.sh"
source "${MERIDIAN_ROOT}/core/validation_engine.sh"
source "${MERIDIAN_ROOT}/core/engine.sh"
source "${MERIDIAN_ROOT}/services/diagnostic_service.sh"
source "${MERIDIAN_ROOT}/reporting/renderer_txt.sh"
source "${MERIDIAN_ROOT}/reporting/renderer_json.sh"
source "${MERIDIAN_ROOT}/services/reporting_service.sh"
printf "  OK\n\n"

export MERIDIAN_OUTPUT_DIR="$OUTPUT_DIR"
export MERIDIAN_EVIDENCE_DIR="${OUTPUT_DIR}/evidencias"
export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"
mkdir -p "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null
logger_init "${OUTPUT_DIR}/diagnostic.log"

module_loader_discover "${MERIDIAN_ROOT}/modules" 2>/dev/null
rule_loader_load "${MERIDIAN_ROOT}/rules/definitions" 2>/dev/null

assert_eq "6 módulos MVP cargados" "6" "$(registry_count)"
assert_eq "7 reglas MVP cargadas" "7" "$(rule_loader_count)"

printf "\n  Ejecutando módulo filevault (fixture: disabled)...\n"
_engine_run_module "filevault" 2>/dev/null
filevault_line="$(_find_result filevault)"
if [ -n "$filevault_line" ]; then
  result_deserialize "$filevault_line"
  fv_status="$RESULT_STATUS"
  fv_severity="$RESULT_SEVERITY"
  fv_rule="$RESULT_RULE_TRIGGERED"
else
  fv_status=""; fv_severity=""; fv_rule=""
fi

assert_eq "filevault: status=FAIL en modo test (fixture disabled)" "FAIL" "$fv_status"
assert_eq "filevault: regla eleva severity a CRITICAL" "CRITICAL" "$fv_severity"
assert_eq "filevault: rule_triggered=filevault_disabled" "filevault_disabled" "$fv_rule"

printf "\n  Ejecutando módulo crowdstrike (fixture: not_found)...\n"
_engine_run_module "crowdstrike" 2>/dev/null
cs_line="$(_find_result crowdstrike)"
cs_status=""
if [ -n "$cs_line" ]; then
  result_deserialize "$cs_line"
  cs_status="$RESULT_STATUS"
fi

case "$cs_status" in
  PASS|FAIL|WARN|SKIP|ERROR)
    printf "  \033[1;32m✓\033[0m  crowdstrike: produce resultado válido (%s)\n" "$cs_status"
    _pass=$((_pass+1))
    ;;
  *)
    printf "  \033[1;31m✗\033[0m  crowdstrike: status inválido '%s'\n" "$cs_status" >&2
    _fail=$((_fail+1))
    ;;
esac

count="$(aggregator_count)"
if [ "$count" -ge 2 ]; then
  printf "  \033[1;32m✓\033[0m  aggregator acumula %s resultados\n" "$count"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  aggregator solo tiene %s resultados\n" "$count" >&2
  _fail=$((_fail+1))
fi

printf "\n  Generando reportes...\n"
summary="$(aggregator_summary)"
results_all="$(aggregator_get_all)"
renderer_txt_generate "$OUTPUT_DIR" "$results_all" "$summary" >/dev/null 2>&1
renderer_json_generate "$OUTPUT_DIR" "$results_all" "$summary" >/dev/null 2>&1

assert_file_exists "Executive_Report.txt generado" "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_exists "results.json generado" "${OUTPUT_DIR}/results.json"
assert_file_contains "TXT contiene nombre del módulo" "filevault" "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_contains "TXT contiene severidad" "CRITICAL" "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_contains "JSON contiene results" '"results"' "${OUTPUT_DIR}/results.json"
assert_file_contains "JSON contiene module_id" "filevault" "${OUTPUT_DIR}/results.json"
assert_file_contains "JSON contiene status FAIL" '"FAIL"' "${OUTPUT_DIR}/results.json"
assert_file_exists "diagnostic.log creado" "${OUTPUT_DIR}/diagnostic.log"

printf "\n  Validando módulos con validate_module.sh...\n"
for mod_id in filevault certificates crowdstrike cisco_umbrella forcepoint workspace_one; do
  if bash "${MERIDIAN_ROOT}/tools/validate_module.sh" "$mod_id" >/dev/null 2>&1; then
    printf "  \033[1;32m✓\033[0m  validate_module: %s\n" "$mod_id"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  validate_module: %s falló\n" "$mod_id" >&2
    _fail=$((_fail+1))
  fi
done

printf "\n  ═══════════════════════════════════════\n"
printf "  INTEGRACIÓN: Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ═══════════════════════════════════════\n\n"

exit "$_fail"
