#!/bin/bash
# Meridian — regression coverage for module_loader result boundaries.
# Written for Bash 3.2/macOS; does not execute real module diagnostics.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"
MERIDIAN_LOG_FILE="/dev/null"
MERIDIAN_TEST_MODE=1

log_debug() { :; }
log_info()  { :; }
log_ok()    { :; }
log_warn()  { :; }
log_error() { :; }

source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/core/module_registry.sh"
source "${MERIDIAN_ROOT}/core/privilege_manager.sh"
source "${MERIDIAN_ROOT}/core/module_loader.sh"

_pass=0
_fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  PASS %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '  FAIL %s: expected=%s actual=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

register_test_module() {
  registry_reset
  registry_add "boundary_test" "Boundary Test" "system" "1.0.0" \
    "low" "/tmp/meridian_boundary_test" "false" "10" "" >/dev/null 2>&1
}

make_repairable_result() {
  result_init
  RESULT_MODULE_ID="boundary_test"
  RESULT_MODULE_VERSION="1.0.0"
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Repairable diagnostic"
  RESULT_DESCRIPTION="Synthetic diagnostic for loader boundary regression."
  RESULT_EXPLANATION="Synthetic fixture."
  RESULT_RISK="Synthetic risk."
  RESULT_SUGGESTED_ACTION="Synthetic action."
  RESULT_REPAIRABLE="true"
  RESULT_REPAIR_RISK="LOW"
  RESULT_REPAIR_ID="synthetic_repair"
  RESULT_EXIT_CODE="0"
  result_serialize
}

printf '\ntest_module_loader_result_boundary.sh\n\n'
register_test_module

# Seed caller state with a completely valid result. If module_loader_run ignores
# a framing failure, result_validate could otherwise accept these stale values.
result_init
RESULT_MODULE_ID="boundary_test"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Stale valid result"
RESULT_DESCRIPTION="This state must never be reused."
RESULT_EXPLANATION="Synthetic fixture."
RESULT_RISK="None."
RESULT_SUGGESTED_ACTION="None."

_module_execute_isolated() {
  printf '%s\n' 'bad|framing'
  return 0
}

malformed_output="$(module_loader_run "boundary_test" "${TMPDIR:-/tmp}" 2>/dev/null)"
malformed_rc=$?
assert_eq "malformed framing is rejected" "1" "$malformed_rc"
assert_eq "malformed framing emits no canonical result" "" "$malformed_output"

# A module may have populated a repairable partial result before crashing. The
# loader must normalize the failure to ERROR and remove all repair authority.
_module_execute_isolated() {
  make_repairable_result
  return 7
}

error_output="$(module_loader_run "boundary_test" "${TMPDIR:-/tmp}" 2>/dev/null)"
error_rc=$?
assert_eq "nonzero module rc is converted to canonical result" "0" "$error_rc"

if result_deserialize "$error_output" >/dev/null 2>&1; then
  assert_eq "nonzero module rc becomes ERROR" "ERROR" "$RESULT_STATUS"
  assert_eq "nonzero module rc becomes HIGH" "HIGH" "$RESULT_SEVERITY"
  assert_eq "failed module cannot remain repairable" "false" "$RESULT_REPAIRABLE"
  assert_eq "failed module repair risk is cleared" "NONE" "$RESULT_REPAIR_RISK"
  assert_eq "failed module repair id is cleared" "" "$RESULT_REPAIR_ID"
  assert_eq "failed module preserves rc" "7" "$RESULT_EXIT_CODE"
  assert_eq "normalized error still validates" "0" "$(result_validate >/dev/null 2>&1; echo $?)"
else
  printf '  FAIL normalized error could not be deserialized\n' >&2
  _fail=$((_fail + 1))
fi

printf '\nPassed: %s | Failed: %s\n\n' "$_pass" "$_fail"
exit "$_fail"
