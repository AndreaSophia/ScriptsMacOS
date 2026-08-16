#!/bin/bash
# Meridian — regression coverage for diagnostic worker infrastructure boundaries.
# Written for Bash 3.2/macOS; uses only synthetic module fixtures.

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

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_worker_boundary.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT
MODULE_DIR="${TMP_ROOT}/boundary_test"
EVIDENCE_DIR="${TMP_ROOT}/evidence"
mkdir -p "$MODULE_DIR" "$EVIDENCE_DIR"

cat > "${MODULE_DIR}/manifest.yaml" <<'EOF'
id: boundary_test
name: Boundary Test
description: Synthetic worker boundary fixture.
category: system
version: 1.0.0
author: Meridian Tests
criticality: low
requires_root: false
timeout_seconds: 5
repairable: false
EOF

cat > "${MODULE_DIR}/diagnose.sh" <<'EOF'
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Synthetic result"
RESULT_DESCRIPTION="Synthetic diagnostic."
RESULT_EXPLANATION="Synthetic fixture."
RESULT_RISK="None."
RESULT_SUGGESTED_ACTION="None."
return 0
EOF

printf '\ntest_module_worker_boundary.sh\n\n'

# Infrastructure failures must have their own explicit worker status even when
# the function is evaluated inside an if/command-substitution context where
# Bash may suppress errexit semantics.
ORIGINAL_CORE_DIR="$MERIDIAN_CORE_DIR"
MERIDIAN_CORE_DIR="${TMP_ROOT}/missing-core"
worker_output="$(_module_execute_isolated "boundary_test" "$MODULE_DIR" "$EVIDENCE_DIR" "5" 2>/dev/null)"
worker_rc=$?
MERIDIAN_CORE_DIR="$ORIGINAL_CORE_DIR"
assert_eq "missing result model is infrastructure rc 70" "70" "$worker_rc"
assert_eq "infrastructure failure emits no result" "" "$worker_output"

# A module itself may legitimately exit with a number in the reserved worker
# range. If it produced a valid result, the loader must treat it as module
# failure and normalize it rather than misclassifying infrastructure.
cat > "${MODULE_DIR}/diagnose.sh" <<'EOF'
RESULT_STATUS="FAIL"
RESULT_SEVERITY="HIGH"
RESULT_TITLE="Synthetic module failure"
RESULT_DESCRIPTION="Synthetic diagnostic."
RESULT_EXPLANATION="Synthetic fixture."
RESULT_RISK="Synthetic risk."
RESULT_SUGGESTED_ACTION="Inspect fixture."
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
return 70
EOF

registry_reset
registry_add "boundary_test" "Boundary Test" "system" "1.0.0" \
  "low" "$MODULE_DIR" "false" "5" "" >/dev/null 2>&1
module_output="$(module_loader_run "boundary_test" "$EVIDENCE_DIR" 2>/dev/null)"
module_rc=$?
assert_eq "module rc 70 with result remains a module result" "0" "$module_rc"
if result_deserialize "$module_output" >/dev/null 2>&1; then
  assert_eq "module rc 70 is normalized to ERROR" "ERROR" "$RESULT_STATUS"
  assert_eq "module rc 70 is preserved" "70" "$RESULT_EXIT_CODE"
else
  printf '  FAIL module rc 70 result could not be deserialized\n' >&2
  _fail=$((_fail + 1))
fi

# Evidence is a privileged write boundary during real runs. Existing symlinks
# must never redirect module evidence outside the session tree.
rm -rf "${EVIDENCE_DIR}/boundary_test"
mkdir -p "${TMP_ROOT}/external-evidence"
ln -s "${TMP_ROOT}/external-evidence" "${EVIDENCE_DIR}/boundary_test"
symlink_output="$(module_loader_run "boundary_test" "$EVIDENCE_DIR" 2>/dev/null)"
symlink_rc=$?
assert_eq "symlinked evidence directory is rejected" "1" "$symlink_rc"
assert_eq "symlinked evidence rejection emits no result" "" "$symlink_output"

# diagnose.sh is part of the registered executable identity and may run as root.
# A symlink must be rejected at manifest validation, before registration.
rm -f "${MODULE_DIR}/diagnose.sh"
cat > "${TMP_ROOT}/external-diagnose.sh" <<'EOF'
return 0
EOF
ln -s "${TMP_ROOT}/external-diagnose.sh" "${MODULE_DIR}/diagnose.sh"
if _manifest_validate "${MODULE_DIR}/manifest.yaml" "$MODULE_DIR" >/dev/null 2>&1; then
  diagnose_symlink_rc=0
else
  diagnose_symlink_rc=$?
fi
assert_eq "symlinked diagnose.sh is rejected" "1" "$diagnose_symlink_rc"

printf '\nPassed: %s | Failed: %s\n\n' "$_pass" "$_fail"
exit "$_fail"
