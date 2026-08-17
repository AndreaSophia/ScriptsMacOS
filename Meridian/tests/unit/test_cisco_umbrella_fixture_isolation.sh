#!/bin/bash
# Regression: --test del módulo Cisco Umbrella no debe inspeccionar el host.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODULE="${ROOT_DIR}/modules/network/cisco_umbrella/diagnose.sh"
TMP_DIR="$(mktemp -d /tmp/meridian_umbrella_test.XXXXXX)" || exit 1
FIXTURE_DIR="${TMP_DIR}/fixtures"
EVIDENCE_DIR="${TMP_DIR}/evidence"
SCUTIL_MARKER="${TMP_DIR}/scutil.called"
PS_MARKER="${TMP_DIR}/ps.called"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_DIR" "$EVIDENCE_DIR"

passed=0
failed=0

pass() {
  printf '✓  %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf '✗  %s\n' "$1" >&2
  failed=$((failed + 1))
}

# Si el módulo intenta consultar estas herramientas en modo fixture, queda marca.
scutil() {
  : > "$SCUTIL_MARKER"
  printf 'nameserver[0] : 208.67.222.222\n'
}
ps() {
  : > "$PS_MARKER"
  printf 'root 1 0.0 0.0 Cisco Secure Client\n'
}

MERIDIAN_TEST_MODE=1
MERIDIAN_FIXTURE_DIR="$FIXTURE_DIR"
MERIDIAN_EVIDENCE_DIR="$EVIDENCE_DIR"
export MERIDIAN_TEST_MODE MERIDIAN_FIXTURE_DIR MERIDIAN_EVIDENCE_DIR

RESULT_STATUS=""
RESULT_SEVERITY=""
RESULT_TITLE=""
RESULT_DESCRIPTION=""
RESULT_EXPLANATION=""
RESULT_RISK=""
RESULT_SUGGESTED_ACTION=""
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=""

# shellcheck disable=SC1090
. "$MODULE"

if [ "$RESULT_STATUS" = "SKIP" ]; then
  pass "fixture vacío permanece limpio: SKIP"
else
  fail "fixture vacío permanece limpio: SKIP (obtuvo ${RESULT_STATUS:-vacío})"
fi

if [ ! -e "$SCUTIL_MARKER" ] && [ ! -e "$PS_MARKER" ]; then
  pass "modo fixture no consulta scutil ni ps del host"
else
  fail "modo fixture consultó herramientas del host"
fi

case "$RESULT_RAW_OUTPUT" in
  *"secure_client=false"*"umbrella_module=false"*"legacy=false"*"active=false"*"umbrella_dns=false"*)
    pass "raw output deriva solo de fixtures vacíos"
    ;;
  *)
    fail "raw output contiene señales ajenas al fixture: $RESULT_RAW_OUTPUT"
    ;;
esac

printf 'true\n' > "${FIXTURE_DIR}/umbrella_secure_client.txt"
printf 'true\n' > "${FIXTURE_DIR}/umbrella_module.txt"
printf 'com.cisco.secureclient.umbrella\n' > "${FIXTURE_DIR}/umbrella_running.txt"

RESULT_STATUS=""
RESULT_RAW_OUTPUT=""
. "$MODULE"

if [ "$RESULT_STATUS" = "PASS" ]; then
  pass "fixture positivo explícito produce PASS"
else
  fail "fixture positivo explícito produce PASS (obtuvo ${RESULT_STATUS:-vacío})"
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
