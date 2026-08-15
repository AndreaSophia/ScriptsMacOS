#!/bin/bash
# =============================================================================
# Meridian — core/module_registry.sh
# Registro en memoria de módulos cargados.
# Compatible con Bash 3.2/macOS sin depender de escapes GNU en sed/awk.
# =============================================================================

_REGISTRY=""
_REGISTRY_COUNT=0

registry_add() {
  local id="$1" name="$2" category="$3" version="$4"
  local criticality="$5" path="$6" requires_root="$7" timeout="$8"
  local dependencies="${9:-}" value

  # El registry usa ||| como framing interno. Ningún campo puede contener el
  # delimitador físico ni saltos de línea; aceptar esos valores corrompería las
  # columnas o crearía registros fantasma. Las dependencias viajan como CSV de
  # IDs snake_case y por eso las comas sí son válidas únicamente en ese campo.
  for value in "$id" "$name" "$category" "$version" "$criticality" "$path" "$requires_root" "$timeout" "$dependencies"; do
    case "$value" in
      *'|'*|*$'\n'*|*$'\r'*)
        log_error "registry" "Campo de módulo contiene caracteres no seguros para el registry: $id"
        return 1
        ;;
    esac
  done

  if registry_exists "$id"; then
    log_warn "registry" "Módulo duplicado ignorado: $id"
    return 1
  fi

  local entry="${id}|||${name}|||${category}|||${version}|||${criticality}|||${path}|||${requires_root}|||${timeout}|||${dependencies}"
  if [ -n "$_REGISTRY" ]; then
    _REGISTRY="${_REGISTRY}"$'\n'"${entry}"
  else
    _REGISTRY="$entry"
  fi
  _REGISTRY_COUNT=$((_REGISTRY_COUNT + 1))

  log_debug "registry" "Registrado: ${id} (${category}) v${version}"
  return 0
}

registry_exists() {
  local id="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ "$(printf '%s\n' "$line" | cut -d'|' -f1)" = "$id" ] && return 0
  done <<EOF
$_REGISTRY
EOF
  return 1
}

# Como el separador lógico es |||, cut con '|' deja dos campos vacíos entre
# valores. Los campos lógicos 1..9 están en posiciones 1,4,7,...,25.
_registry_cut_position() {
  case "$1" in
    1) echo 1;; 2) echo 4;; 3) echo 7;; 4) echo 10;;
    5) echo 13;; 6) echo 16;; 7) echo 19;; 8) echo 22;; 9) echo 25;;
    *) return 1;;
  esac
}

registry_get_field() {
  local id="$1" field="$2" pos line
  pos="$(_registry_cut_position "$field")" || return 1

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$(printf '%s\n' "$line" | cut -d'|' -f1)" = "$id" ]; then
      printf '%s\n' "$line" | cut -d'|' -f"$pos"
      return 0
    fi
  done <<EOF
$_REGISTRY
EOF
  return 1
}

registry_get_path() {
  registry_get_field "$1" 6
}

registry_get_dependencies() {
  registry_get_field "$1" 9
}

registry_get_all_ids() {
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s\n' "$line" | cut -d'|' -f1
  done <<EOF
$_REGISTRY
EOF
}

registry_get_by_category() {
  local category="$1" line id current_category
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(printf '%s\n' "$line" | cut -d'|' -f1)"
    current_category="$(printf '%s\n' "$line" | cut -d'|' -f7)"
    [ "$current_category" = "$category" ] && printf '%s\n' "$id"
  done <<EOF
$_REGISTRY
EOF
}

registry_count() {
  printf '%s\n' "$_REGISTRY_COUNT"
}

registry_reset() {
  _REGISTRY=""
  _REGISTRY_COUNT=0
}

registry_print() {
  local line id category version criticality
  printf "\n  %-30s %-12s %-10s %-10s\n" "MÓDULO" "CATEGORÍA" "VERSIÓN" "CRITICIDAD"
  printf "  %-30s %-12s %-10s %-10s\n" "------------------------------" "------------" "----------" "----------"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(printf '%s\n' "$line" | cut -d'|' -f1)"
    category="$(printf '%s\n' "$line" | cut -d'|' -f7)"
    version="$(printf '%s\n' "$line" | cut -d'|' -f10)"
    criticality="$(printf '%s\n' "$line" | cut -d'|' -f13)"
    printf "  %-30s %-12s %-10s %-10s\n" "$id" "$category" "$version" "$criticality"
  done <<EOF
$_REGISTRY
EOF

  printf "\n"
}
