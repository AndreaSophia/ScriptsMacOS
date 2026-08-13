#!/bin/bash
# =============================================================================
# Meridian — core/module_registry.sh
# Responsabilidad: registro en memoria de módulos cargados y disponibles.
# Es la única fuente de verdad sobre qué módulos están listos para ejecutarse.
#
# Los módulos se almacenan como líneas en _REGISTRY (variable global).
# Formato de cada entrada: id|||name|||category|||version|||criticality|||path|||requires_root|||timeout
# =============================================================================

_REGISTRY=""
_REGISTRY_COUNT=0

# =============================================================================
# registry_add <id> <name> <category> <version> <criticality> <path> <requires_root> <timeout>
# Registra un módulo en el registry
# =============================================================================
registry_add() {
  local id="$1"
  local name="$2"
  local category="$3"
  local version="$4"
  local criticality="$5"
  local path="$6"
  local requires_root="$7"
  local timeout="$8"

  # Verificar que no existe un duplicado
  if registry_exists "$id"; then
    log_warn "registry" "Módulo duplicado ignorado: $id"
    return 1
  fi

  local entry="${id}|||${name}|||${category}|||${version}|||${criticality}|||${path}|||${requires_root}|||${timeout}"
  _REGISTRY="${_REGISTRY}${entry}\n"
  _REGISTRY_COUNT=$(( _REGISTRY_COUNT + 1 ))

  log_debug "registry" "Registrado: ${id} (${category}) v${version}"
  return 0
}

# =============================================================================
# registry_exists <id> — Retorna 0 si el módulo está registrado
# =============================================================================
registry_exists() {
  local id="$1"
  printf "%b" "$_REGISTRY" | grep -q "^${id}|||"
}

# =============================================================================
# registry_get_field <id> <field_number> — Extrae un campo de una entrada
# Campos: 1=id 2=name 3=category 4=version 5=criticality 6=path 7=requires_root 8=timeout
# =============================================================================
registry_get_field() {
  local id="$1"
  local field="$2"
  # El separador ||| se implementa como tres pipes consecutivos.
  # awk -F no soporta ||| como literal — usamos sed para reemplazarlo
  # por un separador no usado (SOH, ASCII 001) antes del split.
  printf "%b" "$_REGISTRY" | grep "^${id}|||" | \
    sed 's/|||/\x01/g' | awk -F'\x01' "{print \$${field}}" | head -1
}

# =============================================================================
# registry_get_path <id> — Atajo para obtener la ruta del módulo
# =============================================================================
registry_get_path() {
  registry_get_field "$1" 6
}

# =============================================================================
# registry_get_all_ids — Lista todos los IDs registrados, uno por línea
# =============================================================================
registry_get_all_ids() {
  printf "%b" "$_REGISTRY" | grep -v '^$' | \
    sed 's/|||/\x01/g' | awk -F'\x01' '{print $1}'
}

# =============================================================================
# registry_get_by_category <category> — Lista IDs de una categoría
# =============================================================================
registry_get_by_category() {
  local category="$1"
  printf "%b" "$_REGISTRY" | grep -v '^$' | \
    sed 's/|||/\x01/g' | awk -F'\x01' "\$3 == \"${category}\" {print \$1}"
}

# =============================================================================
# registry_count — Número de módulos registrados
# =============================================================================
registry_count() {
  echo "$_REGISTRY_COUNT"
}

# =============================================================================
# registry_print — Muestra el registry en formato tabular (para debug)
# =============================================================================
registry_print() {
  printf "\n  %-30s %-12s %-10s %-10s\n" "MÓDULO" "CATEGORÍA" "VERSIÓN" "CRITICIDAD"
  printf "  %-30s %-12s %-10s %-10s\n" "$(printf '%0.s─' {1..30})" \
    "$(printf '%0.s─' {1..12})" "$(printf '%0.s─' {1..10})" "$(printf '%0.s─' {1..10})"
  printf "%b" "$_REGISTRY" | grep -v '^$' | \
    awk -F'|||' '{printf "  %-30s %-12s %-10s %-10s\n", $1, $3, $4, $5}'
  printf "\n"
}
