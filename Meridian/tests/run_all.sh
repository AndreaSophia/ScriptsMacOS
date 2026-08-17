#!/bin/bash
# =============================================================================
# Meridian — tests/run_all.sh
# Ejecuta la regresión completa no destructiva (unit + integration) de forma
# determinista y compatible con Bash 3.2 + userland BSD nativo de macOS.
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

# Los tests viven un nivel bajo unit/ e integration/. El glob evita depender de
# extensiones GNU de find y el sort mantiene orden estable entre máquinas.
for suite in unit integration; do
  test_dir="${TEST_ROOT}/${suite}"
  [ -d "$test_dir" ] || continue

  for test_path in "$test_dir"/test_*.sh; do
    [ -f "$test_path" ] || continue
    printf '%s\n' "$test_path"
  done | LC_ALL=C sort | while IFS= read -r test_path; do
    [ -n "$test_path" ] || continue
    run_test "$test_path"
  done

done

# Los while anteriores corren en subshell por el pipe en Bash 3.2, por lo que
# los contadores no sobrevivirían. Recorremos de nuevo sin pipe, usando el
# orden lexical natural del glob (estable para los nombres ASCII actuales).
_pass=0
_fail=0
_total=0
for suite in unit integration; do
  test_dir="${TEST_ROOT}/${suite}"
  [ -d "$test_dir" ] || continue
  for test_path in "$test_dir"/test_*.sh; do
    [ -f "$test_path" ] || continue
    run_test "$test_path"
  done
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
