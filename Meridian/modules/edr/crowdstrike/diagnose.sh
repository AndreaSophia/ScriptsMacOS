#!/bin/bash
# =============================================================================
# Módulo: crowdstrike — diagnose.sh
# Responsabilidad: verificar el estado operativo del sensor Falcon.
# Usa múltiples métodos de detección para máxima compatibilidad.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/crowdstrike_detail.txt"

# Rutas conocidas de falconctl
_FALCONCTL_PATHS=(
  "/Applications/Falcon.app/Contents/Resources/falconctl"
  "/opt/CrowdStrike/falconctl"
  "/usr/local/bin/falconctl"
)

# Detectar falconctl
_falconctl=""
for _p in "${_FALCONCTL_PATHS[@]}"; do
  if [ -x "$_p" ]; then
    _falconctl="$_p"
    break
  fi
done
command -v falconctl >/dev/null 2>&1 && _falconctl="falconctl"

# En modo test, usar fixtures
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _fixture="${MERIDIAN_FIXTURE_DIR}/falconctl_running.txt"
  [ -f "${MERIDIAN_FIXTURE_DIR}/falconctl_not_found.txt" ] && \
    _fixture="${MERIDIAN_FIXTURE_DIR}/falconctl_not_found.txt"
  _stats="$(cat "$_fixture" 2>/dev/null || echo "")"
else
  _stats=""
  [ -n "$_falconctl" ] && _stats="$("$_falconctl" stats 2>/dev/null || echo "")"
fi

# Guardar evidencia
{
  echo "# CrowdStrike Falcon — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## falconctl path: ${_falconctl:-No encontrado}"
  echo ""
  echo "## falconctl stats:"
  echo "${_stats:-N/A}"
  echo ""
  echo "## App instalada:"
  for _app in "/Applications/Falcon.app" "/Applications/CrowdStrike Falcon.app"; do
    [ -d "$_app" ] && echo "$_app" || true
  done
  echo ""
  echo "## System Extension:"
  systemextensionsctl list 2>/dev/null | grep -iE "crowdstrike|falcon" || echo "Ninguna"
  echo ""
  echo "## Proceso:"
  ps aux 2>/dev/null | grep -iE "[F]alcon|[c]ssensor" || echo "No detectado"
  echo ""
  echo "## LaunchDaemons:"
  launchctl list 2>/dev/null | grep -iE "crowdstrike|falcon" || echo "Ninguno"
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="falconctl=${_falconctl:-none} stats=${_stats:-empty}"

# --- Determinar estado ---

# Caso 1: falconctl disponible y reporta estado
if [ -n "$_stats" ]; then
  if echo "$_stats" | grep -qiE "operational.*true|State=connected|Sensor operational|Running"; then
    _sensor_ver="$(echo "$_stats" | grep -i "version" | head -1 | awk '{print $NF}')"
    RESULT_STATUS="PASS"
    RESULT_SEVERITY="INFO"
    RESULT_TITLE="CrowdStrike Falcon operativo"
    RESULT_DESCRIPTION="El sensor Falcon está corriendo y conectado${_sensor_ver:+ (v${_sensor_ver})}."
    RESULT_EXPLANATION="Falcon protege el endpoint con detección y respuesta en tiempo real."
    RESULT_RISK="N/A"
    RESULT_SUGGESTED_ACTION="N/A"
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="0"
    return 0
  fi

  if echo "$_stats" | grep -qiE "RFM|Reduced Functionality"; then
    RESULT_STATUS="WARN"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="CrowdStrike Falcon en modo RFM"
    RESULT_DESCRIPTION="El sensor está en Reduced Functionality Mode (RFM) — capacidades de protección limitadas."
    RESULT_EXPLANATION="RFM ocurre cuando el sensor no puede comunicarse con la consola o hay un problema de configuración."
    RESULT_RISK="Protección EDR reducida. El endpoint puede no estar reportando eventos a la consola."
    RESULT_SUGGESTED_ACTION="Verificar conectividad con cloud.crowdstrike.com y revisar la consola Falcon para detalles del sensor."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="0"
    return 0
  fi
fi

# Caso 2: App instalada pero falconctl no responde
_app_found=false
for _app in "/Applications/Falcon.app" "/Applications/CrowdStrike Falcon.app"; do
  [ -d "$_app" ] && _app_found=true && break
done

_proc="$(ps aux 2>/dev/null | grep -iE "[F]alcon|[c]ssensor" | grep -v grep | head -1)"

if [ "$_app_found" = "true" ] && [ -n "$_proc" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="CrowdStrike Falcon corriendo — estado no confirmado"
  RESULT_DESCRIPTION="Proceso Falcon detectado pero falconctl no pudo confirmar el estado operativo."
  RESULT_EXPLANATION="Posible fallo en la comunicación del sensor con la consola, o versión sin soporte de stats."
  RESULT_RISK="Estado de protección indeterminado."
  RESULT_SUGGESTED_ACTION="Revisar la consola Falcon para verificar que el sensor reporta correctamente."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  return 0
fi

# Caso 3: No instalado o no corriendo
if [ "$_app_found" = "false" ] && [ -z "$_falconctl" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="CrowdStrike Falcon no instalado"
  RESULT_DESCRIPTION="No se encontró Falcon.app ni falconctl en este equipo."
  RESULT_EXPLANATION="El sensor CrowdStrike Falcon es requerido por política de seguridad corporativa."
  RESULT_RISK="Endpoint sin protección EDR. Incumplimiento de política de seguridad."
  RESULT_SUGGESTED_ACTION="Instalar el sensor Falcon mediante Workspace ONE o Jamf."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
else
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="CrowdStrike Falcon instalado pero no corriendo"
  RESULT_DESCRIPTION="Falcon está instalado pero el proceso sensor no está activo."
  RESULT_EXPLANATION="El sensor puede haberse detenido por una actualización fallida, conflicto de kernel extension o error de configuración."
  RESULT_RISK="Endpoint sin protección EDR activa. Posible incidente de seguridad no detectado."
  RESULT_SUGGESTED_ACTION="Reiniciar el equipo. Si persiste, reinstalar el sensor desde la consola Falcon o contactar al equipo de seguridad."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
