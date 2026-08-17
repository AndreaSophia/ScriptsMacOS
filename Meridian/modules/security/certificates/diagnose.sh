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
_abnormal_evidence=""

_SECURITY="/usr/bin/security"
_OPENSSL="/usr/bin/openssl"
_DATE="/bin/date"
_SED="/usr/bin/sed"
_GREP="/usr/bin/grep"
_HEAD="/usr/bin/head"

_fixture_pem=""
_fixture_mode=false
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ]; then
  _fixture_pem="${MERIDIAN_FIXTURE_DIR}/security_certs.pem"
  [ -f "$_fixture_pem" ] && _fixture_mode=true
fi

# El modo test histórico sigue siendo un PASS simulado cuando no se proporciona
# un fixture PEM explícito. Esto preserva los flujos existentes; el fixture PEM
# permite ejercitar de verdad el parser sin consultar keychains del host.
if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ "$_fixture_mode" != "true" ]; then
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
  RESULT_EVIDENCE=""
  return 0
fi

# Esta frontera puede ejecutarse desde una sesión privilegiada. Fijamos las
# utilidades nativas para que un PATH heredado no sustituya parser o filtros.
_tools_ok=true
for _tool in "$_OPENSSL" "$_DATE" "$_SED" "$_GREP" "$_HEAD"; do
  [ -x "$_tool" ] || _tools_ok=false
done
if [ "$_fixture_mode" != "true" ] && [ ! -x "$_SECURITY" ]; then
  _tools_ok=false
fi

if [ "$_tools_ok" != "true" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Herramientas de certificados no disponibles"
  RESULT_DESCRIPTION="Meridian no encontró una o más utilidades nativas requeridas para inspeccionar certificados."
  RESULT_EXPLANATION="El módulo requiere utilidades nativas de macOS para obtener y analizar certificados."
  RESULT_RISK="El estado de expiración de los certificados es desconocido."
  RESULT_SUGGESTED_ACTION="Validar la integridad de las herramientas nativas de macOS."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security=$([ -x "$_SECURITY" ] && echo ok || echo missing) openssl=$([ -x "$_OPENSSL" ] && echo ok || echo missing) date=$([ -x "$_DATE" ] && echo ok || echo missing)"
  RESULT_EVIDENCE=""
  return 0
fi

if [ "$_fixture_mode" = "true" ]; then
  _cert_pems="$(< "$_fixture_pem")"
  _cert_rc=$?
  {
    echo "# Certificados — fixture de regresión"
    echo "# Generado: $("$_DATE" '+%Y-%m-%d %H:%M:%S')"
    echo "# Fuente: ${_fixture_pem}"
    echo "# ---"
  } > "$_evidence_file" 2>/dev/null
else
  # Capturar una sola vez el contenido PEM. Un resultado vacío NO debe
  # considerarse cumplimiento: puede significar fallo de acceso al keychain.
  _cert_pems="$("$_SECURITY" find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null)"
  _cert_rc=$?

  {
    echo "# Certificados — keychain del sistema"
    echo "# Generado: $("$_DATE" '+%Y-%m-%d %H:%M:%S')"
    echo "# ---"
    "$_SECURITY" find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | \
      "$_GREP" -E "labl|icsk|expi" | "$_HEAD" -100
    echo ""
    echo "# Certificados de usuario"
    "$_SECURITY" find-certificate -a ~/Library/Keychains/login.keychain-db 2>/dev/null | \
      "$_GREP" -E "labl|icsk" | "$_HEAD" -50
    echo ""
    echo "# Resultado de vigencia parseado"
  } > "$_evidence_file" 2>/dev/null
fi

if [ "$_cert_rc" -ne 0 ] || [ -z "$_cert_pems" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudo inspeccionar el keychain del sistema"
  RESULT_DESCRIPTION="La fuente de certificados no devolvió certificados para analizar."
  RESULT_EXPLANATION="Un inventario vacío puede indicar un problema de acceso, ejecución o integridad; no debe interpretarse como cumplimiento."
  RESULT_RISK="El estado de los certificados corporativos es desconocido."
  RESULT_SUGGESTED_ACTION="Revisar diagnostic.log y validar manualmente la fuente de certificados."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security_rc=${_cert_rc} total=0 inspection=unavailable"
  RESULT_EVIDENCE=""
  return 0
fi

_now_epoch="$("$_DATE" +%s)"

_append_abnormal_evidence() {
  local _line="$1"
  if [ -n "$_abnormal_evidence" ]; then
    _abnormal_evidence="${_abnormal_evidence}"$'\n'"${_line}"
  else
    _abnormal_evidence="$_line"
  fi
}

# Un certificado PEM es un registro multilínea. Reconstruimos explícitamente
# cada bloque BEGIN..END en Bash 3.2 y solo entonces lo entregamos a openssl.
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
      _cert_meta="$(printf '%s\n' "$_cert_block" | "$_OPENSSL" x509 -noout -subject -enddate 2>/dev/null)"
      _expiry_str="$(printf '%s\n' "$_cert_meta" | "$_SED" -n 's/^notAfter=//p' | "$_HEAD" -1)"
      _subject_str="$(printf '%s\n' "$_cert_meta" | "$_SED" -n 's/^subject=//p' | "$_HEAD" -1)"
      [ -n "$_subject_str" ] || _subject_str="(subject no disponible)"

      if [ -z "$_expiry_str" ]; then
        _parse_failed_count=$((_parse_failed_count + 1))
        printf '%s\n' "PARSE_FAILED | subject=${_subject_str}" >> "$_evidence_file" 2>/dev/null
      else
        # OpenSSL suele devolver, por ejemplo: "May  7 12:00:00 2030 GMT".
        # %e acepta correctamente el día con espacio; mantenemos %d como fallback.
        _expiry_epoch="$("$_DATE" -j -f "%b %e %T %Y %Z" "$_expiry_str" "+%s" 2>/dev/null || \
          "$_DATE" -j -f "%b %d %T %Y %Z" "$_expiry_str" "+%s" 2>/dev/null || echo 0)"

        if [ "$_expiry_epoch" -eq 0 ] 2>/dev/null; then
          _parse_failed_count=$((_parse_failed_count + 1))
          printf '%s\n' "PARSE_FAILED | subject=${_subject_str} | notAfter=${_expiry_str}" >> "$_evidence_file" 2>/dev/null
        else
          _total_count=$((_total_count + 1))
          _cert_state="VALID"
          if [ "$_expiry_epoch" -lt "$_now_epoch" ]; then
            _expired_count=$((_expired_count + 1))
            _cert_state="EXPIRED"
            _append_abnormal_evidence "EXPIRED | subject=${_subject_str} | notAfter=${_expiry_str}"
          elif [ "$_expiry_epoch" -lt "$((_now_epoch + 30 * 86400))" ]; then
            _expiring_count=$((_expiring_count + 1))
            _cert_state="EXPIRING_SOON"
            _append_abnormal_evidence "EXPIRING_SOON | subject=${_subject_str} | notAfter=${_expiry_str}"
          fi
          printf '%s\n' "${_cert_state} | subject=${_subject_str} | notAfter=${_expiry_str}" >> "$_evidence_file" 2>/dev/null
        fi
      fi

      _cert_block=""
      _in_cert=false
    fi
  fi
done <<EOF
$_cert_pems
EOF

if [ "$_parse_failed_count" -gt 0 ]; then
  _append_abnormal_evidence "PARSE_FAILED | count=${_parse_failed_count}"
fi

# Si había PEMs pero ninguno pudo parsearse, tampoco es seguro devolver PASS.
if [ "$_total_count" -eq 0 ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudieron interpretar los certificados del sistema"
  RESULT_DESCRIPTION="La fuente devolvió datos, pero Meridian no pudo obtener fechas válidas de ningún certificado."
  RESULT_EXPLANATION="Puede existir una incompatibilidad de formato o un problema con openssl/date."
  RESULT_RISK="El estado de expiración de los certificados es desconocido."
  RESULT_SUGGESTED_ACTION="Revisar certificates_detail.txt y validar el parser en un Mac de laboratorio."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  RESULT_RAW_OUTPUT="security_rc=${_cert_rc} total=0 parse_failed=${_parse_failed_count}"
  RESULT_EVIDENCE="$_abnormal_evidence"
  return 0
fi

RESULT_RAW_OUTPUT="total=${_total_count} expired=${_expired_count} expiring_soon=${_expiring_count} parse_failed=${_parse_failed_count}"
RESULT_EVIDENCE="$_abnormal_evidence"

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
  RESULT_EVIDENCE=""
fi
