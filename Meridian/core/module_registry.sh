#!/bin/bash
# =============================================================================
# Meridian — core/module_registry.sh
# Registro en memoria de módulos cargados.
# Compatible con Bash 3.2/macOS; el framing se interpreta con builtins del shell
# para no depender de utilidades resueltas mediante PATH en el core.
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

# Extrae un campo lógico (1..9) de una línea del registry usando únicamente
# parameter expansion de Bash 3.2. El core puede correr privilegiado y no debe
# resolver `cut` (ni ninguna otra utilidad de parsing) desde un PATH heredado.
_registry_field_from_line() {
  local line="$1" target="$2" current=1 value

  case "$target" in
    1|2|3|4|5|6|7|8|9) ;;
    *) return 1 ;;
  esac

  value="$line"
  while [ "$current" -lt "$target" ]; do
    case "$value" in
      *'|||'*) value="${value#*|||}" ;;
      *) return 1 ;;
    esac
    current=$((current + 1))
  done

  if [ "$target" -lt 9 ]; then
    case "$value" in
      *'|||'*) printf '%s\n' "${value%%|||*}" ;;
      *) return 1 ;;
    esac
  else
    # El noveno campo es el resto de la línea y puede estar vacío.
    case "$value" in
      *'|||'*) return 1 ;;
      *) printf '%s\n' "$value" ;;
    esac
  fi
}

registry_exists() {
  local id="$1" line current_id
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    current_id="$(_registry_field_from_line "$line" 1)" || return 1
    [ "$current_id" = "$id" ] && return 0
  done <<EOF
$_REGISTRY
EOF
  return 1
}

registry_get_field() {
  local id="$1" field="$2" line current_id

  case "$field" in
    1|2|3|4|5|6|7|8|9) ;;
    *) return 1 ;;
  esac

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    current_id="$(_registry_field_from_line "$line" 1)" || return 1
    if [ "$current_id" = "$id" ]; then
      _registry_field_from_line "$line" "$field"
      return $?
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
  local line id
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_registry_field_from_line "$line" 1)" || return 1
    printf '%s\n' "$id"
  done <<EOF
$_REGISTRY
EOF
}

registry_get_by_category() {
  local category="$1" line id current_category
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_registry_field_from_line "$line" 1)" || return 1
    current_category="$(_registry_field_from_line "$line" 3)" || return 1
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
    id="$(_registry_field_from_line "$line" 1)" || return 1
    category="$(_registry_field_from_line "$line" 3)" || return 1
    version="$(_registry_field_from_line "$line" 4)" || return 1
    criticality="$(_registry_field_from_line "$line" 5)" || return 1
    printf "  %-30s %-12s %-10s %-10s\n" "$id" "$category" "$version" "$criticality"
  done <<EOF
$_REGISTRY
EOF

  printf "\n"
}
