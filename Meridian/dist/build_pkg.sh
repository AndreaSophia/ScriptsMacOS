#!/bin/bash
# =============================================================================
# Meridian — dist/build_pkg.sh
# Construye el .pkg para distribución mediante Workspace ONE o Jamf.
# Uso: cd dist && sudo bash build_pkg.sh [--sign "Developer ID Installer: ..."]
# =============================================================================

set -euo pipefail

readonly PKG_NAME="Meridian"
readonly PKG_VERSION="$(cat "$(dirname "$0")/../VERSION" 2>/dev/null | tr -d '[:space:]' || echo '1.0.0-mvp')"
readonly PKG_IDENTIFIER="com.itau.apple.meridian"
readonly PKG_INSTALL_LOCATION="/usr/local/lib/meridian"
readonly PKG_OUTPUT="${PKG_NAME}-${PKG_VERSION}.pkg"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${SCRIPT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/payload"
PKG_SCRIPTS_DIR="${SCRIPT_DIR}/pkg/scripts"
SIGN_IDENTITY=""

_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --sign) SIGN_IDENTITY="${2:?'--sign requiere certificado'}"; shift 2 ;;
      --help)
        echo "Uso: sudo bash build_pkg.sh [--sign 'Developer ID Installer: Empresa (TEAMID)']"
        exit 0 ;;
      *) shift ;;
    esac
  done
}

_check_requirements() {
  echo "[CHECK] Verificando requisitos..."
  for tool in pkgbuild productbuild; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "[ERROR] '$tool' no encontrado. Instala: xcode-select --install" >&2
      exit 1
    }
  done
  [ -f "${PROJECT_ROOT}/meridian" ] || {
    echo "[ERROR] No se encontró el entrypoint 'meridian' en: ${PROJECT_ROOT}" >&2
    exit 1
  }
  echo "[OK]    Requisitos verificados. PKG version: ${PKG_VERSION}"
}

_prepare_payload() {
  echo "[BUILD] Preparando payload..."
  rm -rf "$BUILD_DIR"
  mkdir -p "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/lib"
  mkdir -p "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/modules"
  mkdir -p "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/rules"
  mkdir -p "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/config"

  cp "${PROJECT_ROOT}/meridian" "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp "${PROJECT_ROOT}/VERSION"  "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"

  cp "${PROJECT_ROOT}/lib/"*.sh        "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/lib/" 2>/dev/null || true
  cp "${PROJECT_ROOT}/config/"*.yaml   "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/config/"
  cp -r "${PROJECT_ROOT}/modules"      "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/rules"        "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/core"         "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/services"     "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/reporting"    "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/logging"      "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"
  cp -r "${PROJECT_ROOT}/ui"           "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/"

  chmod 755 "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/meridian"
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -name "*.sh" -exec chmod 644 {} \;
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -name "*.yaml" -exec chmod 644 {} \;

  echo "[OK]    Payload preparado"
}

_build_component_pkg() {
  echo "[BUILD] Construyendo componente PKG..."
  mkdir -p "$PKG_SCRIPTS_DIR"
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
    echo "[WARN]  PKG no firmado. Usar --sign para distribución enterprise."
  fi
  echo "[OK]    PKG final: ${output_pkg}"
}

_verify_pkg() {
  local output_pkg="${SCRIPT_DIR}/${PKG_OUTPUT}"
  [ -f "$output_pkg" ] || { echo "[ERROR] PKG no encontrado" >&2; exit 1; }
  local size
  size="$(du -sh "$output_pkg" | awk '{print $1}')"
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  PKG listo para Workspace ONE / Jamf:"
  echo "  ${output_pkg} (${size})"
  echo ""
  echo "  Install location : ${PKG_INSTALL_LOCATION}"
  echo "  Ejecutar         : sudo meridian"
  echo "══════════════════════════════════════════════════"
}

_parse_args "$@"
_check_requirements
_prepare_payload
_build_component_pkg
_build_product_pkg
_verify_pkg
