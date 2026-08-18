#!/bin/bash
# Readiness precheck: todas las ramas son no destructivas y usan herramientas fake.

set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_st_precheck.XXXXXX")" || exit 1
BIN="${TMP_ROOT}/bin"
mkdir -p "$BIN"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

cat >"${BIN}/id" <<'EOF'
#!/bin/bash
[ "${SCENARIO:-ready}" = nonroot ] && printf '501\n' || printf '0\n'
EOF
cat >"${BIN}/stat" <<'EOF'
#!/bin/bash
printf '%s\n' 'CARV8707@itau.cl'
EOF
cat >"${BIN}/tr" <<'EOF'
#!/bin/bash
/usr/bin/tr "$@"
EOF
cat >"${BIN}/dscl" <<'EOF'
#!/bin/bash
case "$*" in
  *'/Groups/admin GroupMembership'*) printf '%s\n' 'GroupMembership: CARV8707@itau.cl lcladmin admincmdb' ;;
  *'/Users/CARV8707@itau.cl RecordName UniqueID'*) printf '%s\n' 'RecordName: CARV8707@itau.cl' 'UniqueID: 502' ;;
  *'/Users/LCLAdmin RecordName UniqueID'*) printf '%s\n' 'RecordName: lcladmin' 'UniqueID: 501' ;;
  *'/Users/AdminCMDB RecordName UniqueID'*)
    [ "${SCENARIO:-ready}" = missing ] && exit 1
    printf '%s\n' 'RecordName: admincmdb' 'UniqueID: 503'
    ;;
  *) exit 1 ;;
esac
EOF
cat >"${BIN}/sysadminctl" <<'EOF'
#!/bin/bash
user="${!#}"
case "$user" in
  CARV8707@itau.cl)
    [ "${SCENARIO:-ready}" = authorizer_disabled ] && state=DISABLED || state=ENABLED
    ;;
  lcladmin|admincmdb)
    [ "${SCENARIO:-ready}" = compliant ] && state=ENABLED || state=DISABLED
    ;;
  *) state=UNKNOWN ;;
esac
[ "${SCENARIO:-ready}" = unknown ] && { printf '%s\n' 'status unavailable' >&2; exit 1; }
printf 'Secure token is %s for user %s\n' "$state" "$user" >&2
EOF
chmod +x "$BIN"/*

export MERIDIAN_TEST_MODE=1 MERIDIAN_SECURE_TOKEN_TEST_BIN_DIR="$BIN"
PRECHECK="${ROOT}/modules/security/secure_token/precheck.sh"
passed=0; failed=0
assert_rc() {
  name="$1" expected="$2" scenario="$3"
  SCENARIO="$scenario" /bin/bash "$PRECHECK" >/dev/null
  actual=$?
  if [ "$actual" = "$expected" ]; then printf 'PASS: %s\n' "$name"; passed=$((passed + 1)); else
    printf 'FAIL: %s expected=%s got=%s\n' "$name" "$expected" "$actual" >&2; failed=$((failed + 1))
  fi
}

assert_rc 'dos objetivos disabled quedan listos' 0 ready
assert_rc 'política ya conforme no ejecuta acción' 3 compliant
assert_rc 'cuenta requerida ausente bloquea' 13 missing
assert_rc 'ejecución sin root bloquea' 12 nonroot
assert_rc 'usuario autorizador sin token bloquea' 14 authorizer_disabled
assert_rc 'estado desconocido bloquea' 15 unknown

printf 'Passed: %s | Failed: %s\n' "$passed" "$failed"
exit "$failed"
