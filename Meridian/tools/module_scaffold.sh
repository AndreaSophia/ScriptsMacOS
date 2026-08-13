#!/bin/bash
# =============================================================================
# Meridian — tools/module_scaffold.sh
# Genera el esqueleto de un nuevo módulo listo para implementar.
# Uso: bash tools/module_scaffold.sh <id> <nombre> <categoría>
# Ejemplo: bash tools/module_scaffold.sh vpn_check "VPN Status" network
# =============================================================================

set -euo pipefail

MODULE_ID="${1:?'Uso: module_scaffold.sh <id> <nombre> <categoría>'}"
MODULE_NAME="${2:?'Falta el nombre del módulo'}"
MODULE_CATEGORY="${3:?'Falta la categoría'}"

MERIDIAN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="${MERIDIAN_ROOT}/modules/${MODULE_CATEGORY}/${MODULE_ID}"

echo ""
echo "Creando módulo: ${MODULE_ID}"
echo "  Nombre    : ${MODULE_NAME}"
echo "  Categoría : ${MODULE_CATEGORY}"
echo "  Ruta      : ${MODULE_DIR}"
echo ""

if [ -d "$MODULE_DIR" ]; then
  echo "[ERROR] El módulo ya existe: ${MODULE_DIR}" >&2
  exit 1
fi

mkdir -p "$MODULE_DIR"

# --- manifest.yaml ---
cat > "${MODULE_DIR}/manifest.yaml" <<MANIFEST
id: ${MODULE_ID}
name: ${MODULE_NAME}
description: TODO — descripción de qué diagnostica este módulo
category: ${MODULE_CATEGORY}
version: 1.0.0
author: Apple Platform Team
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
# Ejemplo de resultado PASS:
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

chmod +x "${MODULE_DIR}/diagnose.sh"
sed -i '' "s/MODULE_ID/${MODULE_ID}/g" "${MODULE_DIR}/diagnose.sh"

echo "[OK] Módulo creado: ${MODULE_DIR}"
echo ""
echo "Próximos pasos:"
echo "  1. Editar ${MODULE_DIR}/manifest.yaml"
echo "  2. Implementar ${MODULE_DIR}/diagnose.sh"
echo "  3. Validar: bash tools/validate_module.sh ${MODULE_ID}"
echo ""
