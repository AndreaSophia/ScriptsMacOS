#!/bin/bash
# =============================================================================
# Meridian — tests/integration/test_headless_entrypoint.sh
# Contrato headless: una ejecución sin TTY y sin selector debe degradar a --all
# en sandbox, sin esperar interacción. Simula launchd/Workspace ONE/MDM sin
# depender de privilegios root ni de agentes instalados en el host.
# Compatible con Bash 3.2 / macOS.
# =============================================================================

set -u

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
out_file="$(mktemp -t meridian_headless_out.XXXXXX)" || exit 1
err_file="$(mktemp -t meridian_headless_err.XXXXXX)" || {
  rm -f "$out_file"
  exit 1
}
trap 'rm -f "$out_file" "$err_file"' EXIT

# --test evita el requisito root. Redirigir stdin desde /dev/null garantiza que
# [ -t 0 ] sea falso, igual que en un job MDM/launchd sin terminal asociada.
"${MERIDIAN_ROOT}/meridian" --test --no-report </dev/null >"$out_file" 2>"$err_file"
rc=$?

if [ "$rc" -ne 0 ]; then
  printf '✗  entrypoint headless retorna %s (esperado 0)\n' "$rc" >&2
  cat "$err_file" >&2
  exit 1
fi
printf '✓  entrypoint headless retorna 0\n'

# Sin selector y sin TTY, el runtime debe ejecutar todos los módulos actuales.
module_count="$(/usr/bin/grep -c '\[module_loader\] Ejecutando módulo:' "$err_file" 2>/dev/null || true)"
if [ "$module_count" -ne 7 ]; then
  printf '✗  headless ejecutó %s módulos (esperado 7)\n' "$module_count" >&2
  cat "$err_file" >&2
  exit 1
fi
printf '✓  headless sin selector ejecuta los 7 módulos\n'

# No debe intentar mostrar el menú interactivo ni pedir entrada al operador.
if /usr/bin/grep -Eqi 'seleccione|selección|opción|presione|menu|menú' "$err_file" "$out_file"; then
  printf '✗  headless mostró o solicitó interacción\n' >&2
  /usr/bin/grep -Ein 'seleccione|selección|opción|presione|menu|menú' "$err_file" "$out_file" >&2 || true
  exit 1
fi
printf '✓  headless no solicita interacción\n'

# Mismo guard que el E2E principal: TUI/progreso en stderr es funcional, pero
# diagnósticos del shell/runtime no deben filtrarse a una ejecución exitosa.
internal_error_pattern='readonly variable|unbound variable|command not found|bad substitution|syntax error|unexpected EOF|unexpected end of file|cannot assign|not a valid identifier|No such file or directory|result_model\.sh: line [0-9]+:'
if /usr/bin/grep -Eqi "$internal_error_pattern" "$err_file"; then
  printf '✗  headless filtró diagnóstico interno de Bash/runtime\n' >&2
  /usr/bin/grep -Ein "$internal_error_pattern" "$err_file" >&2 || true
  exit 1
fi
printf '✓  headless sin diagnósticos internos de Bash/runtime\n'

exit 0
