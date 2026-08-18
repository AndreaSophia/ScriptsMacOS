#!/bin/bash
# Meridian — rules/rule_loader.sh
# Carga reglas YAML planas y las almacena en un formato interno reversible,
# compatible con Bash 3.2/macOS y seguro ante pipes/saltos de línea.

_RULES_STORE=""
_RULES_COUNT=0

_rule_encode() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  s="${s//|/%7C}"
  printf '%s' "$s"
}

_rule_decode() {
  local s="$1"
  s="${s//%7C/|}"
  s="${s//%0A/$'\n'}"
  s="${s//%0D/$'\r'}"
  s="${s//%25/%}"
  printf '%s' "$s"
}

_rule_field() {
  local line="$1" field="$2" raw
  raw="$(printf '%s\n' "$line" | cut -d'|' -f"$field")"
  _rule_decode "$raw"
}

_rule_in_set() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [ "$needle" = "$item" ] && return 0
  done
  return 1
}

_rule_validate_schema() {
  local rule_id="$1" module="$2" field="$3" operator="$4" value="$5"
  local severity="$6" repairable="$7" repair_risk="$8" repair_id="$9"

  printf '%s\n' "$rule_id" | grep -qE '^[a-z][a-z0-9_]*$' || return 1
  printf '%s\n' "$module" | grep -qE '^[a-z][a-z0-9_]*$' || return 1

  _rule_in_set "$field" \
    status severity title description explanation risk suggested_action \
    repairable repair_risk repair_id exit_code raw_output execution_time_ms evidence || return 1

  _rule_in_set "$operator" \
    equals not_equals contains not_contains starts_with matches \
    less_than greater_than is_empty is_not_empty || return 1

  case "$operator" in
    is_empty|is_not_empty) ;;
    *) [ -n "$value" ] || return 1 ;;
  esac

  _rule_in_set "$severity" INFO LOW MEDIUM HIGH CRITICAL || return 1
  _rule_in_set "$repairable" true false || return 1
  _rule_in_set "$repair_risk" NONE LOW MEDIUM HIGH CRITICAL || return 1

  # Una regla que habilita reparación debe entregar el identificador canónico
  # de la acción. Sin repair_id produciría un DiagnosticResult contradictorio:
  # repairable=true pero ninguna reparación concreta que el Repair Engine pueda
  # vincular al resultado canónico.
  if [ "$repairable" = "true" ]; then
    [ "$repair_risk" != "NONE" ] || return 1
    printf '%s\n' "$repair_id" | grep -qE '^[a-z][a-z0-9_]*$' || return 1
  else
    [ "$repair_risk" = "NONE" ] || return 1
    [ -z "$repair_id" ] || return 1
  fi

  return 0
}

_rule_parse_block() {
  local block="$1"

  _yaml_val() {
    printf '%s\n' "$block" | grep "^$1:" | sed "s/^$1:[[:space:]]*//" | \
      sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//" | head -1
  }

  local rule_id condition_module condition_field condition_operator condition_value
  local result_severity result_explanation result_risk result_suggested_action
  local result_repairable result_repair_risk result_repair_id

  rule_id="$(_yaml_val rule_id)"
  condition_module="$(_yaml_val condition_module)"
  condition_field="$(_yaml_val condition_field)"
  condition_operator="$(_yaml_val condition_operator)"
  condition_value="$(_yaml_val condition_value)"
  result_severity="$(_yaml_val result_severity)"
  result_explanation="$(_yaml_val result_explanation)"
  result_risk="$(_yaml_val result_risk)"
  result_suggested_action="$(_yaml_val result_suggested_action)"
  result_repairable="$(_yaml_val result_repairable)"
  result_repair_risk="$(_yaml_val result_repair_risk)"
  result_repair_id="$(_yaml_val result_repair_id)"

  [ -n "$rule_id" ] && [ -n "$condition_module" ] && \
    [ -n "$condition_field" ] && [ -n "$condition_operator" ] && \
    [ -n "$result_severity" ] || return 1

  result_repairable="${result_repairable:-false}"
  result_repair_risk="${result_repair_risk:-NONE}"

  _rule_validate_schema \
    "$rule_id" "$condition_module" "$condition_field" "$condition_operator" \
    "$condition_value" "$result_severity" "$result_repairable" "$result_repair_risk" \
    "$result_repair_id" || return 1

  # Formato interno: 12 campos separados por un solo |.
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$(_rule_encode "$rule_id")" \
    "$(_rule_encode "$condition_module")" \
    "$(_rule_encode "$condition_field")" \
    "$(_rule_encode "$condition_operator")" \
    "$(_rule_encode "$condition_value")" \
    "$(_rule_encode "$result_severity")" \
    "$(_rule_encode "$result_explanation")" \
    "$(_rule_encode "$result_risk")" \
    "$(_rule_encode "$result_suggested_action")" \
    "$(_rule_encode "$result_repairable")" \
    "$(_rule_encode "$result_repair_risk")" \
    "$(_rule_encode "$result_repair_id")"
}

_rule_store_add() {
  local serialized="$1"
  if [ -n "$_RULES_STORE" ]; then
    _RULES_STORE="${_RULES_STORE}"$'\n'"${serialized}"
  else
    _RULES_STORE="$serialized"
  fi
  _RULES_COUNT=$((_RULES_COUNT + 1))
}

rule_loader_load() {
  local rules_dir="$1" file loaded=0 rejected=0 block line serialized

  if [ ! -d "$rules_dir" ]; then
    log_warn "rule_loader" "Directorio de reglas no encontrado: $rules_dir"
    return 0
  fi

  _RULES_STORE=""
  _RULES_COUNT=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    block=""

    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "---" ]; then
        if [ -n "$block" ]; then
          serialized="$(_rule_parse_block "$block")"
          if [ -n "$serialized" ]; then
            _rule_store_add "$serialized"
            loaded=$((loaded + 1))
          else
            rejected=$((rejected + 1))
            log_warn "rule_loader" "Bloque de regla inválido ignorado en $(basename "$file")"
          fi
          block=""
        fi
      else
        printf '%s\n' "$line" | grep -qE '^[[:space:]]*(#|$)' && continue
        if [ -n "$block" ]; then
          block="${block}"$'\n'"${line}"
        else
          block="$line"
        fi
      fi
    done < "$file"

    if [ -n "$block" ]; then
      serialized="$(_rule_parse_block "$block")"
      if [ -n "$serialized" ]; then
        _rule_store_add "$serialized"
        loaded=$((loaded + 1))
      else
        rejected=$((rejected + 1))
        log_warn "rule_loader" "Bloque de regla inválido ignorado en $(basename "$file")"
      fi
    fi
  done < <(find "$rules_dir" -name '*.rules.yaml' -type f 2>/dev/null | sort)

  log_info "rule_loader" "Reglas cargadas: ${loaded} válidas, ${rejected} rechazadas"
  return 0
}

rule_loader_get_for_module() {
  local module_id="$1" line module
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    module="$(_rule_field "$line" 2)"
    [ "$module" = "$module_id" ] && printf '%s\n' "$line"
  done <<EOF
$_RULES_STORE
EOF
}

rule_loader_count() {
  printf '%s\n' "$_RULES_COUNT"
}
