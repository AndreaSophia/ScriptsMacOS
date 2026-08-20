#!/bin/bash
# Habilita Secure Token solo para LCLAdmin y AdminCMDB mediante los prompts
# interactivos de sysadminctl. Ninguna contraseña cruza argv, env o archivos.

set -u

if [ "${MERIDIAN_SECURE_TOKEN_TEST_MODE:-0}" = "1" ] && [ -n "${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR:-}" ]; then
  _ST_DSCL="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/dscl"
  _ST_SYSADMINCTL="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/sysadminctl"
  _ST_STAT="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/stat"
  _ST_ID="${MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR}/id"
else
  _ST_DSCL="/usr/bin/dscl"
  _ST_SYSADMINCTL="/usr/sbin/sysadminctl"
  _ST_STAT="/usr/bin/stat"
  _ST_ID="/usr/bin/id"
fi

_st_fail() {
  printf 'SECURE_TOKEN_REPAIR_BLOCKED reason=%s\n' "$1" >&2
  exit "${2:-1}"
}

_st_status() {
  local output
  output="$("$_ST_SYSADMINCTL" -secureTokenStatus "$1" 2>&1)" || return 2
  case "$output" in
    *"Secure token is ENABLED"*|*"secure token is ENABLED"*) printf 'ENABLED\n' ;;
    *"Secure token is DISABLED"*|*"secure token is DISABLED"*) printf 'DISABLED\n' ;;
    *) return 2 ;;
  esac
}

for _st_tool in "$_ST_DSCL" "$_ST_SYSADMINCTL" "$_ST_STAT" "$_ST_ID"; do
  [ -x "$_st_tool" ] || _st_fail required_tool_unavailable 20
done

[ "$("$_ST_ID" -u 2>/dev/null)" = "0" ] || _st_fail root_required 21
if [ "${MERIDIAN_SECURE_TOKEN_TEST_MODE:-0}" != "1" ]; then
  [ -t 0 ] && [ -t 1 ] || _st_fail interactive_terminal_required 22
fi

_st_authorizer="$("$_ST_STAT" -f '%Su' /dev/console 2>/dev/null)"
case "$_st_authorizer" in
  ""|root|loginwindow|_mbsetupuser) _st_fail productive_user_unavailable 23 ;;
esac
[ "$(_st_status "$_st_authorizer")" = "ENABLED" ] || \
  _st_fail authorizing_user_without_token 24

for _st_requested in LCLAdmin AdminCMDB; do
  _st_record="$("$_ST_DSCL" /Local/Default -read "/Users/${_st_requested}" RecordName 2>/dev/null)" || \
    _st_fail "required_account_missing:${_st_requested}" 25
  case "$_st_record" in
    RecordName:*) _st_target="${_st_record#RecordName: }" ;;
    *) _st_fail "record_name_unavailable:${_st_requested}" 25 ;;
  esac

  _st_before="$(_st_status "$_st_target")" || \
    _st_fail "token_state_unknown:${_st_target}" 26
  if [ "$_st_before" = "ENABLED" ]; then
    printf 'SECURE_TOKEN_REPAIR_SKIPPED target=%s state=ENABLED\n' "$_st_target" >&2
    continue
  fi

  printf 'SECURE_TOKEN_REPAIR_AUTHORIZATION target=%s authorizer=%s\n' \
    "$_st_target" "$_st_authorizer" >&2
  printf '%s\n' 'macOS solicitará las contraseñas de forma interactiva; Meridian no las conserva.' >&2

  # '-' obliga a sysadminctl a solicitar ambos secretos mediante prompt. Nunca
  # sustituir estos guiones por valores, variables o sustituciones de comando.
  if ! "$_ST_SYSADMINCTL" -secureTokenOn "$_st_target" -password - \
      -adminUser "$_st_authorizer" -adminPassword -; then
    _st_fail "sysadminctl_failed:${_st_target}" 27
  fi

  [ "$(_st_status "$_st_target")" = "ENABLED" ] || \
    _st_fail "postcheck_failed:${_st_target}" 28
  printf 'SECURE_TOKEN_REPAIR_VERIFIED target=%s state=ENABLED\n' "$_st_target" >&2
done

printf '%s\n' 'SECURE_TOKEN_REPAIR_COMPLETED policy_targets_verified' >&2
exit 0
