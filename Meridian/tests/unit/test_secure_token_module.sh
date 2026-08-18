#!/bin/bash
# Valida la política corporativa del módulo secure_token contra fixtures deterministas.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/meridian_secure_token.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

export MERIDIAN_TEST_MODE=1
export MERIDIAN_EVIDENCE_DIR="$tmp_root/evidence"
export MERIDIAN_POLICY_CURRENT_USER="CARV8707@itau.cl"
mkdir -p "$MERIDIAN_EVIDENCE_DIR"
source "${MERIDIAN_ROOT}/core/result_model.sh"

_pass=0
_fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '✓  %s\n' "$desc"; _pass=$((_pass + 1))
  else
    printf '✗  %s expected=%s got=%s\n' "$desc" "$expected" "$actual" >&2; _fail=$((_fail + 1))
  fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) printf '✓  %s\n' "$desc"; _pass=$((_pass + 1)) ;;
    *) printf '✗  %s missing=%s\n' "$desc" "$needle" >&2; _fail=$((_fail + 1)) ;;
  esac
}
assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) printf '✗  %s unexpected=%s\n' "$desc" "$needle" >&2; _fail=$((_fail + 1)) ;;
    *) printf '✓  %s\n' "$desc"; _pass=$((_pass + 1)) ;;
  esac
}
assert_file() {
  local desc="$1" path="$2"
  if [ -s "$path" ]; then
    printf '✓  %s\n' "$desc"; _pass=$((_pass + 1))
  else
    printf '✗  %s missing_or_empty=%s\n' "$desc" "$path" >&2; _fail=$((_fail + 1))
  fi
}

run_fixture() {
  local fixture_dir="$1"
  export MERIDIAN_FIXTURE_DIR="$fixture_dir"
  result_init
  RESULT_MODULE_ID="secure_token"
  RESULT_MODULE_VERSION="1.0.0"
  source "${MERIDIAN_ROOT}/modules/security/secure_token/diagnose.sh"
}

evidence_file="$MERIDIAN_EVIDENCE_DIR/secure_token_detail.txt"

# Caso RC real: usuario productivo habilitado; LCLAdmin y AdminCMDB sin token.
fixture_fail="$tmp_root/fail"
mkdir -p "$fixture_fail"
cat > "$fixture_fail/secure_token_admins.txt" <<'EOF'
CARV8707@itau.cl|502|ENABLED
LCLAdmin|501|DISABLED
AdminCMDB|503|DISABLED
_cyberarkepm|504|DISABLED
EOF
run_fixture "$fixture_fail"

assert_eq "incumplimiento de cuenta requerida produce FAIL" "FAIL" "$RESULT_STATUS"
assert_eq "incumplimiento de política es HIGH" "HIGH" "$RESULT_SEVERITY"
assert_eq "título declara política incumplida" "Política Secure Token incumplida" "$RESULT_TITLE"
assert_contains "evidencia conserva usuario productivo requerido" "$RESULT_EVIDENCE" "[REQUIRED] CARV8707@itau.cl (UID 502): Secure Token ENABLED"
assert_contains "evidencia identifica LCLAdmin requerido sin token" "$RESULT_EVIDENCE" "[REQUIRED] LCLAdmin (UID 501): Secure Token DISABLED"
assert_contains "evidencia identifica AdminCMDB requerido sin token" "$RESULT_EVIDENCE" "[REQUIRED] AdminCMDB (UID 503): Secure Token DISABLED"
assert_contains "cuenta técnica queda solo como inventario" "$RESULT_EVIDENCE" "[INVENTORY] _cyberarkepm (UID 504): Secure Token DISABLED"

assert_file "FAIL materializa secure_token_detail.txt" "$evidence_file"
fail_artifact="$(cat "$evidence_file")"
assert_contains "artefacto conserva usuario requerido" "$fail_artifact" "[REQUIRED] CARV8707@itau.cl (UID 502): Secure Token ENABLED"
assert_contains "artefacto conserva LCLAdmin requerido" "$fail_artifact" "[REQUIRED] LCLAdmin (UID 501): Secure Token DISABLED"
assert_contains "artefacto conserva AdminCMDB requerido" "$fail_artifact" "[REQUIRED] AdminCMDB (UID 503): Secure Token DISABLED"
assert_contains "artefacto clasifica cuenta técnica solo como inventario" "$fail_artifact" "[INVENTORY] _cyberarkepm (UID 504): Secure Token DISABLED"
assert_not_contains "artefacto no convierte cuenta técnica en requerida" "$fail_artifact" "[REQUIRED] _cyberarkepm"
assert_not_contains "artefacto no expone salida cruda de sysadminctl" "$fail_artifact" "Secure token is"
assert_not_contains "artefacto no contiene campos de contraseña" "$fail_artifact" "password="
assert_not_contains "artefacto no contiene campos de secreto" "$fail_artifact" "secret="

if result_validate >/dev/null 2>&1; then
  printf '✓  FAIL cumple DiagnosticResult\n'; _pass=$((_pass + 1))
else
  printf '✗  FAIL viola DiagnosticResult\n' >&2; _fail=$((_fail + 1))
fi

# Caso conforme: las tres cuentas objetivo ENABLED; una cuenta no objetivo puede
# seguir DISABLED sin degradar el resultado.
fixture_pass="$tmp_root/pass"
mkdir -p "$fixture_pass"
cat > "$fixture_pass/secure_token_admins.txt" <<'EOF'
CARV8707@itau.cl|502|ENABLED
LCLAdmin|501|ENABLED
AdminCMDB|503|ENABLED
OtherAdmin|505|DISABLED
EOF
run_fixture "$fixture_pass"

assert_eq "tres cuentas requeridas habilitadas producen PASS" "PASS" "$RESULT_STATUS"
assert_eq "PASS usa severidad INFO" "INFO" "$RESULT_SEVERITY"
assert_eq "título declara política cumplida" "Política Secure Token cumplida" "$RESULT_TITLE"
assert_contains "admin ajeno a política permanece visible" "$RESULT_EVIDENCE" "[INVENTORY] OtherAdmin (UID 505): Secure Token DISABLED"
assert_file "PASS también materializa secure_token_detail.txt" "$evidence_file"
pass_artifact="$(cat "$evidence_file")"
assert_contains "artefacto PASS conserva las tres identidades requeridas" "$pass_artifact" "[REQUIRED] AdminCMDB (UID 503): Secure Token ENABLED"
assert_contains "artefacto PASS conserva inventario no objetivo" "$pass_artifact" "[INVENTORY] OtherAdmin (UID 505): Secure Token DISABLED"

if result_validate >/dev/null 2>&1; then
  printf '✓  PASS cumple DiagnosticResult\n'; _pass=$((_pass + 1))
else
  printf '✗  PASS viola DiagnosticResult\n' >&2; _fail=$((_fail + 1))
fi

# Una cuenta requerida ausente también debe ser incumplimiento explícito.
fixture_missing="$tmp_root/missing"
mkdir -p "$fixture_missing"
cat > "$fixture_missing/secure_token_admins.txt" <<'EOF'
CARV8707@itau.cl|502|ENABLED
LCLAdmin|501|ENABLED
EOF
run_fixture "$fixture_missing"

assert_eq "cuenta requerida ausente produce FAIL" "FAIL" "$RESULT_STATUS"
assert_contains "ausencia de AdminCMDB queda accionable" "$RESULT_EVIDENCE" "[REQUIRED] AdminCMDB: cuenta no observada en admin (MISSING)"
assert_file "MISSING también materializa evidencia" "$evidence_file"
missing_artifact="$(cat "$evidence_file")"
assert_contains "artefacto conserva ausencia requerida" "$missing_artifact" "[REQUIRED] AdminCMDB: cuenta no observada en admin (MISSING)"

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
