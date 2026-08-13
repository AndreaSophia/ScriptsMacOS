#!/bin/bash
# =============================================================================
# Meridian — tools/validate_module.sh
# Valida que un módulo cumple el contrato IModule antes de ser desplegado.
# Uso: bash tools/validate_module.sh <module_id>
# Ejemplo: bash tools/validate_module.sh filevault
# =============================================================================

set -uo pipefail

MODULE_ID="${1:?'Uso: validate_module.sh <module_id>'}"
MERIDIAN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

errors=0
warnings=0

_pass() { printf "  \033[1;32m✓\033[0m  %s\n" "$1"; }
_fail() { printf "  \033[1;31m✗\033[0m  %s\n" "$1" >&2; errors=$((errors+1)); }
_warn() { printf "  \033[1;33m!\033[0m  %s\n" "$1"; warnings=$((warnings+1)); }

printf "\n\033[1mValidando módulo: %s\033[0m\n\n" "$MODULE_ID"

# --- Localizar el módulo ---
manifest_path=""
while IFS= read -r f; do
  id_in_manifest="$(grep '^id:' "$f" 2>/dev/null | sed 's/^id:[[:space:]]*//' | tr -d '"' | xargs)"
  if [ "$id_in_manifest" = "$MODULE_ID" ]; then
    manifest_path="$f"
    break
  fi
done < <(find "${MERIDIAN_ROOT}/modules" -name "manifest.yaml" -type f 2>/dev/null)

if [ -z "$manifest_path" ]; then
  _fail "manifest.yaml no encontrado para módulo '$MODULE_ID'"
  echo ""
  exit 1
fi

module_dir="$(dirname "$manifest_path")"
_pass "manifest.yaml encontrado: ${manifest_path#$MERIDIAN_ROOT/}"

# --- Validar campos obligatorios del manifest ---
printf "\n  \033[1mmanifest.yaml — campos obligatorios\033[0m\n"

_check_field() {
  local key="$1"
  local val
  val="$(grep "^${key}:" "$manifest_path" 2>/dev/null | \
    sed "s/^${key}:[[:space:]]*//" | tr -d '"' | xargs | head -1)"
  if [ -n "$val" ]; then
    _pass "${key}: ${val}"
  else
    _fail "Campo obligatorio faltante o vacío: ${key}"
  fi
  echo "$val"
}

_id="$(_check_field "id"         2>/dev/null)"
_nm="$(_check_field "name"       2>/dev/null)"
_ca="$(_check_field "category"   2>/dev/null)"
_ve="$(_check_field "version"    2>/dev/null)"
_cr="$(_check_field "criticality" 2>/dev/null)"
_ro="$(_check_field "requires_root" 2>/dev/null)"
_to="$(_check_field "timeout_seconds" 2>/dev/null)"

# id debe coincidir con el nombre del directorio
dir_name="$(basename "$module_dir")"
if [ "$_id" = "$dir_name" ]; then
  _pass "id coincide con nombre del directorio"
else
  _warn "id='${_id}' no coincide con directorio '${dir_name}'"
fi

# Validar enum criticality
case "$_cr" in
  low|medium|high|critical) _pass "criticality es un valor válido" ;;
  *) _fail "criticality='${_cr}' no es válido (low|medium|high|critical)" ;;
esac

# Validar timeout numérico
if echo "$_to" | grep -qE '^[0-9]+$'; then
  _pass "timeout_seconds es un entero: ${_to}"
else
  _fail "timeout_seconds='${_to}' no es un entero"
fi

# --- Validar archivos requeridos ---
printf "\n  \033[1marchivos requeridos\033[0m\n"

if [ -f "${module_dir}/diagnose.sh" ]; then
  _pass "diagnose.sh presente"
else
  _fail "diagnose.sh FALTANTE — es obligatorio"
fi

repairable="$(grep '^repairable:' "$manifest_path" 2>/dev/null | \
  sed 's/^repairable:[[:space:]]*//' | tr -d '"' | xargs)"

if [ "$repairable" = "true" ]; then
  if [ -f "${module_dir}/repair.sh" ]; then
    _pass "repair.sh presente (repairable=true)"
  else
    _fail "repair.sh FALTANTE (manifest dice repairable=true)"
  fi
  if [ -f "${module_dir}/validate.sh" ]; then
    _pass "validate.sh presente"
  else
    _fail "validate.sh FALTANTE (repair.sh existe pero no validate.sh)"
  fi
else
  [ -f "${module_dir}/repair.sh" ] && \
    _warn "repair.sh presente pero repairable no es true en manifest"
fi

# --- Validar sintaxis bash de los scripts ---
printf "\n  \033[1msintaxis bash\033[0m\n"

for script in diagnose.sh repair.sh validate.sh; do
  if [ -f "${module_dir}/${script}" ]; then
    if bash -n "${module_dir}/${script}" 2>/dev/null; then
      _pass "${script}: sintaxis OK"
    else
      _fail "${script}: error de sintaxis bash"
      bash -n "${module_dir}/${script}" 2>&1 | while IFS= read -r err; do
        printf "       %s\n" "$err" >&2
      done
    fi
  fi
done

# --- Verificar que diagnose.sh setea variables RESULT_* ---
printf "\n  \033[1mcontrato de variables RESULT_*\033[0m\n"

for var in RESULT_STATUS RESULT_SEVERITY RESULT_TITLE RESULT_DESCRIPTION \
           RESULT_EXPLANATION RESULT_RISK RESULT_SUGGESTED_ACTION \
           RESULT_REPAIRABLE RESULT_REPAIR_RISK RESULT_EXIT_CODE; do
  if grep -q "$var" "${module_dir}/diagnose.sh" 2>/dev/null; then
    _pass "$var asignada en diagnose.sh"
  else
    _fail "$var NO encontrada en diagnose.sh"
  fi
done

# --- Verificar respeto al modo test ---
printf "\n  \033[1mmodo test\033[0m\n"

if grep -q "MERIDIAN_TEST_MODE" "${module_dir}/diagnose.sh" 2>/dev/null; then
  _pass "diagnose.sh verifica MERIDIAN_TEST_MODE"
else
  _warn "diagnose.sh no verifica MERIDIAN_TEST_MODE (recomendado para testabilidad)"
fi

# --- Resumen ---
printf "\n"
printf "  ─────────────────────────────────────────\n"
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
  printf "  \033[1;32m✓ Módulo '%s' cumple el contrato IModule\033[0m\n" "$MODULE_ID"
elif [ $errors -eq 0 ]; then
  printf "  \033[1;33m! Módulo '%s' válido con %d advertencia(s)\033[0m\n" \
    "$MODULE_ID" "$warnings"
else
  printf "  \033[1;31m✗ Módulo '%s': %d error(es), %d advertencia(s)\033[0m\n" \
    "$MODULE_ID" "$errors" "$warnings"
fi
printf "  ─────────────────────────────────────────\n\n"

exit $errors
