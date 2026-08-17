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
readonly MERIDIAN_VERSION="$(cat "$(dirname "$0")/../VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
# VERSION es la versión humana del producto y puede llevar un sufijo de
# prerelease (por ejemplo 1.0.0-mvp). Installer necesita una versión de paquete
# estable para comparar upgrades, por lo que usamos únicamente el prefijo
# numérico X.Y.Z como metadata machine-readable del PKG.
readonly PKG_VERSION="${MERIDIAN_VERSION%%-*}"
readonly PKG_IDENTIFIER="com.itau.apple.meridian"
readonly PKG_INSTALL_LOCATION="/usr/local/lib/meridian"
readonly PKG_COMMAND_PATH="/usr/local/bin/meridian"
readonly PKG_OUTPUT="${PKG_NAME}-${MERIDIAN_VERSION}.pkg"
readonly PAYLOAD_MANIFEST_NAME=".meridian-payload-manifest"
# Meridian contiene shell scripts y datos, no binarios Mach-O. Declaramos ambas
# arquitecturas macOS soportadas para impedir que Installer infiera un producto
# x86_64-only y solicite Rosetta innecesariamente en Apple Silicon.
readonly PKG_HOST_ARCHITECTURES="arm64,x86_64"

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

  # Mantener una sola fuente de verdad: VERSION puede ser X.Y.Z o
  # X.Y.Z-etiqueta, pero la porción que llega a Installer debe ser X.Y.Z.
  printf '%s\n' "$MERIDIAN_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9._-]*)?$' || {
    echo "[ERROR] VERSION inválida: '${MERIDIAN_VERSION}' (esperado X.Y.Z o X.Y.Z-etiqueta)" >&2
    exit 1
  }
  printf '%s\n' "$PKG_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "[ERROR] Versión Installer inválida derivada de VERSION: '${PKG_VERSION}'" >&2
    exit 1
  }

  echo "[OK]    Requisitos verificados. Meridian: ${MERIDIAN_VERSION} | PKG metadata: ${PKG_VERSION}"
}

_write_payload_manifest() {
  local install_root="${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}"
  local manifest="${install_root}/${PAYLOAD_MANIFEST_NAME}"

  # El manifiesto enumera archivos regulares y symlinks relativos al install root.
  # Se genera al final para que postinstall pueda retirar residuos de versiones
  # anteriores sin borrar primero una instalación funcional.
  (
    cd "$install_root" || exit 1
    find . \( -type f -o -type l \) ! -name "$PAYLOAD_MANIFEST_NAME" -print | \
      sed 's#^\./##' | LC_ALL=C sort
  ) > "$manifest"
  chmod 644 "$manifest"
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

  # Normalizar permisos del payload. No heredamos bits de escritura/ejecución
  # accidentales del checkout que generó el paquete.
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -type d -exec chmod 755 {} \;
  find "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}" -type f -exec chmod 644 {} \;
  chmod 755 "${PAYLOAD_DIR}${PKG_INSTALL_LOCATION}/meridian"

  _write_payload_manifest

  # preinstall NO borra la versión existente. Un fallo posterior de Installer no
  # debe convertir un upgrade fallido en una desinstalación accidental.
  cat > "${PKG_SCRIPTS_DIR}/preinstall" <<'PREINSTALL'
#!/bin/bash
set -u

COMMAND_PATH="/usr/local/bin/meridian"
EXPECTED_COMMAND_TARGET="/usr/local/lib/meridian/meridian"

if [ -L "$COMMAND_PATH" ]; then
  current_target="$(readlink "$COMMAND_PATH" 2>/dev/null)" || {
    echo "[Meridian] no se pudo resolver el enlace existente: $COMMAND_PATH" >&2
    exit 1
  }
  if [ "$current_target" != "$EXPECTED_COMMAND_TARGET" ]; then
    echo "[Meridian] $COMMAND_PATH apunta a un destino ajeno; no se sobrescribe" >&2
    exit 1
  fi
elif [ -e "$COMMAND_PATH" ]; then
  echo "[Meridian] $COMMAND_PATH existe y no es un enlace; no se sobrescribe" >&2
  exit 1
fi

exit 0
PREINSTALL
  chmod 755 "${PKG_SCRIPTS_DIR}/preinstall"

  cat > "${PKG_SCRIPTS_DIR}/postinstall" <<'POSTINSTALL'
#!/bin/bash
set -eu

INSTALL_ROOT="/usr/local/lib/meridian"
COMMAND_PATH="/usr/local/bin/meridian"
EXPECTED_COMMAND_TARGET="${INSTALL_ROOT}/meridian"
MANIFEST_NAME=".meridian-payload-manifest"
MANIFEST_PATH="${INSTALL_ROOT}/${MANIFEST_NAME}"
CURRENT_LIST=""

_cleanup_tmp() {
  if [ -n "$CURRENT_LIST" ] && [ -f "$CURRENT_LIST" ]; then
    rm -f "$CURRENT_LIST" 2>/dev/null || true
  fi
}
trap _cleanup_tmp EXIT

case "$INSTALL_ROOT" in
  /usr/local/lib/meridian) ;;
  *)
    echo "[Meridian] ruta de instalación inesperada" >&2
    exit 1
    ;;
esac

if [ ! -x "${INSTALL_ROOT}/meridian" ]; then
  echo "[Meridian] entrypoint no encontrado o no ejecutable: ${INSTALL_ROOT}/meridian" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "[Meridian] manifiesto de payload ausente; se evita limpieza insegura" >&2
  exit 1
fi

CURRENT_LIST="$(mktemp /tmp/meridian-installed.XXXXXX)" || {
  echo "[Meridian] no se pudo crear archivo temporal para verificar upgrade" >&2
  exit 1
}
if ! find "$INSTALL_ROOT" \( -type f -o -type l \) -print > "$CURRENT_LIST"; then
  echo "[Meridian] no se pudo enumerar instalación existente; se evita limpieza parcial" >&2
  exit 1
fi

while IFS= read -r path; do
  [ "$path" = "$MANIFEST_PATH" ] && continue
  rel="${path#${INSTALL_ROOT}/}"
  if ! grep -Fqx -e "$rel" "$MANIFEST_PATH"; then
    rm -f "$path" || {
      echo "[Meridian] no se pudo retirar residuo: $path" >&2
      exit 1
    }
  fi
done < "$CURRENT_LIST"

find "$INSTALL_ROOT" -depth -type d ! -path "$INSTALL_ROOT" -exec rmdir {} \; 2>/dev/null || true

mkdir -p "/usr/local/bin" || exit 1
if [ -L "$COMMAND_PATH" ]; then
  current_target="$(readlink "$COMMAND_PATH" 2>/dev/null)" || {
    echo "[Meridian] no se pudo resolver el enlace existente: $COMMAND_PATH" >&2
    exit 1
  }
  if [ "$current_target" != "$EXPECTED_COMMAND_TARGET" ]; then
    echo "[Meridian] $COMMAND_PATH apunta a un destino ajeno; no se sobrescribe" >&2
    exit 1
  fi
elif [ -e "$COMMAND_PATH" ]; then
  echo "[Meridian] $COMMAND_PATH existe y no es un enlace; no se sobrescribe" >&2
  exit 1
fi
rm -f "$COMMAND_PATH" || exit 1
ln -s "${INSTALL_ROOT}/meridian" "$COMMAND_PATH" || exit 1

chown -R root:wheel "$INSTALL_ROOT"
find "$INSTALL_ROOT" -type d -exec chmod 755 {} \;
find "$INSTALL_ROOT" -type f -exec chmod 644 {} \;
chmod 755 "${INSTALL_ROOT}/meridian" || exit 1

# `find -exec chmod` expresa el resultado como predicado y no garantiza que el
# exit status de `find` refleje un chmod rechazado. Verificamos el estado final
# para que Installer no informe éxito con permisos parcialmente normalizados.
bad_dirs="$(find "$INSTALL_ROOT" -type d ! -perm 755 -print)" || {
  echo "[Meridian] no se pudo verificar permisos de directorios" >&2
  exit 1
}
[ -z "$bad_dirs" ] || {
  echo "[Meridian] directorios con permisos inesperados tras normalización" >&2
  exit 1
}
bad_files="$(find "$INSTALL_ROOT" -type f ! -path "${INSTALL_ROOT}/meridian" ! -perm 644 -print)" || {
  echo "[Meridian] no se pudo verificar permisos de archivos" >&2
  exit 1
}
[ -z "$bad_files" ] || {
  echo "[Meridian] archivos con permisos inesperados tras normalización" >&2
  exit 1
}

mkdir -p "/Library/Logs/Meridian" || exit 1
chown root:admin "/Library/Logs/Meridian"
chmod 750 "/Library/Logs/Meridian" || exit 1

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
    <title>Meridian ${MERIDIAN_VERSION}</title>
    <organization>com.itau.apple</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true" hostArchitectures="${PKG_HOST_ARCHITECTURES}"/>
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

  # Fail closed: no producir un paquete si la Distribution pierde por accidente
  # la declaración universal que evita requerir Rosetta en Apple Silicon.
  grep -Fq "hostArchitectures=\"${PKG_HOST_ARCHITECTURES}\"" "$dist_xml" || {
    echo "[ERROR] Distribution.xml no declara las arquitecturas esperadas: ${PKG_HOST_ARCHITECTURES}" >&2
    exit 1
  }

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
  echo "  Meridian version : ${MERIDIAN_VERSION}"
  echo "  Package version  : ${PKG_VERSION}"
  echo "  Architectures    : ${PKG_HOST_ARCHITECTURES}"
  echo "  Install location : ${PKG_INSTALL_LOCATION}"
  echo "  Command          : ${PKG_COMMAND_PATH}"
  echo "  Ejecutar         : sudo meridian"
  echo "══════════════════════════════════════════════════"
}

_parse_args "$@"
_check_requirements
_prepare_payload
_build_component_pkg
_build_product_pkg
_verify_pkg
