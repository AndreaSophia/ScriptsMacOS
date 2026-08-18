#!/bin/bash
# Valida que CrowdStrike no degrade por un rc=1 transitorio si un segundo
# falconctl stats devuelve evidencia operativa, manteniendo fail-closed si no.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_crowdstrike_evidence.XXXXXX")"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_crowdstrike_fixture.XXXXXX")"
trap 'rm -rf "$evidence_dir" "$fixture_dir"' EXIT

cat > "${fixture_dir}/falconctl_first_error.txt" <<'EOF'
falconctl transient observation failure
EOF
cat > "${fixture_dir}/falconctl_retry_running.txt" <<'EOF'
=== CloudInfo ===
Cloud Info
Host: fixture.cloudsink.net
Port: 443
State: connected

=== agent_info ===
version: 7.39.21104.0
Sensor operational: true
Sensor status: loaded
EOF

export MERIDIAN_TEST_MODE=1
export MERIDIAN_FIXTURE_DIR="$fixture_dir"
export MERIDIAN_EVIDENCE_DIR="$evidence_dir"
source "${MERIDIAN_ROOT}/core/result_model.sh"

_pass=0
_fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '✓  %s\n' "$desc"
    _pass=$((_pass + 1))
  else
    printf '✗  %s expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2
    _fail=$((_fail + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) printf '✓  %s\n' "$desc"; _pass=$((_pass + 1));;
    *) printf '✗  %s falta=%s\n' "$desc" "$needle" >&2; _fail=$((_fail + 1));;
  esac
}

result_init
RESULT_MODULE_ID="crowdstrike"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/edr/crowdstrike/diagnose.sh"

assert_eq "retry exitoso conserva PASS" "PASS" "$RESULT_STATUS"
assert_eq "retry exitoso conserva severidad INFO" "INFO" "$RESULT_SEVERITY"
assert_contains "raw output registra dos intentos" "$RESULT_RAW_OUTPUT" "stats_attempts=2"
assert_contains "raw output conserva rc final cero" "$RESULT_RAW_OUTPUT" "stats_rc=0"
assert_contains "raw output contiene estado operativo" "$RESULT_RAW_OUTPUT" "Sensor operational: true"

if /usr/bin/grep -q "falconctl stats attempts: 2" "${evidence_dir}/crowdstrike_detail.txt" 2>/dev/null; then
  printf '✓  evidencia registra el retry\n'
  _pass=$((_pass + 1))
else
  printf '✗  evidencia no registra dos intentos\n' >&2
  _fail=$((_fail + 1))
fi

if result_validate >/dev/null 2>&1; then
  printf '✓  resultado cumple DiagnosticResult\n'
  _pass=$((_pass + 1))
else
  printf '✗  resultado viola DiagnosticResult\n' >&2
  _fail=$((_fail + 1))
fi

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
