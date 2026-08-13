#!/bin/bash
# Meridian — rules/rule_loader.sh
_RULES_STORE=""
_RULES_COUNT=0

_rule_parse_block() {
  local block="$1"
  _yaml_val() {
    printf '%s\n' "$block" | grep "^$1:" | sed "s/^$1:[[:space:]]*//" | \
      sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//" | head -1
  }
  local rule_id condition_module condition_field condition_operator condition_value
  local result_severity result_explanation result_risk result_suggested_action result_repairable result_repair_risk
  rule_id="$(_yaml_val rule_id)"; condition_module="$(_yaml_val condition_module)"
  condition_field="$(_yaml_val condition_field)"; condition_operator="$(_yaml_val condition_operator)"
  condition_value="$(_yaml_val condition_value)"; result_severity="$(_yaml_val result_severity)"
  result_explanation="$(_yaml_val result_explanation)"; result_risk="$(_yaml_val result_risk)"
  result_suggested_action="$(_yaml_val result_suggested_action)"; result_repairable="$(_yaml_val result_repairable)"
  result_repair_risk="$(_yaml_val result_repair_risk)"
  [ -n "$rule_id" ] && [ -n "$condition_module" ] && [ -n "$condition_field" ] && \
    [ -n "$condition_operator" ] && [ -n "$condition_value" ] && [ -n "$result_severity" ] || return 1
  result_repairable="${result_repairable:-false}"; result_repair_risk="${result_repair_risk:-NONE}"
  printf '%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s\n' \
    "$rule_id" "$condition_module" "$condition_field" "$condition_operator" "$condition_value" \
    "$result_severity" "$result_explanation" "$result_risk" "$result_suggested_action" \
    "$result_repairable" "$result_repair_risk"
}

_rule_store_add() {
  local serialized="$1"
  [ -n "$_RULES_STORE" ] && _RULES_STORE="${_RULES_STORE}"$'\n'"${serialized}" || _RULES_STORE="$serialized"
  _RULES_COUNT=$((_RULES_COUNT + 1))
}

rule_loader_load() {
  local rules_dir="$1" file loaded=0 rejected=0 block line serialized
  [ -d "$rules_dir" ] || { log_warn "rule_loader" "Directorio de reglas no encontrado: $rules_dir"; return 0; }
  _RULES_STORE=""; _RULES_COUNT=0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    block=""
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "---" ]; then
        if [ -n "$block" ]; then
          serialized="$(_rule_parse_block "$block")"
          if [ -n "$serialized" ]; then _rule_store_add "$serialized"; loaded=$((loaded+1));
          else rejected=$((rejected+1)); log_warn "rule_loader" "Bloque de regla inválido ignorado en $(basename "$file")"; fi
          block=""
        fi
      else
        printf '%s\n' "$line" | grep -qE '^[[:space:]]*(#|$)' && continue
        [ -n "$block" ] && block="${block}"$'\n'"${line}" || block="$line"
      fi
    done < "$file"
    if [ -n "$block" ]; then
      serialized="$(_rule_parse_block "$block")"
      if [ -n "$serialized" ]; then _rule_store_add "$serialized"; loaded=$((loaded+1));
      else rejected=$((rejected+1)); fi
    fi
  done < <(find "$rules_dir" -name '*.rules.yaml' -type f 2>/dev/null | sort)
  log_info "rule_loader" "Reglas cargadas: ${loaded} válidas, ${rejected} rechazadas"
}

rule_loader_get_for_module() {
  local module_id="$1" line module
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    module="$(printf '%s\n' "$line" | cut -d'|' -f4)"
    [ "$module" = "$module_id" ] && printf '%s\n' "$line"
  done <<EOF
$_RULES_STORE
EOF
}
rule_loader_count() { printf '%s\n' "$_RULES_COUNT"; }
