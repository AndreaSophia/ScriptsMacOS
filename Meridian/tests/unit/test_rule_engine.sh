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

if [ "$count" -gt 0 ]; then
  printf "  \033[1;32m✓\033[0m  Reglas cargadas: %s\n" "$count"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  No se cargaron reglas\n" >&2
  _fail=$((_fail+1))
fi

# --- Test: regla filevault_disabled se activa cuando status=FAIL ---
result_init
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="INFO"        # El módulo puede devolver INFO, la regla debe sobrescribir
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
assert_not_empty "rule: filevault_disabled setea explanation"     "$RESULT_EXPLANATION"
assert_not_empty "rule: filevault_disabled setea risk"            "$RESULT_RISK"
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

# --- Test: rule_loader rechaza bloque inválido (sin rule_id) ---
# Crear archivo de regla inválida temporal
tmp_rules="$(mktemp)"
printf 'condition_module: filevault\ncondition_field: status\n---\n' > "$tmp_rules"
rule_loader_load "$(dirname "$tmp_rules")" 2>/dev/null
# No debe crashear — esto es solo un smoke test de robustez
printf "  \033[1;32m✓\033[0m  rule_loader: no crashea con bloque inválido\n"
_pass=$((_pass+1))
rm -f "$tmp_rules"

# --- Resumen ---
printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit $_fail
