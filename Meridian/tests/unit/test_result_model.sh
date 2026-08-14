#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_result_model.sh
# Tests unitarios para core/result_model.sh
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/core/result_model.sh"
MERIDIAN_LOG_FILE="/dev/null"
log_debug() { :; }
log_warn()  { echo "[WARN] $2" >&2; }
log_error() { echo "[ERROR] $2" >&2; }

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     '%s' no encontrado en output\n" \
      "$desc" "$needle" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_result_model.sh\033[0m\n\n"

result_init
assert_eq "result_init: STATUS=ERROR por defecto" "ERROR" "$RESULT_STATUS"
assert_eq "result_init: REPAIRABLE=false por defecto" "false" "$RESULT_REPAIRABLE"
assert_eq "result_init: EXIT_CODE=0 por defecto" "0" "$RESULT_EXIT_CODE"
assert_eq "result_init: EXECUTION_TIME_MS=0" "0" "$RESULT_EXECUTION_TIME_MS"

result_init
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="PASS"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Test OK"
RESULT_DESCRIPTION="desc"
RESULT_EXPLANATION="expl"
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="N/A"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="100"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=""

result_validate 2>/dev/null
assert_eq "result_validate: resultado válido retorna 0" "0" "$?"

RESULT_STATUS="INVALID"
result_validate 2>/dev/null
assert_eq "result_validate: STATUS inválido retorna error" "1" "$?"
RESULT_STATUS="PASS"

RESULT_SEVERITY="EXTREME"
result_validate 2>/dev/null
assert_eq "result_validate: SEVERITY inválida retorna error" "1" "$?"
RESULT_SEVERITY="INFO"

# Invariante del contrato: PASS solo admite INFO o LOW. Un PASS con severidad
# operativa elevada debe rechazarse para evitar estados verdes contradictorios.
RESULT_STATUS="PASS"
RESULT_SEVERITY="HIGH"
result_validate 2>/dev/null
assert_eq "result_validate: PASS/HIGH viola contrato" "1" "$?"
RESULT_SEVERITY="LOW"
result_validate 2>/dev/null
assert_eq "result_validate: PASS/LOW es válido" "0" "$?"
RESULT_SEVERITY="INFO"

RESULT_REPAIRABLE="true"
RESULT_REPAIR_ID=""
result_validate 2>/dev/null
assert_eq "result_validate: repairable=true sin repair_id falla" "1" "$?"
RESULT_REPAIRABLE="false"

# Serialización básica.
result_init
RESULT_MODULE_ID="test_module"
RESULT_MODULE_VERSION="2.0.0"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="HIGH"
RESULT_TITLE="Test serialization"
RESULT_DESCRIPTION="desc test"
RESULT_EXPLANATION="expl test"
RESULT_RISK="risk test"
RESULT_SUGGESTED_ACTION="action test"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="250"
RESULT_EXIT_CODE="1"
RESULT_RAW_OUTPUT="raw output"

serialized="$(result_serialize)"
assert_contains "result_serialize: contiene module_id" "test_module" "$serialized"
assert_contains "result_serialize: contiene status" "FAIL" "$serialized"
assert_contains "result_serialize: contiene severity" "HIGH" "$serialized"

result_init
result_deserialize "$serialized"
assert_eq "result_deserialize: MODULE_ID correcto" "test_module" "$RESULT_MODULE_ID"
assert_eq "result_deserialize: STATUS correcto" "FAIL" "$RESULT_STATUS"
assert_eq "result_deserialize: SEVERITY correcto" "HIGH" "$RESULT_SEVERITY"
assert_eq "result_deserialize: EXEC_TIME correcto" "250" "$RESULT_EXECUTION_TIME_MS"

# Payload arbitrario: protege el protocolo v2 frente a pipes, %, CR/LF y texto
# parecido a escapes internos. Esto cubre especialmente RAW_OUTPUT/EVIDENCE.
result_init
RESULT_MODULE_ID="payload_test"
RESULT_MODULE_VERSION="1.0.0"
RESULT_STATUS="WARN"
RESULT_SEVERITY="MEDIUM"
RESULT_TITLE="Título | con %"
RESULT_DESCRIPTION=$'línea 1\nlínea 2 | valor %7C literal'
RESULT_EXPLANATION="expl"
RESULT_RISK="risk"
RESULT_SUGGESTED_ACTION="action"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXECUTION_TIME_MS="42"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=$'uno|||dos\ntres%25\rfin'
RESULT_EVIDENCE="ruta|evidencia%20"

expected_title="$RESULT_TITLE"
expected_description="$RESULT_DESCRIPTION"
expected_raw="$RESULT_RAW_OUTPUT"
expected_evidence="$RESULT_EVIDENCE"
serialized="$(result_serialize)"
result_init
result_deserialize "$serialized"
assert_eq "roundtrip: title conserva pipes/%" "$expected_title" "$RESULT_TITLE"
assert_eq "roundtrip: description conserva multilinea" "$expected_description" "$RESULT_DESCRIPTION"
assert_eq "roundtrip: raw_output conserva delimitadores/CRLF" "$expected_raw" "$RESULT_RAW_OUTPUT"
assert_eq "roundtrip: evidence conserva caracteres especiales" "$expected_evidence" "$RESULT_EVIDENCE"

result_time_start
sleep 0
result_time_end
if printf '%s\n' "$RESULT_EXECUTION_TIME_MS" | grep -qE '^[0-9]+$'; then
  printf "  \033[1;32m✓\033[0m  result_time_end: EXECUTION_TIME_MS es numérico\n"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  result_time_end: EXECUTION_TIME_MS no es numérico\n" >&2
  _fail=$((_fail+1))
fi

printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit "$_fail"
