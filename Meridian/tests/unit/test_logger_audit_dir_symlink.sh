#!/bin/bash
# Meridian — regression: audit directory symlink must fail closed.
# Bash 3.2 / macOS.

set -u

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/logging/logger.sh"

_pass=0
_fail=0
_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_audit_dir_link.XXXXXX")" || exit 1
trap 'rm -rf "$_tmp_dir"' EXIT INT TERM

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '✗  %s — esperado=%s obtenido=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

real_dir="${_tmp_dir}/real-audit-dir"
link_dir="${_tmp_dir}/linked-audit-dir"
/bin/mkdir -p "$real_dir" || exit 1
/bin/ln -s "$real_dir" "$link_dir" || exit 1

# MERIDIAN_TEST_MODE permite probar la frontera aun si la suite se ejecuta como root.
export MERIDIAN_TEST_MODE=1
export MERIDIAN_AUDIT_LOG="${link_dir}/audit.log"
export MERIDIAN_LOG_FILE=""

if log_audit "logger_test" "AUDIT_DIR_SYMLINK" "must-fail-closed" >/dev/null 2>&1; then
  result="accepted"
else
  result="rejected"
fi

assert_eq "audit rechaza directorio symlink" "rejected" "$result"
assert_eq "audit no crea archivo detrás del symlink" "absent" "$([ -e "${real_dir}/audit.log" ] && printf present || printf absent)"

printf 'Pasaron: %d | Fallaron: %d\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
