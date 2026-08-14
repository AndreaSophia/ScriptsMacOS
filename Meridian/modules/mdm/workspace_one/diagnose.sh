#!/bin/bash
# =============================================================================
# Módulo: workspace_one — diagnose.sh
# Responsabilidad: verificar enrollment MDM y estado del agente
# Workspace ONE Intelligent Hub.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/workspace_one_detail.txt"

_WS1_APP_PATHS=(
  "/Applications/Workspace ONE Intelligent Hub.app"
  "/Applications/VMware Workspace ONE.app"
  "/Applications/Intelligent Hub.app"
)

# Modo test
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _enrollment_output="$(cat "${MERIDIAN_FIXTURE_DIR}/profiles_enrolled.txt" 2>/dev/null || echo "")"
else
  _enrollment_output="$(profiles status -type enrollment 2>/dev/null || echo "")"
fi

# Detectar app instalada
_ws1_app=""
_ws1_ver=""
for _app in "${_WS1_APP_PATHS[@]}"; do
  if [ -d "$_app" ]; then
    _ws1_app="$_app"
    _ws1_ver="$(defaults read "${_app}/Contents/Info" \
      CFBundleShortVersionString 2>/dev/null || echo "N/A")"
    break
  fi
done

# UDID del dispositivo
_udid="$(system_profiler SPHardwareDataType 2>/dev/null | \
  awk -F': ' '/Provisioning UDID/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
[ -z "$_udid" ] && _udid="$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | \
  awk -F'"' '/IOPlatformUUID/{print $4; exit}')"

# Perfiles instalados. grep -c imprime 0 y retorna rc=1 cuando no hay coincidencias;
# combinarlo con `|| echo 0` generaba "0\n0". awk entrega siempre un único entero.
_profile_count="$(profiles list -all 2>/dev/null | \
  awk '/profileIdentifier/{count++} END{print count+0}')"
_profile_count="${_profile_count:-0}"

# Guardar evidencia
{
  echo "# Workspace ONE — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## App instalada: ${_ws1_app:-No encontrada}"
  echo "## Versión Hub: ${_ws1_ver:-N/A}"
  echo "## UDID: ${_udid:-No detectado}"
  echo "## Perfiles instalados: ${_profile_count}"
  echo ""
  echo "## profiles status:"
  echo "${_enrollment_output}"
  echo ""
  echo "## Supervisión:"
  profiles status -type supervising 2>/dev/null || echo "N/A"
  echo ""
  echo "## LaunchDaemons WS1:"
  launchctl list 2>/dev/null | \
    grep -iE "airwatch|workspace|hub|vmware|mdm" || echo "Ninguno"
  echo ""
  echo "## Procesos WS1:"
  ps aux 2>/dev/null | \
    grep -iE "[H]ub|[A]irWatch|[I]ntelligent|[W]orkspace" || echo "Ninguno"
  echo ""
  echo "## Managed Preferences:"
  ls "/Library/Managed Preferences/" 2>/dev/null || echo "Ninguna"
} > "$_evidence_file" 2>/dev/null

# --- Determinar estado ---
_enrolled=false
printf '%s\n' "$_enrollment_output" | \
  grep -qiE 'MDM enrollment:[[:space:]]*Yes|enrolled[^[:alnum:]]*Yes|Yes[^[:alnum:]]*enrolled' && \
  _enrolled=true

RESULT_RAW_OUTPUT="enrolled=${_enrolled} app=${_ws1_app:-none} ver=${_ws1_ver:-N/A} profiles=${_profile_count} udid=${_udid:-none}"

if [ "$_enrolled" = "true" ] && [ -n "$_ws1_app" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Workspace ONE enrollado y Hub instalado"
  RESULT_DESCRIPTION="El equipo está enrollado en MDM y el Intelligent Hub v${_ws1_ver} está instalado."
  RESULT_EXPLANATION="Workspace ONE garantiza que las políticas corporativas se aplican y el equipo está gestionado."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif [ "$_enrolled" = "true" ] && [ -z "$_ws1_app" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Enrollado en MDM pero Hub no encontrado"
  RESULT_DESCRIPTION="El equipo está enrollado en MDM pero no se detectó Intelligent Hub instalado."
  RESULT_EXPLANATION="Sin el Hub, ciertas políticas y funciones de self-service no están disponibles."
  RESULT_RISK="Gestión MDM parcial. Sin acceso al catálogo de apps corporativas."
  RESULT_SUGGESTED_ACTION="Instalar Workspace ONE Intelligent Hub desde el portal de empresa."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif [ "$_enrolled" = "false" ] && [ -n "$_ws1_app" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Hub instalado pero equipo no enrollado en MDM"
  RESULT_DESCRIPTION="Intelligent Hub está instalado pero el equipo no está enrollado en MDM."
  RESULT_EXPLANATION="Sin enrollment, el equipo no recibe políticas, certificados ni aplicaciones corporativas."
  RESULT_RISK="Equipo fuera de gestión corporativa. Incumplimiento de política de seguridad."
  RESULT_SUGGESTED_ACTION="Completar el enrollment MDM abriendo Intelligent Hub y siguiendo el proceso de registro."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

else
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="Equipo no enrollado en MDM y sin Hub"
  RESULT_DESCRIPTION="No se detectó enrollment MDM ni Intelligent Hub en este equipo."
  RESULT_EXPLANATION="El equipo no está gestionado corporativamente. No recibe políticas de seguridad ni aplicaciones."
  RESULT_RISK="Equipo completamente fuera de gestión corporativa. Incumplimiento severo de política de seguridad."
  RESULT_SUGGESTED_ACTION="Contactar al equipo de soporte Apple para iniciar el proceso de enrollment corporativo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
