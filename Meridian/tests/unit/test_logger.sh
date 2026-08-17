#!/bin/bash
# =============================================================================
# Meridian — tests/unit/test_logger.sh
# Regresión para integridad y fronteras de destino del logger.
# Diseñado para Bash 3.2+; pendiente de ejecución en laboratorio macOS.
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

# El logger nunca debe seguir un symlink proporcionado como destino. Esta
# regresión se puede verificar sin root usando el override permitido en modo
# no privilegiado; la misma comprobación protege la ruta corporativa fija.
real_target="${_tmp_dir}/do-not-touch.log"
symlink_target="${_tmp_dir}/audit-link.log"
printf '%s\n' 'sentinel' > "$real_target"
ln -s "$real_target" "$symlink_target" || exit 1
export MERIDIAN_AUDIT_LOG="$symlink_target"

if log_audit "logger_test" "SYMLINK_REJECT" "must-not-append" >/dev/null 2>&1; then
  assert_eq "audit: symlink de destino es rechazado" "rejected" "accepted"
else
  assert_eq "audit: symlink de destino es rechazado" "rejected" "rejected"
fi
assert_eq "audit: rechazo de symlink no modifica el target" "sentinel" "$(cat "$real_target")"

# diagnostic.log es un artefacto de sesión nuevo: logger_init no debe truncar
# un archivo preexistente ni seguir symlinks de archivo/directorio.
session_dir="${_tmp_dir}/session"
session_log="${session_dir}/diagnostic.log"
if logger_init "$session_log" >/dev/null 2>&1; then
  assert_eq "session log: destino nuevo se inicializa" "created" "created"
else
  assert_eq "session log: destino nuevo se inicializa" "created" "failed"
fi

# La sesión puede contener evidencia sensible. En macOS, stat -f %Lp devuelve
# los bits POSIX sin adornos; el logger debe dejar el archivo exactamente 0600.
session_mode="$(/usr/bin/stat -f '%Lp' "$session_log" 2>/dev/null || true)"
assert_eq "session log: permisos finales son 600" "600" "$session_mode"

printf '%s\n' 'preserve-me' >> "$session_log"

if logger_init "$session_log" >/dev/null 2>&1; then
  assert_eq "session log: archivo preexistente se rechaza" "rejected" "accepted"
else
  assert_eq "session log: archivo preexistente se rechaza" "rejected" "rejected"
fi
assert_contains "session log: rechazo no trunca contenido" "preserve-me" "$(cat "$session_log")"

session_real_target="${_tmp_dir}/session-target.log"
session_link="${_tmp_dir}/session-link.log"
printf '%s\n' 'session-sentinel' > "$session_real_target"
ln -s "$session_real_target" "$session_link" || exit 1
if logger_init "$session_link" >/dev/null 2>&1; then
  assert_eq "session log: symlink de archivo se rechaza" "rejected" "accepted"
else
  assert_eq "session log: symlink de archivo se rechaza" "rejected" "rejected"
fi
assert_eq "session log: symlink no modifica target" "session-sentinel" "$(cat "$session_real_target")"

real_dir="${_tmp_dir}/real-log-dir"
link_dir="${_tmp_dir}/linked-log-dir"
mkdir -p "$real_dir"
ln -s "$real_dir" "$link_dir" || exit 1
if logger_init "${link_dir}/diagnostic.log" >/dev/null 2>&1; then
  assert_eq "session log: directorio symlink se rechaza" "rejected" "accepted"
else
  assert_eq "session log: directorio symlink se rechaza" "rejected" "rejected"
fi
assert_eq "session log: directorio symlink no crea archivo" "absent" "$([ -e "${real_dir}/diagnostic.log" ] && printf present || printf absent)"

printf "\n  Resultado: %d OK, %d FAIL\n\n" "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
