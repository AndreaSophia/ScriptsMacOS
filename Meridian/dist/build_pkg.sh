#!/bin/bash
# =============================================================================
# Meridian — dist/build_pkg.sh
# Construye el .pkg para distribución enterprise (Workspace ONE / Jamf).
# Compatible con herramientas nativas de macOS.
#
# Uso:
#   bash dist/build_pkg.sh
#   bash dist/build_pkg.sh --sign "Developer ID Installer: Empresa (TEAMID)"
# =============================================================================

set -euo pipefail

readonly PKG_NAME="Meridian"
readonly PKG_VERSION="$(cat "$(dirname "$0")/../VERSION" 2>/dev/null | tr -d '[:space:]' || echo '1.0.0-mvp')"
readonly PKG_IDENTIFIER="com.itau.apple.meridian"
readonly PKG_INSTALL_LOCATION="/usr/local/lib/meridian"
readonly PKG_COMMAND_PATH="/usr/local/bin/meridian"
readonly PKG_OUTPUT="${PKG_NAME}-${PKG_VERSION}.pkg"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${SCRIPT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/payload"
PKG_SCRIPTS_DIR="${BUILD_DIR}/scripts"
SIGN_IDENTITY=""

_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --sign)
        [ $# -ge 2 ] || { echo "[ERROR] --sign requiere certificado" >&2; exit 2; }
        SIGN_IDENTITY="$2"
        shift 2
        ;;
      --help|-h)
        echo "Uso: bash dist/build_pkg.sh [--sign 'Developer ID Installer: Empresa (TEAMID)']"
        exit 0
        ;;
      *)
        echo "[ERROR] Argumento desconocido: $1" >&2
        exit 2
        ;;
    esac
  done
}

_check_requirements() {
  echo "[CHECK] Verificando requisitos..."
  for tool in pkgbuild productbuild; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "[ERROR] '$tool' no encontrado. Instala Command Line Tools: xcode-select --install" >&2
      exit 1
    }
  done

  [ -f "${PROJECT_ROOT}/meridian" ] || {
    echo "[ERROR] No se encontró el entrypoint 'meridian' en: ${PROJECT_ROOT}" >&2
    exit 1
  }

  [ -s "${PROJECT_ROOT}/VERSION" ] || {
    echo "[ERROR] VERSION ausente o vacío" >&2
    exit 1
  }

  echo "[OK]    Requisitos verificados. PKG version: ${PKG_VERSION}"
}

_prepare_payload() {
  echo "[BUILD] Preparando payload..."
  rm -rf "$BUILD_DIR"

  mkdir -p "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}"
  mkdir -p "${PAYLOAD_DIR}/usr/local/bin"
  mkdir -p "$PKG_SCRIPTS_DIR"

  cp "${PROJECT_ROOT}/meridian" "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/meridian"
  cp "${PROJECT_ROOT}/VERSION"  "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/VERSION"

  for dir in config modules rules core services reporting logging ui contracts; do
    if [ -d "${PROJECT_ROOT}/${dir}" ]; then
      cp -R "${PROJECT_ROOT}/${dir}" "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
    fi
  done

  # El entrypoint debe ser ejecutable. Los .sh internos se cargan/ejecutan
  # explícitamente mediante bash/source y no necesitan permiso executable.
  chmod 755 "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/meridian"
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -type f -name "*.sh" -exec chmod 644 {} \;
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -type f -name "*.yaml" -exec chmod 644 {} \;

  # El enlace se crea en postinstall, no dentro del payload. Así evitamos
  # empaquetar symlinks absolutos ambiguos y podemos reemplazar instalaciones previas.
  cat > "${PKG_SCRIPTS_DIR}/postinstall" <<'POSTINSTALL'
#!/bin/bash
set -u

INSTALL_ROOT="/usr/local/lib/meridian"
COMMAND_PATH="/usr/local/bin/meridian"

mkdir -p "/usr/local/bin" || exit 1

if [ ! -x "${INSTALL_ROOT}/meridian" ]; then
  echo "[Meridian] entrypoint no encontrado o no ejecutable: ${INSTALL_ROOT}/meridian" >&2
  exit 1
fi

rm -f "$COMMAND_PATH" || exit 1
ln -s "${INSTALL_ROOT}/meridian" "$COMMAND_PATH" || exit 1

# Asegurar directorio corporativo de audit log con acceso restringido.
mkdir -p "/Library/Logs/Meridian" || exit 1
chmod 750 "/Library/Logs/Meridian" || true

exit 0
POSTINSTALL
  chmod 755 "${PKG_SCRIPTS_DIR}/postinstall"

  echo "[OK]    Payload preparado"
}

_build_component_pkg() {
  echo "[BUILD] Construyendo componente PKG..."
  pkgbuild \
    --root "${PAYLOAD_DIR}" \
    --identifier "${PKG_IDENTIFIER}" \
    --version "${PKG_VERSION}" \
    --install-location "/" \
    --scripts "${PKG_SCRIPTS_DIR}" \
    "${BUILD_DIR}/${PKG_NAME}-component.pkg"
  echo "[OK]    Componente PKG creado"
}

_build_product_pkg() {
  echo "[BUILD] Construyendo PKG final..."
  local dist_xml="${BUILD_DIR}/Distribution.xml"

  cat > "$dist_xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Meridian ${PKG_VERSION}</title>
    <organization>com.itau.apple</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <pkg-ref id="${PKG_IDENTIFIER}"/>
    <choices-outline>
        <line choice="${PKG_IDENTIFIER}"/>
    </choices-outline>
    <choice id="${PKG_IDENTIFIER}" visible="false">
        <pkg-ref id="${PKG_IDENTIFIER}"/>
    </choice>
    <pkg-ref id="${PKG_IDENTIFIER}" version="${PKG_VERSION}" onConclusion="none">${PKG_NAME}-component.pkg</pkg-ref>
</installer-gui-script>
XML

  local output_pkg="${SCRIPT_DIR}/${PKG_OUTPUT}"
  rm -f "$output_pkg"

  if [ -n "$SIGN_IDENTITY" ]; then
    productbuild \
      --distribution "$dist_xml" \
      --package-path "$BUILD_DIR" \
      --sign "$SIGN_IDENTITY" \
      "$output_pkg"
  else
    productbuild \
      --distribution "$dist_xml" \
      --package-path "$BUILD_DIR" \
      "$output_pkg"
    echo "[WARN]  PKG no firmado. Firmar antes de distribución productiva."
  fi

  echo "[OK]    PKG final: ${output_pkg}"
}

_verify_pkg() {
  local output_pkg="${SCRIPT_DIR}/${PKG_OUTPUT}"
  [ -f "$output_pkg" ] || { echo "[ERROR] PKG no encontrado" >&2; exit 1; }

  local size
  size="$(du -sh "$output_pkg" | awk '{print $1}')"

  if command -v pkgutil >/dev/null 2>&1; then
    pkgutil --check-signature "$output_pkg" >/dev/null 2>&1 || {
      [ -z "$SIGN_IDENTITY" ] || {
        echo "[ERROR] El PKG firmado no supera pkgutil --check-signature" >&2
        exit 1
      }
    }
  fi

  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  PKG preparado para Workspace ONE / Jamf"
  echo "  ${output_pkg} (${size})"
  echo ""
  echo "  Install location : ${PKG_INSTALL_LOCATION}"
  echo "  Command           : ${PKG_COMMAND_PATH}"
  echo "  Ejecutar          : sudo meridian"
  echo "══════════════════════════════════════════════════"
}

_parse_args "$@"
_check_requirements
_prepare_payload
_build_component_pkg
_build_product_pkg
_verify_pkg
