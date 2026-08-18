#!/bin/bash
# Truth tests: un enrollment MDM genérico no puede atribuirse a Workspace ONE.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_ws1_truth.XXXXXX")"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_ws1_evidence.XXXXXX")"
trap 'rm -rf "$fixture_dir" "$evidence_dir"' EXIT

export MERIDIAN_TEST_MODE=1
export MERIDIAN_FIXTURE_DIR="$fixture_dir"
export MERIDIAN_EVIDENCE_DIR="$evidence_dir"
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

# Caso 1: macOS dice MDM=Yes, pero no existe ninguna señal WS1.
printf '%s\n' 'Enrolled via DEP: No' 'MDM enrollment: Yes (User Approved)' > "${fixture_dir}/profiles_enrolled.txt"
result_init
RESULT_MODULE_ID="workspace_one"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/mdm/workspace_one/diagnose.sh"
assert_eq "MDM genérico no se atribuye a WS1" "SKIP" "$RESULT_STATUS"
assert_eq "título declara proveedor no confirmado" "MDM detectado; Workspace ONE no confirmado" "$RESULT_TITLE"

# Caso 2: misma señal MDM + evidencia explícita de AirWatch/WS1, sin Hub.
printf '%s\n' 'profileIdentifier: com.airwatch.macos.enrollment' > "${fixture_dir}/workspace_one_vendor_evidence.txt"
result_init
RESULT_MODULE_ID="workspace_one"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/mdm/workspace_one/diagnose.sh"
assert_eq "evidencia WS1 + MDM sin Hub produce WARN" "WARN" "$RESULT_STATUS"
assert_eq "WARN solo ocurre con proveedor demostrado" "Workspace ONE detectado pero Hub no encontrado" "$RESULT_TITLE"

# Caso 3: sin MDM y sin señales WS1 debe ser ausencia, no incumplimiento global.
rm -f "${fixture_dir}/workspace_one_vendor_evidence.txt"
printf '%s\n' 'Enrolled via DEP: No' 'MDM enrollment: No' > "${fixture_dir}/profiles_enrolled.txt"
result_init
RESULT_MODULE_ID="workspace_one"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/mdm/workspace_one/diagnose.sh"
assert_eq "Mac limpio sin WS1 produce SKIP" "SKIP" "$RESULT_STATUS"
assert_eq "Mac limpio se describe como WS1 no detectado" "Workspace ONE no detectado" "$RESULT_TITLE"

printf 'Pasaron: %s | Fallaron: %s\n' "$_pass" "$_fail"
exit "$_fail"
