#!/bin/bash
# =============================================================================
# Meridian — tools/module_scaffold.sh
# Genera el esqueleto de un nuevo módulo conforme al contrato IModule.
# Uso: bash tools/module_scaffold.sh <id> <nombre> <categoría>
# Ejemplo: bash tools/module_scaffold.sh vpn_check "VPN Status" network
#
# Compatible con Bash 3.2/macOS. Los argumentos se validan antes de construir
# rutas o escribir archivos para evitar módulos que el runtime rechazaría y
# para impedir traversal accidental fuera de Meridian/modules.
# =============================================================================

set -euo pipefail

MODULE_ID="${1:?'Uso: module_scaffold.sh <id> <nombre> <categoría>'}"
MODULE_NAME="${2:?'Falta el nombre del módulo'}"
MODULE_CATEGORY="${3:?'Falta la categoría'}"

MERIDIAN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

_fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

_yaml_quote() {
  # YAML single-quoted scalar: una comilla simple se representa como ''.
  # El scaffold rechaza CR/LF antes de llegar aquí.
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

_validate_inputs() {
  printf '%s\n' "$MODULE_ID" | grep -qE '^[a-z][a-z0-9_]*$' || \
    _fail "id inválido '${MODULE_ID}': usa snake_case [a-z][a-z0-9_]*"

  case "$MODULE_CATEGORY" in
    security|edr|mdm|network|storage|performance|system|apps|developer) ;;
    *) _fail "categoría inválida '${MODULE_CATEGORY}'" ;;
  esac

  [ -n "$MODULE_NAME" ] || _fail "el nombre no puede estar vacío"
  [ "${#MODULE_NAME}" -le 60 ] || _fail "el nombre excede 60 caracteres"

  case "$MODULE_NAME" in
    *$'\n'*|*$'\r'*) _fail "el nombre no puede contener saltos de línea" ;;
  esac
}

_validate_inputs

MODULE_DIR="${MERIDIAN_ROOT}/modules/${MODULE_CATEGORY}/${MODULE_ID}"

printf '\nCreando módulo: %s\n' "$MODULE_ID"
printf '  Nombre    : %s\n' "$MODULE_NAME"
printf '  Categoría : %s\n' "$MODULE_CATEGORY"
printf '  Ruta      : %s\n\n' "$MODULE_DIR"

if [ -e "$MODULE_DIR" ]; then
  _fail "el módulo ya existe: ${MODULE_DIR}"
fi

mkdir -p "$MODULE_DIR"

# --- manifest.yaml ---
cat > "${MODULE_DIR}/manifest.yaml" <<MANIFEST
id: ${MODULE_ID}
name: $(_yaml_quote "$MODULE_NAME")
description: 'TODO — descripción de qué diagnostica este módulo'
category: ${MODULE_CATEGORY}
version: 1.0.0
author: 'Apple Platform Team'
criticality: medium
requires_root: false
timeout_seconds: 30
repairable: false
tags:
  - ${MODULE_CATEGORY}
MANIFEST

# --- diagnose.sh ---
cat > "${MODULE_DIR}/diagnose.sh" <<'DIAGNOSE'
#!/bin/bash
# =============================================================================
# Módulo: MODULE_ID — diagnose.sh
# TODO: implementar lógica de diagnóstico
# Contrato: poblar todas las variables RESULT_* antes de retornar
# No modificar el sistema. Solo leer.
# =============================================================================

# Modo test — usar fixtures si están disponibles
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  # TODO: cargar fixture correspondiente
  :
fi

# TODO: recopilar evidencia
# _evidence_file="${MERIDIAN_EVIDENCE_DIR}/MODULE_ID_detail.txt"
# { echo "# Evidencia"; some_command; } > "$_evidence_file"

# TODO: implementar lógica de diagnóstico
RESULT_STATUS="SKIP"
RESULT_SEVERITY="INFO"
RESULT_TITLE="Módulo pendiente de implementación"
RESULT_DESCRIPTION="Este módulo aún no ha sido implementado."
RESULT_EXPLANATION="Ver diagnose.sh para implementar la lógica."
RESULT_RISK="N/A"
RESULT_SUGGESTED_ACTION="Implementar el módulo."
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT=""
DIAGNOSE

chmod 755 "${MODULE_DIR}/diagnose.sh"
# MODULE_ID ya está restringido a [a-z0-9_], por lo que puede usarse como
# reemplazo literal sin convertir el sed en una frontera de inyección.
sed -i '' "s/MODULE_ID/${MODULE_ID}/g" "${MODULE_DIR}/diagnose.sh"
chmod 644 "${MODULE_DIR}/manifest.yaml"

printf '[OK] Módulo creado: %s\n\n' "$MODULE_DIR"
printf 'Próximos pasos:\n'
printf '  1. Editar %s/manifest.yaml\n' "$MODULE_DIR"
printf '  2. Implementar %s/diagnose.sh\n' "$MODULE_DIR"
printf '  3. Validar: bash tools/validate_module.sh %s\n\n' "$MODULE_ID"
