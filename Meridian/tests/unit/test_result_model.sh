#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_result_model.sh
# Tests unitarios para core/result_model.sh
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/core/result_model.sh"
# Logger stub para tests (no escribe a disco)
MERIDIAN_LOG_FILE="/dev/null"
log_debug() { :; }
log_warn()  { echo "[WARN] $2" >&2; }
log_error() { echo "[ERROR] $2" >&2; }

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     '%s' no encontrado en output\n" \
      "$desc" "$needle" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_result_model.sh\033[0m\n\n"

# --- Test: result_init establece defaults correctos ---
result_init
assert_eq "result_init: STATUS=ERROR por defecto"    "ERROR" "$RESULT_STATUS"
assert_eq "result_init: REPAIRABLE=false por defecto" "false" "$RESULT_REPAIRABLE"
assert_eq "result_init: EXIT_CODE=0 por defecto"      "0"     "$RESULT_EXIT_CODE"
assert_eq "result_init: EXECUTION_TIME_MS=0"          "0"     "$RESULT_EXECUTION_TIME_MS"

# --- Test: resultado válido pasa la validación ---
result_init
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Test OK"
RESULT_DESCRIPTION="desc"
RESULT_EXPLANATION="expl"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="100"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=""

result_validate 2>/dev/null
assert_eq "result_validate: resultado válido retorna 0" "0" "$?"

# --- Test: STATUS inválido falla la validación ---
RESULT_STATUS="INVALID"
result_validate 2>/dev/null
assert_eq "result_validate: STATUS inválido retorna error" "1" "$?"
RESULT_STATUS="PASS"

# --- Test: SEVERITY inválida falla la validación ---
RESULT_SEVERITY="EXTREME"
result_validate 2>/dev/null
assert_eq "result_validate: SEVERITY inválida retorna error" "1" "$?"
RESULT_SEVERITY="INFO"

# --- Test: repairable=true sin repair_id falla ---
RESULT_REPAIRABLE="true"
RESULT_REPAIR_ID=""
result_validate 2>/dev/null
assert_eq "result_validate: repairable=true sin repair_id falla" "1" "$?"
RESULT_REPAIRABLE="false"

# --- Test: serialización y deserialización son simétricas ---
result_init
RESULT_MODULE_ID="test_module"
RESULT_MODULE_VERSION="2.0.0"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="HIGH"
RESULT_TITLE="Test serialization"
RESULT_DESCRIPTION="desc test"
RESULT_EXPLANATION="expl test"
RESULT_RISK="risk test"
RESULT_SUGGESTED_ACTION="action test"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="250"
RESULT_EXIT_CODE="1"
RESULT_RAW_OUTPUT="raw output"

serialized="$(result_serialize)"
assert_contains "result_serialize: contiene module_id" "test_module" "$serialized"
assert_contains "result_serialize: contiene status"    "FAIL"        "$serialized"
assert_contains "result_serialize: contiene severity"  "HIGH"        "$serialized"

# Deserializar y verificar
result_init
result_deserialize "$serialized"
assert_eq "result_deserialize: MODULE_ID correcto"  "test_module" "$RESULT_MODULE_ID"
assert_eq "result_deserialize: STATUS correcto"     "FAIL"        "$RESULT_STATUS"
assert_eq "result_deserialize: SEVERITY correcto"   "HIGH"        "$RESULT_SEVERITY"
assert_eq "result_deserialize: EXEC_TIME correcto"  "250"         "$RESULT_EXECUTION_TIME_MS"

# --- Test: cronómetro funciona ---
result_time_start
sleep 0
result_time_end
assert_eq "result_time_end: EXECUTION_TIME_MS es numérico" \
  "0" "$(echo "$RESULT_EXECUTION_TIME_MS" | grep -cE '^[0-9]+$' | awk '{print ($1>0)?0:1}')"

# --- Resumen ---
printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit $_fail
