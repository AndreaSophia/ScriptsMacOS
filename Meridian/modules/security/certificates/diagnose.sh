#!/bin/bash
# =============================================================================
# Módulo: certificates — diagnose.sh
# Responsabilidad: inspeccionar el keychain del sistema buscando certificados
# expirados o próximos a expirar.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/certificates_detail.txt"
_expired_count=0
_expiring_count=0
_total_count=0

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ]; then
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Certificados del sistema en orden"
  RESULT_DESCRIPTION="No se detectaron certificados expirados en el keychain del sistema (modo test)."
  RESULT_EXPLANATION="El keychain del sistema contiene los certificados de confianza corporativos."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
  RESULT_RAW_OUTPUT="[TEST MODE] Certificates check simulated OK"
  return 0
fi

# Capturar una sola vez el contenido PEM. Un resultado vacío NO debe considerarse
# cumplimiento: puede significar fallo de acceso al keychain o de `security`.
_cert_pems="$(security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null)"
_cert_rc=$?

{
  echo "# Certificados — keychain del sistema"
  echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# ---"
  security find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | \
    grep -E "labl|icsk|expi" | head -100
  echo ""
  echo "# Certificados de usuario"
  security find-certificate -a ~/Library/Keychains/login.keychain-db 2>/dev/null | \
    grep -E "labl|icsk" | head -50
} > "$_evidence_file" 2>/dev/null

if [ "$_cert_rc" -ne 0 ] || [ -z "$_cert_pems" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudo inspeccionar el keychain del sistema"
  RESULT_DESCRIPTION="El comando security no devolvió certificados del keychain del sistema."
  RESULT_EXPLANATION="Un inventario vacío puede indicar un problema de acceso, ejecución o integridad del keychain; no debe interpretarse como cumplimiento."
  RESULT_RISK="El estado de los certificados corporativos es desconocido."
  RESULT_SUGGESTED_ACTION="Revisar diagnostic.log y validar manualmente /Library/Keychains/System.keychain."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security_rc=${_cert_rc} total=0 inspection=unavailable"
  return 0
fi

_now_epoch="$(date +%s)"

# Separar cada PEM de forma compatible con awk/BSD de macOS. El total se cuenta
# exclusivamente aquí para evitar el doble conteo que producía la versión previa.
while IFS= read -r _cert_pem; do
  [ -z "$_cert_pem" ] && continue

  _expiry_str="$(printf '%s\n' "$_cert_pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
  [ -z "$_expiry_str" ] && continue

  _expiry_epoch="$(date -j -f "%b %d %T %Y %Z" "$_expiry_str" "+%s" 2>/dev/null || echo 0)"
  [ "$_expiry_epoch" -eq 0 ] 2>/dev/null && continue

  _total_count=$((_total_count + 1))

  if [ "$_expiry_epoch" -lt "$_now_epoch" ]; then
    _expired_count=$((_expired_count + 1))
  elif [ "$_expiry_epoch" -lt "$((_now_epoch + 30 * 86400))" ]; then
    _expiring_count=$((_expiring_count + 1))
  fi
done < <(printf '%s\n' "$_cert_pems" | awk '
  /-----BEGIN CERTIFICATE-----/ { cert=$0; in_cert=1; next }
  in_cert { cert=cert "\n" $0 }
  /-----END CERTIFICATE-----/ { print cert; cert=""; in_cert=0 }
')

# Si había PEMs pero ninguno pudo parsearse, tampoco es seguro devolver PASS.
if [ "$_total_count" -eq 0 ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudieron interpretar los certificados del sistema"
  RESULT_DESCRIPTION="El keychain devolvió datos, pero Meridian no pudo obtener fechas válidas de ningún certificado."
  RESULT_EXPLANATION="Puede existir una incompatibilidad de formato o un problema con openssl/date."
  RESULT_RISK="El estado de expiración de los certificados es desconocido."
  RESULT_SUGGESTED_ACTION="Revisar certificates_detail.txt y validar el parser en un Mac de laboratorio."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security_rc=${_cert_rc} total=0 parse=failed"
  return 0
fi

RESULT_RAW_OUTPUT="total=${_total_count} expired=${_expired_count} expiring_soon=${_expiring_count}"

if [ "$_expired_count" -gt 0 ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="${_expired_count} certificado(s) expirado(s) detectado(s)"
  RESULT_DESCRIPTION="Se encontraron ${_expired_count} certificado(s) expirado(s) en el keychain del sistema."
  RESULT_EXPLANATION="Los certificados expirados pueden causar fallos de autenticación, problemas de TLS y rechazo en servicios corporativos."
  RESULT_RISK="Posibles fallos de autenticación en servicios corporativos, VPN o WiFi 802.1X."
  RESULT_SUGGESTED_ACTION="Renovar los certificados expirados desde el portal PKI corporativo o contactar al equipo de seguridad."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
elif [ "$_expiring_count" -gt 0 ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="${_expiring_count} certificado(s) próximo(s) a expirar (< 30 días)"
  RESULT_DESCRIPTION="${_expiring_count} certificado(s) expiran en menos de 30 días."
  RESULT_EXPLANATION="Los certificados próximos a expirar deben renovarse antes de causar interrupciones."
  RESULT_RISK="Posible interrupción de servicios al expirar los certificados."
  RESULT_SUGGESTED_ACTION="Iniciar proceso de renovación de certificados con el equipo de PKI."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
else
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Certificados del sistema en orden"
  RESULT_DESCRIPTION="No se detectaron certificados expirados en el keychain del sistema (${_total_count} verificados)."
  RESULT_EXPLANATION="El keychain del sistema contiene certificados con fechas de validez correctas."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="0"
fi
