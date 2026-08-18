#!/bin/bash
# =============================================================================
# Meridian — dist/uninstall.sh
# Desinstalación segura del producto instalado por PKG.
# Compatible con Bash 3.2 / macOS.
#
# Por defecto conserva logs y sesiones históricas en /Library/Logs/Meridian.
# Use --purge-logs únicamente cuando la política de soporte/retención lo permita.
# =============================================================================

set -u
umask 027

readonly INSTALL_ROOT="/usr/local/lib/meridian"
readonly COMMAND_PATH="/usr/local/bin/meridian"
readonly LOG_ROOT="/Library/Logs/Meridian"
readonly PKG_IDENTIFIER="com.itau.apple.meridian"
readonly MANIFEST_NAME=".meridian-payload-manifest"
readonly RM_BIN="/bin/rm"
readonly RMDIR_BIN="/bin/rmdir"
readonly PKGUTIL_BIN="/usr/sbin/pkgutil"
readonly ID_BIN="/usr/bin/id"
readonly READLINK_BIN="/usr/bin/readlink"

_PURGE_LOGS=false

_usage() {
  cat <<'HELP'
Uso:
  sudo bash dist/uninstall.sh [--purge-logs]

Opciones:
  --purge-logs   Elimina también /Library/Logs/Meridian.
  --help, -h     Muestra esta ayuda.

Por defecto se elimina únicamente el producto instalado y su receipt; los logs
se conservan para no destruir evidencia de soporte o auditoría accidentalmente.
HELP
}

_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge-logs)
        _PURGE_LOGS=true
        shift
        ;;
      --help|-h)
        _usage
        exit 0
        ;;
      *)
        printf '[ERROR] Argumento desconocido: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done
}

_require_root() {
  [ -x "$ID_BIN" ] || {
    printf '%s\n' '[ERROR] /usr/bin/id no disponible' >&2
    return 1
  }
  if [ "$("$ID_BIN" -u 2>/dev/null)" != "0" ]; then
    printf '%s\n' '[ERROR] La desinstalación requiere root (sudo).' >&2
    return 1
  fi
}

_require_tools() {
  local tool
  for tool in "$RM_BIN" "$RMDIR_BIN" "$READLINK_BIN" "$PKGUTIL_BIN"; do
    [ -x "$tool" ] || {
      printf '[ERROR] Utilidad requerida no disponible: %s\n' "$tool" >&2
      return 1
    }
  done
}

_validate_command_link() {
  # No borrar jamás un archivo/launcher de terceros que ocupe el nombre meridian.
  if [ -L "$COMMAND_PATH" ]; then
    local target
    target="$("$READLINK_BIN" "$COMMAND_PATH" 2>/dev/null || true)"
    if [ "$target" != "${INSTALL_ROOT}/meridian" ]; then
      printf '[ERROR] %s apunta a un destino inesperado: %s\n' \
        "$COMMAND_PATH" "${target:-desconocido}" >&2
      return 1
    fi
    return 0
  fi

  if [ -e "$COMMAND_PATH" ]; then
    printf '[ERROR] %s existe pero no es el symlink administrado por Meridian; no se toca.\n' \
      "$COMMAND_PATH" >&2
    return 1
  fi

  return 0
}

_validate_install_root() {
  [ -e "$INSTALL_ROOT" ] || return 0

  if [ -L "$INSTALL_ROOT" ] || [ ! -d "$INSTALL_ROOT" ]; then
    printf '[ERROR] install root inesperado o inseguro: %s\n' "$INSTALL_ROOT" >&2
    return 1
  fi

  # El manifiesto es una señal de que este árbol pertenece al PKG de Meridian.
  # Sin él, fallamos cerrado en vez de hacer rm -rf sobre una ruta fija.
  if [ ! -f "${INSTALL_ROOT}/${MANIFEST_NAME}" ] || [ -L "${INSTALL_ROOT}/${MANIFEST_NAME}" ]; then
    printf '[ERROR] manifiesto de payload ausente o inválido; se rechaza borrar %s\n' \
      "$INSTALL_ROOT" >&2
    return 1
  fi

  return 0
}

_remove_product() {
  if [ -L "$COMMAND_PATH" ]; then
    "$RM_BIN" -f "$COMMAND_PATH" || return 1
    printf '✓ comando retirado: %s\n' "$COMMAND_PATH"
  else
    printf '· comando ya ausente: %s\n' "$COMMAND_PATH"
  fi

  if [ -d "$INSTALL_ROOT" ] && [ ! -L "$INSTALL_ROOT" ]; then
    "$RM_BIN" -rf "$INSTALL_ROOT" || return 1
    printf '✓ payload retirado: %s\n' "$INSTALL_ROOT"
  else
    printf '· payload ya ausente: %s\n' "$INSTALL_ROOT"
  fi

  return 0
}

_forget_receipt() {
  if "$PKGUTIL_BIN" --pkg-info "$PKG_IDENTIFIER" >/dev/null 2>&1; then
    if "$PKGUTIL_BIN" --forget "$PKG_IDENTIFIER" >/dev/null 2>&1; then
      printf '✓ receipt retirado: %s\n' "$PKG_IDENTIFIER"
      return 0
    fi

    printf '[ERROR] no se pudo retirar receipt: %s\n' "$PKG_IDENTIFIER" >&2
    return 1
  fi

  printf '· receipt ya ausente: %s\n' "$PKG_IDENTIFIER"
  return 0
}

_purge_logs_if_requested() {
  if [ "$_PURGE_LOGS" != "true" ]; then
    if [ -e "$LOG_ROOT" ]; then
      printf '· logs conservados: %s\n' "$LOG_ROOT"
    fi
    return 0
  fi

  if [ -L "$LOG_ROOT" ]; then
    printf '[ERROR] ruta de logs es symlink; se rechaza purga: %s\n' "$LOG_ROOT" >&2
    return 1
  fi

  if [ -d "$LOG_ROOT" ]; then
    "$RM_BIN" -rf "$LOG_ROOT" || return 1
    printf '✓ logs retirados: %s\n' "$LOG_ROOT"
  else
    printf '· logs ya ausentes: %s\n' "$LOG_ROOT"
  fi
}

main() {
  _parse_args "$@" || return $?
  _require_root || return 1
  _require_tools || return 1
  _validate_command_link || return 1
  _validate_install_root || return 1

  printf '%s\n' 'Meridian — desinstalación segura'
  printf '%s\n' '================================'

  _remove_product || {
    printf '%s\n' '[ERROR] No se pudo retirar completamente el producto.' >&2
    return 1
  }

  _forget_receipt || return 1
  _purge_logs_if_requested || return 1

  printf '%s\n' '✓ Meridian desinstalado'
  return 0
}

main "$@"
