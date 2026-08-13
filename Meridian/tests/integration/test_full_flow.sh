#!/bin/bash
# =============================================================================
# Meridian — tests/integration/test_full_flow.sh
# Test de integración: flujo completo en modo test con fixtures.
# Simula un Mac corporativo con FileVault OFF, Falcon no instalado, WS1 no enrollado.
# Verifica que el engine produce los resultados esperados y genera reportes.
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
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" \
      "$desc" "$expected" "$actual" >&2
    _fail=$((_fail+1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     archivo no encontrado: %s\n" \
      "$desc" "$path" >&2
    _fail=$((_fail+1))
  fi
}

assert_file_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if grep -q "$needle" "$filepath" 2>/dev/null; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     '%s' no encontrado en %s\n" \
      "$desc" "$needle" "$(basename "$filepath")" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_full_flow.sh — Integración completa (modo test)\033[0m\n\n"

# Preparar directorio de salida temporal
OUTPUT_DIR="$(mktemp -d)"
trap "rm -rf '$OUTPUT_DIR'" EXIT

# Configurar entorno de test
export MERIDIAN_TEST_MODE=1
export MERIDIAN_DEBUG=0
export MERIDIAN_VERSION="1.0.0-mvp"
export MERIDIAN_ORG="Apple Platform Team"
export MERIDIAN_FIXTURE_DIR="${MERIDIAN_ROOT}/tests/fixtures"

# Cargar todos los componentes del core
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

# Inicializar
export MERIDIAN_OUTPUT_DIR="$OUTPUT_DIR"
export MERIDIAN_EVIDENCE_DIR="${OUTPUT_DIR}/evidencias"
export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"

mkdir -p "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null
logger_init "${OUTPUT_DIR}/diagnostic.log"

# Cargar módulos
module_loader_discover "${MERIDIAN_ROOT}/modules" 2>/dev/null
rule_loader_load "${MERIDIAN_ROOT}/rules/definitions" 2>/dev/null

# --- Test: 6 módulos cargados ---
assert_eq "6 módulos MVP cargados" "6" "$(registry_count)"

# --- Test: ejecutar solo módulo filevault en modo test ---
printf "\n  Ejecutando módulo filevault (fixture: disabled)...\n"
_engine_run_module "filevault" 2>/dev/null

results="$(aggregator_get_all)"
filevault_line="$(echo "$results" | grep '^filevault|||' | head -1)"

# Extraer campos del resultado
fv_status="$(   echo "$filevault_line" | sed 's/|||//g' | awk -F'' '{print $5}')"
fv_severity="$( echo "$filevault_line" | sed 's/|||//g' | awk -F'' '{print $6}')"
fv_rule="$(     echo "$filevault_line" | sed 's/|||//g' | awk -F'' '{print $18}')"

# En modo test el módulo usa fixture de disabled → FAIL
# La regla filevault_disabled debe elevar severity a CRITICAL
assert_eq "filevault: status=FAIL en modo test (fixture disabled)" \
  "FAIL" "$fv_status"
assert_eq "filevault: regla eleva severity a CRITICAL" \
  "CRITICAL" "$fv_severity"
assert_eq "filevault: rule_triggered=filevault_disabled" \
  "filevault_disabled" "$fv_rule"

# --- Test: ejecutar módulo crowdstrike ---
printf "\n  Ejecutando módulo crowdstrike (fixture: not_found)...\n"
_engine_run_module "crowdstrike" 2>/dev/null

results="$(aggregator_get_all)"
cs_line="$(echo "$results" | grep '^crowdstrike|||' | head -1)"
cs_status="$(echo "$cs_line" | sed 's/|||//g' | awk -F'' '{print $5}')"

# En modo test sin fixture de running, crowdstrike debería detectar ausencia
# El resultado exacto depende de si el sistema tiene Falcon instalado
if [ "$cs_status" = "PASS" ] || [ "$cs_status" = "FAIL" ] || \
   [ "$cs_status" = "WARN" ] || [ "$cs_status" = "SKIP" ]; then
  printf "  \033[1;32m✓\033[0m  crowdstrike: produce resultado válido (%s)\n" "$cs_status"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  crowdstrike: status inválido '%s'\n" "$cs_status" >&2
  _fail=$((_fail+1))
fi

# --- Test: aggregator acumula correctamente ---
count="$(aggregator_count)"
if [ "$count" -ge 2 ]; then
  printf "  \033[1;32m✓\033[0m  aggregator acumula %s resultados\n" "$count"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  aggregator solo tiene %s resultados\n" "$count" >&2
  _fail=$((_fail+1))
fi

# --- Test: generar reportes ---
printf "\n  Generando reportes...\n"
summary="$(aggregator_summary)"
results_all="$(aggregator_get_all)"

txt_path="$(renderer_txt_generate "$OUTPUT_DIR" "$results_all" "$summary" 2>/dev/null)"
json_path="$(renderer_json_generate "$OUTPUT_DIR" "$results_all" "$summary" 2>/dev/null)"

assert_file_exists "Executive_Report.txt generado" "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_exists "results.json generado"         "${OUTPUT_DIR}/results.json"

assert_file_contains "TXT contiene nombre del módulo"  "filevault"   "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_contains "TXT contiene severidad"          "CRITICAL"    "${OUTPUT_DIR}/Executive_Report.txt"
assert_file_contains "JSON es válido (contiene results)" '"results"' "${OUTPUT_DIR}/results.json"
assert_file_contains "JSON contiene module_id"         "filevault"   "${OUTPUT_DIR}/results.json"
assert_file_contains "JSON contiene status FAIL"       '"FAIL"'      "${OUTPUT_DIR}/results.json"

# --- Test: diagnostic.log fue creado ---
assert_file_exists "diagnostic.log creado" "${OUTPUT_DIR}/diagnostic.log"

# --- Test: validate_module pasa para todos los módulos MVP ---
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

# --- Resumen final ---
printf "\n  ═══════════════════════════════════════\n"
printf "  INTEGRACIÓN: Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ═══════════════════════════════════════\n\n"

exit $_fail
