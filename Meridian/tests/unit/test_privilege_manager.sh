#!/bin/bash
# Meridian — tests/unit/test_privilege_manager.sh
# Regresiones de mínimo privilegio para ejecución real vs sandbox de fixtures.
# Pendiente de ejecución en Bash 3.2/macOS real.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MERIDIAN_ROOT

log_warn() { :; }
log_error() { :; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/core/privilege_manager.sh"

failures=0

assert_pass() {
  local name="$1"; shift
  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
}

assert_fail() {
  local name="$1"; shift
  if "$@"; then
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$name"
  fi
}

# Aislamos el comportamiento del host donde corra la prueba: fingimos una
# sesión sin root para comprobar únicamente la política del manager.
privilege_check_root() { return 1; }

export MERIDIAN_TEST_MODE=0
assert_fail "root requirement devuelve control al caller sin privilegios" \
  privilege_require_root
assert_fail "módulo root se bloquea en ejecución real sin privilegios" \
  privilege_check_module filevault true
assert_pass "módulo no-root se permite en ejecución real" \
  privilege_check_module certificates false

export MERIDIAN_TEST_MODE=1
assert_pass "fixture permite ejercitar módulo requires_root sin sudo" \
  privilege_check_module filevault true
assert_pass "fixture permite módulo no-root" \
  privilege_check_module certificates false

assert_pass "repair LOW permitido por política MVP" privilege_check_repair LOW
assert_pass "repair MEDIUM permitido por política MVP" privilege_check_repair MEDIUM
assert_fail "repair HIGH bloqueado por política MVP" privilege_check_repair HIGH
assert_fail "repair CRITICAL bloqueado por política MVP" privilege_check_repair CRITICAL

# SUDO_USER solo es identidad válida si el sistema puede resolver la cuenta.
# Un valor inválido debe caer al usuario efectivo en vez de contaminar auditoría.
export SUDO_USER="__meridian_missing_user__"
expected_user="$(whoami 2>/dev/null || printf '%s\n' unknown)"
actual_user="$(privilege_get_current_user)"
if [ "$actual_user" = "$expected_user" ]; then
  printf 'PASS: SUDO_USER inválido cae al usuario efectivo\n'
else
  printf 'FAIL: SUDO_USER inválido no fue rechazado (%s)\n' "$actual_user" >&2
  failures=$((failures + 1))
fi
unset SUDO_USER

if [ "$failures" -ne 0 ]; then
  printf '%s\n' "${failures} fallo(s)" >&2
  exit 1
fi

printf '%s\n' "Privilege manager regression coverage complete"
