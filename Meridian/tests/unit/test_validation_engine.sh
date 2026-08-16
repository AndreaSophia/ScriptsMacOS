#!/bin/bash
# Meridian — tests/unit/test_validation_engine.sh
# Regresiones de la frontera de validación post-reparación.
# Pendiente de ejecución en Bash 3.2/macOS real.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
REAL_MERIDIAN_ROOT="$MERIDIAN_ROOT"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_validation_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

export MERIDIAN_ROOT
export TMPDIR="${TMP_ROOT}/tmp"
export MERIDIAN_LOG_FILE="${TMP_ROOT}/diagnostic.log"
export MERIDIAN_AUDIT_LOG="${TMP_ROOT}/audit.log"
mkdir -p "$TMPDIR"

_REGISTERED=1
_MODULE_DIR="${TMP_ROOT}/module"
mkdir -p "$_MODULE_DIR"

registry_exists() { [ "$_REGISTERED" -eq 1 ]; }
registry_get_path() { printf '%s\n' "$_MODULE_DIR"; }
registry_get_field() {
  case "${2:-}" in
    4) printf '%s\n' "1.0.0" ;;
    *) printf '\n' ;;
  esac
}
log_error() { :; }
log_warn() { :; }
log_ok() { :; }
log_step() { :; }
log_audit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$MERIDIAN_AUDIT_LOG"; }

# Estas funciones solo son necesarias para caminos posteriores a la precondición.
result_deserialize() { return 0; }
result_validate() { return 0; }
aggregator_replace_current_by_module_id() { return 0; }

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

assert_no_validation_temps() {
  local name="$1"
  if find "$TMPDIR" -type f -name 'meridian_validation_*' -print 2>/dev/null | grep -q .; then
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$name"
  fi
}

_REGISTERED=0
assert_fail "rechaza módulo no registrado" validation_engine_run ghost
assert_contains "audita módulo no registrado" "reason=not_registered" "$MERIDIAN_AUDIT_LOG"

_REGISTERED=1
: > "$MERIDIAN_AUDIT_LOG"
assert_fail "rechaza validator ausente" validation_engine_run filevault
assert_contains "audita validator ausente" "reason=validator_unavailable" "$MERIDIAN_AUDIT_LOG"

# Un fallo de infraestructura dentro del worker debe regresar control al caller,
# auditarse y limpiar los temporales aunque el entrypoint use `set -e`.
cat > "${_MODULE_DIR}/manifest.yaml" <<'EOF'
id: filevault
name: FileVault
version: 1.0.0
EOF
cat > "${_MODULE_DIR}/validate.sh" <<'EOF'
return 0
EOF

: > "$MERIDIAN_AUDIT_LOG"
MERIDIAN_ROOT="${TMP_ROOT}/missing_runtime"
export MERIDIAN_ROOT
assert_fail "rechaza fallo de infraestructura del worker" validation_engine_run filevault
assert_contains "audita fallo de infraestructura del worker" "reason=validator_execution_failed rc=70" "$MERIDIAN_AUDIT_LOG"
assert_no_validation_temps "limpia temporales tras fallo del worker"
MERIDIAN_ROOT="$REAL_MERIDIAN_ROOT"
export MERIDIAN_ROOT

if [ "$failures" -ne 0 ]; then
  printf '%s\n' "${failures} fallo(s)" >&2
  exit 1
fi

printf '%s\n' "Validation engine fail-closed regression coverage complete"
