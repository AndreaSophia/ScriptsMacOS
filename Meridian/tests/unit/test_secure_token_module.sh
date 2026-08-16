#!/bin/bash
# Valida el módulo secure_token contra fixtures deterministas.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_secure_token.XXXXXX")"
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
    printf '✓  %s\n' "$desc"; _pass=$((_pass + 1))
  else
    printf '✗  %s expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2; _fail=$((_fail + 1))
  fi
}

result_init
RESULT_MODULE_ID="secure_token"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/security/secure_token/diagnose.sh"

assert_eq "fixture mixto produce WARN" "WARN" "$RESULT_STATUS"
assert_eq "severidad mixta es MEDIUM" "MEDIUM" "$RESULT_SEVERITY"

case "$RESULT_EVIDENCE" in
  *"safiye (UID 501): Secure Token ENABLED"*) printf '✓  conserva admin habilitado\n'; _pass=$((_pass + 1));;
  *) printf '✗  falta evidencia de safiye\n' >&2; _fail=$((_fail + 1));;
esac
case "$RESULT_EVIDENCE" in
  *"lcladmin (UID 502): Secure Token DISABLED"*) printf '✓  conserva admin sin token\n'; _pass=$((_pass + 1));;
  *) printf '✗  falta evidencia de lcladmin\n' >&2; _fail=$((_fail + 1));;
esac

if result_validate >/dev/null 2>&1; then
  printf '✓  resultado cumple DiagnosticResult\n'; _pass=$((_pass + 1))
else
  printf '✗  resultado viola DiagnosticResult\n' >&2; _fail=$((_fail + 1))
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
