#!/bin/bash
# =============================================================================
# Módulo: forcepoint — diagnose.sh
# Responsabilidad: verificar el estado del agente Forcepoint Web Security.
# Detecta instalación, proceso activo y extensión de navegador.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/forcepoint_detail.txt"

# Identificadores conocidos de Forcepoint en macOS
_FP_APP_PATHS=(
  "/Applications/Forcepoint Endpoint.app"
  "/Applications/Websense Endpoint.app"
  "/Library/Application Support/Websense/wsep_mac"
)
_FP_AGENT_IDS=(
  "com.forcepoint.endpoint.agent"
  "com.websense.endpoint"
  "com.forcepoint.wse"
)
_FP_PROCESS_PATTERNS="[F]orcepoint|[W]ebsense|[w]sep"

# Modo test
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _launchd_output="$(cat "${MERIDIAN_FIXTURE_DIR}/forcepoint_running.txt" 2>/dev/null || echo "")"
else
  _launchd_output=""
  for _agent_id in "${_FP_AGENT_IDS[@]}"; do
    _match="$(launchctl list 2>/dev/null | grep -i "$_agent_id")"
    if [ -n "$_match" ]; then
      _launchd_output="$_match"
      break
    fi
  done
fi

_proc="$(ps aux 2>/dev/null | grep -E "$_FP_PROCESS_PATTERNS" | grep -v grep | head -1)"

_app_found=false
for _app in "${_FP_APP_PATHS[@]}"; do
  if [ -d "$_app" ] || [ -f "$_app" ]; then
    _app_found=true
    break
  fi
done

# Guardar evidencia
{
  echo "# Forcepoint Web Security — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## App instalada: $([ "$_app_found" = "true" ] && echo "Sí" || echo "No")"
  echo ""
  echo "## launchctl (forcepoint/websense):"
  echo "${_launchd_output:-Ninguno}"
  echo ""
  echo "## Procesos:"
  echo "${_proc:-Ninguno}"
  echo ""
  echo "## System Extensions:"
  systemextensionsctl list 2>/dev/null | grep -iE "forcepoint|websense" || echo "Ninguna"
  echo ""
  echo "## Proxy del sistema:"
  scutil --proxy 2>/dev/null | grep -iE "HTTPProxy|HTTPSProxy|ProxyAutoConfig" | head -5
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="app=${_app_found} proc=${_proc:-none} launchd=${_launchd_output:-none}"

# --- Determinar estado ---
_agent_active=false
[ -n "$_launchd_output" ] && _agent_active=true
[ -n "$_proc" ] && _agent_active=true

if [ "$_agent_active" = "true" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Forcepoint Web Security activo"
  RESULT_DESCRIPTION="El agente Forcepoint está corriendo y aplicando políticas de navegación web."
  RESULT_EXPLANATION="Forcepoint controla y filtra el tráfico HTTP/HTTPS según las políticas corporativas."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif [ "$_app_found" = "true" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Forcepoint instalado pero no activo"
  RESULT_DESCRIPTION="El agente Forcepoint está instalado pero su proceso no está corriendo."
  RESULT_EXPLANATION="El agente puede haberse detenido por un reinicio o actualización."
  RESULT_RISK="Navegación web sin filtrado corporativo activo."
  RESULT_SUGGESTED_ACTION="Reiniciar el equipo o reinstalar el agente Forcepoint."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

else
  RESULT_STATUS="SKIP"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Forcepoint no detectado"
  RESULT_DESCRIPTION="No se encontró el agente Forcepoint en este equipo."
  RESULT_EXPLANATION="Forcepoint puede no ser requerido para este equipo o perfil de usuario."
  RESULT_RISK="Sin filtrado de navegación web corporativa si este equipo lo requiere."
  RESULT_SUGGESTED_ACTION="Verificar si Forcepoint es requerido en la política de seguridad para este equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
