#!/bin/bash
# =============================================================================
# Meridian — tools/validate_module.sh
# Valida el contrato IModule sin perder estado en subshells.
# Compatible con Bash 3.2/macOS.
# =============================================================================

set -uo pipefail

MODULE_ID="${1:?'Uso: validate_module.sh <module_id>'}"
MERIDIAN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0
warnings=0

_pass() { printf "  \033[1;32m✓\033[0m  %s\n" "$1"; }
_fail() { printf "  \033[1;31m✗\033[0m  %s\n" "$1" >&2; errors=$((errors+1)); }
_warn() { printf "  \033[1;33m!\033[0m  %s\n" "$1"; warnings=$((warnings+1)); }

_manifest_value() {
  local key="$1"
  grep "^${key}:" "$manifest_path" 2>/dev/null | \
    sed "s/^${key}:[[:space:]]*//" | \
    sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | \
    tr -d '\r' | head -1
}

_check_field() {
  local key="$1" varname="$2" val
  val="$(_manifest_value "$key")"
  printf -v "$varname" '%s' "$val"
  if [ -n "$val" ]; then
    _pass "${key}: ${val}"
  else
    _fail "Campo obligatorio faltante o vacío: ${key}"
  fi
}

printf "\n\033[1mValidando módulo: %s\033[0m\n\n" "$MODULE_ID"

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
  exit 1
fi

module_dir="$(dirname "$manifest_path")"
_pass "manifest.yaml encontrado: ${manifest_path#$MERIDIAN_ROOT/}"

printf "\n  \033[1mmanifest.yaml — campos obligatorios\033[0m\n"
_check_field id _id
_check_field name _nm
_check_field category _ca
_check_field version _ve
_check_field criticality _cr
_check_field requires_root _ro
_check_field timeout_seconds _to

case "$_ro" in
  true|false) _pass "requires_root es booleano" ;;
  *) _fail "requires_root='${_ro}' no es válido (true|false)" ;;
esac

case "$_cr" in
  low|medium|high|critical) _pass "criticality es un valor válido" ;;
  *) _fail "criticality='${_cr}' no es válido (low|medium|high|critical)" ;;
esac

if echo "$_to" | grep -qE '^[0-9]+$' && [ "$_to" -gt 0 ] 2>/dev/null; then
  _pass "timeout_seconds es un entero positivo: ${_to}"
else
  _fail "timeout_seconds='${_to}' no es un entero positivo"
fi

dir_name="$(basename "$module_dir")"
if [ "$_id" = "$dir_name" ]; then
  _pass "id coincide con nombre del directorio"
else
  _warn "id='${_id}' no coincide con directorio '${dir_name}'"
fi

printf "\n  \033[1marchivos requeridos\033[0m\n"
[ -f "${module_dir}/diagnose.sh" ] && _pass "diagnose.sh presente" || _fail "diagnose.sh FALTANTE"

repairable="$(_manifest_value repairable)"
case "$repairable" in
  true)
    [ -f "${module_dir}/repair.sh" ] && _pass "repair.sh presente" || _fail "repair.sh FALTANTE (repairable=true)"
    [ -f "${module_dir}/validate.sh" ] && _pass "validate.sh presente" || _fail "validate.sh FALTANTE (repairable=true)"
    ;;
  false|"")
    [ -f "${module_dir}/repair.sh" ] && _warn "repair.sh presente pero repairable no es true"
    ;;
  *) _fail "repairable='${repairable}' no es válido (true|false)" ;;
esac

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

printf "\n  \033[1mcontrato RESULT_*\033[0m\n"
for var in RESULT_STATUS RESULT_SEVERITY RESULT_TITLE RESULT_DESCRIPTION \
           RESULT_EXPLANATION RESULT_RISK RESULT_SUGGESTED_ACTION \
           RESULT_REPAIRABLE RESULT_REPAIR_RISK RESULT_EXIT_CODE; do
  if grep -q "$var" "${module_dir}/diagnose.sh" 2>/dev/null; then
    _pass "$var declarada en diagnose.sh"
  else
    _fail "$var NO encontrada en diagnose.sh"
  fi
done

printf "\n  \033[1mmodo test\033[0m\n"
if grep -q "MERIDIAN_TEST_MODE" "${module_dir}/diagnose.sh" 2>/dev/null; then
  _pass "diagnose.sh verifica MERIDIAN_TEST_MODE"
else
  _warn "diagnose.sh no verifica MERIDIAN_TEST_MODE"
fi

printf "\n  ─────────────────────────────────────────\n"
if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
  printf "  \033[1;32m✓ Módulo '%s' cumple el contrato IModule\033[0m\n" "$MODULE_ID"
elif [ "$errors" -eq 0 ]; then
  printf "  \033[1;33m! Módulo '%s' válido con %d advertencia(s)\033[0m\n" "$MODULE_ID" "$warnings"
else
  printf "  \033[1;31m✗ Módulo '%s': %d error(es), %d advertencia(s)\033[0m\n" "$MODULE_ID" "$errors" "$warnings"
fi
printf "  ─────────────────────────────────────────\n\n"

[ "$errors" -eq 0 ]
