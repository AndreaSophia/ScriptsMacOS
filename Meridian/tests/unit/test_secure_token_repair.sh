#!/bin/bash
# Verifica argv seguro, orden, postcheck y fallo cerrado sin tocar macOS real.

set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_st_repair.XXXXXX")" || exit 1
BIN="${TMP_ROOT}/bin"
STATE="${TMP_ROOT}/state"
CALLS="${TMP_ROOT}/calls"
mkdir -p "$BIN" "$STATE"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

cat >"${BIN}/id" <<'EOF'
#!/bin/bash
printf '0\n'
EOF
cat >"${BIN}/stat" <<'EOF'
#!/bin/bash
printf 'CARV8707@itau.cl\n'
EOF
cat >"${BIN}/dscl" <<'EOF'
#!/bin/bash
case "$*" in
  *'/Users/LCLAdmin RecordName') printf 'RecordName: lcladmin\n' ;;
  *'/Users/AdminCMDB RecordName') printf 'RecordName: admincmdb\n' ;;
  *) exit 1 ;;
esac
EOF
cat >"${BIN}/sysadminctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CALLS"
case "$1" in
  -secureTokenStatus)
    if [ "$2" = 'CARV8707@itau.cl' ] || [ -f "$TEST_STATE/$2" ]; then state=ENABLED; else state=DISABLED; fi
    printf 'Secure token is %s for user %s\n' "$state" "$2" >&2
    ;;
  -secureTokenOn)
    [ "$3" = '-password' ] && [ "$4" = '-' ] && \
      [ "$5" = '-adminUser' ] && [ "$6" = 'CARV8707@itau.cl' ] && \
      [ "$7" = '-adminPassword' ] && [ "$8" = '-' ] || exit 91
    [ "${SCENARIO:-success}" != fail_action ] || exit 92
    : >"$TEST_STATE/$2"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN"/*

export MERIDIAN_SECURE_TOKEN_TEST_MODE=1
export MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR="$BIN"
export TEST_STATE="$STATE" TEST_CALLS="$CALLS"
REPAIR="${ROOT}/modules/security/secure_token/repair.sh"
failures=0

if /bin/bash "$REPAIR" >/dev/null 2>&1; then
  printf 'PASS: reparación simulada completa\n'
else
  printf 'FAIL: reparación simulada completa\n' >&2; failures=$((failures + 1))
fi

if [ -f "$STATE/lcladmin" ] && [ -f "$STATE/admincmdb" ]; then
  printf 'PASS: ambos objetivos quedaron verificados\n'
else
  printf 'FAIL: faltó un objetivo\n' >&2; failures=$((failures + 1))
fi

if grep -Fq -- '-password - -adminUser CARV8707@itau.cl -adminPassword -' "$CALLS" && \
   ! grep -Eiq 'password ([^-]|$)' "$CALLS"; then
  printf 'PASS: argv contiene prompts y ningún secreto\n'
else
  printf 'FAIL: argv inseguro\n' >&2; failures=$((failures + 1))
fi

rm -f "$STATE/lcladmin" "$STATE/admincmdb"; : >"$CALLS"
if SCENARIO=fail_action /bin/bash "$REPAIR" >/dev/null 2>&1; then
  printf 'FAIL: fallo de sysadminctl no fue bloqueado\n' >&2; failures=$((failures + 1))
else
  printf 'PASS: fallo de sysadminctl cierra la acción\n'
fi

exit "$failures"
