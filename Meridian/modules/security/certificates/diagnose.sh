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
_parse_failed_count=0

_SECURITY="/usr/bin/security"
_OPENSSL="/usr/bin/openssl"
_DATE="/bin/date"

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

# Esta frontera puede ejecutarse como root. Fijamos las utilidades nativas de
# macOS para que el entorno heredado no pueda sustituir security/openssl/date.
if [ ! -x "$_SECURITY" ] || [ ! -x "$_OPENSSL" ] || [ ! -x "$_DATE" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Herramientas de certificados no disponibles"
  RESULT_DESCRIPTION="Meridian no encontró una o más utilidades nativas requeridas para inspeccionar certificados."
  RESULT_EXPLANATION="El módulo requiere /usr/bin/security, /usr/bin/openssl y /bin/date."
  RESULT_RISK="El estado de expiración de los certificados es desconocido."
  RESULT_SUGGESTED_ACTION="Validar la integridad de las herramientas nativas de macOS."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security=$([ -x "$_SECURITY" ] && echo ok || echo missing) openssl=$([ -x "$_OPENSSL" ] && echo ok || echo missing) date=$([ -x "$_DATE" ] && echo ok || echo missing)"
  return 0
fi

# Capturar una sola vez el contenido PEM. Un resultado vacío NO debe considerarse
# cumplimiento: puede significar fallo de acceso al keychain o de `security`.
_cert_pems="$("$_SECURITY" find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null)"
_cert_rc=$?

{
  echo "# Certificados — keychain del sistema"
  echo "# Generado: $("$_DATE" '+%Y-%m-%d %H:%M:%S')"
  echo "# ---"
  "$_SECURITY" find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | \
    grep -E "labl|icsk|expi" | head -100
  echo ""
  echo "# Certificados de usuario"
  "$_SECURITY" find-certificate -a ~/Library/Keychains/login.keychain-db 2>/dev/null | \
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

_now_epoch="$("$_DATE" +%s)"

# Un certificado PEM es un registro multilínea. La implementación anterior
# imprimía bloques completos con awk pero después los consumía con `read`, que
# vuelve a dividir por líneas; openssl recibía fragmentos y todos los parseos
# fallaban. Aquí reconstruimos explícitamente cada bloque BEGIN..END en Bash 3.2
# y solo entonces lo entregamos completo a openssl.
_cert_block=""
_in_cert=false
while IFS= read -r _cert_line || [ -n "$_cert_line" ]; do
  if [ "$_cert_line" = "-----BEGIN CERTIFICATE-----" ]; then
    _cert_block="$_cert_line"
    _in_cert=true
    continue
  fi

  if [ "$_in_cert" = "true" ]; then
    _cert_block="${_cert_block}"$'\n'"${_cert_line}"

    if [ "$_cert_line" = "-----END CERTIFICATE-----" ]; then
      _expiry_str="$(printf '%s\n' "$_cert_block" | "$_OPENSSL" x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
      if [ -z "$_expiry_str" ]; then
        _parse_failed_count=$((_parse_failed_count + 1))
      else
        # OpenSSL suele devolver, por ejemplo: "May  7 12:00:00 2030 GMT".
        # %e acepta correctamente el día con espacio; mantenemos %d como fallback.
        _expiry_epoch="$("$_DATE" -j -f "%b %e %T %Y %Z" "$_expiry_str" "+%s" 2>/dev/null || \
          "$_DATE" -j -f "%b %d %T %Y %Z" "$_expiry_str" "+%s" 2>/dev/null || echo 0)"

        if [ "$_expiry_epoch" -eq 0 ] 2>/dev/null; then
          _parse_failed_count=$((_parse_failed_count + 1))
        else
          _total_count=$((_total_count + 1))
          if [ "$_expiry_epoch" -lt "$_now_epoch" ]; then
            _expired_count=$((_expired_count + 1))
          elif [ "$_expiry_epoch" -lt "$((_now_epoch + 30 * 86400))" ]; then
            _expiring_count=$((_expiring_count + 1))
          fi
        fi
      fi

      _cert_block=""
      _in_cert=false
    fi
  fi
done <<EOF
$_cert_pems
EOF

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
  RESULT_RAW_OUTPUT="security_rc=${_cert_rc} total=0 parse_failed=${_parse_failed_count}"
  return 0
fi

RESULT_RAW_OUTPUT="total=${_total_count} expired=${_expired_count} expiring_soon=${_expiring_count} parse_failed=${_parse_failed_count}"

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
elif [ "$_parse_failed_count" -gt 0 ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Inventario de certificados parcialmente interpretado"
  RESULT_DESCRIPTION="Se validaron ${_total_count} certificado(s), pero ${_parse_failed_count} bloque(s) no pudieron interpretarse."
  RESULT_EXPLANATION="Meridian no declara cumplimiento completo cuando parte del inventario no pudo evaluarse."
  RESULT_RISK="Puede existir algún certificado con estado de expiración desconocido."
  RESULT_SUGGESTED_ACTION="Revisar certificates_detail.txt y los certificados no interpretados."
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
