#!/bin/bash
# =============================================================================
# Módulo: forcepoint — diagnose.sh
# Verifica presencia y señales operativas de Forcepoint/F1E en macOS.
# Evita declarar PASS por la mera existencia de un proceso auxiliar.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/forcepoint_detail.txt"

_FP_PATHS=(
  "/Applications/Forcepoint Endpoint.app"
  "/Applications/Websense Endpoint.app"
  "/Library/Application Support/Websense Endpoint"
  "/Library/Application Support/Websense Endpoint/DLP/wsdlpd"
  "/Library/Application Support/Websense Endpoint/EPClassifier/EndPointClassifier"
  "/Library/Application Support/Websense Endpoint/Cloud/FPEPAgent"
)
_FP_AGENT_IDS=(
  "com.forcepoint.endpoint.agent"
  "com.websense.endpoint"
  "com.forcepoint.wse"
)
_FP_PROCESS_PATTERNS="[F]orcepoint|[W]ebsense|[w]sdlpd|[E]ndPointClassifier|[F]PEPAgent|[f]pneone|[f]ppnehost"

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _launchd_output="$(cat "${MERIDIAN_FIXTURE_DIR}/forcepoint_running.txt" 2>/dev/null || echo "")"
  _systemext_output="$(cat "${MERIDIAN_FIXTURE_DIR}/forcepoint_systemextension.txt" 2>/dev/null || echo "")"
else
  _launchd_output=""
  for _agent_id in "${_FP_AGENT_IDS[@]}"; do
    _match="$(launchctl list 2>/dev/null | grep -i "$_agent_id" || true)"
    if [ -n "$_match" ]; then
      _launchd_output="$_match"
      break
    fi
  done
  _systemext_output="$(systemextensionsctl list 2>/dev/null | grep -iE 'forcepoint|websense|fpneone|fppnehost' || true)"
fi

_proc="$(ps aux 2>/dev/null | grep -E "$_FP_PROCESS_PATTERNS" | grep -v grep | head -10 || true)"

_install_found=false
for _path in "${_FP_PATHS[@]}"; do
  if [ -e "$_path" ]; then
    _install_found=true
    break
  fi
done

_launchd_active=false
[ -n "$_launchd_output" ] && _launchd_active=true
_systemext_active=false
[ -n "$_systemext_output" ] && _systemext_active=true
_process_active=false
[ -n "$_proc" ] && _process_active=true

{
  echo "# Forcepoint — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Instalación detectada: $([ "$_install_found" = true ] && echo 'Sí' || echo 'No')"
  echo
  echo "## launchctl:"
  echo "${_launchd_output:-Ninguno}"
  echo
  echo "## Procesos:"
  echo "${_proc:-Ninguno}"
  echo
  echo "## System Extensions / Network Extensions:"
  echo "${_systemext_output:-Ninguna detectada}"
  echo
  echo "## Proxy del sistema:"
  scutil --proxy 2>/dev/null | grep -iE 'HTTPProxy|HTTPSProxy|ProxyAutoConfig' | head -10 || true
  echo
  echo "## Artefactos DLP conocidos:"
  for _path in "${_FP_PATHS[@]}"; do [ -e "$_path" ] && echo "$_path"; done
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="installed=${_install_found} process=${_process_active} launchd=${_launchd_active} systemext=${_systemext_active}"

# PASS requiere más de una señal: instalación + ejecución observable. La mera
# presencia de un helper o proceso con nombre Forcepoint no demuestra que la
# capa de red/DLP completa esté aplicando política.
if [ "$_install_found" = "true" ] && [ "$_process_active" = "true" ] && { [ "$_launchd_active" = "true" ] || [ "$_systemext_active" = "true" ]; }; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Forcepoint activo"
  RESULT_DESCRIPTION="Se detectaron artefactos de instalación y múltiples señales operativas de Forcepoint."
  RESULT_EXPLANATION="Meridian observó proceso y servicio/extensión asociados al endpoint."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_install_found" = "true" ] && { [ "$_process_active" = "true" ] || [ "$_launchd_active" = "true" ] || [ "$_systemext_active" = "true" ]; }; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Forcepoint detectado — estado operativo incompleto"
  RESULT_DESCRIPTION="Forcepoint está instalado, pero Meridian solo encontró una parte de las señales esperadas de ejecución."
  RESULT_EXPLANATION="Un proceso auxiliar, servicio o extensión aislados no bastan para demostrar que todas las políticas estén activas."
  RESULT_RISK="Protección web/DLP potencialmente degradada o indeterminada."
  RESULT_SUGGESTED_ACTION="Verificar Network Extension, servicios del endpoint, Full Disk Access requerido y estado en la consola Forcepoint."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_install_found" = "true" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Forcepoint instalado pero sin ejecución detectable"
  RESULT_DESCRIPTION="Se encontraron artefactos de Forcepoint, pero no procesos, servicios ni extensiones activas asociados."
  RESULT_EXPLANATION="El endpoint puede estar detenido, incompleto o bloqueado por permisos/extensiones de macOS."
  RESULT_RISK="Protección web/DLP no confirmada."
  RESULT_SUGGESTED_ACTION="Revisar servicios, Network Extension, Full Disk Access y despliegue del agente."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_process_active" = "true" ] || [ "$_launchd_active" = "true" ] || [ "$_systemext_active" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Señales de Forcepoint sin instalación canónica"
  RESULT_DESCRIPTION="Se observaron procesos/servicios/extensiones de Forcepoint, pero no rutas de instalación conocidas."
  RESULT_EXPLANATION="Puede tratarse de una versión con layout distinto, restos de instalación o detección parcial."
  RESULT_RISK="Estado del endpoint indeterminado."
  RESULT_SUGGESTED_ACTION="Revisar versión y layout instalado antes de concluir cumplimiento."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
else
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Forcepoint no detectado"
  RESULT_DESCRIPTION="No se encontraron artefactos ni señales operativas de Forcepoint."
  RESULT_EXPLANATION="Forcepoint puede no ser requerido para este equipo o perfil."
  RESULT_RISK="Sin protección Forcepoint si la política del equipo la exige."
  RESULT_SUGGESTED_ACTION="Verificar la política de seguridad aplicable al equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
