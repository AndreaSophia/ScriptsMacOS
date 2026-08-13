#!/bin/bash
# =============================================================================
# Meridian — rules/rule_loader.sh
# Responsabilidad: descubrir y cargar archivos *.rules.yaml del directorio
# de definiciones. Las reglas se almacenan en memoria como texto estructurado.
#
# Formato de regla en YAML (flat, compatible con parser bash):
#   rule_id: filevault_disabled
#   condition_module: filevault
#   condition_field: status
#   condition_operator: equals
#   condition_value: FAIL
#   result_severity: CRITICAL
#   result_explanation: "..."
#   result_risk: "..."
#   result_suggested_action: "..."
#   result_repairable: true
#   result_repair_risk: LOW
# Cada bloque de regla está separado por una línea "---"
# =============================================================================

# Almacenamiento de reglas en memoria
_RULES_STORE=""
_RULES_COUNT=0

# =============================================================================
# _rule_parse_block <block_text>
# Parsea un bloque YAML de regla y lo serializa en formato interno
# Formato serializado: rule_id|||module|||field|||operator|||value|||severity|||explanation|||risk|||suggested_action|||repairable|||repair_risk
# =============================================================================
_rule_parse_block() {
  local block="$1"

  # Función helper: extraer valor de una clave en el bloque
  _yaml_val() {
    echo "$block" | grep "^$1:" | sed "s/^$1:[[:space:]]*//" | \
      sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//" | head -1
  }

  local rule_id condition_module condition_field condition_operator condition_value
  local result_severity result_explanation result_risk result_suggested_action
  local result_repairable result_repair_risk

  rule_id="$(_yaml_val "rule_id")"
  condition_module="$(_yaml_val "condition_module")"
  condition_field="$(_yaml_val "condition_field")"
  condition_operator="$(_yaml_val "condition_operator")"
  condition_value="$(_yaml_val "condition_value")"
  result_severity="$(_yaml_val "result_severity")"
  result_explanation="$(_yaml_val "result_explanation")"
  result_risk="$(_yaml_val "result_risk")"
  result_suggested_action="$(_yaml_val "result_suggested_action")"
  result_repairable="$(_yaml_val "result_repairable")"
  result_repair_risk="$(_yaml_val "result_repair_risk")"

  # Validar campos mínimos obligatorios
  if [ -z "$rule_id" ] || [ -z "$condition_module" ] || \
     [ -z "$condition_field" ] || [ -z "$condition_operator" ] || \
     [ -z "$condition_value" ] || [ -z "$result_severity" ]; then
    return 1
  fi

  # Defaults opcionales
  result_repairable="${result_repairable:-false}"
  result_repair_risk="${result_repair_risk:-NONE}"

  # Serializar
  printf '%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s\n' \
    "$rule_id" "$condition_module" "$condition_field" \
    "$condition_operator" "$condition_value" \
    "$result_severity" "$result_explanation" "$result_risk" \
    "$result_suggested_action" "$result_repairable" "$result_repair_risk"
}

# =============================================================================
# rule_loader_load <rules_dir>
# Carga todos los archivos *.rules.yaml del directorio dado.
# =============================================================================
rule_loader_load() {
  local rules_dir="$1"

  if [ ! -d "$rules_dir" ]; then
    log_warn "rule_loader" "Directorio de reglas no encontrado: $rules_dir"
    return 0  # No es fatal — puede correr sin reglas
  fi

  local file loaded=0 rejected=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    log_debug "rule_loader" "Cargando reglas: $(basename "$file")"

    # Dividir el archivo en bloques separados por "---"
    local block=""
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "---" ]; then
        if [ -n "$block" ]; then
          local serialized
          serialized="$(_rule_parse_block "$block")"
          if [ -n "$serialized" ]; then
            _RULES_STORE="${_RULES_STORE}${serialized}\n"
            _RULES_COUNT=$(( _RULES_COUNT + 1 ))
            loaded=$((loaded + 1))
            local rid
            rid="$(echo "$serialized" | cut -d'|' -f1)"
            log_debug "rule_loader" "Regla cargada: $rid"
          else
            rejected=$((rejected + 1))
            log_warn "rule_loader" "Bloque de regla inválido ignorado en $(basename "$file")"
          fi
          block=""
        fi
      else
        # Ignorar comentarios y líneas vacías dentro de bloques
        echo "$line" | grep -qE '^[[:space:]]*#' && continue
        echo "$line" | grep -qE '^[[:space:]]*$' && continue
        block="${block}${line}\n"
      fi
    done < "$file"

    # Procesar último bloque si no hay "---" al final
    if [ -n "$block" ]; then
      local serialized
      serialized="$(_rule_parse_block "$block")"
      if [ -n "$serialized" ]; then
        _RULES_STORE="${_RULES_STORE}${serialized}\n"
        _RULES_COUNT=$(( _RULES_COUNT + 1 ))
        loaded=$((loaded + 1))
      fi
    fi

  done < <(find "$rules_dir" -name "*.rules.yaml" -type f 2>/dev/null | sort)

  log_info "rule_loader" \
    "Reglas cargadas: ${loaded} válidas, ${rejected} rechazadas"
  return 0
}

# =============================================================================
# rule_loader_get_for_module <module_id>
# Retorna todas las reglas serializadas que aplican al módulo dado
# =============================================================================
rule_loader_get_for_module() {
  local module_id="$1"
  printf "%b" "$_RULES_STORE" | grep -v '^$' | \
    awk -F'|||' "\$2 == \"${module_id}\""
}

# =============================================================================
# rule_loader_count — Número de reglas cargadas
# =============================================================================
rule_loader_count() {
  echo "$_RULES_COUNT"
}
