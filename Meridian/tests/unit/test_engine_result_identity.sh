#!/bin/bash
# Regression coverage: a diagnostic module cannot publish canonical state under
# another module_id or module version. Written for Bash 3.2 compatibility.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MERIDIAN_EVIDENCE_DIR="${TMPDIR:-/tmp}/meridian_identity_evidence.$$"
mkdir -p "$MERIDIAN_EVIDENCE_DIR" || exit 1
trap 'rm -rf "$MERIDIAN_EVIDENCE_DIR"' EXIT

source "${MERIDIAN_ROOT}/core/result_model.sh"

log_error() { :; }
log_warn()  { :; }
log_info()  { :; }
log_debug() { :; }

registry_exists() { [ "$1" = "alpha" ]; }
registry_get_field() {
  case "$2" in
    2) printf '%s\n' "Alpha" ;;
    4) printf '%s\n' "1.2.3" ;;
    *) return 1 ;;
  esac
}

_AGG_CAPTURE=""
aggregator_add() {
  _AGG_CAPTURE="$(result_serialize)" || return 1
  return 0
}

_RULE_CALLED=0
rule_engine_evaluate() {
  _RULE_CALLED=$((_RULE_CALLED + 1))
  return 0
}

module_loader_run() {
  result_init
  RESULT_MODULE_ID="${FAKE_RESULT_ID:-alpha}"
  RESULT_MODULE_VERSION="${FAKE_RESULT_VERSION:-1.2.3}"
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Fixture result"
  RESULT_DESCRIPTION="Fixture description"
  RESULT_EXPLANATION="Fixture explanation"
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  result_serialize
}

source "${MERIDIAN_ROOT}/core/engine.sh"

_pass=0
_fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  ✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '  ✗  %s — expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

run_case() {
  _AGG_CAPTURE=""
  _RULE_CALLED=0
  _engine_run_module alpha >/dev/null 2>&1
  local rc=$?
  assert_eq "$1: engine retorna 0 y degrada a error canónico" "0" "$rc"
  if [ -n "$_AGG_CAPTURE" ] && result_deserialize "$_AGG_CAPTURE" >/dev/null 2>&1; then
    assert_eq "$1: resultado canónico pertenece al módulo solicitado" "alpha" "$RESULT_MODULE_ID"
    assert_eq "$1: versión canónica pertenece al registry" "1.2.3" "$RESULT_MODULE_VERSION"
    assert_eq "$1: identidad inconsistente produce ERROR" "ERROR" "$RESULT_STATUS"
  else
    printf '  ✗  %s — no se capturó DiagnosticResult interno válido\n' "$1" >&2
    _fail=$((_fail + 1))
  fi
  assert_eq "$1: reglas no se evalúan sobre identidad no confiable" "0" "$_RULE_CALLED"
}

printf '\ntest_engine_result_identity.sh\n\n'

FAKE_RESULT_ID="other_module"
FAKE_RESULT_VERSION="1.2.3"
run_case "module_id ajeno"

FAKE_RESULT_ID="alpha"
FAKE_RESULT_VERSION="9.9.9"
run_case "versión ajena"

# Camino sano: identidad y versión correctas conservan el resultado y sí pasan
# por rule_engine antes de incorporarse al aggregator.
FAKE_RESULT_ID="alpha"
FAKE_RESULT_VERSION="1.2.3"
_AGG_CAPTURE=""
_RULE_CALLED=0
_engine_run_module alpha >/dev/null 2>&1
rc=$?
assert_eq "identidad correcta: engine retorna 0" "0" "$rc"
if [ -n "$_AGG_CAPTURE" ] && result_deserialize "$_AGG_CAPTURE" >/dev/null 2>&1; then
  assert_eq "identidad correcta: conserva PASS" "PASS" "$RESULT_STATUS"
else
  printf '  ✗  identidad correcta — no se capturó resultado válido\n' >&2
  _fail=$((_fail + 1))
fi
assert_eq "identidad correcta: evalúa reglas" "1" "$_RULE_CALLED"

printf '\n  Pasaron: %s | Fallaron: %s\n\n' "$_pass" "$_fail"
exit "$_fail"
