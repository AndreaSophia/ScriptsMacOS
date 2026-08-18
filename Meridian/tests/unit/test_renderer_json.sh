#!/bin/bash
# Meridian — tests/unit/test_renderer_json.sh
# Regresión: una línea con framing inválido no debe reutilizar RESULT_* del
# registro válido anterior ni duplicarlo en results.json.
# Compatible con Bash 3.2; no requiere llamadas mutantes al sistema.

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

log_warn() { :; }
log_error() { :; }
log_ok() { :; }

# Linux de CI/desarrollo puede no tener sw_vers. El renderer ya tolera eso,
# pero este stub mantiene la prueba determinista sin alterar la lógica objetivo.
sw_vers() { [ "${1:-}" = "-productVersion" ] && printf '%s\n' '26.0'; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/core/result_model.sh"
# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/reporting/renderer_json.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_renderer_json_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

result_init
RESULT_MODULE_ID="fixture_module"
RESULT_MODULE_VERSION="1.0.0"
RESULT_TIMESTAMP="2026-08-15T12:00:00Z"
RESULT_HOSTNAME="fixture-host"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Resultado válido"
RESULT_DESCRIPTION="Fixture"
RESULT_EXPLANATION="N/A"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_REPAIR_ID=""
RESULT_EXECUTION_TIME_MS="1"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT="ok"
RESULT_RULE_TRIGGERED=""
RESULT_EVIDENCE=""

VALID_RESULT="$(result_serialize)"
MALFORMED_RESULT='malformed|frame'
RESULTS_BLOB="${VALID_RESULT}"$'\n'"${MALFORMED_RESULT}"
SUMMARY='total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO'

OUTFILE="$(renderer_json_generate "$TMP_ROOT" "$RESULTS_BLOB" "$SUMMARY")"

if [ -f "$OUTFILE" ]; then
  _pass "JSON renderer creates output"
else
  _fail "JSON renderer creates output"
fi

MODULE_COUNT="$(grep -o '"module_id":"fixture_module"' "$OUTFILE" 2>/dev/null | wc -l | tr -d ' ')"
_assert_eq "1" "$MODULE_COUNT" "malformed frame does not duplicate previous canonical result"

MALFORMED_COUNT="$(grep -o 'malformed' "$OUTFILE" 2>/dev/null | wc -l | tr -d ' ')"
_assert_eq "0" "$MALFORMED_COUNT" "malformed frame is omitted from JSON"

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
