#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_logger.sh
# Regresión para integridad de registros del audit log.
# =============================================================================

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${MERIDIAN_ROOT}/logging/logger.sh"

_pass=0; _fail=0
_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_logger_test.XXXXXX")" || exit 1
trap 'rm -rf "$_tmp_dir"' EXIT INT TERM

export MERIDIAN_LOG_FILE="${_tmp_dir}/diagnostic.log"
export MERIDIAN_AUDIT_LOG="${_tmp_dir}/audit.log"
: > "$MERIDIAN_LOG_FILE"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass + 1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     expected='%s' got='%s'\n" \
      "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
    printf "  \033[1;32m✓\033[0m  %s\n" "$desc"
    _pass=$((_pass + 1))
  else
    printf "  \033[1;31m✗\033[0m  %s\n     '%s' no encontrado\n" \
      "$desc" "$needle" >&2
    _fail=$((_fail + 1))
  fi
}

printf "\n\033[1mtest_logger.sh\033[0m\n\n"

# Un detalle procedente de un módulo puede contener delimitadores y saltos de
# línea. Debe seguir ocupando exactamente un registro y siete columnas.
detail="module=filevault|reason=unexpected%value
second-record-looking-line"
log_audit "repair|engine" "REPAIR_STARTED" "$detail" >/dev/null 2>&1

line_count="$(wc -l < "$MERIDIAN_AUDIT_LOG" | tr -d ' ')"
field_count="$(awk -F'|' 'NR==1 { print NF }' "$MERIDIAN_AUDIT_LOG")"
audit_line="$(cat "$MERIDIAN_AUDIT_LOG")"

assert_eq "audit: un evento produce exactamente una línea" "1" "$line_count"
assert_eq "audit: conserva siete columnas estructurales" "7" "$field_count"
assert_contains "audit: codifica pipes" "%7C" "$audit_line"
assert_contains "audit: codifica porcentajes" "%25" "$audit_line"
assert_contains "audit: codifica saltos de línea" "%0A" "$audit_line"

printf "\n  Resultado: %d OK, %d FAIL\n\n" "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
