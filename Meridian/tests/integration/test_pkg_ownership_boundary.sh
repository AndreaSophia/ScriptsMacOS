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

if printf '%s\n' "$postinstall_body" | grep -Fq 'bad_dirs="$(find "$INSTALL_ROOT" -type d ! -perm 755 -print)"'; then
  pass "postinstall verifica permisos finales de directorios"
else
  fail "postinstall no verifica que los directorios terminen en modo 755"
fi

if printf '%s\n' "$postinstall_body" | grep -Fq 'bad_files="$(find "$INSTALL_ROOT" -type f ! -path "${INSTALL_ROOT}/meridian" ! -perm 644 -print)"'; then
  pass "postinstall verifica permisos finales de archivos"
else
  fail "postinstall no verifica que los archivos terminen en modo 644"
fi

if printf '%s\n' "$postinstall_body" | grep -Fq 'chmod 755 "${INSTALL_ROOT}/meridian" || exit 1'; then
  pass "entrypoint conserva modo ejecutable 755"
else
  fail "entrypoint no conserva contrato ejecutable 755"
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
