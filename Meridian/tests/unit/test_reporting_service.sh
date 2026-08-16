#!/bin/bash
# Meridian — tests/unit/test_reporting_service.sh
# Regression coverage for the reporting service boundary.
# Compatible with Bash 3.2; no macOS system calls required.

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

log_error() { :; }
log_warn() { :; }

diagnostic_service_get_results() { printf '%s\n' 'fixture-result'; }
diagnostic_service_get_summary() { printf '%s\n' 'total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO'; }
# Si reporting_service vuelve a saltarse la frontera service y toca el engine
# directamente, este stub hace visible la regresión.
engine_get_summary() { printf '%s\n' 'ENGINE_BOUNDARY_VIOLATION'; }

# shellcheck source=/dev/null
source "${MERIDIAN_ROOT}/services/reporting_service.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meridian_reporting_test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

# Caso 1: ambos renderers exitosos y el service conserva ambas rutas.
CAPTURED_SUMMARY=""
renderer_txt_generate() {
  CAPTURED_SUMMARY="$3"
  : > "$1/Executive_Report.txt" || return 1
  printf '%s\n' "$1/Executive_Report.txt"
}
renderer_json_generate() {
  : > "$1/results.json" || return 1
  printf '%s\n' "$1/results.json"
}

if reporting_service_generate "$TMP_ROOT" txt json; then
  _pass "reporting service succeeds when both renderers create artifacts"
else
  _fail "reporting service succeeds when both renderers create artifacts"
fi
_assert_eq "$TMP_ROOT/Executive_Report.txt" "$REPORTING_TXT_PATH" "TXT path is retained"
_assert_eq "$TMP_ROOT/results.json" "$REPORTING_JSON_PATH" "JSON path is retained"
_assert_eq "total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO" "$CAPTURED_SUMMARY" "summary comes through diagnostic service boundary"

# Caso 2: TXT falla, JSON debe ejecutarse igualmente y conservar su ruta.
TXT_CALLED=0
JSON_CALLED=0
renderer_txt_generate() { TXT_CALLED=$((TXT_CALLED + 1)); return 1; }
renderer_json_generate() {
  JSON_CALLED=$((JSON_CALLED + 1))
  : > "$1/results.json" || return 1
  printf '%s\n' "$1/results.json"
}

if reporting_service_generate "$TMP_ROOT" txt json; then
  _fail "reporting service reports partial renderer failure"
else
  _pass "reporting service reports partial renderer failure"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "failed TXT renderer leaves empty path"
_assert_eq "$TMP_ROOT/results.json" "$REPORTING_JSON_PATH" "successful JSON path survives TXT failure"
_assert_eq "1" "$TXT_CALLED" "TXT renderer attempted once"
_assert_eq "1" "$JSON_CALLED" "JSON renderer still attempted after TXT failure"

# Caso 3: invocación sin output_dir debe fallar de forma explícita bajo set -u.
if reporting_service_generate; then
  _fail "reporting service rejects missing output directory"
else
  _pass "reporting service rejects missing output directory"
fi

# Caso 4: una sesión sin resultados no debe producir reportes vacíos ni depender
# de cómo el caller tenga configurado errexit.
diagnostic_service_get_results() { return 1; }
renderer_txt_generate() { _fail "TXT renderer must not run without session results"; return 1; }
renderer_json_generate() { _fail "JSON renderer must not run without session results"; return 1; }
if reporting_service_generate "$TMP_ROOT" txt json; then
  _fail "reporting service fails when session results are unavailable"
else
  _pass "reporting service fails when session results are unavailable"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "TXT path remains empty without results"
_assert_eq "" "$REPORTING_JSON_PATH" "JSON path remains empty without results"

# Caso 5: un resumen ausente también falla antes de entrar a renderers.
diagnostic_service_get_results() { printf '%s\n' 'fixture-result'; }
diagnostic_service_get_summary() { return 1; }
if reporting_service_generate "$TMP_ROOT" txt; then
  _fail "reporting service fails when session summary is unavailable"
else
  _pass "reporting service fails when session summary is unavailable"
fi

# Caso 6: rc=0 sin ruta no cuenta como éxito.
diagnostic_service_get_summary() { printf '%s\n' 'total=1 pass=1 warn=0 fail=0 skip=0 error=0 worst_severity=INFO'; }
renderer_txt_generate() { return 0; }
if reporting_service_generate "$TMP_ROOT" txt; then
  _fail "reporting service rejects empty renderer success path"
else
  _pass "reporting service rejects empty renderer success path"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "empty renderer success does not publish TXT path"

# Caso 7: una ruta no vacía pero inexistente tampoco es un artefacto válido.
renderer_txt_generate() { printf '%s\n' "$1/ghost-report.txt"; }
if reporting_service_generate "$TMP_ROOT" txt; then
  _fail "reporting service rejects nonexistent renderer artifact"
else
  _pass "reporting service rejects nonexistent renderer artifact"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "nonexistent artifact is not published"

# Caso 8: un renderer no puede publicar un archivo fuera del directorio de sesión.
OUTSIDE_FILE="${TMP_ROOT}.outside.txt"
: > "$OUTSIDE_FILE" || exit 1
renderer_txt_generate() { printf '%s\n' "$OUTSIDE_FILE"; }
if reporting_service_generate "$TMP_ROOT" txt; then
  _fail "reporting service rejects artifact outside session directory"
else
  _pass "reporting service rejects artifact outside session directory"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "outside artifact is not published"
rm -f "$OUTSIDE_FILE"

# Caso 9: symlinks no se publican como artefactos canónicos de reporting.
REAL_FILE="$TMP_ROOT/real-report.txt"
LINK_FILE="$TMP_ROOT/link-report.txt"
: > "$REAL_FILE" || exit 1
ln -s "$REAL_FILE" "$LINK_FILE" || exit 1
renderer_txt_generate() { printf '%s\n' "$LINK_FILE"; }
if reporting_service_generate "$TMP_ROOT" txt; then
  _fail "reporting service rejects symlink renderer artifact"
else
  _pass "reporting service rejects symlink renderer artifact"
fi
_assert_eq "" "$REPORTING_TXT_PATH" "symlink artifact is not published"

# Caso 10: el propio directorio de reporting no puede ser un symlink. Esta
# frontera puede correr como root y no debe aceptar redirección de escritura.
REAL_DIR="$TMP_ROOT/real-dir"
LINK_DIR="$TMP_ROOT/link-dir"
mkdir "$REAL_DIR" || exit 1
ln -s "$REAL_DIR" "$LINK_DIR" || exit 1
renderer_txt_generate() {
  : > "$1/linked-report.txt" || return 1
  printf '%s\n' "$1/linked-report.txt"
}
if reporting_service_generate "$LINK_DIR" txt; then
  _fail "reporting service rejects symlink output directory"
else
  _pass "reporting service rejects symlink output directory"
fi
[ ! -e "$REAL_DIR/linked-report.txt" ] && _pass "symlink output directory is rejected before renderer write" || _fail "symlink output directory is rejected before renderer write"

# Caso 11: mkdir y dirname falsos en PATH no deben participar en la frontera.
# El service fija /bin/mkdir y valida padres con parameter expansion + builtins.
HOSTILE_BIN="$TMP_ROOT/hostile-bin"
HOSTILE_MARKER="$TMP_ROOT/hostile-called"
mkdir "$HOSTILE_BIN" || exit 1
printf '%s\n' '#!/bin/bash' "printf 'called\\n' >> '$HOSTILE_MARKER'" > "$HOSTILE_BIN/mkdir"
printf '%s\n' '#!/bin/bash' "printf 'called\\n' >> '$HOSTILE_MARKER'" > "$HOSTILE_BIN/dirname"
chmod +x "$HOSTILE_BIN/mkdir" "$HOSTILE_BIN/dirname" || exit 1
SAFE_PATH="$PATH"
PATH="$HOSTILE_BIN:$PATH"
NEW_REPORT_DIR="$TMP_ROOT/new-report-dir"
renderer_txt_generate() {
  : > "$1/path-safe.txt" || return 1
  printf '%s\n' "$1/path-safe.txt"
}
if reporting_service_generate "$NEW_REPORT_DIR" txt; then
  _pass "reporting service ignores hostile PATH filesystem tools"
else
  _fail "reporting service ignores hostile PATH filesystem tools"
fi
PATH="$SAFE_PATH"
[ ! -e "$HOSTILE_MARKER" ] && _pass "hostile PATH tools were not executed" || _fail "hostile PATH tools were not executed"
_assert_eq "$NEW_REPORT_DIR/path-safe.txt" "$REPORTING_TXT_PATH" "trusted mkdir path still publishes valid artifact"

printf '\nTests: %s | Failures: %s\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
