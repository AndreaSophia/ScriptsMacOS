#!/bin/bash
# Secure Token Remedy readiness precheck. No modifica cuentas ni solicita
# credenciales. Compatible con Bash 3.2 y herramientas nativas de macOS.

set -u

if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR:-}" ]; then
  _PC_DSCL="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/dscl"
  _PC_SYSADMINCTL="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/sysadminctl"
  _PC_STAT="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/stat"
  _PC_ID="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/id"
  _PC_TR="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/tr"
else
  _PC_DSCL="/usr/bin/dscl"
  _PC_SYSADMINCTL="/usr/sbin/sysadminctl"
  _PC_STAT="/usr/bin/stat"
  _PC_ID="/usr/bin/id"
  _PC_TR="/usr/bin/tr"
fi

_pc_fail() {
  printf 'SECURE_TOKEN_PRECHECK_BLOCKED reason=%s\n' "$1" >&2
  return "${2:-1}"
}

_pc_fold() {
  printf '%s' "$1" | "$_PC_TR" '[:upper:]' '[:lower:]'
}

_pc_extract_record_name() {
  local _pc_line
  while IFS= read -r _pc_line; do
    case "$_pc_line" in
      RecordName:*) printf '%s\n' "${_pc_line#RecordName: }"; return 0 ;;
    esac
  done
  return 1
}

for _pc_tool in "$_PC_DSCL" "$_PC_SYSADMINCTL" "$_PC_STAT" "$_PC_ID" "$_PC_TR"; do
  [ -x "$_pc_tool" ] || { _pc_fail "required_tool_unavailable" 10; exit $?; }
done

if [ "${MERIDIAN_TEST_MODE:-0}" != "1" ]; then
  [ -t 0 ] && [ -t 1 ] || { _pc_fail "interactive_terminal_required" 11; exit $?; }
fi

[ "$("$_PC_ID" -u 2>/dev/null)" = "0" ] || { _pc_fail "root_required" 12; exit $?; }

_pc_console_user="$("$_PC_STAT" -f '%Su' /dev/console 2>/dev/null)"
case "$_pc_console_user" in
  ""|root|loginwindow|_mbsetupuser) _pc_fail "productive_user_unavailable" 13; exit $? ;;
esac

_pc_admin_line="$("$_PC_DSCL" /Local/Default -read /Groups/admin GroupMembership 2>/dev/null)"
case "$_pc_admin_line" in
  GroupMembership:*) _pc_admin_members="${_pc_admin_line#GroupMembership: }" ;;
  *) _pc_fail "admin_inventory_unavailable" 13; exit $? ;;
esac

_pc_admin_keys="|"
for _pc_admin in $_pc_admin_members; do
  _pc_admin_keys="${_pc_admin_keys}$(_pc_fold "$_pc_admin")|"
done

_pc_product_key="$(_pc_fold "$_pc_console_user")"
_pc_disabled_targets=0

for _pc_requested in "$_pc_console_user" LCLAdmin AdminCMDB; do
  _pc_record="$("$_PC_DSCL" /Local/Default -read "/Users/${_pc_requested}" RecordName UniqueID 2>/dev/null)" || {
    _pc_fail "required_account_missing:$(_pc_fold "$_pc_requested")" 13
    exit $?
  }
  _pc_record_name="$(_pc_extract_record_name <<EOF
$_pc_record
EOF
)"
  [ -n "$_pc_record_name" ] || { _pc_fail "record_name_unavailable" 13; exit $?; }

  _pc_key="$(_pc_fold "$_pc_record_name")"
  case "$_pc_admin_keys" in
    *"|${_pc_key}|"*) ;;
    *) _pc_fail "required_account_not_admin:${_pc_key}" 13; exit $? ;;
  esac

  _pc_token_output="$("$_PC_SYSADMINCTL" -secureTokenStatus "$_pc_record_name" 2>&1)"
  case "$_pc_token_output" in
    *"Secure token is ENABLED"*|*"secure token is ENABLED"*) _pc_state="ENABLED" ;;
    *"Secure token is DISABLED"*|*"secure token is DISABLED"*) _pc_state="DISABLED" ;;
    *) _pc_fail "token_state_unknown:${_pc_key}" 15; exit $? ;;
  esac

  if [ "$_pc_key" = "$_pc_product_key" ]; then
    [ "$_pc_state" = "ENABLED" ] || { _pc_fail "authorizing_user_without_token:${_pc_key}" 14; exit $?; }
  elif [ "$_pc_state" = "DISABLED" ]; then
    _pc_disabled_targets=$((_pc_disabled_targets + 1))
  fi
done

if [ "$_pc_disabled_targets" -eq 0 ]; then
  printf '%s\n' 'SECURE_TOKEN_PRECHECK_NO_ACTION policy_already_compliant' >&2
  exit 3
fi

printf 'SECURE_TOKEN_PRECHECK_READY disabled_targets=%s authorizing_user=%s\n' \
  "$_pc_disabled_targets" "$_pc_console_user" >&2
exit 0
