#!/bin/bash
# Regression coverage for IDiagnosticResult structural/semantic invariants.
# Written for Bash 3.2/macOS; pending execution on a real Mac.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/core/result_model.sh"

_pass=0
_fail=0

assert_valid() {
  local desc="$1"
  if result_validate >/dev/null 2>&1; then
    printf '  ✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '  ✗  %s (se esperaba válido)\n' "$desc" >&2
    _fail=$((_fail + 1))
  fi
}

assert_invalid() {
  local desc="$1"
  if result_validate >/dev/null 2>&1; then
    printf '  ✗  %s (se esperaba inválido)\n' "$desc" >&2
    _fail=$((_fail + 1))
  else
    printf '  ✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  fi
}

seed_valid_result() {
  result_init
  RESULT_MODULE_ID="test_module"
  RESULT_MODULE_VERSION="1.2.3"
  RESULT_TIMESTAMP="2026-08-14T20:00:00Z"
  RESULT_HOSTNAME="Mac-Test"
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Resultado de prueba"
  RESULT_DESCRIPTION="Descripción"
  RESULT_EXPLANATION="Explicación"
  RESULT_RISK="Riesgo"
  RESULT_SUGGESTED_ACTION="Acción"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_REPAIR_ID=""
  RESULT_EXECUTION_TIME_MS="0"
  RESULT_EXIT_CODE="0"
}

printf '\ntest_result_contract.sh\n\n'

seed_valid_result
assert_valid "resultado base cumple el contrato"

seed_valid_result
RESULT_MODULE_ID="Bad-Module"
assert_invalid "module_id fuera de snake_case se rechaza"

seed_valid_result
RESULT_MODULE_VERSION="1.2"
assert_invalid "module_version no semver se rechaza"

seed_valid_result
RESULT_TIMESTAMP="2026-08-14 20:00:00"
assert_invalid "timestamp sin formato ISO8601 UTC se rechaza"

seed_valid_result
RESULT_TITLE="123456789012345678901234567890123456789012345678901234567890123456789012345678901"
assert_invalid "title mayor a 80 caracteres se rechaza"

seed_valid_result
RESULT_REPAIRABLE="true"
RESULT_REPAIR_RISK="LOW"
RESULT_REPAIR_ID="repair_test"
assert_valid "repairable=true con id y riesgo explícitos es válido"

seed_valid_result
RESULT_REPAIRABLE="true"
RESULT_REPAIR_RISK="NONE"
RESULT_REPAIR_ID="repair_test"
assert_invalid "repairable=true con riesgo NONE se rechaza"

seed_valid_result
RESULT_REPAIRABLE="true"
RESULT_REPAIR_RISK="LOW"
RESULT_REPAIR_ID="Bad-Repair"
assert_invalid "repair_id fuera de snake_case se rechaza"

seed_valid_result
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="HIGH"
assert_invalid "repairable=false con riesgo distinto de NONE se rechaza"

seed_valid_result
RESULT_REPAIRABLE="false"
RESULT_REPAIR_ID="stale_repair"
assert_invalid "repairable=false con repair_id residual se rechaza"

printf '\n  Pasaron: %s | Fallaron: %s\n\n' "$_pass" "$_fail"
exit "$_fail"
