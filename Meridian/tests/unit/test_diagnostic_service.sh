#!/bin/bash
# Meridian — tests/unit/test_diagnostic_service.sh
# Regresiones de la frontera service -> engine.
# Pendiente de ejecución en Bash 3.2/macOS real.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Stubs del engine para probar solo la semántica de la capa service.
_ENGINE_INIT_RC=0
_ENGINE_RUN_RC=0
_ENGINE_INIT_ARG=""
_ENGINE_RUN_ARGS=""

engine_init() {
  _ENGINE_INIT_ARG="${1:-}"
  return "$_ENGINE_INIT_RC"
}

engine_run() {
  _ENGINE_RUN_ARGS="$*"
  return "$_ENGINE_RUN_RC"
}

engine_get_results() { printf '%s\n' 'serialized-results'; }
engine_get_summary() { printf '%s\n' 'summary-ok'; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/services/diagnostic_service.sh"

failures=0
assert_ok() {
  local name="$1"; shift
  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
}

assert_fail() {
  local name="$1"; shift
  if "$@"; then
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$name"
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$name" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

assert_fail "init rechaza output vacío" diagnostic_service_init ""

_ENGINE_INIT_RC=1
assert_fail "init propaga fallo del engine" diagnostic_service_init "/tmp/out"
_ENGINE_INIT_RC=0
assert_ok "init sano" diagnostic_service_init "/tmp/out"
assert_eq "init conserva output_dir" "/tmp/out" "$_ENGINE_INIT_ARG"

_ENGINE_RUN_RC=1
assert_fail "execute propaga fallo del engine" diagnostic_service_execute filevault
_ENGINE_RUN_RC=0
assert_ok "execute sano" diagnostic_service_execute filevault certificates
assert_eq "execute conserva selección" "filevault certificates" "$_ENGINE_RUN_ARGS"

assert_fail "run rechaza falta de output" diagnostic_service_run

summary="$(diagnostic_service_run "/tmp/out" filevault)"
assert_eq "run devuelve resumen" "summary-ok" "$summary"
assert_eq "getter de resultados" "serialized-results" "$(diagnostic_service_get_results)"
assert_eq "getter de resumen" "summary-ok" "$(diagnostic_service_get_summary)"

if [ "$failures" -ne 0 ]; then
  printf '%s\n' "${failures} fallo(s)" >&2
  exit 1
fi

printf '%s\n' "Diagnostic service regression coverage complete"
