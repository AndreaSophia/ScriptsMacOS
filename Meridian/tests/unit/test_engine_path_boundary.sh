#!/bin/bash
# Regression coverage: privileged engine boundaries must not resolve filesystem
# or framing utilities through an inherited PATH. Bash 3.2 compatible.

MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
_TMP_ROOT="${TMPDIR:-/tmp}/meridian-engine-path-$$"
_EVIDENCE_DIR="${_TMP_ROOT}/evidence"
_HOSTILE_DIR="${_TMP_ROOT}/hostile"
_MARKER="${_TMP_ROOT}/hostile-invoked"

/bin/mkdir -p "$_EVIDENCE_DIR" "$_HOSTILE_DIR" || exit 1
trap '/bin/rm -rf "$_TMP_ROOT"' EXIT

source "${MERIDIAN_ROOT}/core/result_model.sh"

log_error() { :; }
log_warn()  { :; }
log_info()  { :; }
log_debug() { :; }

registry_exists() { [ "$1" = "alpha" ]; }
registry_get_field() {
  case "$2" in
    2) printf '%s\n' "Alpha" ;;
    4) printf '%s\n' "1.0.0" ;;
    *) return 1 ;;
  esac
}

_AGG_CAPTURE=""
aggregator_add() {
  _AGG_CAPTURE="$(result_serialize)" || return 1
  return 0
}
rule_engine_evaluate() { return 0; }

module_loader_run() {
  result_init
  RESULT_MODULE_ID="alpha"
  RESULT_MODULE_VERSION="1.0.0"
  RESULT_STATUS="PASS"
  RESULT_SEVERITY="INFO"
  RESULT_TITLE="Fixture"
  RESULT_DESCRIPTION="Fixture description"
  RESULT_EXPLANATION="Fixture explanation"
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="N/A"
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  result_serialize
}

source "${MERIDIAN_ROOT}/core/engine.sh"
MERIDIAN_EVIDENCE_DIR="$_EVIDENCE_DIR"

# Cada nombre coincide con una utilidad externa que el engine utiliza al crear
# sesiones o procesar stdout del module loader. Si cualquiera se resuelve por
# PATH, deja una marca y aborta con rc=99.
for _name in dirname mkdir mktemp tail wc tr sed rm; do
  printf '#!/bin/bash\nprintf "%s\\n" %q >> %q\nexit 99\n' \
    "$_name" "$_name" "$_MARKER" >"${_HOSTILE_DIR}/${_name}"
  /bin/chmod 700 "${_HOSTILE_DIR}/${_name}"
done

_ORIGINAL_PATH="$PATH"
PATH="$_HOSTILE_DIR"

_fail=0
printf '\ntest_engine_path_boundary.sh\n\n'

if _engine_run_module alpha >/dev/null 2>&1; then
  printf 'PASS: engine procesa resultado con PATH hostil\n'
else
  printf 'FAIL: engine falló al procesar resultado con PATH hostil\n' >&2
  _fail=$((_fail + 1))
fi

if [ -n "$_AGG_CAPTURE" ] && result_deserialize "$_AGG_CAPTURE" >/dev/null 2>&1 && [ "$RESULT_STATUS" = "PASS" ]; then
  printf 'PASS: resultado canónico permanece intacto\n'
else
  printf 'FAIL: resultado canónico no fue preservado\n' >&2
  _fail=$((_fail + 1))
fi

if [ -e "$_MARKER" ]; then
  printf 'FAIL: el engine ejecutó una utilidad desde PATH hostil\n' >&2
  /bin/cat "$_MARKER" >&2
  _fail=$((_fail + 1))
else
  printf 'PASS: ninguna utilidad hostil fue ejecutada\n'
fi

PATH="$_ORIGINAL_PATH"

printf '\nFallaron: %s\n\n' "$_fail"
exit "$_fail"
