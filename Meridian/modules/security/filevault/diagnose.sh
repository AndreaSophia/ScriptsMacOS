#!/bin/bash
# =============================================================================
# Módulo: filevault — diagnose.sh
# Responsabilidad: verificar el estado de FileVault.
# No modifica el sistema. Solo lee.
# =============================================================================

# Obtener estado de FileVault.
# En modo test se usa el fixture; en producción se llama fdesetup.
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
  RESULT_SUGGESTED_ACTION="Verificar disponibilidad de fdesetup y revisar diagnostic.log."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  return 0
fi

# IMPORTANTE: fdesetup puede informar "FileVault is On" mientras el volumen
# todavía está cifrándose. Las transiciones deben evaluarse antes de On/Off
# para no convertir un cifrado incompleto en PASS.
if printf '%s\n' "$fv_output" | grep -qi "Encryption in progress"; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Cifrado FileVault en progreso"
  RESULT_DESCRIPTION="FileVault está habilitado, pero el cifrado del volumen aún no ha finalizado."
  RESULT_EXPLANATION="Durante la transición el disco todavía no debe considerarse completamente protegido."
  RESULT_RISK="La protección completa del volumen aún no está confirmada."
  RESULT_SUGGESTED_ACTION="Mantener el equipo encendido y conectado a energía hasta completar el cifrado; volver a validar después."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif printf '%s\n' "$fv_output" | grep -qi "Decryption in progress"; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Descifrado FileVault en progreso"
  RESULT_DESCRIPTION="El volumen está perdiendo progresivamente la protección de FileVault."
  RESULT_EXPLANATION="fdesetup reporta una transición activa de descifrado."
  RESULT_RISK="La protección de datos está siendo removida y el equipo puede quedar sin cifrado al finalizar."
  RESULT_SUGGESTED_ACTION="Investigar por qué se inició el descifrado y aplicar la política corporativa correspondiente."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

elif printf '%s\n' "$fv_output" | grep -qi "FileVault is On"; then
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

elif printf '%s\n' "$fv_output" | grep -qi "FileVault is Off"; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="CRITICAL"
  RESULT_TITLE="FileVault deshabilitado"
  RESULT_DESCRIPTION="El cifrado de disco FileVault está desactivado en este equipo."
  RESULT_EXPLANATION="Sin FileVault, los datos del disco no cuentan con cifrado completo en reposo."
  RESULT_RISK="Datos sensibles del equipo expuestos ante acceso físico no autorizado. Incumplimiento de política de seguridad corporativa."
  RESULT_SUGGESTED_ACTION="Habilitar FileVault desde Configuración del Sistema > Privacidad y seguridad > FileVault."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"

else
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Estado de FileVault indeterminado"
  RESULT_DESCRIPTION="La salida de fdesetup no pudo ser interpretada: $fv_output"
  RESULT_EXPLANATION="Puede existir un estado transitorio o una variante de salida no contemplada."
  RESULT_RISK="El estado de protección del disco no está confirmado."
  RESULT_SUGGESTED_ACTION="Revisar fdesetup status y Configuración del Sistema > Privacidad y seguridad > FileVault."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
