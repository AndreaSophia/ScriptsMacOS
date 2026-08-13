#!/bin/bash
# =============================================================================
# Módulo: filevault — diagnose.sh
# Responsabilidad: verificar el estado de FileVault.
# No modifica el sistema. Solo lee.
# =============================================================================

# Obtener estado de FileVault
# En modo test se usa el fixture; en producción se llama fdesetup
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  fv_output="$(cat "${MERIDIAN_FIXTURE_DIR}/fdesetup_disabled.txt" 2>/dev/null || echo "")"
else
  fv_output="$(fdesetup status 2>/dev/null || echo "")"
fi

RESULT_RAW_OUTPUT="$fv_output"

if [ -z "$fv_output" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudo obtener el estado de FileVault"
  RESULT_DESCRIPTION="El comando fdesetup no respondió o no está disponible."
  RESULT_EXPLANATION="fdesetup es la herramienta de macOS para gestionar FileVault."
  RESULT_RISK="Estado de cifrado desconocido."
  RESULT_SUGGESTED_ACTION="Verificar que el equipo corra macOS 14 o superior."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  return 0
fi

if echo "$fv_output" | grep -qi "FileVault is On"; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="FileVault habilitado"
  RESULT_DESCRIPTION="El cifrado de disco FileVault está activo en este equipo."
  RESULT_EXPLANATION="FileVault cifra el contenido del disco con XTS-AES-128."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif echo "$fv_output" | grep -qi "FileVault is Off"; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="FileVault deshabilitado"
  RESULT_DESCRIPTION="El cifrado de disco FileVault está desactivado en este equipo."
  RESULT_EXPLANATION="Sin FileVault, todos los datos del disco son accesibles si el equipo es robado o se arranca desde un medio externo."
  RESULT_RISK="Datos sensibles del equipo expuestos ante acceso físico no autorizado. Incumplimiento de política de seguridad corporativa."
  RESULT_SUGGESTED_ACTION="Habilitar FileVault desde Preferencias del Sistema > Privacidad y Seguridad > FileVault."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

else
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Estado de FileVault indeterminado"
  RESULT_DESCRIPTION="La salida de fdesetup no pudo ser interpretada: $fv_output"
  RESULT_EXPLANATION="Puede estar en proceso de cifrado o descifrado."
  RESULT_RISK="El estado de protección del disco no está confirmado."
  RESULT_SUGGESTED_ACTION="Revisar el estado en Preferencias del Sistema > Privacidad y Seguridad > FileVault."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
