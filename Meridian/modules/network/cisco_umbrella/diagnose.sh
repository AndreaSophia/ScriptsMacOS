#!/bin/bash
# =============================================================================
# Módulo: cisco_umbrella — diagnose.sh
# Responsabilidad: verificar que Cisco Umbrella esté instalado y operativo.
# Umbrella puede desplegarse como agente o como configuración DNS (208.67.222.222).
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/cisco_umbrella_detail.txt"

# Rutas y identificadores conocidos de Umbrella en macOS
_UMBRELLA_APP="/Applications/Cisco Umbrella Roaming Security.app"
_UMBRELLA_AGENT_ID="com.cisco.umbrella.agent"
_UMBRELLA_LAUNCHDAEMON="/Library/LaunchDaemons/com.cisco.umbrella.agent.plist"
_UMBRELLA_DNS_IPS="208.67.222.222 208.67.220.220 208.67.222.123"

# Modo test
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _launchd_output="$(cat "${MERIDIAN_FIXTURE_DIR}/umbrella_running.txt" 2>/dev/null || echo "")"
else
  _launchd_output="$(launchctl list 2>/dev/null | grep -i "$_UMBRELLA_AGENT_ID" || echo "")"
fi

# Guardar evidencia
{
  echo "# Cisco Umbrella — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## App instalada: $([ -d "$_UMBRELLA_APP" ] && echo "Sí" || echo "No")"
  echo "## LaunchDaemon: $([ -f "$_UMBRELLA_LAUNCHDAEMON" ] && echo "Presente" || echo "No encontrado")"
  echo ""
  echo "## launchctl list (umbrella):"
  echo "${_launchd_output:-Ninguno}"
  echo ""
  echo "## DNS configurado:"
  scutil --dns 2>/dev/null | grep -i "nameserver" | head -10 || echo "N/A"
  echo ""
  echo "## Procesos Umbrella:"
  ps aux 2>/dev/null | grep -i "[u]mbrella" || echo "Ninguno"
} > "$_evidence_file" 2>/dev/null

# Verificar DNS de Umbrella como señal secundaria
_umbrella_dns=false
for _dns_ip in $_UMBRELLA_DNS_IPS; do
  if scutil --dns 2>/dev/null | grep -q "$_dns_ip"; then
    _umbrella_dns=true
    break
  fi
done

RESULT_RAW_OUTPUT="launchd=${_launchd_output:-none} umbrella_dns=${_umbrella_dns} app=$([ -d "$_UMBRELLA_APP" ] && echo 1 || echo 0)"

# --- Determinar estado ---
_agent_running=false
echo "$_launchd_output" | grep -qi "running\|${_UMBRELLA_AGENT_ID}" && _agent_running=true

if [ "$_agent_running" = "true" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Cisco Umbrella activo"
  RESULT_DESCRIPTION="El agente Cisco Umbrella está corriendo y protegiendo las consultas DNS."
  RESULT_EXPLANATION="Umbrella filtra el tráfico DNS para bloquear dominios maliciosos antes de que se establezca la conexión."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif [ -d "$_UMBRELLA_APP" ] || [ -f "$_UMBRELLA_LAUNCHDAEMON" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Cisco Umbrella instalado pero no corriendo"
  RESULT_DESCRIPTION="El agente Umbrella está instalado pero su proceso no está activo."
  RESULT_EXPLANATION="El agente puede haberse detenido por una actualización o conflicto de sistema."
  RESULT_RISK="Tráfico DNS sin filtrado. El equipo puede acceder a dominios maliciosos."
  RESULT_SUGGESTED_ACTION="Reiniciar el servicio o reinstalar el agente desde Workspace ONE."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif [ "$_umbrella_dns" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Cisco Umbrella — solo DNS configurado (sin agente)"
  RESULT_DESCRIPTION="Se detectaron servidores DNS de Umbrella pero no hay agente instalado."
  RESULT_EXPLANATION="La protección DNS sin agente es menos robusta y puede evadirse fácilmente."
  RESULT_RISK="Protección DNS parcial — sin visibilidad de identidad ni control granular por usuario."
  RESULT_SUGGESTED_ACTION="Instalar el agente Umbrella completo mediante Workspace ONE."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

else
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Cisco Umbrella no detectado"
  RESULT_DESCRIPTION="No se encontró el agente Cisco Umbrella ni configuración DNS de Umbrella en este equipo."
  RESULT_EXPLANATION="Umbrella puede no estar incluido en el perfil de seguridad de este equipo o red."
  RESULT_RISK="Sin protección DNS de nivel corporativo si este equipo lo requiere."
  RESULT_SUGGESTED_ACTION="Verificar si Umbrella es requerido para este equipo en la política de seguridad."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
