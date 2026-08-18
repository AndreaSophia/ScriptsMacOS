#!/bin/bash
# Remedy 1.1: ciclo seguro, entorno mínimo, auditoría fail-closed y rollback.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_remedy.XXXXXX")" || exit 1
MODULE_DIR="${TEST_ROOT}/module"
AUDIT_LOG="${TEST_ROOT}/audit.log"
FLOW_LOG="${TEST_ROOT}/flow.log"
mkdir -p "$MODULE_DIR"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

write_worker() {
  local name="$1" body="$2"
  { printf '%s\n' '#!/bin/bash'; printf '%s\n' "$body"; } >"${MODULE_DIR}/${name}.sh"
  chmod +x "${MODULE_DIR}/${name}.sh"
}

write_worker precheck 'printf "%s\n" precheck >>"$MERIDIAN_EVIDENCE_DIR/flow.log"; [ -z "${MERIDIAN_TEST_PASSWORD:-}" ]'
write_worker repair 'printf "%s\n" action >>"$MERIDIAN_EVIDENCE_DIR/flow.log"; exit 0'
write_worker rollback 'printf "%s\n" rollback >>"$MERIDIAN_EVIDENCE_DIR/flow.log"; exit 0'
write_worker validate 'return 0'

log_error() { :; }; log_warn() { :; }; log_info() { :; }; log_ok() { :; }; log_step() { :; }
log_audit() {
  [ "${AUDIT_FAIL_ACTION:-}" != "$2" ] || return 1
  printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$AUDIT_LOG"
}
registry_exists() { [ "$1" = fixture ]; }
registry_get_path() { printf '%s\n' "$MODULE_DIR"; }
registry_get_field() { case "$2" in 2) printf Fixture ;; 7) printf false ;; esac; }
aggregator_get_by_module_id() { printf fixture; }
result_deserialize() {
  RESULT_MODULE_ID=fixture; RESULT_MODULE_VERSION=1.1.0; RESULT_TIMESTAMP=2026-08-18T00:00:00Z
  RESULT_HOSTNAME=fixture; RESULT_STATUS=FAIL; RESULT_SEVERITY=HIGH; RESULT_TITLE=Fixture
  RESULT_DESCRIPTION=Fixture; RESULT_EXPLANATION=Fixture; RESULT_RISK=Fixture
  RESULT_SUGGESTED_ACTION=Fixture; RESULT_REPAIRABLE=true; RESULT_REPAIR_RISK=MEDIUM
  RESULT_REPAIR_ID=repair_fixture; RESULT_EXECUTION_TIME_MS=0; RESULT_EXIT_CODE=0
  RESULT_RAW_OUTPUT=; RESULT_RULE_TRIGGERED=; RESULT_EVIDENCE=
}
result_validate() { return 0; }
privilege_check_repair() { return 0; }; privilege_check_module() { return 0; }
privilege_get_current_user() { printf tester; }
tui_confirm_repair() { return 0; }
validation_engine_run() { return "${VALIDATION_RC:-0}"; }

export MERIDIAN_ROOT MERIDIAN_EVIDENCE_DIR="$TEST_ROOT" MERIDIAN_LOG_FILE="${TEST_ROOT}/session.log"
export MERIDIAN_TEST_PASSWORD='must-not-cross-worker-boundary'
source "${MERIDIAN_ROOT}/core/repair_engine.sh"

failures=0
assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then printf 'PASS: %s\n' "$name"; else
    printf 'FAIL: %s expected=%s got=%s\n' "$name" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() { if grep -Fq "$2" "$3"; then printf 'PASS: %s\n' "$1"; else printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); fi; }

repair_engine_run fixture repair_fixture MEDIUM
assert_eq 'happy path succeeds' 0 "$?"
assert_eq 'precheck precedes action' "precheck action" "$(tr '\n' ' ' <"$FLOW_LOG" | sed 's/ $//')"
assert_contains 'consent is audited' CONSENT_GRANTED "$AUDIT_LOG"
assert_contains 'completion is audited' REPAIR_COMPLETED "$AUDIT_LOG"

: >"$FLOW_LOG"; : >"$AUDIT_LOG"; VALIDATION_RC=1; export VALIDATION_RC
repair_engine_run fixture repair_fixture MEDIUM
assert_eq 'failed validation returns failure' 1 "$?"
assert_eq 'failed validation triggers rollback' "precheck action rollback" "$(tr '\n' ' ' <"$FLOW_LOG" | sed 's/ $//')"
assert_contains 'rollback completion is audited' ROLLBACK_COMPLETED "$AUDIT_LOG"

: >"$FLOW_LOG"; : >"$AUDIT_LOG"; unset VALIDATION_RC
write_worker precheck 'printf "%s\n" precheck >>"$MERIDIAN_EVIDENCE_DIR/flow.log"; exit 9'
repair_engine_run fixture repair_fixture MEDIUM
assert_eq 'failed precheck blocks lifecycle' 1 "$?"
assert_eq 'action does not run after failed precheck' precheck "$(tr -d '\n' <"$FLOW_LOG")"
assert_contains 'precheck failure is audited' PRECHECK_FAILED "$AUDIT_LOG"

: >"$FLOW_LOG"; : >"$AUDIT_LOG"
write_worker precheck 'printf "%s\n" precheck >>"$MERIDIAN_EVIDENCE_DIR/flow.log"; exit 0'
AUDIT_FAIL_ACTION=PRECHECK_PASSED; export AUDIT_FAIL_ACTION
repair_engine_run fixture repair_fixture MEDIUM
assert_eq 'audit failure blocks lifecycle' 1 "$?"
assert_eq 'action does not run after audit failure' precheck "$(tr -d '\n' <"$FLOW_LOG")"
unset AUDIT_FAIL_ACTION

printf '\nFailures: %s\n' "$failures"
exit "$failures"
