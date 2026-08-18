#!/bin/bash
# Meridian — tests/unit/test_tui_menu.sh
# Regresión para asegurar que la TUI separa presentación (stderr)
# de selección consumible por el caller (stdout).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Stubs mínimos requeridos por menu.sh.
registry_get_field() {
  case "$1:$2" in
    filevault:2) printf '%s\n' "FileVault Disk Encryption" ;;
    filevault:3) printf '%s\n' "security" ;;
    certificates:2) printf '%s\n' "Certificates & Trust Store" ;;
    certificates:3) printf '%s\n' "security" ;;
    *) return 1 ;;
  esac
}

registry_get_all_ids() {
  printf '%s\n' "filevault" "certificates"
}

registry_count() {
  printf '%s\n' "2"
}

log_error() { printf '%s\n' "$*" >&2; }
log_warn()  { printf '%s\n' "$*" >&2; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/ui/tui/menu.sh"

PASS=0
FAIL=0

_assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS: %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

_tmp="${TMPDIR:-/tmp}/meridian_tui_menu.$$"
mkdir -p "$_tmp" || exit 1
trap 'rm -rf "$_tmp"' EXIT HUP INT TERM

# Selección individual: stdout debe contener solo el ID; el menú debe existir
# por stderr y no viajar mezclado con el dato.
out="$(printf '1\n' | _tui_menu_plain $'filevault\ncertificates' 2>"${_tmp}/ui1.err")"
_assert_eq "filevault" "$out" "plain menu returns only selected module on stdout"
if grep -q 'Todos los módulos' "${_tmp}/ui1.err" && grep -q 'FileVault Disk Encryption' "${_tmp}/ui1.err"; then
  printf 'PASS: plain menu presentation is emitted on stderr\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL: plain menu presentation missing from stderr\n' >&2
  FAIL=$((FAIL + 1))
fi

# Selección múltiple conserva IDs en una única línea normalizada.
out="$(printf '1 2\n' | _tui_menu_plain $'filevault\ncertificates' 2>"${_tmp}/ui2.err")"
_assert_eq "filevault certificates" "$out" "plain menu returns normalized multi-selection"

# 0 y EOF tienen semántica fail-safe: todos los módulos.
out="$(printf '0\n' | _tui_menu_plain $'filevault\ncertificates' 2>"${_tmp}/ui3.err")"
_assert_eq "all" "$out" "plain menu zero selects all"

out="$(_tui_menu_plain $'filevault\ncertificates' </dev/null 2>"${_tmp}/ui4.err")"
_assert_eq "all" "$out" "plain menu EOF falls back to all"

printf '\nResult: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
