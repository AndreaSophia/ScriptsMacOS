#!/bin/bash
# =============================================================================
# Módulo: secure_token — diagnose.sh
# Responsabilidad: validar la política corporativa de Secure Token sin modificar
# el sistema. Cuentas requeridas: usuario productivo actual + LCLAdmin + AdminCMDB.
# =============================================================================

_DSCL="/usr/bin/dscl"
_SYSADMINCTL="/usr/sbin/sysadminctl"
_STAT="/usr/bin/stat"

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
  [ -x "$_STAT" ] || {
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="stat no disponible"
    RESULT_DESCRIPTION="No se puede identificar de forma confiable al usuario productivo actual."
    RESULT_EXPLANATION="Meridian requiere /usr/bin/stat para identificar el propietario de /dev/console."
    RESULT_RISK="La política de Secure Token no puede evaluarse completamente."
    RESULT_SUGGESTED_ACTION="Verificar la integridad de /usr/bin/stat."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="1"
    return 0
  }
fi

# La identidad productiva cambia entre equipos. En producción se toma del
# usuario de consola; en regresiones puede fijarse explícitamente sin depender
# del host donde corre el test.
policy_current_user="${MERIDIAN_POLICY_CURRENT_USER:-}"
if [ -z "$policy_current_user" ] && [ "${MERIDIAN_TEST_MODE:-0}" != "1" ]; then
  policy_current_user="$("$_STAT" -f '%Su' /dev/console 2>/dev/null)"
fi
case "$policy_current_user" in
  ""|root|loginwindow|_mbsetupuser) policy_current_user="" ;;
esac

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
    # Las cuentas de sistema no son objetivo de esta política. Las cuentas
    # técnicas con prefijo '_' tampoco deben convertirse en falsos incumplimientos.
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
  RESULT_EXPLANATION="Sin cuentas administradoras locales observables no es posible evaluar la política de Secure Token."
  RESULT_RISK="Estado de identidad local y capacidad de desbloqueo FileVault indeterminados."
  RESULT_SUGGESTED_ACTION="Revisar /Groups/admin y las cuentas locales del equipo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  return 0
fi

if [ -z "$policy_current_user" ]; then
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Usuario productivo actual no identificable"
  RESULT_DESCRIPTION="Meridian no pudo determinar qué usuario productivo debe cumplir la política de Secure Token."
  RESULT_EXPLANATION="La política exige Secure Token para el usuario productivo actual, LCLAdmin y AdminCMDB."
  RESULT_RISK="No es posible declarar cumplimiento completo de Secure Token."
  RESULT_SUGGESTED_ACTION="Ejecutar Meridian con una sesión productiva iniciada o validar la identidad de consola."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  return 0
fi

total=0
evidence=""
policy_current_state="MISSING"
policy_current_uid="?"
policy_lcl_state="MISSING"
policy_lcl_uid="?"
policy_cmdb_state="MISSING"
policy_cmdb_uid="?"

while IFS='|' read -r user uid token_state; do
  [ -n "$user" ] || continue
  total=$((total + 1))

  required="false"
  if [ "$user" = "$policy_current_user" ]; then
    policy_current_state="$token_state"
    policy_current_uid="$uid"
    required="true"
  fi
  if [ "$user" = "LCLAdmin" ]; then
    policy_lcl_state="$token_state"
    policy_lcl_uid="$uid"
    required="true"
  fi
  if [ "$user" = "AdminCMDB" ]; then
    policy_cmdb_state="$token_state"
    policy_cmdb_uid="$uid"
    required="true"
  fi

  if [ "$required" = "true" ]; then
    evidence="${evidence}[REQUIRED] ${user} (UID ${uid}): Secure Token ${token_state}"$'\n'
  else
    evidence="${evidence}[INVENTORY] ${user} (UID ${uid}): Secure Token ${token_state}"$'\n'
  fi
done <<EOF
$admins
EOF

# Si una cuenta requerida no apareció en el inventario, dejarlo explícito en la
# evidencia: ausencia y token deshabilitado son fallos diferentes, pero ambos
# impiden cumplir la política.
[ "$policy_current_state" != "MISSING" ] || evidence="${evidence}[REQUIRED] ${policy_current_user}: cuenta no observada en admin (MISSING)"$'\n'
[ "$policy_lcl_state" != "MISSING" ] || evidence="${evidence}[REQUIRED] LCLAdmin: cuenta no observada en admin (MISSING)"$'\n'
[ "$policy_cmdb_state" != "MISSING" ] || evidence="${evidence}[REQUIRED] AdminCMDB: cuenta no observada en admin (MISSING)"$'\n'

RESULT_EVIDENCE="${evidence%$'\n'}"
RESULT_REPAIRABLE="false"
RESULT_REPAIR_RISK="NONE"
RESULT_EXIT_CODE="0"

policy_failures=0
policy_unknown=0
for state in "$policy_current_state" "$policy_lcl_state" "$policy_cmdb_state"; do
  case "$state" in
    ENABLED) ;;
    UNKNOWN) policy_failures=$((policy_failures + 1)); policy_unknown=$((policy_unknown + 1)) ;;
    *) policy_failures=$((policy_failures + 1)) ;;
  esac
done

if [ "$policy_failures" -gt 0 ]; then
  RESULT_STATUS="FAIL"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Política Secure Token incumplida"
  RESULT_DESCRIPTION="Las 3 cuentas requeridas deben tener Secure Token habilitado: ${policy_current_user}, LCLAdmin y AdminCMDB. Se detectaron ${policy_failures} incumplimiento(s)."
  RESULT_EXPLANATION="La política operativa exige Secure Token para el usuario productivo y las dos cuentas administrativas de soporte/CMDB; otras cuentas técnicas no forman parte de esta evaluación."
  RESULT_RISK="Una cuenta requerida sin Secure Token puede perder capacidad esperada en flujos de FileVault, desbloqueo preboot o administración criptográfica del equipo."
  if [ "$policy_unknown" -gt 0 ]; then
    RESULT_SUGGESTED_ACTION="Revisar RESULT_EVIDENCE y corregir las cuentas requeridas con estado DISABLED/MISSING; validar manualmente cualquier estado UNKNOWN. No otorgar tokens fuera de estas cuentas por inferencia."
  else
    RESULT_SUGGESTED_ACTION="Revisar RESULT_EVIDENCE y restablecer Secure Token únicamente en las cuentas requeridas que estén DISABLED o MISSING, siguiendo el procedimiento corporativo autorizado."
  fi
else
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Política Secure Token cumplida"
  RESULT_DESCRIPTION="Usuario productivo actual, LCLAdmin y AdminCMDB tienen Secure Token habilitado."
  RESULT_EXPLANATION="Las tres identidades requeridas por la política operativa reportan Secure Token ENABLED."
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
fi
