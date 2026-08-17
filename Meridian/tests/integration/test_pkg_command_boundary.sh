#!/bin/bash
# =============================================================================
# Meridian — test_pkg_command_boundary.sh
# Protege el límite de propiedad de /usr/local/bin/meridian durante install/upgrade.
# No modifica el sistema: valida el contrato generado por build_pkg.sh.
# =============================================================================

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_SCRIPT="${ROOT}/dist/build_pkg.sh"
_pass=0
_fail=0

pass() {
  printf '✓  %s\n' "$1"
  _pass=$((_pass + 1))
}

fail() {
  printf '✗  %s\n' "$1" >&2
  _fail=$((_fail + 1))
}

if bash -n "$BUILD_SCRIPT"; then
  pass "build_pkg.sh válido para parser Bash"
else
  fail "build_pkg.sh contiene error de sintaxis"
fi

expected_count="$(grep -c '^EXPECTED_COMMAND_TARGET=' "$BUILD_SCRIPT" 2>/dev/null || true)"
if [ "$expected_count" -eq 2 ]; then
  pass "preinstall y postinstall declaran destino esperado del comando"
else
  fail "destino esperado del comando no está declarado en ambos scripts de Installer"
fi

link_guard_count="$(grep -F -c 'if [ -L "$COMMAND_PATH" ]; then' "$BUILD_SCRIPT" 2>/dev/null || true)"
if [ "$link_guard_count" -eq 2 ]; then
  pass "preinstall y postinstall inspeccionan symlink existente"
else
  fail "falta inspección de symlink en preinstall o postinstall"
fi

readlink_count="$(grep -F -c 'readlink "$COMMAND_PATH"' "$BUILD_SCRIPT" 2>/dev/null || true)"
if [ "$readlink_count" -eq 2 ]; then
  pass "destino del symlink se resuelve antes de reemplazarlo"
else
  fail "el symlink no se resuelve en ambos límites de instalación"
fi

foreign_guard_count="$(grep -F -c 'apunta a un destino ajeno; no se sobrescribe' "$BUILD_SCRIPT" 2>/dev/null || true)"
if [ "$foreign_guard_count" -eq 2 ]; then
  pass "symlink ajeno falla cerrado en preinstall y postinstall"
else
  fail "falta fail-closed para symlink ajeno en algún script de Installer"
fi

unsafe_count="$(grep -F -c 'if [ -e "$COMMAND_PATH" ] && [ ! -L "$COMMAND_PATH" ]; then' "$BUILD_SCRIPT" 2>/dev/null || true)"
if [ "$unsafe_count" -eq 0 ]; then
  pass "no queda el contrato que aceptaba cualquier symlink"
else
  fail "persiste el contrato inseguro que acepta cualquier symlink"
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
