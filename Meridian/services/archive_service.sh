#!/bin/bash
# =============================================================================
# Meridian — services/archive_service.sh
# Responsabilidad: crear el ZIP de una sesión sin reutilizar ni sobrescribir
# artefactos preexistentes. El caller decide si un fallo de archivado es fatal.
# Compatible con Bash 3.2 / macOS.
# =============================================================================

# Esta capa puede ejecutarse como root. No resolvemos utilidades críticas desde
# PATH: un entorno heredado de sudo/MDM no debe poder sustituir zip, mktemp, ln
# o rm por ejecutables controlados por otro usuario. Estas rutas son estándar en
# macOS y forman parte de la frontera privilegiada del servicio.
_ARCHIVE_ZIP_BIN="/usr/bin/zip"
_ARCHIVE_MKTEMP_BIN="/usr/bin/mktemp"
_ARCHIVE_LN_BIN="/bin/ln"
_ARCHIVE_RM_BIN="/bin/rm"
_ARCHIVE_MKDIR_BIN="/bin/mkdir"
_ARCHIVE_DIRNAME_BIN="/usr/bin/dirname"
_ARCHIVE_BASENAME_BIN="/usr/bin/basename"

_archive_require_tools() {
  local tool
  for tool in \
    "$_ARCHIVE_ZIP_BIN" \
    "$_ARCHIVE_MKTEMP_BIN" \
    "$_ARCHIVE_LN_BIN" \
    "$_ARCHIVE_RM_BIN" \
    "$_ARCHIVE_MKDIR_BIN" \
    "$_ARCHIVE_DIRNAME_BIN" \
    "$_ARCHIVE_BASENAME_BIN"; do
    if [ ! -x "$tool" ]; then
      printf '[archive] utilidad del sistema no disponible: %s\n' "$tool" >&2
      return 1
    fi
  done
  return 0
}

# archive_service_create <session_dir> <zip_path>
#
# Invariantes:
#   - session_dir debe existir como directorio real (no symlink)
#   - zip_path debe ser nuevo: nunca se actualiza ni reemplaza un ZIP existente
#   - el ZIP se construye fuera de session_dir y se publica mediante hard-link
#     atómico, evitando una carrera check-then-overwrite
#   - las utilidades críticas se ejecutan por ruta absoluta, nunca vía PATH
#   - stdout devuelve exclusivamente la ruta publicada
archive_service_create() {
  local session_dir="${1:-}"
  local zip_path="${2:-}"

  [ -n "$session_dir" ] || {
    printf '%s\n' '[archive] session_dir vacío' >&2
    return 2
  }
  [ -n "$zip_path" ] || {
    printf '%s\n' '[archive] zip_path vacío' >&2
    return 2
  }

  if [ ! -d "$session_dir" ] || [ -L "$session_dir" ]; then
    printf '[archive] directorio de sesión inválido: %s\n' "$session_dir" >&2
    return 3
  fi

  if ! _archive_require_tools; then
    return 4
  fi

  local zip_parent zip_name session_parent session_name
  zip_parent="$("$_ARCHIVE_DIRNAME_BIN" "$zip_path")" || return 5
  zip_name="$("$_ARCHIVE_BASENAME_BIN" "$zip_path")" || return 5
  session_parent="$("$_ARCHIVE_DIRNAME_BIN" "$session_dir")" || return 5
  session_name="$("$_ARCHIVE_BASENAME_BIN" "$session_dir")" || return 5

  # Nunca seguir un symlink directo como directorio de publicación.
  if [ -L "$zip_parent" ]; then
    printf '[archive] directorio de destino es symlink: %s\n' "$zip_parent" >&2
    return 5
  fi

  if [ ! -d "$zip_parent" ]; then
    "$_ARCHIVE_MKDIR_BIN" -p "$zip_parent" 2>/dev/null || {
      printf '[archive] no se pudo crear directorio de destino: %s\n' "$zip_parent" >&2
      return 5
    }
  fi

  # No reutilizar una ruta existente, ni siquiera un symlink colgante.
  if [ -e "$zip_path" ] || [ -L "$zip_path" ]; then
    printf '[archive] destino ya existe; se rechaza overwrite/update: %s\n' "$zip_path" >&2
    return 6
  fi

  # Construir el temporal en el mismo filesystem que el destino para poder
  # publicarlo con ln(1) de forma atómica y fail-closed.
  local temp_dir temp_zip
  temp_dir="$("$_ARCHIVE_MKTEMP_BIN" -d "${zip_parent}/.meridian_archive.XXXXXX" 2>/dev/null)" || {
    printf '[archive] no se pudo crear temporal en: %s\n' "$zip_parent" >&2
    return 7
  }
  temp_zip="${temp_dir}/${zip_name}"

  if ! ( cd "$session_parent" && "$_ARCHIVE_ZIP_BIN" -r "$temp_zip" "$session_name" >/dev/null 2>&1 ); then
    "$_ARCHIVE_RM_BIN" -rf "$temp_dir" 2>/dev/null || true
    printf '[archive] zip falló para sesión: %s\n' "$session_dir" >&2
    return 8
  fi

  if [ ! -f "$temp_zip" ] || [ -L "$temp_zip" ]; then
    "$_ARCHIVE_RM_BIN" -rf "$temp_dir" 2>/dev/null || true
    printf '%s\n' '[archive] zip no produjo un artefacto regular' >&2
    return 9
  fi

  # ln falla si zip_path apareció durante el build. A diferencia de mv/cp, no
  # reemplaza el objeto existente y no sigue un symlink de destino.
  if ! "$_ARCHIVE_LN_BIN" "$temp_zip" "$zip_path" 2>/dev/null; then
    "$_ARCHIVE_RM_BIN" -rf "$temp_dir" 2>/dev/null || true
    printf '[archive] destino apareció durante publicación; se rechaza: %s\n' "$zip_path" >&2
    return 10
  fi

  "$_ARCHIVE_RM_BIN" -rf "$temp_dir" 2>/dev/null || true

  if [ ! -f "$zip_path" ] || [ -L "$zip_path" ]; then
    "$_ARCHIVE_RM_BIN" -f "$zip_path" 2>/dev/null || true
    printf '[archive] artefacto publicado inválido: %s\n' "$zip_path" >&2
    return 11
  fi

  printf '%s\n' "$zip_path"
}
