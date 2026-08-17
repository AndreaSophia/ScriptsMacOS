#!/bin/bash
# =============================================================================
# Meridian — tests/run_all.sh
# Ejecuta la regresión completa no destructiva (unit + integration) de forma
# determinista y compatible con Bash 3.2 de macOS.
# =============================================================================

set -u

MERIDIAN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${MERIDIAN_ROOT}/tests"
_pass=0
_fail=0
_total=0

printf '\n══════════════════════════════════════════════════\n'
printf ' Meridian — regresión completa pre-release\n'
printf '══════════════════════════════════════════════════\n\n'

run_test() {
  local test_path="$1"
  local rel
  local rc

  rel="${test_path#${MERIDIAN_ROOT}/}"
  _total=$((_total + 1))

  printf '▶ %s\n' "$rel"
  if bash "$test_path"; then
    rc=0
  else
    rc=$?
  fi

  if [ "$rc" -eq 0 ]; then
    printf '✓ %s\n\n' "$rel"
    _pass=$((_pass + 1))
  else
    printf '✗ %s (rc=%s)\n\n' "$rel" "$rc" >&2
    _fail=$((_fail + 1))
  fi
}

# LC_ALL=C mantiene un orden estable entre máquinas y versiones de macOS.
# Se evita find -print0/read -d porque Bash 3.2 y herramientas BSD deben ser
# suficientes para el árbol de tests actual (rutas sin saltos de línea).
for suite in unit integration; do
  test_dir="${TEST_ROOT}/${suite}"
  [ -d "$test_dir" ] || continue

  while IFS= read -r test_path; do
    [ -n "$test_path" ] || continue
    run_test "$test_path"
  done <<EOF
$(LC_ALL=C find "$test_dir" -type f -name 'test_*.sh' -maxdepth 1 2>/dev/null | LC_ALL=C sort)
EOF
done

printf '──────────────────────────────────────────────────\n'
printf 'Suites ejecutadas : %s\n' "$_total"
printf '✓ Pasaron          : %s\n' "$_pass"
printf '✗ Fallaron         : %s\n' "$_fail"
printf '──────────────────────────────────────────────────\n'

if [ "$_total" -eq 0 ]; then
  printf '✗ No se descubrieron tests.\n' >&2
  exit 2
fi

if [ "$_fail" -ne 0 ]; then
  exit 1
fi

printf '✓ Regresión completa verde.\n'
exit 0
