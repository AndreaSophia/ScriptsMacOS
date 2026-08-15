#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_result_aggregator.sh
# Regresión para acumulación/resúmenes de DiagnosticResult v2.
# =============================================================================

set -uo pipefail

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/core/result_aggregator.sh"

log_debug() { :; }
log_error() { printf '[ERROR] %s\n' "$2" >&2; }

_pass=0
_fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass + 1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" \
      "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

add_result() {
  local id="$1" status="$2" severity="$3"
  result_init
  RESULT_MODULE_ID="$id"
  RESULT_MODULE_VERSION="1.0.0"
  RESULT_STATUS="$status"
  RESULT_SEVERITY="$severity"
  RESULT_TITLE="Resultado $id"
  RESULT_DESCRIPTION="desc"
  RESULT_EXPLANATION="expl"
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  aggregator_add >/dev/null
}

printf "\n\033[1mtest_result_aggregator.sh\033[0m\n\n"

aggregator_reset
add_result "one" "PASS" "INFO"
add_result "two" "FAIL" "CRITICAL"
add_result "three" "WARN" "MEDIUM"

assert_eq "count total" "3" "$(aggregator_count)"
assert_eq "count PASS" "1" "$(aggregator_count_by_status PASS)"
assert_eq "count FAIL" "1" "$(aggregator_count_by_status FAIL)"
assert_eq "count WARN" "1" "$(aggregator_count_by_status WARN)"
assert_eq "worst severity" "CRITICAL" "$(aggregator_get_worst_severity)"

# Una validación post-reparación debe sustituir el estado canónico, no duplicarlo.
result_init
RESULT_MODULE_ID="two"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Reparación validada"
RESULT_DESCRIPTION="desc"
RESULT_EXPLANATION="expl"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"
assert_eq "replace existing canonical result" "0" "$(aggregator_replace_current_by_module_id >/dev/null; echo $?)"
assert_eq "replace preserves total" "3" "$(aggregator_count)"
assert_eq "replace updates PASS count" "2" "$(aggregator_count_by_status PASS)"
assert_eq "replace removes FAIL count" "0" "$(aggregator_count_by_status FAIL)"
assert_eq "replace updates worst severity" "MEDIUM" "$(aggregator_get_worst_severity)"
replaced="$(aggregator_get_by_module_id two)"
assert_eq "replace updates canonical status" "PASS" "$(_result_field "$replaced" 5)"

# Un module_id inexistente debe fallar sin mutar el aggregator.
result_init
RESULT_MODULE_ID="missing"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Missing"
RESULT_DESCRIPTION="desc"
RESULT_EXPLANATION="expl"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"
assert_eq "replace missing result fails" "1" "$(aggregator_replace_current_by_module_id >/dev/null 2>&1; echo $?)"
assert_eq "failed replace preserves total" "3" "$(aggregator_count)"

# Las consultas del aggregator no deben sobrescribir el DiagnosticResult activo.
result_init
RESULT_MODULE_ID="sentinel"
RESULT_MODULE_VERSION="9.9.9"
RESULT_STATUS="ERROR"
RESULT_SEVERITY="HIGH"
RESULT_TITLE="Sentinel"
RESULT_DESCRIPTION="sentinel"
RESULT_EXPLANATION="sentinel"
RESULT_RISK="sentinel"
RESULT_SUGGESTED_ACTION="sentinel"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="7"

before_id="$RESULT_MODULE_ID"
before_status="$RESULT_STATUS"
before_title="$RESULT_TITLE"
summary="$(aggregator_summary)"
assert_eq "summary total" "3" "$(printf '%s\n' "$summary" | grep -o 'total=[0-9]*' | cut -d= -f2)"
assert_eq "summary no muta MODULE_ID" "$before_id" "$RESULT_MODULE_ID"
assert_eq "summary no muta STATUS" "$before_status" "$RESULT_STATUS"
assert_eq "summary no muta TITLE" "$before_title" "$RESULT_TITLE"

aggregator_reset
assert_eq "reset count" "0" "$(aggregator_count)"
assert_eq "reset output vacío" "" "$(aggregator_get_all)"

printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit "$_fail"
