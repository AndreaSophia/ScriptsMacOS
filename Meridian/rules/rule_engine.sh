#!/bin/bash
# =============================================================================
# Meridian — rules/rule_engine.sh
# Responsabilidad: evaluar reglas cargadas contra un DiagnosticResult y
# enriquecer el resultado si alguna regla aplica.
#
# El engine NUNCA cambia STATUS ni TITLE — esos los define el módulo.
# El engine puede sobrescribir: SEVERITY, EXPLANATION, RISK,
# SUGGESTED_ACTION, REPAIRABLE, REPAIR_RISK y establece RULE_TRIGGERED.
# =============================================================================

# =============================================================================
# _rule_evaluate_condition <operator> <actual_value> <expected_value>
# Evalúa si la condición se cumple.
# Retorna 0 si se cumple, 1 si no.
# =============================================================================
_rule_evaluate_condition() {
  local operator="$1"
  local actual="$2"
  local expected="$3"

  case "$operator" in
    equals)
      [ "$actual" = "$expected" ] && return 0
      ;;
    not_equals)
      [ "$actual" != "$expected" ] && return 0
      ;;
    contains)
      echo "$actual" | grep -qi "$expected" && return 0
      ;;
    not_contains)
      ! echo "$actual" | grep -qi "$expected" && return 0
      ;;
    starts_with)
      case "$actual" in "$expected"*) return 0 ;; esac
      ;;
    matches)
      echo "$actual" | grep -qE "$expected" && return 0
      ;;
    less_than)
      [ "$actual" -lt "$expected" ] 2>/dev/null && return 0
      ;;
    greater_than)
      [ "$actual" -gt "$expected" ] 2>/dev/null && return 0
      ;;
    is_empty)
      [ -z "$actual" ] && return 0
      ;;
    is_not_empty)
      [ -n "$actual" ] && return 0
      ;;
  esac

  return 1
}

# =============================================================================
# _result_get_field <field_name>
# Extrae un campo del DiagnosticResult actual (variables RESULT_*)
# Mapea nombres de campo del contrato a variables de bash
# =============================================================================
_result_get_field() {
  local field="$1"
  case "$field" in
    status)           echo "$RESULT_STATUS" ;;
    severity)         echo "$RESULT_SEVERITY" ;;
    title)            echo "$RESULT_TITLE" ;;
    description)      echo "$RESULT_DESCRIPTION" ;;
    repairable)       echo "$RESULT_REPAIRABLE" ;;
    exit_code)        echo "$RESULT_EXIT_CODE" ;;
    raw_output)       echo "$RESULT_RAW_OUTPUT" ;;
    execution_time_ms) echo "$RESULT_EXECUTION_TIME_MS" ;;
    *)                echo "" ;;
  esac
}

# =============================================================================
# rule_engine_evaluate <module_id>
# Evalúa todas las reglas aplicables al módulo actual.
# Las variables RESULT_* deben estar cargadas antes de llamar esta función.
# Si una regla aplica, enriquece RESULT_* con los valores de la regla.
# =============================================================================
rule_engine_evaluate() {
  local module_id="$1"
  local rules_applied=0

  local rule
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue

    # Deserializar regla
    # Formato: rule_id|||module|||field|||operator|||value|||severity|||explanation|||risk|||suggested_action|||repairable|||repair_risk
    local rule_id module_id_rule field operator expected_value
    local r_severity r_explanation r_risk r_suggested_action r_repairable r_repair_risk

    rule_id="$(           echo "$rule" | sed 's/|||//g' | awk -F'' '{print $1}')"
    module_id_rule="$(    echo "$rule" | sed 's/|||//g' | awk -F'' '{print $2}')"
    field="$(             echo "$rule" | sed 's/|||//g' | awk -F'' '{print $3}')"
    operator="$(          echo "$rule" | sed 's/|||//g' | awk -F'' '{print $4}')"
    expected_value="$(    echo "$rule" | sed 's/|||//g' | awk -F'' '{print $5}')"
    r_severity="$(        echo "$rule" | sed 's/|||//g' | awk -F'' '{print $6}')"
    r_explanation="$(     echo "$rule" | sed 's/|||//g' | awk -F'' '{print $7}')"
    r_risk="$(            echo "$rule" | sed 's/|||//g' | awk -F'' '{print $8}')"
    r_suggested_action="$(echo "$rule" | sed 's/|||//g' | awk -F'' '{print $9}')"
    r_repairable="$(      echo "$rule" | sed 's/|||//g' | awk -F'' '{print $10}')"
    r_repair_risk="$(     echo "$rule" | sed 's/|||//g' | awk -F'' '{print $11}')"

    # Obtener valor actual del campo correspondiente
    local actual_value
    actual_value="$(_result_get_field "$field")"

    # Evaluar condición
    if _rule_evaluate_condition "$operator" "$actual_value" "$expected_value"; then
      log_debug "rule_engine" \
        "Regla '${rule_id}' activada para módulo '${module_id}'"

      # Enriquecer el resultado — el módulo definió STATUS y TITLE,
      # la regla aporta el contexto de severidad y acción
      [ -n "$r_severity" ]         && RESULT_SEVERITY="$r_severity"
      [ -n "$r_explanation" ]      && RESULT_EXPLANATION="$r_explanation"
      [ -n "$r_risk" ]             && RESULT_RISK="$r_risk"
      [ -n "$r_suggested_action" ] && RESULT_SUGGESTED_ACTION="$r_suggested_action"
      [ -n "$r_repairable" ]       && RESULT_REPAIRABLE="$r_repairable"
      [ -n "$r_repair_risk" ]      && RESULT_REPAIR_RISK="$r_repair_risk"
      RESULT_RULE_TRIGGERED="$rule_id"

      rules_applied=$((rules_applied + 1))

      # Solo la primera regla que aplica enriquece (prioridad por orden de carga)
      break
    fi

  done < <(rule_loader_get_for_module "$module_id")

  log_debug "rule_engine" \
    "Módulo '${module_id}': ${rules_applied} regla(s) aplicada(s)"

  return 0
}
