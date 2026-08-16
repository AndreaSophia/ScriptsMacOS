#!/bin/bash
# Meridian — tests/unit/test_archive_service.sh
# Regression coverage for fail-closed session archive publication.
# Compatible with Bash 3.2; no macOS-only system calls required.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERIDIAN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TESTS=0
FAILURES=0

_pass() { TESTS=$((TESTS + 1)); printf 'PASS: %s\n' "$1"; }
_fail() { TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }
_assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" = "$actual" ]; then _pass "$name"; else _fail "$name (expected='$expected' actual='$actual')"; fi
}

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/services/archive_service.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_archive_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

SESSION_DIR="$TMP_ROOT/session"
OUTPUT_DIR="$TMP_ROOT/output"
mkdir -p "$SESSION_DIR" "$OUTPUT_DIR" || exit 1
printf '%s\n' 'fixture-evidence' > "$SESSION_DIR/evidence.txt"

# Caso 1: argumentos incompletos se rechazan antes de tocar filesystem.
if archive_service_create >/dev/null 2>&1; then
  _fail "archive service rejects missing arguments"
else
  _pass "archive service rejects missing arguments"
fi

# Caso 2: el directorio de sesión no puede ser un symlink.
SESSION_LINK="$TMP_ROOT/session-link"
ln -s "$SESSION_DIR" "$SESSION_LINK" || exit 1
if archive_service_create "$SESSION_LINK" "$OUTPUT_DIR/symlink-session.zip" >/dev/null 2>&1; then
  _fail "archive service rejects symlink session directory"
else
  _pass "archive service rejects symlink session directory"
fi

# Caso 3: un ZIP preexistente nunca se actualiza ni sobrescribe.
EXISTING_ZIP="$OUTPUT_DIR/existing.zip"
printf '%s\n' 'do-not-touch' > "$EXISTING_ZIP"
BEFORE="$(cat "$EXISTING_ZIP")"
if archive_service_create "$SESSION_DIR" "$EXISTING_ZIP" >/dev/null 2>&1; then
  _fail "archive service rejects preexisting destination"
else
  _pass "archive service rejects preexisting destination"
fi
_assert_eq "$BEFORE" "$(cat "$EXISTING_ZIP")" "preexisting destination remains unchanged"

# Caso 4: un symlink de destino se rechaza y su target queda intacto.
TARGET_FILE="$TMP_ROOT/target.txt"
LINK_ZIP="$OUTPUT_DIR/link.zip"
printf '%s\n' 'protected-target' > "$TARGET_FILE"
ln -s "$TARGET_FILE" "$LINK_ZIP" || exit 1
if archive_service_create "$SESSION_DIR" "$LINK_ZIP" >/dev/null 2>&1; then
  _fail "archive service rejects symlink destination"
else
  _pass "archive service rejects symlink destination"
fi
_assert_eq "protected-target" "$(cat "$TARGET_FILE")" "symlink target remains unchanged"

# Caso 5: el directorio directo de publicación tampoco puede ser symlink.
REAL_OUTPUT="$TMP_ROOT/real-output"
LINK_OUTPUT="$TMP_ROOT/link-output"
mkdir -p "$REAL_OUTPUT" || exit 1
ln -s "$REAL_OUTPUT" "$LINK_OUTPUT" || exit 1
if archive_service_create "$SESSION_DIR" "$LINK_OUTPUT/session.zip" >/dev/null 2>&1; then
  _fail "archive service rejects symlink destination directory"
else
  _pass "archive service rejects symlink destination directory"
fi

# Los casos que construyen ZIP requieren la utilidad estándar. En macOS está
# disponible, pero el test sigue siendo portable para runners mínimos.
if command -v zip >/dev/null 2>&1; then
  # Caso 6: publicación sana produce un archivo regular nuevo.
  GOOD_ZIP="$OUTPUT_DIR/good.zip"
  PUBLISHED="$(archive_service_create "$SESSION_DIR" "$GOOD_ZIP")"
  _assert_eq "$GOOD_ZIP" "$PUBLISHED" "archive service returns canonical published path"
  if [ -f "$GOOD_ZIP" ] && [ ! -L "$GOOD_ZIP" ]; then
    _pass "archive service publishes a regular ZIP artifact"
  else
    _fail "archive service publishes a regular ZIP artifact"
  fi

  # Caso 7: simular que el destino aparece entre build y publicación. ln(1)
  # debe fallar y el service no puede reemplazar el objeto que apareció.
  RACE_ZIP="$OUTPUT_DIR/race.zip"
  ln() {
    printf '%s\n' 'appeared-during-publication' > "$2"
    return 1
  }
  if archive_service_create "$SESSION_DIR" "$RACE_ZIP" >/dev/null 2>&1; then
    _fail "archive service fails closed on publication race"
  else
    _pass "archive service fails closed on publication race"
  fi
  unset -f ln
  _assert_eq "appeared-during-publication" "$(cat "$RACE_ZIP")" "publication race object is not overwritten"
else
  _pass "zip unavailable; archive build cases skipped on this runner"
fi

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
