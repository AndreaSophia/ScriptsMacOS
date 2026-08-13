#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_module_loader.sh
# Tests para module_loader, module_registry y manifest validation
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Stubs mínimos
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
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" \
      "$desc" "$expected" "$actual" >&2
    _fail=$((_fail+1))
  fi
}

assert_gt() {
  local desc="$1" threshold="$2" actual="$3"
  if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
    printf "  \033[1;32m✓\033[0m  %s (%s > %s)\n" "$desc" "$actual" "$threshold"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  %s (got %s, esperaba > %s)\n" \
      "$desc" "$actual" "$threshold" >&2
    _fail=$((_fail+1))
  fi
}

printf "\n\033[1mtest_module_loader.sh\033[0m\n\n"

# --- Test: descubrir módulos reales ---
module_loader_discover "${MERIDIAN_ROOT}/modules" 2>/dev/null
assert_gt "module_loader_discover: carga al menos 1 módulo" "0" "$(registry_count)"

# --- Test: módulos MVP están registrados ---
for expected_id in filevault certificates crowdstrike cisco_umbrella forcepoint workspace_one; do
  if registry_exists "$expected_id"; then
    printf "  \033[1;32m✓\033[0m  Módulo registrado: %s\n" "$expected_id"
    _pass=$((_pass+1))
  else
    printf "  \033[1;31m✗\033[0m  Módulo NO encontrado: %s\n" "$expected_id" >&2
    _fail=$((_fail+1))
  fi
done

# --- Test: registry_get_field devuelve datos correctos ---
filevault_cat="$(registry_get_field "filevault" 3)"
assert_eq "registry_get_field: filevault category=security" "security" "$filevault_cat"

crowdstrike_cat="$(registry_get_field "crowdstrike" 3)"
assert_eq "registry_get_field: crowdstrike category=edr" "edr" "$crowdstrike_cat"

ws1_cat="$(registry_get_field "workspace_one" 3)"
assert_eq "registry_get_field: workspace_one category=mdm" "mdm" "$ws1_cat"

# --- Test: registry_get_by_category ---
security_modules="$(registry_get_by_category "security")"
if echo "$security_modules" | grep -q "filevault"; then
  printf "  \033[1;32m✓\033[0m  registry_get_by_category 'security' incluye filevault\n"
  _pass=$((_pass+1))
else
  printf "  \033[1;31m✗\033[0m  registry_get_by_category 'security' no incluyó filevault\n" >&2
  _fail=$((_fail+1))
fi

# --- Test: registry rechaza duplicados ---
count_before="$(registry_count)"
registry_add "filevault" "Duplicate" "security" "1.0.0" "critical" "/tmp" "false" "10" 2>/dev/null
count_after="$(registry_count)"
assert_eq "registry_add: rechaza duplicado (count no cambia)" \
  "$count_before" "$count_after"

# --- Test: directorio inválido no rompe el loader ---
module_loader_discover "/nonexistent/path" 2>/dev/null
rc=$?
assert_eq "module_loader_discover: directorio inválido retorna 1" "1" "$rc"

# --- Resumen ---
printf "\n  ─────────────────────────────────────\n"
printf "  Pasaron: %s | Fallaron: %s\n" "$_pass" "$_fail"
printf "  ─────────────────────────────────────\n\n"
exit $_fail
