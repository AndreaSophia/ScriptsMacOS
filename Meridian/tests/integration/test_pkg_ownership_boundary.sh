#!/bin/bash
# =============================================================================
# Meridian — test_pkg_ownership_boundary.sh
# Protege el contrato de ownership/permisos del postinstall generado por build_pkg.sh.
# No modifica el sistema.
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

postinstall_body="$(awk '/^  cat > .*postinstall.*POSTINSTALL/{capture=1; next} /^POSTINSTALL$/{capture=0} capture {print}' "$BUILD_SCRIPT")"

if printf '%s\n' "$postinstall_body" | grep -Fqx 'set -eu'; then
  pass "postinstall aborta ante fallos de comandos críticos"
else
  fail "postinstall no activa fail-fast"
fi

if printf '%s\n' "$postinstall_body" | grep -Fqx 'chown -R root:wheel "$INSTALL_ROOT"'; then
  pass "ownership del payload es obligatorio"
else
  fail "ownership root:wheel del payload no está protegido"
fi

if printf '%s\n' "$postinstall_body" | grep -Fqx 'chown root:admin "/Library/Logs/Meridian"'; then
  pass "ownership del directorio de logs es obligatorio"
else
  fail "ownership root:admin de logs no está protegido"
fi

if printf '%s\n' "$postinstall_body" | grep -Eq 'chown .*\|\| true'; then
  fail "postinstall aún ignora fallos de chown"
else
  pass "ningún chown crítico se degrada a best-effort"
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
