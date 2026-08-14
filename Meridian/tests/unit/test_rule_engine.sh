#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_rule_engine.sh
# Tests para rule_loader y rule_engine
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

MERIDIAN_LOG_FILE="/dev/null"
MERIDIAN_DEBUG=0
log_debug() { :; }
log_info()  { :; }
log_ok()    { :; }
log_warn()  { echo "[WARN] $2" >&2; }
log_error() { echo "[ERROR] $2" >&2; }

source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/rules/rule_loader.sh"
source "${MERIDIAN_ROOT}/rules/rule_engine.sh"

_pass=0; _fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" \
      "$desc" "$expected" "$actual" >&2
    _fail=$((_fail+1))
  fi
}

assert_not_empty() {
  local desc="$1" val="$2"
  if [ -n "$val" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s (valor vacío)\n" "$desc" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_rule_engine.sh\033[0m\n\n"

# --- Cargar reglas reales ---
rule_loader_load "${MERIDIAN_ROOT}/rules/definitions" 2>/dev/null
count="$(rule_loader_count)"

assert_eq "rule_loader: carga las 7 reglas MVP" "7" "$count"

# --- Test: regla filevault_disabled se activa cuando status=FAIL ---
result_init
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="INFO"
RESULT_TITLE="FileVault deshabilitado"
RESULT_DESCRIPTION="FileVault is Off."
RESULT_EXPLANATION="default"
RESULT_RISK="default"
RESULT_SUGGESTED_ACTION="default"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="100"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT="FileVault is Off."

rule_engine_evaluate "filevault" 2>/dev/null

assert_eq "rule: filevault_disabled activa severity=CRITICAL" "CRITICAL" "$RESULT_SEVERITY"
assert_not_empty "rule: filevault_disabled setea explanation"      "$RESULT_EXPLANATION"
assert_not_empty "rule: filevault_disabled setea risk"             "$RESULT_RISK"
assert_not_empty "rule: filevault_disabled setea suggested_action" "$RESULT_SUGGESTED_ACTION"
assert_eq "rule: filevault_disabled setea rule_triggered" \
  "filevault_disabled" "$RESULT_RULE_TRIGGERED"

# --- Test: regla NO se activa cuando status=PASS ---
result_init
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="FileVault habilitado"
RESULT_DESCRIPTION="FileVault is On."
RESULT_EXPLANATION="orig_explanation"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="50"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT="FileVault is On."

rule_engine_evaluate "filevault" 2>/dev/null

assert_eq "rule: filevault no se activa en PASS (severity sigue INFO)" "INFO" "$RESULT_SEVERITY"
assert_eq "rule: filevault no se activa en PASS (rule_triggered vacío)" "" "$RESULT_RULE_TRIGGERED"

# --- Test: operador equals con valor incorrecto no activa ---
result_init
RESULT_MODULE_ID="crowdstrike"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="CrowdStrike operativo"
RESULT_DESCRIPTION="Running"
RESULT_EXPLANATION="orig"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="300"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=""

rule_engine_evaluate "crowdstrike" 2>/dev/null

assert_eq "rule: crowdstrike_not_installed no activa en PASS" "" "$RESULT_RULE_TRIGGERED"

# --- Test: rule_loader rechaza realmente un bloque inválido ---
# El loader solo descubre *.rules.yaml, por lo que el fixture temporal debe
# respetar ese patrón; el test anterior usaba mktemp sin sufijo y no probaba nada.
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_rules.XXXXXX")"
tmp_rules="${tmp_dir}/invalid.rules.yaml"
printf 'condition_module: filevault\ncondition_field: status\ncondition_operator: equals\ncondition_value: FAIL\nresult_severity: HIGH\n---\n' > "$tmp_rules"
rule_loader_load "$tmp_dir" 2>/dev/null
assert_eq "rule_loader: bloque inválido no se incorpora" "0" "$(rule_loader_count)"
rm -rf "$tmp_dir"

# --- Re-cargar reglas reales para verificar que load() reemplaza estado previo ---
rule_loader_load "${MERIDIAN_ROOT}/rules/definitions" 2>/dev/null
assert_eq "rule_loader: recarga limpia las 7 reglas MVP" "7" "$(rule_loader_count)"

# --- Resumen ---
printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit $_fail
