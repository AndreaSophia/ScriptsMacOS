#!/bin/bash
# Unit coverage for engine_init failure boundaries.
# Designed for Bash 3.2+; pending execution on macOS laboratory hardware.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
MERIDIAN_VERSION="test"
export MERIDIAN_ROOT MERIDIAN_VERSION

_PASS=0
_FAIL=0
_LOADER_RC=0
_RULES_RC=0
_REGISTRY_COUNT=1
_RULES_CALLED=0

_pass() { printf 'PASS: %s\n' "$1"; _PASS=$((_PASS + 1)); }
_fail() { printf 'FAIL: %s\n' "$1" >&2; _FAIL=$((_FAIL + 1)); }
_assert_rc() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" -eq "$actual" ]; then _pass "$name"; else _fail "$name (expected=$expected actual=$actual)"; fi
}

# Minimal collaborators used by engine_init.
registry_reset() { :; }
aggregator_reset() { :; }
logger_init() { [ -n "${1:-}" ]; }
log_step() { :; }
log_error() { :; }
log_warn() { :; }
log_info() { :; }
module_loader_discover() { return "$_LOADER_RC"; }
registry_count() { printf '%s\n' "$_REGISTRY_COUNT"; }
rule_loader_load() { _RULES_CALLED=$((_RULES_CALLED + 1)); return "$_RULES_RC"; }

# Stubs needed only so the sourced engine has all referenced names available.
registry_get_all_ids() { :; }
registry_exists() { return 1; }
registry_get_field() { :; }
module_loader_run() { return 1; }
result_init() { :; }
result_deserialize() { return 1; }
rule_engine_evaluate() { :; }
aggregator_add() { return 0; }
aggregator_get_all() { :; }
aggregator_summary() { :; }

# shellcheck source=/dev/null
. "${MERIDIAN_ROOT}/core/engine.sh"

# Empty output path must fail without exiting the caller shell.
if engine_init "" >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "engine_init rejects empty output path"

_tmp="${TMPDIR:-/tmp}/meridian_engine_init_test.$$"
rm -rf "$_tmp"

# Loader failure must propagate and rules must not run.
_LOADER_RC=1
_RULES_RC=0
_REGISTRY_COUNT=1
_RULES_CALLED=0
if engine_init "${_tmp}/loader" >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "module discovery failure propagates"
_assert_rc 0 "$_RULES_CALLED" "rules are not loaded after discovery failure"

# A syntactically successful scan with zero valid modules must fail closed.
_LOADER_RC=0
_REGISTRY_COUNT=0
_RULES_CALLED=0
if engine_init "${_tmp}/empty" >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "zero registered modules fails initialization"
_assert_rc 0 "$_RULES_CALLED" "rules are not loaded with empty registry"

# Rule loader failure must propagate.
_REGISTRY_COUNT=1
_RULES_RC=1
_RULES_CALLED=0
if engine_init "${_tmp}/rules" >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "rule loader failure propagates"
_assert_rc 1 "$_RULES_CALLED" "rule loader attempted once"

# Healthy collaborators should initialize successfully.
_RULES_RC=0
_RULES_CALLED=0
if engine_init "${_tmp}/ok" >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 0 "$rc" "engine_init succeeds with valid collaborators"
_assert_rc 1 "$_RULES_CALLED" "rule loader attempted on healthy initialization"

rm -rf "$_tmp"
printf '\nSummary: %s passed, %s failed\n' "$_PASS" "$_FAIL"
[ "$_FAIL" -eq 0 ]
