#!/bin/bash
# Regression: el entrypoint puede ejecutarse privilegiado y no debe resolver
# utilidades críticas desde PATH heredado. Compatible con Bash 3.2/macOS.

MERIDIAN_ROOT="$(cd "$(/usr/bin/dirname "$0")/../.." && pwd)"
_TMP_ROOT="${TMPDIR:-/tmp}/meridian-entrypoint-path-$$"
_HOSTILE_DIR="${_TMP_ROOT}/hostile"
_MARKER="${_TMP_ROOT}/hostile-invoked"
_STDOUT="${_TMP_ROOT}/stdout"
_STDERR="${_TMP_ROOT}/stderr"

/bin/mkdir -p "$_HOSTILE_DIR" || exit 1
trap '/bin/rm -rf "$_TMP_ROOT"' EXIT

# Nombres usados por el entrypoint para resolver ubicación/versión, construir
# nombres de sesión y devolver ownership. Cualquier ejecución desde PATH deja
# evidencia y aborta con un rc inequívoco.
for _name in readlink dirname cat tr dscacheutil awk hostname date id chown; do
  printf '#!/bin/bash\nprintf "%%s\\n" %q >> %q\nexit 99\n' \
    "$_name" "$_MARKER" >"${_HOSTILE_DIR}/${_name}"
  /bin/chmod 700 "${_HOSTILE_DIR}/${_name}"
done

_fail=0
printf '\ntest_entrypoint_path_boundary.sh\n\n'

if PATH="$_HOSTILE_DIR" /bin/bash "${MERIDIAN_ROOT}/meridian" --help >"$_STDOUT" 2>"$_STDERR"; then
  printf 'PASS: entrypoint --help funciona con PATH hostil\n'
else
  _rc=$?
  printf 'FAIL: entrypoint --help falló con PATH hostil (rc=%s)\n' "$_rc" >&2
  _fail=$((_fail + 1))
fi

_HELP=""
[ -f "$_STDOUT" ] && _HELP="$(/bin/cat "$_STDOUT")"
case "$_HELP" in
  *"Meridian v1.0.0-mvp"*)
    printf 'PASS: versión se resolvió sin depender de PATH\n'
    ;;
  *)
    printf 'FAIL: --help no contiene la versión esperada\n' >&2
    _fail=$((_fail + 1))
    ;;
esac

if [ -e "$_MARKER" ]; then
  printf 'FAIL: entrypoint ejecutó una utilidad desde PATH hostil\n' >&2
  /bin/cat "$_MARKER" >&2
  _fail=$((_fail + 1))
else
  printf 'PASS: ninguna utilidad hostil fue ejecutada\n'
fi

printf '\nFallaron: %s\n\n' "$_fail"
exit "$_fail"
