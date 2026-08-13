#!/bin/bash
# =============================================================================
# Módulo: certificates — diagnose.sh
# Responsabilidad: inspeccionar el keychain del sistema buscando certificados
# expirados o próximos a expirar, y verificar la presencia de CAs corporativas.
# =============================================================================

_evidence_file="${MERIDIAN_EVIDENCE_DIR}/certificates_detail.txt"
_expired_count=0
_expiring_count=0
_total_count=0
_raw=""

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ]; then
  # En modo test: simular un certificado válido
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

# Listar certificados del keychain del sistema con fechas de expiración
_cert_list="$(security find-certificate -a -p /Library/Keychains/System.keychain \
  2>/dev/null | \
  openssl x509 -noout -subject -dates 2>/dev/null || echo "")"

# Guardar evidencia completa
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

_raw="$(security find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | \
  grep "labl" | wc -l | tr -d ' ')"
_total_count="${_raw:-0}"

# Verificar certificados expirados via openssl
_now_epoch="$(date +%s)"
while IFS= read -r cert_pem; do
  [ -z "$cert_pem" ] && continue
  local expiry_str
  expiry_str="$(echo "$cert_pem" | openssl x509 -noout -enddate 2>/dev/null | \
    sed 's/notAfter=//')"
  [ -z "$expiry_str" ] && continue

  local expiry_epoch
  expiry_epoch="$(date -j -f "%b %d %T %Y %Z" "$expiry_str" "+%s" 2>/dev/null || echo 0)"
  [ "$expiry_epoch" -eq 0 ] && continue

  _total_count=$(( _total_count + 1 ))

  if [ "$expiry_epoch" -lt "$_now_epoch" ]; then
    _expired_count=$(( _expired_count + 1 ))
  elif [ "$expiry_epoch" -lt "$(( _now_epoch + 30 * 86400 ))" ]; then
    _expiring_count=$(( _expiring_count + 1 ))
  fi
done < <(security find-certificate -a -p /Library/Keychains/System.keychain \
  2>/dev/null | awk '/-----BEGIN/,/-----END/' | \
  awk 'BEGIN{p=""} /-----BEGIN/{p=$0; next} /-----END/{print p"\n"$0; p=""; next} {p=p"\n"$0}')

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
