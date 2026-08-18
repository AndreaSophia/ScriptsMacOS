#!/bin/bash
# =============================================================================
# Módulo: workspace_one — diagnose.sh
# Responsabilidad: verificar evidencia específica de Workspace ONE y su relación
# con el enrollment MDM. Un MDM genérico nunca se atribuye automáticamente a WS1.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/workspace_one_detail.txt"

_WS1_APP_PATHS=(
  "/Applications/Workspace ONE Intelligent Hub.app"
  "/Applications/VMware Workspace ONE.app"
  "/Applications/Intelligent Hub.app"
)
_WS1_PATTERN='airwatch|workspace[[:space:]_-]*one|intelligent[[:space:]_-]*hub|vmware.*hub|com\.air-watch|com\.airwatch'

_enrollment_output=""
_vendor_output=""
_runtime_output=""
_ws1_app=""
_ws1_ver=""
_udid=""
_profile_count="0"

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  # El sandbox no debe contaminarse con el estado del host. Cada señal procede
  # exclusivamente de fixtures explícitos.
  _enrollment_output="$(cat "${MERIDIAN_FIXTURE_DIR}/profiles_enrolled.txt" 2>/dev/null || echo "")"
  _vendor_output="$(cat "${MERIDIAN_FIXTURE_DIR}/workspace_one_vendor_evidence.txt" 2>/dev/null || echo "")"
  if [ -f "${MERIDIAN_FIXTURE_DIR}/workspace_one_app.txt" ]; then
    IFS='|' read -r _ws1_app _ws1_ver < "${MERIDIAN_FIXTURE_DIR}/workspace_one_app.txt"
  fi
  _udid="TEST-UDID"
  _profile_count="0"
else
  _enrollment_output="$(profiles status -type enrollment 2>/dev/null || echo "")"

  for _app in "${_WS1_APP_PATHS[@]}"; do
    if [ -d "$_app" ]; then
      _ws1_app="$_app"
      _ws1_ver="$(defaults read "${_app}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "N/A")"
      break
    fi
  done

  _udid="$(system_profiler SPHardwareDataType 2>/dev/null | \
    awk -F': ' '/Provisioning UDID/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
  [ -z "$_udid" ] && _udid="$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | \
    awk -F'"' '/IOPlatformUUID/{print $4; exit}')"

  _profiles_all="$(profiles list -all 2>/dev/null || true)"
  _profile_count="$(printf '%s\n' "$_profiles_all" | awk '/profileIdentifier/{count++} END{print count+0}')"
  _profile_count="${_profile_count:-0}"
  _vendor_output="$(printf '%s\n' "$_profiles_all" | grep -iE "$_WS1_PATTERN" | head -20 || true)"
  _runtime_output="$(launchctl list 2>/dev/null | grep -iE "$_WS1_PATTERN" | head -20 || true)"
fi

_mdm_enrolled=false
printf '%s\n' "$_enrollment_output" | \
  grep -qiE 'MDM enrollment:[[:space:]]*Yes|enrolled[^[:alnum:]]*Yes|Yes[^[:alnum:]]*enrolled' && \
  _mdm_enrolled=true

# Workspace ONE requiere evidencia propia. La existencia de cualquier MDM no
# demuestra proveedor; puede ser Jamf, Intune u otro servicio.
_ws1_confirmed=false
if [ -n "$_ws1_app" ] || [ -n "$_vendor_output" ] || [ -n "$_runtime_output" ]; then
  _ws1_confirmed=true
fi

{
  echo "# Workspace ONE — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Enrollment MDM genérico: ${_mdm_enrolled}"
  echo "## Workspace ONE confirmado: ${_ws1_confirmed}"
  echo "## App instalada: ${_ws1_app:-No encontrada}"
  echo "## Versión Hub: ${_ws1_ver:-N/A}"
  echo "## UDID: ${_udid:-No detectado}"
  echo "## Perfiles instalados: ${_profile_count}"
  echo
  echo "## profiles status:"
  echo "${_enrollment_output:-Sin salida}"
  echo
  echo "## Evidencia específica WS1 en perfiles:"
  echo "${_vendor_output:-Ninguna}"
  echo
  echo "## Evidencia específica WS1 en runtime:"
  echo "${_runtime_output:-Ninguna}"
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="mdm_enrolled=${_mdm_enrolled} ws1_confirmed=${_ws1_confirmed} app=${_ws1_app:-none} ver=${_ws1_ver:-N/A} profiles=${_profile_count} udid=${_udid:-none}"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"

if [ "$_mdm_enrolled" = "true" ] && [ "$_ws1_confirmed" = "true" ] && [ -n "$_ws1_app" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Workspace ONE enrollado y Hub instalado"
  RESULT_DESCRIPTION="Se detectó enrollment MDM junto con evidencia específica de Workspace ONE e Intelligent Hub v${_ws1_ver}."
  RESULT_EXPLANATION="Meridian exige señales específicas de Workspace ONE antes de atribuir el enrollment a ese proveedor."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"

elif [ "$_mdm_enrolled" = "true" ] && [ "$_ws1_confirmed" = "true" ] && [ -z "$_ws1_app" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Workspace ONE detectado pero Hub no encontrado"
  RESULT_DESCRIPTION="Existe enrollment MDM y evidencia específica de Workspace ONE, pero no se detectó Intelligent Hub instalado."
  RESULT_EXPLANATION="La conclusión se basa en señales WS1 explícitas, no únicamente en el estado MDM genérico."
  RESULT_RISK="Funciones dependientes del Hub podrían no estar disponibles."
  RESULT_SUGGESTED_ACTION="Validar el diseño de enrollment y, si el Hub es obligatorio, revisar su despliegue desde Workspace ONE."

elif [ "$_mdm_enrolled" = "true" ] && [ "$_ws1_confirmed" = "false" ]; then
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="MDM detectado; Workspace ONE no confirmado"
  RESULT_DESCRIPTION="macOS reporta enrollment MDM, pero Meridian no encontró evidencia suficiente para atribuirlo a Workspace ONE."
  RESULT_EXPLANATION="El estado 'MDM enrollment: Yes' es independiente del proveedor y no demuestra Workspace ONE."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"

elif [ "$_mdm_enrolled" = "false" ] && [ -n "$_ws1_app" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Hub instalado pero sin enrollment MDM"
  RESULT_DESCRIPTION="Intelligent Hub está instalado, pero macOS no reporta enrollment MDM activo."
  RESULT_EXPLANATION="La presencia del cliente no equivale a una relación de gestión activa."
  RESULT_RISK="El equipo puede no estar recibiendo políticas, certificados o aplicaciones administradas."
  RESULT_SUGGESTED_ACTION="Revisar el estado de enrollment en Workspace ONE antes de reinstalar componentes."

elif [ "$_mdm_enrolled" = "false" ] && [ "$_ws1_confirmed" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Evidencia de Workspace ONE sin enrollment MDM activo"
  RESULT_DESCRIPTION="Se encontraron señales específicas de Workspace ONE, pero macOS no reporta enrollment MDM activo."
  RESULT_EXPLANATION="Puede tratarse de restos de una instalación anterior o de un enrollment incompleto."
  RESULT_RISK="Estado de gestión corporativa indeterminado."
  RESULT_SUGGESTED_ACTION="Revisar perfiles MDM y estado del dispositivo en la consola Workspace ONE."

else
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Workspace ONE no detectado"
  RESULT_DESCRIPTION="No se encontró enrollment atribuible a Workspace ONE ni artefactos específicos del producto."
  RESULT_EXPLANATION="Este módulo no presume que Workspace ONE sea obligatorio en todos los equipos."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
fi
