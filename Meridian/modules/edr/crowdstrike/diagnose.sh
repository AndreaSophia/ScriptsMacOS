#!/bin/bash
# =============================================================================
# Módulo: crowdstrike — diagnose.sh
# Verifica el estado operativo de CrowdStrike Falcon sin convertir fallos de
# observación en falsos FAIL de servicio.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/crowdstrike_detail.txt"

_FALCONCTL_PATHS=(
  "/Applications/Falcon.app/Contents/Resources/falconctl"
  "/opt/CrowdStrike/falconctl"
  "/usr/local/bin/falconctl"
)

_falconctl=""
for _p in "${_FALCONCTL_PATHS[@]}"; do
  if [ -x "$_p" ]; then
    _falconctl="$_p"
    break
  fi
done
if [ -z "$_falconctl" ] && command -v falconctl >/dev/null 2>&1; then
  _falconctl="$(command -v falconctl)"
fi

_stats=""
_stats_rc=127
_stats_attempts=0
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  if [ -f "${MERIDIAN_FIXTURE_DIR}/falconctl_not_found.txt" ]; then
    _stats="$(cat "${MERIDIAN_FIXTURE_DIR}/falconctl_not_found.txt" 2>/dev/null || true)"
    _stats_rc=127
    _falconctl=""
  elif [ -f "${MERIDIAN_FIXTURE_DIR}/falconctl_retry_running.txt" ]; then
    # Fixture específico para la regresión del fallo transitorio observado en
    # corporativo: primera consulta rc=1, segundo intento rc=0 + estado válido.
    _stats_attempts=1
    _stats="$(cat "${MERIDIAN_FIXTURE_DIR}/falconctl_first_error.txt" 2>/dev/null || true)"
    _stats_rc=1
    [ -n "$_falconctl" ] || _falconctl="fixture:falconctl"
    _stats_attempts=2
    _stats="$(cat "${MERIDIAN_FIXTURE_DIR}/falconctl_retry_running.txt" 2>/dev/null || true)"
    _stats_rc=0
  elif [ -f "${MERIDIAN_FIXTURE_DIR}/falconctl_running.txt" ]; then
    _stats_attempts=1
    _stats="$(cat "${MERIDIAN_FIXTURE_DIR}/falconctl_running.txt" 2>/dev/null || true)"
    _stats_rc=0
    [ -n "$_falconctl" ] || _falconctl="fixture:falconctl"
  fi
elif [ -n "$_falconctl" ]; then
  _stats_attempts=1
  _stats="$("$_falconctl" stats 2>/dev/null)"
  _stats_rc=$?

  # En el Mac corporativo se observó un rc=1 aislado seguido, minutos después,
  # de una ejecución manual exitosa con salida operativa. Un único fallo de
  # observación no es evidencia suficiente para degradar el sensor. Reintentamos
  # una sola vez y mantenemos fail-closed si el segundo intento también falla.
  if [ "$_stats_rc" -ne 0 ]; then
    sleep 1
    _stats_attempts=2
    _stats="$("$_falconctl" stats 2>/dev/null)"
    _stats_rc=$?
  fi
fi

_app_found=false
for _app in "/Applications/Falcon.app" "/Applications/CrowdStrike Falcon.app"; do
  [ -d "$_app" ] && _app_found=true && break
done
_proc="$(ps aux 2>/dev/null | grep -iE '[F]alcon|[c]ssensor' | head -10 || true)"
_process_found=false
[ -n "$_proc" ] && _process_found=true
_systemext="$(systemextensionsctl list 2>/dev/null | grep -iE 'crowdstrike|falcon' || true)"

{
  echo "# CrowdStrike Falcon — estado"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## falconctl path: ${_falconctl:-No encontrado}"
  echo "## falconctl stats rc: ${_stats_rc}"
  echo "## falconctl stats attempts: ${_stats_attempts}"
  echo
  echo "## falconctl stats:"
  echo "${_stats:-N/A}"
  echo
  echo "## App instalada: $([ "$_app_found" = true ] && echo 'Sí' || echo 'No')"
  echo
  echo "## System Extension:"
  echo "${_systemext:-Ninguna}"
  echo
  echo "## Procesos:"
  echo "${_proc:-No detectado}"
  echo
  echo "## LaunchDaemons:"
  launchctl list 2>/dev/null | grep -iE 'crowdstrike|falcon' || echo "Ninguno"
} > "$_evidence_file" 2>/dev/null

RESULT_RAW_OUTPUT="falconctl=${_falconctl:-none} stats_rc=${_stats_rc} stats_attempts=${_stats_attempts} app=${_app_found} process=${_process_found} stats=${_stats:-empty}"

if [ "$_stats_rc" -eq 0 ] && [ -n "$_stats" ]; then
  if printf '%s\n' "$_stats" | grep -qiE 'operational.*true|State=connected|Sensor operational|Running'; then
    _sensor_ver="$(printf '%s\n' "$_stats" | grep -i 'version' | head -1 | awk '{print $NF}')"
    RESULT_STATUS="PASS"
    RESULT_SEVERITY="INFO"
    RESULT_TITLE="CrowdStrike Falcon operativo"
    RESULT_DESCRIPTION="Falcon reporta estado operativo${_sensor_ver:+ (v${_sensor_ver})}."
    RESULT_EXPLANATION="El sensor pudo ser consultado mediante falconctl."
    RESULT_RISK="N/A"
    RESULT_SUGGESTED_ACTION="N/A"
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="0"
    return 0
  fi

  if printf '%s\n' "$_stats" | grep -qiE 'RFM|Reduced Functionality'; then
    RESULT_STATUS="WARN"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="CrowdStrike Falcon en modo RFM"
    RESULT_DESCRIPTION="El sensor reporta Reduced Functionality Mode."
    RESULT_EXPLANATION="RFM implica capacidades de protección o comunicación reducidas."
    RESULT_RISK="Protección EDR degradada y posible pérdida de telemetría."
    RESULT_SUGGESTED_ACTION="Revisar conectividad, política y estado del sensor en la consola Falcon."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="0"
    return 0
  fi

  RESULT_STATUS="WARN"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="CrowdStrike Falcon respondió con estado no reconocido"
  RESULT_DESCRIPTION="falconctl respondió correctamente, pero Meridian no reconoció un estado operativo conocido."
  RESULT_EXPLANATION="Puede existir un cambio de formato/versionado o un estado degradado no contemplado."
  RESULT_RISK="Estado EDR indeterminado."
  RESULT_SUGGESTED_ACTION="Revisar la salida de evidencia y validar el sensor en la consola Falcon."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  return 0
fi

if [ -n "$_falconctl" ] && [ "$_stats_rc" -ne 0 ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="CrowdStrike Falcon instalado — consulta falconctl falló"
  RESULT_DESCRIPTION="Se encontró falconctl, pero el comando stats terminó con rc=${_stats_rc} tras ${_stats_attempts} intento(s)."
  RESULT_EXPLANATION="Un fallo de observación no demuestra que el sensor esté detenido."
  RESULT_RISK="Estado de protección no verificable desde Meridian."
  RESULT_SUGGESTED_ACTION="Revisar permisos, versión del sensor y consola Falcon antes de concluir incumplimiento."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  return 0
fi

if [ "$_app_found" = "true" ] && [ "$_process_found" = "true" ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="CrowdStrike Falcon corriendo — estado no confirmado"
  RESULT_DESCRIPTION="Se detectó instalación y proceso Falcon, pero no fue posible consultar un estado canónico."
  RESULT_EXPLANATION="La ejecución local es una señal secundaria; no confirma conexión con la consola."
  RESULT_RISK="Estado EDR parcialmente observado."
  RESULT_SUGGESTED_ACTION="Verificar que el sensor reporte correctamente en la consola Falcon."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  return 0
fi

if [ "$_app_found" = "false" ] && [ -z "$_falconctl" ] && [ "$_process_found" = "false" ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="CrowdStrike Falcon no detectado"
  RESULT_DESCRIPTION="No se encontró aplicación, falconctl ni proceso Falcon en el equipo."
  RESULT_EXPLANATION="No existen señales locales conocidas del sensor CrowdStrike Falcon."
  RESULT_RISK="Endpoint potencialmente sin protección EDR."
  RESULT_SUGGESTED_ACTION="Verificar alcance de política e instalar Falcon mediante la plataforma de gestión si corresponde."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
else
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="CrowdStrike Falcon instalado pero sin proceso detectable"
  RESULT_DESCRIPTION="Se encontraron artefactos de Falcon, pero no un proceso sensor activo."
  RESULT_EXPLANATION="El sensor puede estar detenido, incompleto o en transición de actualización."
  RESULT_RISK="Protección EDR activa no confirmada."
  RESULT_SUGGESTED_ACTION="Revisar servicios del sensor, reinicio/actualización y estado en la consola Falcon."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
