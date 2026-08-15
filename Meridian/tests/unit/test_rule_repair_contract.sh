#!/bin/bash
# Meridian — tests/unit/test_rule_repair_contract.sh
# Verifica que una regla que habilita reparación produzca un DiagnosticResult
# completo y que configuraciones ambiguas sean rechazadas en carga.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log_debug() { :; }
log_info()  { :; }
log_ok()    { :; }
log_warn()  { :; }
log_error() { :; }

source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/rules/rule_loader.sh"
source "${MERIDIAN_ROOT}/rules/rule_engine.sh"

_pass=0
_fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  ✓ %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '  ✗ %s expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_rule_repair.XXXXXX")" || exit 1
trap 'rm -rf "$tmp_dir"' EXIT
rules_file="${tmp_dir}/repair.rules.yaml"

cat > "$rules_file" <<'YAML'
rule_id: enable_safe_repair
condition_module: demo
condition_field: status
condition_operator: equals
condition_value: FAIL
result_severity: HIGH
result_explanation: "Repair candidate"
result_risk: "Demo risk"
result_suggested_action: "Run controlled repair"
result_repairable: true
result_repair_risk: MEDIUM
result_repair_id: reset_demo_state
---
YAML

rule_loader_load "$tmp_dir" 2>/dev/null
assert_eq "repairable rule accepted with canonical repair_id" "1" "$(rule_loader_count)"

result_init
RESULT_MODULE_ID="demo"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="LOW"
RESULT_TITLE="Demo failed"
RESULT_DESCRIPTION="Demo state"
RESULT_EXPLANATION="N/A"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_REPAIR_ID=""

rule_engine_evaluate demo 2>/dev/null
assert_eq "rule promotes repairable" "true" "$RESULT_REPAIRABLE"
assert_eq "rule propagates repair risk" "MEDIUM" "$RESULT_REPAIR_RISK"
assert_eq "rule propagates canonical repair_id" "reset_demo_state" "$RESULT_REPAIR_ID"
if result_validate 2>/dev/null; then
  _pass=$((_pass + 1))
  printf '  ✓ enriched result remains contract-valid\n'
else
  _fail=$((_fail + 1))
  printf '  ✗ enriched result became contract-invalid\n' >&2
fi

cat > "$rules_file" <<'YAML'
rule_id: missing_repair_id
condition_module: demo
condition_field: status
condition_operator: equals
condition_value: FAIL
result_severity: HIGH
result_repairable: true
result_repair_risk: MEDIUM
---
YAML
rule_loader_load "$tmp_dir" 2>/dev/null
assert_eq "repairable rule without repair_id rejected" "0" "$(rule_loader_count)"

cat > "$rules_file" <<'YAML'
rule_id: stale_repair_id
condition_module: demo
condition_field: status
condition_operator: equals
condition_value: FAIL
result_severity: HIGH
result_repairable: false
result_repair_risk: NONE
result_repair_id: should_not_exist
---
YAML
rule_loader_load "$tmp_dir" 2>/dev/null
assert_eq "non-repairable rule with repair_id rejected" "0" "$(rule_loader_count)"

printf '\nPassed: %s | Failed: %s\n' "$_pass" "$_fail"
exit "$_fail"
