#!/bin/bash
# Producto completo: el sandbox debe terminar sin diagnósticos internos del
# intérprete/runtime en stderr. Meridian usa stderr deliberadamente para TUI,
# progreso y audit; esa salida funcional forma parte del contrato del CLI.
# Este test reproduce exactamente ./meridian --test --all y bloquea síntomas
# inequívocos de fallos Bash que podrían quedar ocultos aunque el proceso retorne 0.

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

# No confundimos presentación funcional con errores del shell. Estos patrones
# cubren la regresión readonly reproducida y familias de fallos internos que no
# deben filtrarse al operador desde un flujo exitoso.
internal_error_pattern='readonly variable|unbound variable|command not found|bad substitution|syntax error|unexpected EOF|unexpected end of file|cannot assign|not a valid identifier|No such file or directory|result_model\.sh: line [0-9]+:'

if /usr/bin/grep -Eqi "$internal_error_pattern" "$err_file"; then
  printf '✗  stderr contiene diagnóstico interno de Bash/runtime:\n' >&2
  /usr/bin/grep -Ein "$internal_error_pattern" "$err_file" >&2 || true
  exit 1
fi

printf '✓  stderr contiene solo salida funcional; sin diagnósticos internos de Bash/runtime\n'
exit 0
