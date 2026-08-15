#!/bin/bash
# Meridian — tests/unit/test_tui_result_display.sh
# Regresión: la TUI no debe reutilizar RESULT_* tras framing inválido y un
# resumen incompleto no debe abortar una sesión bajo `set -e`.
# Compatible con Bash 3.2; no realiza cambios al sistema.

set -eu

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

tui_separator() { printf '%s\n' '---'; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/core/result_model.sh"
# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/ui/tui/result_display.sh"

result_init
RESULT_MODULE_ID="fixture_module"
RESULT_MODULE_VERSION="1.0.0"
RESULT_TIMESTAMP="2026-08-15T12:00:00Z"
RESULT_HOSTNAME="fixture-host"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Resultado canónico único"
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
RESULTS_BLOB="${VALID_RESULT}"$'\n''malformed|frame'

DISPLAY_OUTPUT="$(tui_display_results "$RESULTS_BLOB")"
TITLE_COUNT="$(printf '%s\n' "$DISPLAY_OUTPUT" | grep -c 'Resultado canónico único' || true)"
INVALID_COUNT="$(printf '%s\n' "$DISPLAY_OUTPUT" | grep -c 'Resultado inválido omitido' || true)"
_assert_eq "1" "$TITLE_COUNT" "malformed frame does not duplicate previous TUI result"
_assert_eq "1" "$INVALID_COUNT" "malformed frame is visibly rejected once"

# Bajo set -e, una clave ausente no debe convertir una limitación visual en
# terminación de la aplicación. Defaults: campos ausentes -> 0, severidad -> INFO.
SUMMARY_OUTPUT="$(tui_display_summary 'total=1 pass=1')"
if printf '%s\n' "$SUMMARY_OUTPUT" | grep -q 'Módulos ejecutados'; then
  _pass "incomplete summary remains renderable under errexit"
else
  _fail "incomplete summary remains renderable under errexit"
fi
if printf '%s\n' "$SUMMARY_OUTPUT" | grep -q 'INFO'; then
  _pass "missing worst severity defaults safely to INFO"
else
  _fail "missing worst severity defaults safely to INFO"
fi

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
