#!/bin/bash
# Regression: el builder no debe publicar metadata Finder/AppleDouble en el PKG.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/dist/build_pkg.sh"

passed=0
failed=0

pass() {
  printf '✓  %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf '✗  %s\n' "$1" >&2
  failed=$((failed + 1))
}

assert_contains() {
  needle="$1"
  label="$2"
  if /usr/bin/grep -Fq "$needle" "$BUILD_SCRIPT"; then
    pass "$label"
  else
    fail "$label"
  fi
}

if /bin/bash -n "$BUILD_SCRIPT"; then
  pass "build_pkg.sh válido para parser Bash"
else
  fail "build_pkg.sh válido para parser Bash"
fi

assert_contains 'COPYFILE_DISABLE=1 cp' \
  "copias del payload deshabilitan metadata lateral de macOS"
assert_contains '/usr/bin/xattr -cr "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}"' \
  "payload elimina extended attributes antes de pkgbuild"
assert_contains "-name '._*'" \
  "payload elimina defensivamente archivos AppleDouble"
assert_contains "-name '.DS_Store'" \
  "payload elimina metadata Finder"
assert_contains 'pkgutil --payload-files "$output_pkg"' \
  "PKG final inspecciona su payload publicado"
assert_contains "grep -Eq '(^|/)\\._|(^|/)\\.DS_Store$'" \
  "verificación final rechaza metadata AppleDouble/Finder"

echo "Pasaron: ${passed} | Fallaron: ${failed}"
[ "$failed" -eq 0 ]
