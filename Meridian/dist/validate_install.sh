#!/bin/bash
# =============================================================================
# Meridian — dist/validate_install.sh
# Valida de forma read-only una instalación PKG existente.
# Compatible con Bash 3.2 y herramientas nativas de macOS.
# =============================================================================

set -u

INSTALL_ROOT="/usr/local/lib/meridian"
COMMAND_PATH="/usr/local/bin/meridian"
EXPECTED_OWNER="root"
EXPECTED_GROUP="wheel"
EXPECTED_DIR_MODE="755"
EXPECTED_FILE_MODE="644"
EXPECTED_ENTRY_MODE="755"
MANIFEST_NAME=".meridian-payload-manifest"

_pass=0
_fail=0

_ok() {
  _pass=$((_pass + 1))
  printf '✓ %s\n' "$1"
}

_bad() {
  _fail=$((_fail + 1))
  printf '✗ %s\n' "$1" >&2
}

_stat_owner() { /usr/bin/stat -f '%Su' "$1" 2>/dev/null; }
_stat_group() { /usr/bin/stat -f '%Sg' "$1" 2>/dev/null; }
_stat_mode()  { /usr/bin/stat -f '%Lp' "$1" 2>/dev/null; }

_check_exact_mode() {
  _path="$1"
  _expected="$2"
  _actual="$(_stat_mode "$_path")"
  if [ "$_actual" = "$_expected" ]; then
    _ok "modo $_expected: $_path"
  else
    _bad "modo inesperado en $_path (esperado=$_expected actual=${_actual:-desconocido})"
  fi
}

_check_owner_group() {
  _path="$1"
  _owner="$(_stat_owner "$_path")"
  _group="$(_stat_group "$_path")"
  if [ "$_owner" = "$EXPECTED_OWNER" ] && [ "$_group" = "$EXPECTED_GROUP" ]; then
    _ok "ownership root:wheel: $_path"
  else
    _bad "ownership inesperado en $_path (esperado=root:wheel actual=${_owner:-?}:${_group:-?})"
  fi
}

printf 'Meridian — validación de instalación\n'
printf '===================================\n'

if [ ! -d "$INSTALL_ROOT" ]; then
  _bad "install root ausente: $INSTALL_ROOT"
  printf '\nPasaron: %d | Fallaron: %d\n' "$_pass" "$_fail"
  exit 1
fi
_ok "install root presente"

if [ ! -x "${INSTALL_ROOT}/meridian" ]; then
  _bad "entrypoint ausente o no ejecutable"
else
  _ok "entrypoint ejecutable"
fi

if [ ! -s "${INSTALL_ROOT}/VERSION" ]; then
  _bad "VERSION ausente o vacío"
else
  _version="$(tr -d '[:space:]' < "${INSTALL_ROOT}/VERSION")"
  case "$_version" in
    [0-9]*.[0-9]*.[0-9]*) _ok "VERSION instalada: $_version" ;;
    *) _bad "VERSION instalada inválida: $_version" ;;
  esac
fi

if [ -L "$COMMAND_PATH" ]; then
  _target="$(/usr/bin/readlink "$COMMAND_PATH" 2>/dev/null || true)"
  if [ "$_target" = "${INSTALL_ROOT}/meridian" ]; then
    _ok "symlink de comando correcto"
  else
    _bad "symlink apunta a destino inesperado: ${_target:-desconocido}"
  fi
else
  _bad "$COMMAND_PATH no es symlink"
fi

_check_owner_group "$INSTALL_ROOT"
_check_exact_mode "$INSTALL_ROOT" "$EXPECTED_DIR_MODE"
_check_owner_group "${INSTALL_ROOT}/meridian"
_check_exact_mode "${INSTALL_ROOT}/meridian" "$EXPECTED_ENTRY_MODE"
_check_owner_group "${INSTALL_ROOT}/VERSION"
_check_exact_mode "${INSTALL_ROOT}/VERSION" "$EXPECTED_FILE_MODE"

_manifest="${INSTALL_ROOT}/${MANIFEST_NAME}"
if [ -s "$_manifest" ]; then
  _ok "manifiesto de payload presente"
  _check_owner_group "$_manifest"
  _check_exact_mode "$_manifest" "$EXPECTED_FILE_MODE"
else
  _bad "manifiesto de payload ausente o vacío"
fi

# Verificar todo el árbol instalado. No asumimos que los módulos sean ejecutables:
# Meridian los carga por source y el builder normaliza los archivos a 0644.
while IFS= read -r _path; do
  [ -n "$_path" ] || continue
  _check_owner_group "$_path"
  if [ -d "$_path" ]; then
    _check_exact_mode "$_path" "$EXPECTED_DIR_MODE"
  elif [ -f "$_path" ]; then
    if [ "$_path" = "${INSTALL_ROOT}/meridian" ]; then
      _check_exact_mode "$_path" "$EXPECTED_ENTRY_MODE"
    else
      _check_exact_mode "$_path" "$EXPECTED_FILE_MODE"
    fi
  fi
done < <(/usr/bin/find "$INSTALL_ROOT" \( -type d -o -type f \) -print 2>/dev/null)

if [ -x "$COMMAND_PATH" ]; then
  _help_out="$($COMMAND_PATH --help 2>&1)"
  _help_rc=$?
  if [ "$_help_rc" -eq 0 ] && printf '%s\n' "$_help_out" | /usr/bin/grep -q 'Meridian'; then
    _ok "comando instalado responde a --help"
  else
    _bad "comando instalado no supera --help (rc=$_help_rc)"
  fi
else
  _bad "comando instalado no es ejecutable"
fi

printf '\nPasaron: %d | Fallaron: %d\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
