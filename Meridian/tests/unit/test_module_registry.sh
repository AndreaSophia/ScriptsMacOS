#!/bin/bash
# Regression coverage for module registry framing boundaries.
# Written for Bash 3.2/macOS; no external test framework required.

set -u

TEST_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log_debug() { :; }
log_warn() { :; }
log_error() { :; }

# shellcheck source=/dev/null
source "${TEST_ROOT}/core/module_registry.sh"

_failures=0

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
    _failures=$((_failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_failure() {
  local label="$1"
  shift
  if "$@"; then
    printf 'FAIL: %s (command unexpectedly succeeded)\n' "$label" >&2
    _failures=$((_failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

registry_reset

registry_add \
  "filevault" \
  "FileVault Disk Encryption" \
  "security" \
  "1.0.0" \
  "critical" \
  "/tmp/Meridian/modules/security/filevault" \
  "true" \
  "30" >/dev/null

assert_eq "1" "$(registry_count)" "valid module is registered"
assert_eq "FileVault Disk Encryption" "$(registry_get_field filevault 2)" "name roundtrip"
assert_eq "/tmp/Meridian/modules/security/filevault" "$(registry_get_path filevault)" "path roundtrip"
assert_eq "filevault" "$(registry_get_by_category security)" "category lookup"
assert_eq "" "$(registry_get_dependencies filevault)" "empty dependency field roundtrip"
assert_eq "filevault" "$(registry_get_all_ids)" "all ids roundtrip"

assert_failure \
  "pipe in module name is rejected" \
  registry_add "unsafe_name" "Unsafe | Name" "security" "1.0.0" "low" "/tmp/unsafe_name" "false" "10"

assert_failure \
  "newline in module name is rejected" \
  registry_add "unsafe_newline" $'Unsafe\nName' "security" "1.0.0" "low" "/tmp/unsafe_newline" "false" "10"

assert_failure \
  "pipe in module path is rejected" \
  registry_add "unsafe_path" "Unsafe Path" "security" "1.0.0" "low" "/tmp/unsafe|path" "false" "10"

assert_eq "1" "$(registry_count)" "rejected records do not change registry count"

# El registry forma parte del core y puede ejecutarse en contexto privilegiado.
# Un PATH heredado no debe poder reemplazar la utilidad usada para interpretar
# su framing. Este falso `cut` dejaría una marca si alguna función lo invoca.
_hostile_dir="${TMPDIR:-/tmp}/meridian-registry-path-$$"
_hostile_marker="${_hostile_dir}/cut-invoked"
/bin/mkdir -p "$_hostile_dir"
printf '#!/bin/bash\nprintf invoked > %q\nexit 99\n' "$_hostile_marker" >"${_hostile_dir}/cut"
/bin/chmod 700 "${_hostile_dir}/cut"
_original_path="$PATH"
PATH="$_hostile_dir"

assert_eq "FileVault Disk Encryption" "$(registry_get_field filevault 2)" "registry parsing ignores hostile PATH"
assert_eq "filevault" "$(registry_get_by_category security)" "category parsing ignores hostile PATH"
assert_eq "filevault" "$(registry_get_all_ids)" "id enumeration ignores hostile PATH"

if [ -e "$_hostile_marker" ]; then
  printf 'FAIL: hostile cut was executed\n' >&2
  _failures=$((_failures + 1))
else
  printf 'PASS: hostile cut was not executed\n'
fi

PATH="$_original_path"
/bin/rm -rf "$_hostile_dir"

if [ "$_failures" -ne 0 ]; then
  printf '\n%d module registry test(s) failed.\n' "$_failures" >&2
  exit 1
fi

printf '\nAll module registry boundary tests passed.\n'
