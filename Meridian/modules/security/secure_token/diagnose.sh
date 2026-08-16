#!/bin/bash
# =============================================================================
# Módulo: secure_token — diagnose.sh
# Responsabilidad: inventariar administradores locales humanos y consultar
# Secure Token sin modificar el sistema.
# =============================================================================

_DSCL="/usr/bin/dscl"
_SYSADMINCTL="/usr/sbin/sysadminctl"

if [ "${MERIDIAN_TEST_MODE:-0}" != "1" ]; then
  [ -x "$_DSCL" ] || {
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="dscl no disponible"
    RESULT_DESCRIPTION="No se puede enumerar de forma confiable el grupo local admin."
    RESULT_EXPLANATION="Meridian requiere la herramienta nativa dscl para consultar el directorio local."
    RESULT_RISK="El estado de administradores y Secure Token permanece desconocido."
    RESULT_SUGGESTED_ACTION="Verificar la integridad de /usr/bin/dscl."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="1"
    return 0
  }
  [ -x "$_SYSADMINCTL" ] || {
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="sysadminctl no disponible"
    RESULT_DESCRIPTION="No se puede consultar Secure Token de forma confiable."
    RESULT_EXPLANATION="Apple expone la gestión/consulta de Secure Token mediante sysadminctl."
    RESULT_RISK="El estado de Secure Token permanece desconocido."
    RESULT_SUGGESTED_ACTION="Verificar la integridad de /usr/sbin/sysadminctl."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="1"
    return 0
  }
fi

admins=""
raw=""

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_FIXTURE_DIR:-}" ] && [ -f "${MERIDIAN_FIXTURE_DIR}/secure_token_admins.txt" ]; then
  while IFS='|' read -r user uid token_state; do
    [ -n "$user" ] || continue
    admins="${admins}${user}|${uid}|${token_state}"$'\n'
  done < "${MERIDIAN_FIXTURE_DIR}/secure_token_admins.txt"
else
  admin_line="$("$_DSCL" /Local/Default -read /Groups/admin GroupMembership 2>/dev/null)"
  raw="$admin_line"
  case "$admin_line" in
    GroupMembership:*) admin_members="${admin_line#GroupMembership: }" ;;
    *) admin_members="" ;;
  esac

  for user in $admin_members; do
    # Excluir cuentas de sistema; el objetivo es inventariar administradores
    # humanos/locales que realmente participan en flujos de Secure Token.
    case "$user" in
      root|daemon|nobody|_*) continue ;;
    esac

    uid_line="$("$_DSCL" /Local/Default -read "/Users/${user}" UniqueID 2>/dev/null)"
    case "$uid_line" in
      UniqueID:*) uid="${uid_line#UniqueID: }" ;;
      *) continue ;;
    esac

    case "$uid" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$uid" -ge 500 ] 2>/dev/null || continue

    token_output="$("$_SYSADMINCTL" -secureTokenStatus "$user" 2>&1)"
    raw="${raw}"$'\n'"${user}: ${token_output}"

    token_state="UNKNOWN"
    case "$token_output" in
      *"Secure token is ENABLED"*|*"secure token is ENABLED"*) token_state="ENABLED" ;;
      *"Secure token is DISABLED"*|*"secure token is DISABLED"*) token_state="DISABLED" ;;
    esac

    admins="${admins}${user}|${uid}|${token_state}"$'\n'
  done
fi

RESULT_RAW_OUTPUT="$raw"

if [ -z "$admins" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="No se pudieron inventariar administradores locales"
  RESULT_DESCRIPTION="No se obtuvo una lista confiable de administradores locales humanos."
  RESULT_EXPLANATION="Sin una cuenta administradora local observable no es posible evaluar Secure Token de forma útil."
  RESULT_RISK="Estado de identidad local y capacidad de desbloqueo FileVault indeterminados."
  RESULT_SUGGESTED_ACTION="Revisar /Groups/admin y las cuentas locales del equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  return 0
fi

total=0
enabled=0
disabled=0
unknown=0
evidence=""

while IFS='|' read -r user uid token_state; do
  [ -n "$user" ] || continue
  total=$((total + 1))
  case "$token_state" in
    ENABLED) enabled=$((enabled + 1)) ;;
    DISABLED) disabled=$((disabled + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
  esac
  evidence="${evidence}${user} (UID ${uid}): Secure Token ${token_state}"$'\n'
done <<EOF
$admins
EOF

RESULT_EVIDENCE="${evidence%$'\n'}"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"

if [ "$enabled" -eq 0 ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Ningún administrador local tiene Secure Token"
  RESULT_DESCRIPTION="Se detectaron ${total} administradores locales humanos y ninguno reporta Secure Token habilitado."
  RESULT_EXPLANATION="Secure Token participa en flujos de FileVault y, según la plataforma, en Bootstrap Token y volume ownership."
  RESULT_RISK="Puede existir pérdida de capacidad administrativa sobre FileVault o flujos de identidad/propiedad del volumen."
  RESULT_SUGGESTED_ACTION="Revisar el flujo de aprovisionamiento y qué administrador debe poseer Secure Token; no otorgarlo automáticamente sin validar la política."
elif [ "$disabled" -gt 0 ] || [ "$unknown" -gt 0 ]; then
  RESULT_STATUS="WARN"
  RESULT_SEVERITY="MEDIUM"
  RESULT_TITLE="Administradores con estado Secure Token inconsistente"
  RESULT_DESCRIPTION="Administradores: ${total}; token habilitado: ${enabled}; deshabilitado: ${disabled}; desconocido: ${unknown}."
  RESULT_EXPLANATION="No todos los administradores locales observados tienen un estado Secure Token confirmado como habilitado."
  RESULT_RISK="Algunas cuentas administrativas podrían no participar correctamente en flujos de FileVault o administración de Secure Token."
  RESULT_SUGGESTED_ACTION="Revisar RESULT_EVIDENCE y confirmar qué administradores requieren Secure Token según el diseño de identidad del equipo."
else
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Secure Token consistente en administradores locales"
  RESULT_DESCRIPTION="Los ${total} administradores locales humanos detectados tienen Secure Token habilitado."
  RESULT_EXPLANATION="El inventario local no muestra administradores humanos sin Secure Token."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
fi
