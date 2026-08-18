#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_module_loader.sh
# Tests para module_loader, module_registry, manifest validation y ejecución.
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"

MERIDIAN_LOG_FILE="/dev/null"
MERIDIAN_DEBUG=0
log_debug() { :; }
log_info()  { :; }
log_ok()    { :; }
log_warn()  { echo "[WARN] $2" >&2; }
log_error() { echo "[ERROR] $2" >&2; }

source "${MERIDIAN_ROOT}/core/result_model.sh"
source "${MERIDIAN_ROOT}/core/module_registry.sh"
source "${MERIDIAN_ROOT}/core/privilege_manager.sh"
source "${MERIDIAN_ROOT}/core/module_loader.sh"

_pass=0; _fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" "$desc" "$expected" "$actual" >&2
    _fail=$((_fail+1))
  fi
}

assert_gt() {
  local desc="$1" threshold="$2" actual="$3"
  if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
    printf "  \033[1;32m✓\033[0m  %s (%s > %s)\n" "$desc" "$actual" "$threshold"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s (got %s, esperaba > %s)\n" "$desc" "$actual" "$threshold" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_module_loader.sh\033[0m\n\n"

registry_reset 2>/dev/null || true
module_loader_discover "${MERIDIAN_ROOT}/modules" 2>/dev/null
assert_gt "module_loader_discover: carga al menos 1 módulo" "0" "$(registry_count)"

for expected_id in filevault certificates secure_token crowdstrike cisco_umbrella forcepoint workspace_one; do
  if registry_exists "$expected_id"; then
    printf "  \033[1;32m✓\033[0m  Módulo registrado: %s\n" "$expected_id"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  Módulo NO encontrado: %s\n" "$expected_id" >&2
    _fail=$((_fail+1))
  fi
done

filevault_cat="$(registry_get_field "filevault" 3)"
assert_eq "registry_get_field: filevault category=security" "security" "$filevault_cat"

crowdstrike_cat="$(registry_get_field "crowdstrike" 3)"
assert_eq "registry_get_field: crowdstrike category=edr" "edr" "$crowdstrike_cat"

ws1_cat="$(registry_get_field "workspace_one" 3)"
assert_eq "registry_get_field: workspace_one category=mdm" "mdm" "$ws1_cat"

security_modules="$(registry_get_by_category "security")"
if echo "$security_modules" | grep -q "filevault" && echo "$security_modules" | grep -q "secure_token"; then
  printf "  \033[1;32m✓\033[0m  registry_get_by_category 'security' incluye filevault y secure_token\n"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  registry_get_by_category 'security' no incluyó todos los módulos esperados\n" >&2
  _fail=$((_fail+1))
fi

count_before="$(registry_count)"
registry_add "filevault" "Duplicate" "security" "1.0.0" "critical" "/tmp" "false" "10" 2>/dev/null
count_after="$(registry_count)"
assert_eq "registry_add: rechaza duplicado (count no cambia)" "$count_before" "$count_after"

tmp_evidence="$(mktemp -d "${TMPDIR:-/tmp}/meridian_loader_test.XXXXXX")"
export MERIDIAN_TEST_MODE=1
export MERIDIAN_FIXTURE_DIR="${MERIDIAN_ROOT}/tests/fixtures"
export MERIDIAN_POLICY_CURRENT_USER="safiye"
serialized="$(module_loader_run "filevault" "$tmp_evidence" 2>/dev/null)"
run_rc=$?
assert_eq "module_loader_run: filevault retorna 0" "0" "$run_rc"

if [ -n "$serialized" ]; then
  result_deserialize "$serialized"
  assert_eq "module_loader_run: conserva module_id" "filevault" "$RESULT_MODULE_ID"
  assert_eq "module_loader_run: fixture disabled produce FAIL" "FAIL" "$RESULT_STATUS"
  assert_eq "module_loader_run: resultado valida contrato" "0" "$(result_validate >/dev/null 2>&1; echo $?)"
else
  printf "  \033[1;31m✗\033[0m  module_loader_run: no produjo DiagnosticResult\n" >&2
  _fail=$((_fail+1))
fi

serialized="$(module_loader_run "secure_token" "$tmp_evidence" 2>/dev/null)"
run_rc=$?
assert_eq "secure_token: retorna 0 con fixture" "0" "$run_rc"
if [ -n "$serialized" ]; then
  result_deserialize "$serialized"
  assert_eq "secure_token: conserva module_id" "secure_token" "$RESULT_MODULE_ID"
  assert_eq "secure_token: cuenta requerida sin token produce FAIL" "FAIL" "$RESULT_STATUS"
  assert_eq "secure_token: incumplimiento de política es HIGH" "HIGH" "$RESULT_SEVERITY"
  case "$RESULT_EVIDENCE" in
    *"[REQUIRED] safiye (UID 501): Secure Token ENABLED"*"[REQUIRED] LCLAdmin (UID 502): Secure Token DISABLED"*"[REQUIRED] AdminCMDB (UID 503): Secure Token DISABLED"*"[INVENTORY] _cyberarkepm (UID 504): Secure Token DISABLED"*)
      printf "  \033[1;32m✓\033[0m  secure_token: evidencia separa política e inventario\n"
      _pass=$((_pass+1)) ;;
    *)
      printf "  \033[1;31m✗\033[0m  secure_token: evidencia incompleta\n" >&2
      _fail=$((_fail+1)) ;;
  esac
else
  printf "  \033[1;31m✗\033[0m  secure_token: no produjo DiagnosticResult\n" >&2
  _fail=$((_fail+1))
fi

transition_fixture="$(mktemp -d "${TMPDIR:-/tmp}/meridian_fv_transition.XXXXXX")"
printf '%s\n' 'FileVault is On.' 'Encryption in progress: Percent completed = 42' > "${transition_fixture}/fdesetup_disabled.txt"
export MERIDIAN_FIXTURE_DIR="$transition_fixture"
serialized="$(module_loader_run "filevault" "$tmp_evidence" 2>/dev/null)"
if [ -n "$serialized" ]; then
  result_deserialize "$serialized"
  assert_eq "filevault: cifrado en progreso produce WARN" "WARN" "$RESULT_STATUS"
  assert_eq "filevault: cifrado en progreso no es severidad INFO" "MEDIUM" "$RESULT_SEVERITY"
else
  printf "  \033[1;31m✗\033[0m  filevault transición de cifrado: sin resultado\n" >&2
  _fail=$((_fail+1))
fi

printf '%s\n' 'FileVault is Off.' 'Decryption in progress: Percent completed = 35' > "${transition_fixture}/fdesetup_disabled.txt"
serialized="$(module_loader_run "filevault" "$tmp_evidence" 2>/dev/null)"
if [ -n "$serialized" ]; then
  result_deserialize "$serialized"
  assert_eq "filevault: descifrado en progreso produce FAIL" "FAIL" "$RESULT_STATUS"
  assert_eq "filevault: descifrado en progreso eleva severidad" "HIGH" "$RESULT_SEVERITY"
else
  printf "  \033[1;31m✗\033[0m  filevault transición de descifrado: sin resultado\n" >&2
  _fail=$((_fail+1))
fi

rm -rf "$tmp_evidence" "$transition_fixture"
unset MERIDIAN_TEST_MODE MERIDIAN_FIXTURE_DIR MERIDIAN_POLICY_CURRENT_USER

module_loader_discover "/nonexistent/path" 2>/dev/null
rc=$?
assert_eq "module_loader_discover: directorio inválido retorna 1" "1" "$rc"

printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit $_fail
