#!/bin/bash
# Truth test: --test no puede consultar procesos/servicios/rutas del host para
# construir el estado Forcepoint.

set -u
MERIDIAN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_fp_fixture.XXXXXX")"
evidence_dir="$(mktemp -d "${TMPDIR:-/tmp}/meridian_fp_evidence.XXXXXX")"
fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/meridian_fp_fakebin.XXXXXX")"
marker="${fixture_dir}/host_command_called"
trap 'rm -rf "$fixture_dir" "$evidence_dir" "$fake_bin"' EXIT

# Si el módulo intenta observar el host en modo fixture, estos stubs dejan una
# marca y además simulan señales Forcepoint para hacer visible la contaminación.
for cmd in ps launchctl systemextensionsctl scutil; do
  cat > "${fake_bin}/${cmd}" <<EOF
#!/bin/bash
echo "${cmd}" >> "${marker}"
echo "Forcepoint fake host signal"
exit 0
EOF
  chmod +x "${fake_bin}/${cmd}"
done

export PATH="${fake_bin}:${PATH}"
export MERIDIAN_TEST_MODE=1
export MERIDIAN_FIXTURE_DIR="$fixture_dir"
export MERIDIAN_EVIDENCE_DIR="$evidence_dir"

source "${MERIDIAN_ROOT}/core/result_model.sh"
result_init
RESULT_MODULE_ID="forcepoint"
RESULT_MODULE_VERSION="1.0.0"
source "${MERIDIAN_ROOT}/modules/network/forcepoint/diagnose.sh"

_fail=0
if [ "$RESULT_STATUS" = "SKIP" ] && [ "$RESULT_TITLE" = "Forcepoint no detectado" ]; then
  printf '✓  fixture vacío permanece limpio: %s\n' "$RESULT_STATUS"
else
  printf '✗  fixture vacío contaminado: status=%s title=%s\n' "$RESULT_STATUS" "$RESULT_TITLE" >&2
  _fail=$((_fail + 1))
fi

if [ ! -e "$marker" ]; then
  printf '✓  no se consultaron ps/launchctl/systemextensionsctl/scutil del host\n'
else
  printf '✗  se consultaron comandos del host durante --test:\n' >&2
  cat "$marker" >&2
  _fail=$((_fail + 1))
fi

case "$RESULT_RAW_OUTPUT" in
  'installed=false process=false launchd=false systemext=false')
    printf '✓  raw output deriva solo de fixtures vacíos\n'
    ;;
  *)
    printf '✗  raw output inesperado: %s\n' "$RESULT_RAW_OUTPUT" >&2
    _fail=$((_fail + 1))
    ;;
esac

exit "$_fail"
