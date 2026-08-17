#!/bin/bash
# =============================================================================
# Meridian — tests/integration/test_uninstall_contract.sh
# Regresión estática del contrato de desinstalación segura.
#
# No ejecuta rm/pkgutil ni requiere root: comprueba sintaxis y conserva los
# invariantes fail-closed que protegen un Mac real durante uninstall.
# Compatible con Bash 3.2 / macOS.
# =============================================================================

set -u

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UNINSTALLER="${MERIDIAN_ROOT}/dist/uninstall.sh"
passed=0
failed=0

_pass() {
  passed=$((passed + 1))
  printf '✓  %s\n' "$1"
}

_fail() {
  failed=$((failed + 1))
  printf '✗  %s\n' "$1" >&2
}

_assert_contains() {
  local pattern="$1"
  local description="$2"

  if /usr/bin/grep -Eq "$pattern" "$UNINSTALLER"; then
    _pass "$description"
  else
    _fail "$description"
  fi
}

if [ ! -f "$UNINSTALLER" ]; then
  printf '✗  uninstaller no encontrado: %s\n' "$UNINSTALLER" >&2
  exit 1
fi

if /bin/bash -n "$UNINSTALLER"; then
  _pass 'uninstaller válido para parser Bash'
else
  _fail 'uninstaller válido para parser Bash'
fi

# pkgutil forma parte del contrato de limpieza, no una operación best-effort.
_assert_contains 'for tool in .*\$PKGUTIL_BIN' \
  'pkgutil es herramienta requerida para uninstall completo'
_assert_contains "\[ERROR\] no se pudo retirar receipt:" \
  'fallo de pkgutil --forget se clasifica como ERROR'
_assert_contains '_forget_receipt \|\| return 1' \
  'main propaga fallo al retirar receipt'

# Invariantes destructivos: sólo se toca el launcher propio y un payload con
# manifiesto canónico. Estas comprobaciones deben existir antes del rm -rf.
_assert_contains 'no es el symlink administrado por Meridian; no se toca' \
  'archivo ajeno en /usr/local/bin/meridian se preserva'
_assert_contains 'manifiesto de payload ausente o inválido; se rechaza borrar' \
  'payload sin manifiesto falla cerrado'

# La retención de evidencia sigue siendo la conducta por defecto.
_assert_contains 'if \[ "\$_PURGE_LOGS" != "true" \]' \
  'logs se conservan salvo --purge-logs explícito'
_assert_contains 'ruta de logs es symlink; se rechaza purga' \
  'purga de logs rechaza symlinks'

printf 'Pasaron: %s | Fallaron: %s\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
