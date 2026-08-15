#!/bin/bash
# Meridian — tests/unit/test_validation_engine.sh
# Regresiones de la frontera de validación post-reparación.
# Pendiente de ejecución en Bash 3.2/macOS real.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_validation_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

export MERIDIAN_ROOT
export MERIDIAN_LOG_FILE="${TMP_ROOT}/diagnostic.log"
export MERIDIAN_AUDIT_LOG="${TMP_ROOT}/audit.log"

_REGISTERED=1
_MODULE_DIR="${TMP_ROOT}/module"
mkdir -p "$_MODULE_DIR"

registry_exists() { [ "$_REGISTERED" -eq 1 ]; }
registry_get_path() { printf '%s\n' "$_MODULE_DIR"; }
log_error() { :; }
log_warn() { :; }
log_ok() { :; }
log_step() { :; }
log_audit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$MERIDIAN_AUDIT_LOG"; }

# Estas funciones solo son necesarias para caminos posteriores a la precondición.
result_deserialize() { return 0; }
result_validate() { return 0; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/core/validation_engine.sh"

failures=0
assert_fail() {
  local name="$1"; shift
  if "$@"; then
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$name"
  fi
}

assert_contains() {
  local name="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file" 2>/dev/null; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
}

_REGISTERED=0
assert_fail "rechaza módulo no registrado" validation_engine_run ghost
assert_contains "audita módulo no registrado" "reason=not_registered" "$MERIDIAN_AUDIT_LOG"

_REGISTERED=1
: > "$MERIDIAN_AUDIT_LOG"
assert_fail "rechaza validator ausente" validation_engine_run filevault
assert_contains "audita validator ausente" "reason=validator_unavailable" "$MERIDIAN_AUDIT_LOG"

if [ "$failures" -ne 0 ]; then
  printf '%s\n' "${failures} fallo(s)" >&2
  exit 1
fi

printf '%s\n' "Validation engine fail-closed regression coverage complete"
