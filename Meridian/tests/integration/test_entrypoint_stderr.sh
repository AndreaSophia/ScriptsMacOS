#!/bin/bash
# Producto completo: el sandbox debe terminar sin ruido interno en stderr.
# Este test reproduce exactamente ./meridian --test --all y trata cualquier
# salida por stderr como regresión del runtime/contrato del producto.

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

# En un flujo sandbox exitoso Meridian no debe escribir nada a stderr. Esto
# bloquea no solo el bug readonly reproducido, sino futuras advertencias de
# Bash, sources repetidos, variables unset o fallos internos que aún retornen 0.
if [ -s "$err_file" ]; then
  printf '✗  stderr no está limpio durante --test --all:\n' >&2
  cat "$err_file" >&2
  exit 1
fi

printf '✓  stderr completamente limpio en --test --all\n'
exit 0
