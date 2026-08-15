#!/bin/bash
# Unit coverage for engine dependency planning.
# Designed for Bash 3.2+; pending execution on macOS laboratory hardware.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MERIDIAN_ROOT

_PASS=0
_FAIL=0

_pass() { printf 'PASS: %s\n' "$1"; _PASS=$((_PASS + 1)); }
_fail() { printf 'FAIL: %s\n' "$1" >&2; _FAIL=$((_FAIL + 1)); }
_assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" = "$actual" ]; then _pass "$name"; else _fail "$name (expected=[$expected] actual=[$actual])"; fi
}
_assert_rc() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" -eq "$actual" ]; then _pass "$name"; else _fail "$name (expected=$expected actual=$actual)"; fi
}

log_error() { :; }
log_warn() { :; }
log_info() { :; }
log_step() { :; }

registry_exists() {
  case "$1" in
    alpha|beta|gamma|cycle_a|cycle_b|missing_parent) return 0 ;;
    *) return 1 ;;
  esac
}

registry_get_dependencies() {
  case "$1" in
    alpha) printf '%s\n' 'beta,gamma' ;;
    beta) printf '%s\n' 'gamma' ;;
    gamma) printf '\n' ;;
    cycle_a) printf '%s\n' 'cycle_b' ;;
    cycle_b) printf '%s\n' 'cycle_a' ;;
    missing_parent) printf '%s\n' 'ghost' ;;
    *) printf '\n' ;;
  esac
}

# Remaining collaborators are never exercised by these tests, but are defined
# so engine.sh remains sourceable as its public surface grows.
registry_reset() { :; }
aggregator_reset() { :; }
logger_init() { return 0; }
module_loader_discover() { return 0; }
registry_count() { printf '1\n'; }
rule_loader_load() { return 0; }
registry_get_all_ids() { :; }
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

if order="$(_engine_resolve_dependencies alpha 2>/dev/null)"; then rc=0; else rc=$?; fi
_assert_rc 0 "$rc" "dependency graph resolves"
_assert_eq $'gamma\nbeta\nalpha' "$order" "dependencies run before dependent and are deduplicated"

if order="$(_engine_resolve_dependencies beta 2>/dev/null)"; then rc=0; else rc=$?; fi
_assert_rc 0 "$rc" "resolver resets between plans"
_assert_eq $'gamma\nbeta' "$order" "second plan has no stale modules"

if _engine_resolve_dependencies missing_parent >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "missing dependency fails closed"

if _engine_resolve_dependencies cycle_a >/dev/null 2>&1; then rc=0; else rc=$?; fi
_assert_rc 1 "$rc" "dependency cycle fails closed"

printf '\nSummary: %s passed, %s failed\n' "$_PASS" "$_FAIL"
[ "$_FAIL" -eq 0 ]
