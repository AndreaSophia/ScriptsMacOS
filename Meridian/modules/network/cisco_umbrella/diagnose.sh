#!/bin/bash
# =============================================================================
# Módulo: cisco_umbrella — diagnose.sh
# Verifica Cisco Secure Client + Umbrella en macOS y conserva detección legacy.
# Cisco migró Umbrella al Secure Client; el roaming client legacy ya no debe ser
# la única señal de instalación.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/cisco_umbrella_detail.txt"

_UMBRELLA_LEGACY_APP="/Applications/Cisco Umbrella Roaming Security.app"
_UMBRELLA_LEGACY_LAUNCHDAEMON="/Library/LaunchDaemons/com.cisco.umbrella.agent.plist"
_CSC_APP="/Applications/Cisco/Cisco Secure Client.app"
_CSC_UMBRELLA_DIRS=(
  "/opt/cisco/secureclient/Umbrella"
  "/opt/cisco/secureclient/umbrella"
)
_CSC_SOCKET_FILTER="/Applications/Cisco/Cisco Secure Client - Socket Filter.app"
_CSC_SYSTEM_EXTENSION_ID="com.cisco.anyconnect.macos.acsockext"
_UMBRELLA_DNS_IPS="208.67.222.222 208.67.220.220 208.67.222.123"

_secure_client_found=false
_umbrella_module_found=false
_legacy_found=false
_socket_filter_found=false
_launchd_output=""
_systemext_output=""
_dns_output=""
_proc_output=""

_fixture_true() {
  local file="$1"
  local value=""
  [ -f "$file" ] || return 1
  value="$(cat "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|si|sí|present|installed|active) return 0 ;;
  esac
  return 1
}

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  # El sandbox debe depender exclusivamente de fixtures explícitos. No se
  # consultan aplicaciones, procesos, DNS ni extensiones del Mac anfitrión.
  _fixture_true "${MERIDIAN_FIXTURE_DIR}/umbrella_secure_client.txt" && _secure_client_found=true
  _fixture_true "${MERIDIAN_FIXTURE_DIR}/umbrella_module.txt" && _umbrella_module_found=true
  _fixture_true "${MERIDIAN_FIXTURE_DIR}/umbrella_legacy.txt" && _legacy_found=true
  _fixture_true "${MERIDIAN_FIXTURE_DIR}/umbrella_socket_filter.txt" && _socket_filter_found=true

  _launchd_output="$(cat "${MERIDIAN_FIXTURE_DIR}/umbrella_running.txt" 2>/dev/null || echo "")"
  _systemext_output="$(cat "${MERIDIAN_FIXTURE_DIR}/umbrella_systemextension.txt" 2>/dev/null || echo "")"
  _dns_output="$(cat "${MERIDIAN_FIXTURE_DIR}/umbrella_dns.txt" 2>/dev/null || echo "")"
  _proc_output="$(cat "${MERIDIAN_FIXTURE_DIR}/umbrella_processes.txt" 2>/dev/null || echo "")"
else
  [ -d "$_CSC_APP" ] && _secure_client_found=true

  for _dir in "${_CSC_UMBRELLA_DIRS[@]}"; do
    [ -d "$_dir" ] && _umbrella_module_found=true && break
  done

  [ -d "$_UMBRELLA_LEGACY_APP" ] && _legacy_found=true
  [ -f "$_UMBRELLA_LEGACY_LAUNCHDAEMON" ] && _legacy_found=true
  [ -d "$_CSC_SOCKET_FILTER" ] && _socket_filter_found=true

  _launchd_output="$(launchctl list 2>/dev/null | grep -iE 'com\.cisco\.(umbrella|secureclient)' || true)"
  _systemext_output="$(systemextensionsctl list 2>/dev/null | grep -iE "${_CSC_SYSTEM_EXTENSION_ID}|cisco.*secure.*client|umbrella" || true)"
  _dns_output="$(scutil --dns 2>/dev/null || true)"
  _proc_output="$(ps aux 2>/dev/null | grep -iE '[u]mbrella|[c]isco.*secure.*client|[a]csock' || true)"
fi

_umbrella_dns=false
for _dns_ip in $_UMBRELLA_DNS_IPS; do
  printf '%s\n' "$_dns_output" | grep -Fq "$_dns_ip" && { _umbrella_dns=true; break; }
done

_agent_running=false
if printf '%s\n%s\n%s\n' "$_launchd_output" "$_systemext_output" "$_proc_output" | grep -qiE 'umbrella|secureclient|acsockext|cisco.*secure.*client'; then
  _agent_running=true
fi

{
  echo "# Cisco Umbrella — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# Fuente: $([ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && echo 'fixtures simulados' || echo 'sistema real')"
  echo
  echo "## Cisco Secure Client: $([ "$_secure_client_found" = true ] && echo 'Sí' || echo 'No')"
  echo "## Módulo Umbrella: $([ "$_umbrella_module_found" = true ] && echo 'Presente' || echo 'No detectado')"
  echo "## Cliente legacy: $([ "$_legacy_found" = true ] && echo 'Presente' || echo 'No')"
  echo "## Socket Filter: $([ "$_socket_filter_found" = true ] && echo 'Presente' || echo 'No detectado')"
  echo
  echo "## launchctl (Cisco):"
  echo "${_launchd_output:-Ninguno}"
  echo
  echo "## System Extension:"
  echo "${_systemext_output:-Ninguna}"
  echo
  echo "## DNS configurado:"
  printf '%s\n' "$_dns_output" | grep -i 'nameserver' | head -10 || true
  echo
  echo "## Procesos Cisco/Umbrella:"
  echo "${_proc_output:-Ninguno}"
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="secure_client=${_secure_client_found} umbrella_module=${_umbrella_module_found} legacy=${_legacy_found} active=${_agent_running} umbrella_dns=${_umbrella_dns}"

if [ "$_umbrella_module_found" = "true" ] && [ "$_agent_running" = "true" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Cisco Secure Client Umbrella activo"
  RESULT_DESCRIPTION="Se detectó el módulo Umbrella de Cisco Secure Client y señales de ejecución del cliente/extensión."
  RESULT_EXPLANATION="Umbrella forma parte de Cisco Secure Client en despliegues actuales de macOS."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_umbrella_module_found" = "true" ] || [ "$_secure_client_found" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Cisco Secure Client detectado — Umbrella no confirmado"
  RESULT_DESCRIPTION="Cisco Secure Client está instalado, pero Meridian no pudo confirmar simultáneamente el módulo Umbrella y su ejecución."
  RESULT_EXPLANATION="La aplicación base puede existir sin el módulo Umbrella o con la extensión de red inactiva."
  RESULT_RISK="Protección DNS corporativa indeterminada."
  RESULT_SUGGESTED_ACTION="Verificar el módulo Umbrella, la extensión de red de Cisco y el estado del cliente en el equipo/consola."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_legacy_found" = "true" ] && [ "$_agent_running" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Umbrella Roaming Client legacy activo"
  RESULT_DESCRIPTION="Se detectó el cliente Umbrella legacy en ejecución."
  RESULT_EXPLANATION="Los despliegues modernos de macOS deben usar el módulo Umbrella de Cisco Secure Client."
  RESULT_RISK="Cliente legacy fuera de la arquitectura actual de Cisco Secure Client."
  RESULT_SUGGESTED_ACTION="Planificar o verificar la migración a Cisco Secure Client con módulo Umbrella."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_legacy_found" = "true" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Umbrella legacy instalado pero no activo"
  RESULT_DESCRIPTION="Se detectaron artefactos del cliente Umbrella legacy sin señales de ejecución."
  RESULT_EXPLANATION="El agente puede estar detenido o incompleto."
  RESULT_RISK="Protección DNS corporativa no confirmada."
  RESULT_SUGGESTED_ACTION="Verificar estado del endpoint y migración a Cisco Secure Client."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_umbrella_dns" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="DNS de Umbrella detectado sin agente"
  RESULT_DESCRIPTION="Se detectaron resolvers públicos asociados a Umbrella, pero no el módulo de endpoint."
  RESULT_EXPLANATION="La presencia de esos resolvers no demuestra por sí sola que el endpoint esté gestionado por Umbrella."
  RESULT_RISK="Protección e identidad de endpoint no confirmadas."
  RESULT_SUGGESTED_ACTION="Verificar si el módulo Umbrella de Cisco Secure Client es requerido para este equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
else
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Cisco Umbrella no detectado"
  RESULT_DESCRIPTION="No se encontraron artefactos del módulo Umbrella, cliente legacy ni DNS asociados."
  RESULT_EXPLANATION="El módulo puede no estar incluido en el perfil de seguridad de este equipo."
  RESULT_RISK="Sin protección DNS corporativa si este equipo la requiere."
  RESULT_SUGGESTED_ACTION="Verificar la política de seguridad aplicable al equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
