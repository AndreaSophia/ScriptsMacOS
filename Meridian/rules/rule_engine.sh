#!/bin/bash
# Meridian — rules/rule_engine.sh
_rule_evaluate_condition() {
  local operator="$1" actual="$2" expected="$3"
  case "$operator" in
    equals) [ "$actual" = "$expected" ] && return 0 ;;
    not_equals) [ "$actual" != "$expected" ] && return 0 ;;
    contains) printf '%s\n' "$actual" | grep -qi -- "$expected" && return 0 ;;
    not_contains) ! printf '%s\n' "$actual" | grep -qi -- "$expected" && return 0 ;;
    starts_with) case "$actual" in "$expected"*) return 0;; esac ;;
    matches) printf '%s\n' "$actual" | grep -qE -- "$expected" && return 0 ;;
    less_than) [ "$actual" -lt "$expected" ] 2>/dev/null && return 0 ;;
    greater_than) [ "$actual" -gt "$expected" ] 2>/dev/null && return 0 ;;
    is_empty) [ -z "$actual" ] && return 0 ;;
    is_not_empty) [ -n "$actual" ] && return 0 ;;
  esac
  return 1
}

_result_get_field() {
  case "$1" in
    status) printf '%s\n' "$RESULT_STATUS";; severity) printf '%s\n' "$RESULT_SEVERITY";;
    title) printf '%s\n' "$RESULT_TITLE";; description) printf '%s\n' "$RESULT_DESCRIPTION";;
    repairable) printf '%s\n' "$RESULT_REPAIRABLE";; exit_code) printf '%s\n' "$RESULT_EXIT_CODE";;
    raw_output) printf '%s\n' "$RESULT_RAW_OUTPUT";; execution_time_ms) printf '%s\n' "$RESULT_EXECUTION_TIME_MS";;
    *) printf '\n';;
  esac
}

_rule_field() { printf '%s\n' "$1" | cut -d'|' -f"$2"; }

rule_engine_evaluate() {
  local module_id="$1" rules_applied=0 rule
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    local rule_id field operator expected_value r_severity r_explanation r_risk r_suggested_action r_repairable r_repair_risk actual_value
    # ||| produce dos campos vacíos entre valores al usar cut con |.
    rule_id="$(_rule_field "$rule" 1)"
    field="$(_rule_field "$rule" 7)"
    operator="$(_rule_field "$rule" 10)"
    expected_value="$(_rule_field "$rule" 13)"
    r_severity="$(_rule_field "$rule" 16)"
    r_explanation="$(_rule_field "$rule" 19)"
    r_risk="$(_rule_field "$rule" 22)"
    r_suggested_action="$(_rule_field "$rule" 25)"
    r_repairable="$(_rule_field "$rule" 28)"
    r_repair_risk="$(_rule_field "$rule" 31)"
    actual_value="$(_result_get_field "$field")"
    if _rule_evaluate_condition "$operator" "$actual_value" "$expected_value"; then
      [ -n "$r_severity" ] && RESULT_SEVERITY="$r_severity"
      [ -n "$r_explanation" ] && RESULT_EXPLANATION="$r_explanation"
      [ -n "$r_risk" ] && RESULT_RISK="$r_risk"
      [ -n "$r_suggested_action" ] && RESULT_SUGGESTED_ACTION="$r_suggested_action"
      [ -n "$r_repairable" ] && RESULT_REPAIRABLE="$r_repairable"
      [ -n "$r_repair_risk" ] && RESULT_REPAIR_RISK="$r_repair_risk"
      RESULT_RULE_TRIGGERED="$rule_id"
      rules_applied=$((rules_applied + 1))
      break
    fi
  done < <(rule_loader_get_for_module "$module_id")
  log_debug "rule_engine" "Módulo '${module_id}': ${rules_applied} regla(s) aplicada(s)"
  return 0
}
