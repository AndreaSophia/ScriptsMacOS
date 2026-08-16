#!/bin/bash
# Producto completo: el sandbox debe terminar sin diagnósticos internos de Bash
# en stderr. Este test reproduce exactamente ./meridian --test --all.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
out_file="$(mktemp "${TMPDIR:-/tmp}/meridian_e2e_out.XXXXXX")"
err_file="$(mktemp "${TMPDIR:-/tmp}/meridian_e2e_err.XXXXXX")"
trap 'rm -f "$out_file" "$err_file"' EXIT

if "${MERIDIAN_ROOT}/meridian" --test --all --no-report >"$out_file" 2>"$err_file"; then
  printf '✓  entrypoint --test --all retorna 0\n'
else
  rc=$?
  printf '✗  entrypoint --test --all retornó %s\n' "$rc" >&2
  cat "$err_file" >&2
  exit 1
fi

# No confundimos mensajes funcionales de Meridian con errores del intérprete.
# La regresión busca síntomas inequívocos de Bash/runtime que nunca deben
# filtrarse al operador.
if grep -Eqi 'readonly variable|unbound variable|command not found|bad substitution|syntax error|unexpected EOF|result_model\.sh: line [0-9]+:' "$err_file"; then
  printf '✗  stderr contiene diagnóstico interno de Bash:\n' >&2
  cat "$err_file" >&2
  exit 1
fi

printf '✓  stderr no contiene diagnósticos internos de Bash\n'
exit 0
