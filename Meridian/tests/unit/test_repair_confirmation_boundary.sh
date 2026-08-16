#!/bin/bash
# Regression coverage: la frontera de confirmación de reparaciones debe ser la
# función TUI canónica, nunca un ejecutable externo resuelto mediante PATH.
# Compatible con Bash 3.2.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="${TMPDIR:-/tmp}/meridian_repair_confirm.$$"
MODULE_DIR="${TEST_ROOT}/module"
HOSTILE_BIN="${TEST_ROOT}/bin"
CONFIRM_MARKER="${TEST_ROOT}/external_confirm_ran"
REPAIR_MARKER="${TEST_ROOT}/repair_ran"
AUDIT_LOG="${TEST_ROOT}/audit.txt"

mkdir -p "$MODULE_DIR" "$HOSTILE_BIN" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT

cat >"${MODULE_DIR}/repair.sh" <<EOF
#!/bin/bash
printf '%s\n' ran >"${REPAIR_MARKER}"
exit 0
EOF
chmod +x "${MODULE_DIR}/repair.sh" || exit 1

cat >"${HOSTILE_BIN}/tui_confirm_repair" <<EOF
#!/bin/bash
printf '%s\n' ran >"${CONFIRM_MARKER}"
exit 0
EOF
chmod +x "${HOSTILE_BIN}/tui_confirm_repair" || exit 1

log_error() { :; }
log_warn()  { :; }
log_info()  { :; }
log_ok()    { :; }
log_step()  { :; }
log_audit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$AUDIT_LOG"; }

registry_exists() { [ "$1" = "alpha" ]; }
registry_get_path() { printf '%s\n' "$MODULE_DIR"; }
registry_get_field() {
  case "$2" in
    2) printf '%s\n' "Alpha" ;;
    7) printf '%s\n' "true" ;;
    *) return 1 ;;
  esac
}
aggregator_get_by_module_id() { printf '%s\n' "fixture"; }
result_deserialize() {
  RESULT_REPAIRABLE="true"
  RESULT_REPAIR_ID="repair_alpha"
  RESULT_REPAIR_RISK="LOW"
  RESULT_SUGGESTED_ACTION="Repair fixture"
  RESULT_MODULE_ID="alpha"
  RESULT_MODULE_VERSION="1.0.0"
  RESULT_TIMESTAMP="2026-08-16T00:00:00Z"
  RESULT_HOSTNAME="fixture"
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Fixture"
  RESULT_DESCRIPTION="Fixture"
  RESULT_EXPLANATION="Fixture"
  RESULT_RISK="Fixture"
  RESULT_EXECUTION_TIME_MS="0"
  RESULT_EXIT_CODE="0"
  RESULT_RAW_OUTPUT=""
  RESULT_RULE_TRIGGERED=""
  RESULT_EVIDENCE=""
  return 0
}
result_validate() { return 0; }
privilege_check_repair() { return 0; }
privilege_check_module() { return 0; }
privilege_get_current_user() { printf '%s\n' "tester"; }
validation_engine_run() { return 0; }

source "${MERIDIAN_ROOT}/core/repair_engine.sh"

_pass=0
_fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  ✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '  ✗  %s — expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

printf '\ntest_repair_confirmation_boundary.sh\n\n'

OLD_PATH="$PATH"
PATH="${HOSTILE_BIN}:${PATH}"
repair_engine_run alpha repair_alpha LOW >/dev/null 2>&1
rc=$?
PATH="$OLD_PATH"

assert_eq "ejecutable externo no satisface la frontera TUI" "1" "$rc"
assert_eq "confirmador externo no fue ejecutado" "false" "$([ -e "$CONFIRM_MARKER" ] && printf true || printf false)"
assert_eq "repair.sh no fue ejecutado sin función canónica" "false" "$([ -e "$REPAIR_MARKER" ] && printf true || printf false)"

if grep -q 'reason=confirmation_unavailable' "$AUDIT_LOG" 2>/dev/null; then
  assert_eq "rechazo queda auditado" "true" "true"
else
  assert_eq "rechazo queda auditado" "true" "false"
fi

printf '\n  Pasaron: %s | Fallaron: %s\n\n' "$_pass" "$_fail"
exit "$_fail"
