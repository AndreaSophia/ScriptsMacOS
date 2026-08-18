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

_manifest_list_csv() {
  local key="$1" raw item out=""
  raw="$(awk -v key="$key" '
    $0 ~ "^" key ":[[:space:]]*\\[" {
      line=$0
      sub("^" key ":[[:space:]]*\\[", "", line)
      sub("\\][[:space:]]*$", "", line)
      n=split(line, values, ",")
      for (i=1; i<=n; i++) print values[i]
      exit
    }
    $0 ~ "^" key ":[[:space:]]*$" { in_list=1; next }
    in_list && $0 ~ "^[[:space:]]*-[[:space:]]*" {
      line=$0
      sub("^[[:space:]]*-[[:space:]]*", "", line)
      print line
      next
    }
    in_list && $0 ~ "^[[:space:]]*$" { next }
    in_list { exit }
  ' "$manifest_path" 2>/dev/null)"

  while IFS= read -r item; do
    item="$(printf '%s\n' "$item" | tr -d "\"'\r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$item" ] && continue
    if [ -n "$out" ]; then out="${out},${item}"; else out="$item"; fi
  done <<EOF
$raw
EOF
  printf '%s\n' "$out"
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
_check_field description _de
_check_field category _ca
_check_field version _ve
_check_field author _au
_check_field criticality _cr
_check_field requires_root _ro
_check_field timeout_seconds _to

if printf '%s\n' "$_id" | grep -qE '^[a-z][a-z0-9_]*$'; then
  _pass "id cumple snake_case"
else
  _fail "id='${_id}' no cumple snake_case"
fi

case "$_ca" in
  security|edr|mdm|network|storage|performance|system|apps|developer)
    _pass "category es un valor válido"
    ;;
  *) _fail "category='${_ca}' no es válida" ;;
esac

if printf '%s\n' "$_ve" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  _pass "version cumple semver X.Y.Z"
else
  _fail "version='${_ve}' no cumple semver X.Y.Z"
fi

if [ "${#_nm}" -le 60 ]; then
  _pass "name no excede 60 caracteres"
else
  _fail "name excede 60 caracteres"
fi

if [ "${#_de}" -le 200 ]; then
  _pass "description no excede 200 caracteres"
else
  _fail "description excede 200 caracteres"
fi

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
  _fail "id='${_id}' no coincide con directorio '${dir_name}'"
fi

printf "\n  \033[1mdependencias\033[0m\n"
dependencies="$(_manifest_list_csv dependencies)"
if [ -z "$dependencies" ]; then
  _pass "sin dependencias declaradas"
else
  dep_seen=""
  dep_ids=()
  IFS=',' read -r -a dep_ids <<< "$dependencies"
  for dep in "${dep_ids[@]}"; do
    if printf '%s\n' "$dep" | grep -qE '^[a-z][a-z0-9_]*$'; then
      _pass "dependency '${dep}' tiene module_id válido"
    else
      _fail "dependency='${dep}' no es un module_id válido"
      continue
    fi

    if [ "$dep" = "$_id" ]; then
      _fail "el módulo no puede depender de sí mismo"
    fi

    case "$dep_seen" in
      *"|${dep}|"*) _fail "dependency duplicada: ${dep}" ;;
      *) dep_seen="${dep_seen}|${dep}|" ;;
    esac

    dep_manifest="$(find "${MERIDIAN_ROOT}/modules" -path "*/${dep}/manifest.yaml" -type f -print 2>/dev/null | head -1)"
    if [ -n "$dep_manifest" ]; then
      _pass "dependency '${dep}' existe en el árbol de módulos"
    else
      _fail "dependency '${dep}' no existe en el árbol de módulos"
    fi
  done
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
    if [ -f "${module_dir}/repair.sh" ]; then
      _fail "repair.sh presente pero repairable no es true"
    else
      _pass "módulo no reparable sin repair.sh"
    fi
    ;;
  *) _fail "repairable='${repairable}' no es válido (true|false)" ;;
esac

if [ -f "${module_dir}/repair.sh" ] && [ ! -f "${module_dir}/validate.sh" ]; then
  _fail "validate.sh FALTANTE: IModule lo exige cuando existe repair.sh"
fi

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
