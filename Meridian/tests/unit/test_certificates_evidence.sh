#!/bin/bash
# Valida que un certificado expirado produzca evidencia accionable y que el
# parser use fixtures sin consultar el keychain real del host.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_certificates.XXXXXX")"
trap 'rm -rf "$evidence_dir"' EXIT

export MERIDIAN_TEST_MODE=1
export MERIDIAN_FIXTURE_DIR="${MERIDIAN_ROOT}/tests/fixtures"
export MERIDIAN_EVIDENCE_DIR="$evidence_dir"
source "${MERIDIAN_ROOT}/core/result_model.sh"

_pass=0
_fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '✗  %s expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) printf '✓  %s\n' "$desc"; _pass=$((_pass + 1));;
    *) printf '✗  %s falta=%s\n' "$desc" "$needle" >&2; _fail=$((_fail + 1));;
  esac
}

result_init
RESULT_MODULE_ID="certificates"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/security/certificates/diagnose.sh"

assert_eq "fixture con un expirado produce FAIL" "FAIL" "$RESULT_STATUS"
assert_eq "certificado expirado eleva severidad HIGH" "HIGH" "$RESULT_SEVERITY"
assert_contains "raw output conserva conteo total" "$RESULT_RAW_OUTPUT" "total=2"
assert_contains "raw output conserva conteo expirado" "$RESULT_RAW_OUTPUT" "expired=1"
assert_contains "evidencia identifica estado expirado" "$RESULT_EVIDENCE" "EXPIRED"
assert_contains "evidencia identifica subject" "$RESULT_EVIDENCE" "Meridian Expired Fixture"
assert_contains "evidencia conserva fecha notAfter" "$RESULT_EVIDENCE" "notAfter=Jan  1 00:00:00 2020 GMT"

if printf '%s\n' "$RESULT_EVIDENCE" | /usr/bin/grep -q "Meridian Valid Fixture"; then
  printf '✗  RESULT_EVIDENCE no debe incluir certificados sanos\n' >&2
  _fail=$((_fail + 1))
else
  printf '✓  RESULT_EVIDENCE limita salida a hallazgos anómalos\n'
  _pass=$((_pass + 1))
fi

if /usr/bin/grep -q "Meridian Valid Fixture" "${evidence_dir}/certificates_detail.txt" 2>/dev/null && \
   /usr/bin/grep -q "Meridian Expired Fixture" "${evidence_dir}/certificates_detail.txt" 2>/dev/null; then
  printf '✓  detalle conserva inventario parseado completo\n'
  _pass=$((_pass + 1))
else
  printf '✗  detalle no conserva ambos certificados del fixture\n' >&2
  _fail=$((_fail + 1))
fi

if result_validate >/dev/null 2>&1; then
  printf '✓  resultado cumple DiagnosticResult\n'
  _pass=$((_pass + 1))
else
  printf '✗  resultado viola DiagnosticResult\n' >&2
  _fail=$((_fail + 1))
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
