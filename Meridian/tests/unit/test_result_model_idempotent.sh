#!/bin/bash
# Regresión: result_model.sh puede cargarse repetidamente sin ruido ni pérdida
# del contrato readonly. Reproduce la topología entrypoint -> worker.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
err_file="$(mktemp "${TMPDIR:-/tmp}/meridian_result_source.XXXXXX")"
trap 'rm -f "$err_file"' EXIT

_pass=0
_fail=0
pass() { printf '✓  %s\n' "$1"; _pass=$((_pass + 1)); }
fail() { printf '✗  %s\n' "$1" >&2; _fail=$((_fail + 1)); }

if source "${MERIDIAN_ROOT}/core/result_model.sh" 2>"$err_file" && \
   source "${MERIDIAN_ROOT}/core/result_model.sh" 2>>"$err_file"; then
  pass "source repetido retorna 0"
else
  fail "source repetido retorna error"
fi

if [ ! -s "$err_file" ]; then
  pass "source repetido no emite stderr"
else
  fail "source repetido emitió stderr: $(cat "$err_file")"
fi

result_init
if [ "$RESULT_STATUS" = "ERROR" ] && [ "$RESULT_REPAIRABLE" = "false" ]; then
  pass "API DiagnosticResult permanece operativa"
else
  fail "API DiagnosticResult quedó inconsistente"
fi

if readonly -p 2>/dev/null | grep -q '_VALID_STATUSES'; then
  pass "constantes siguen readonly"
else
  fail "_VALID_STATUSES dejó de ser readonly"
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
