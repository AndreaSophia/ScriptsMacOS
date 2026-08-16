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

# Los casos que construyen ZIP requieren las rutas estándar que el servicio fija
# explícitamente. En macOS son parte del sistema base; un runner mínimo puede no
# tenerlas y en ese caso no fingimos haber ejercitado la construcción real.
if [ -x /usr/bin/zip ] && [ -x /usr/bin/mktemp ] && [ -x /bin/ln ] && [ -x /bin/rm ]; then
  # Caso 6: publicación sana produce un archivo regular nuevo.
  GOOD_ZIP="$OUTPUT_DIR/good.zip"
  PUBLISHED="$(archive_service_create "$SESSION_DIR" "$GOOD_ZIP")"
  _assert_eq "$GOOD_ZIP" "$PUBLISHED" "archive service returns canonical published path"
  if [ -f "$GOOD_ZIP" ] && [ ! -L "$GOOD_ZIP" ]; then
    _pass "archive service publishes a regular ZIP artifact"
  else
    _fail "archive service publishes a regular ZIP artifact"
  fi

  # Caso 7: PATH hostil no debe poder sustituir utilidades privilegiadas. Se
  # instalan binarios falsos con los mismos nombres; ninguno debe ejecutarse.
  FAKE_BIN="$TMP_ROOT/fake-bin"
  HIJACK_MARKER="$TMP_ROOT/path-hijack-executed"
  mkdir -p "$FAKE_BIN" || exit 1
  for tool in zip mktemp ln rm mkdir dirname basename; do
    cat > "$FAKE_BIN/$tool" <<EOF
#!/bin/sh
printf '%s\n' '$tool' >> '$HIJACK_MARKER'
exit 99
EOF
    chmod +x "$FAKE_BIN/$tool" || exit 1
  done

  PATH_BEFORE="$PATH"
  PATH="$FAKE_BIN:$PATH"
  export PATH
  PINNED_ZIP="$OUTPUT_DIR/pinned-tools.zip"
  if archive_service_create "$SESSION_DIR" "$PINNED_ZIP" >/dev/null 2>&1; then
    _pass "archive service ignores hostile PATH for privileged tools"
  else
    _fail "archive service ignores hostile PATH for privileged tools"
  fi
  PATH="$PATH_BEFORE"
  export PATH

  if [ ! -e "$HIJACK_MARKER" ]; then
    _pass "hostile PATH binaries were not executed"
  else
    _fail "hostile PATH binaries were not executed"
  fi
else
  _pass "system archive tools unavailable; archive build cases skipped on this runner"
fi

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
