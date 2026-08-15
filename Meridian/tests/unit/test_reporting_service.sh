#!/bin/bash
# Meridian — tests/unit/test_reporting_service.sh
# Regression coverage for the reporting service boundary.
# Compatible with Bash 3.2; no macOS system calls required.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TESTS=0
FAILURES=0

_pass() { TESTS=$((TESTS + 1)); printf 'PASS: %s\n' "$1"; }
_fail() { TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }
_assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" = "$actual" ]; then _pass "$name"; else _fail "$name (expected='$expected' actual='$actual')"; fi
}

log_error() { :; }
log_warn() { :; }

diagnostic_service_get_results() { printf '%s\n' 'fixture-result'; }
diagnostic_service_get_summary() { printf '%s\n' 'total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO'; }
# Si reporting_service vuelve a saltarse la frontera service y toca el engine
# directamente, este stub hace visible la regresión.
engine_get_summary() { printf '%s\n' 'ENGINE_BOUNDARY_VIOLATION'; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/services/reporting_service.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_reporting_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

# Caso 1: ambos renderers exitosos y el service conserva ambas rutas.
CAPTURED_SUMMARY=""
renderer_txt_generate() { CAPTURED_SUMMARY="$3"; printf '%s\n' "$1/Executive_Report.txt"; }
renderer_json_generate() { printf '%s\n' "$1/results.json"; }

if reporting_service_generate "$TMP_ROOT" txt json; then
  _pass "reporting service succeeds when both renderers succeed"
else
  _fail "reporting service succeeds when both renderers succeed"
fi
_assert_eq "$TMP_ROOT/Executive_Report.txt" "$REPORTING_TXT_PATH" "TXT path is retained"
_assert_eq "$TMP_ROOT/results.json" "$REPORTING_JSON_PATH" "JSON path is retained"
_assert_eq "total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO" "$CAPTURED_SUMMARY" "summary comes through diagnostic service boundary"

# Caso 2: TXT falla, JSON debe ejecutarse igualmente y conservar su ruta.
TXT_CALLED=0
JSON_CALLED=0
renderer_txt_generate() { TXT_CALLED=$((TXT_CALLED + 1)); return 1; }
renderer_json_generate() { JSON_CALLED=$((JSON_CALLED + 1)); printf '%s\n' "$1/results.json"; }

if reporting_service_generate "$TMP_ROOT" txt json; then
  _fail "reporting service reports partial renderer failure"
else
  _pass "reporting service reports partial renderer failure"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "failed TXT renderer leaves empty path"
_assert_eq "$TMP_ROOT/results.json" "$REPORTING_JSON_PATH" "successful JSON path survives TXT failure"
_assert_eq "1" "$TXT_CALLED" "TXT renderer attempted once"
_assert_eq "1" "$JSON_CALLED" "JSON renderer still attempted after TXT failure"

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
