#!/bin/bash

# Variables
PKG_NAME="HostnameSeal"
PKG_VERSION="1.0"
PKG_IDENTIFIER="com.empresa.hostname.seal"
BUILD_DIR="/tmp/hostname_seal_build"
PAYLOAD_DIR="$BUILD_DIR/payload"
SCRIPTS_DIR="$BUILD_DIR/scripts"

echo "🔥 Limpiando y preparando entorno..."
rm -rf "$BUILD_DIR"
mkdir -p "$PAYLOAD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/Library/LaunchDaemons"
mkdir -p "$SCRIPTS_DIR"

# --------- Preinstall: cambia hostname ----------
cat > "$SCRIPTS_DIR/preinstall" << 'EOF'
#!/bin/bash
LOG="/var/log/hostname_config.log"
echo "$(date) - [PREINSTALL] Iniciando configuración de hostname..." >> "$LOG"

WIFI_MAC=$(networksetup -getmacaddress "Wi-Fi" 2>/dev/null | awk '{print $3}' | tr -d ':' | tr '[:upper:]' '[:lower:]')
if [ -z "$WIFI_MAC" ]; then
  echo "$(date) - ❌ No se pudo obtener MAC Wi-Fi" >> "$LOG"
  exit 1
fi
NEW_HOSTNAME="MAC${WIFI_MAC}"
echo "$(date) - Hostname generado: $NEW_HOSTNAME" >> "$LOG"

scutil --set ComputerName "$NEW_HOSTNAME"
scutil --set LocalHostName "$NEW_HOSTNAME"
scutil --set HostName "$NEW_HOSTNAME"
defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$NEW_HOSTNAME"

echo "$(date) - ✅ Hostname configurado como $NEW_HOSTNAME" >> "$LOG"
exit 0
EOF

chmod +x "$SCRIPTS_DIR/preinstall"

# --------- Script reafirmador ---------
cat > "$PAYLOAD_DIR/usr/local/bin/reaffirm_hostname.sh" << 'EOF'
#!/bin/bash
LOG="/var/log/hostname_reaffirm.log"

WIFI_MAC=$(networksetup -getmacaddress "Wi-Fi" 2>/dev/null | awk '{print $3}' | tr -d ':' | tr '[:upper:]' '[:lower:]')
EXPECTED_HOSTNAME="MAC${WIFI_MAC}"

CURRENT_HOSTNAME=$(scutil --get HostName 2>/dev/null || echo "")
CURRENT_LOCALHOSTNAME=$(scutil --get LocalHostName 2>/dev/null || echo "")
CURRENT_COMPUTERNAME=$(scutil --get ComputerName 2>/dev/null || echo "")
CURRENT_NETBIOS=$(defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName 2>/dev/null || echo "")

echo "$(date) - 🔍 Verificando estado..." >> "$LOG"

CHANGED=0

if [ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]; then
  echo "$(date) - ⚠️ HostName alterado: $CURRENT_HOSTNAME ➡️ $EXPECTED_HOSTNAME" >> "$LOG"
  scutil --set HostName "$EXPECTED_HOSTNAME"
  CHANGED=1
fi

if [ "$CURRENT_LOCALHOSTNAME" != "$EXPECTED_HOSTNAME" ]; then
  echo "$(date) - ⚠️ LocalHostName alterado: $CURRENT_LOCALHOSTNAME ➡️ $EXPECTED_HOSTNAME" >> "$LOG"
  scutil --set LocalHostName "$EXPECTED_HOSTNAME"
  CHANGED=1
fi

if [ "$CURRENT_COMPUTERNAME" != "$EXPECTED_HOSTNAME" ]; then
  echo "$(date) - ⚠️ ComputerName alterado: $CURRENT_COMPUTERNAME ➡️ $EXPECTED_HOSTNAME" >> "$LOG"
  scutil --set ComputerName "$EXPECTED_HOSTNAME"
  CHANGED=1
fi

if [ "$CURRENT_NETBIOS" != "$EXPECTED_HOSTNAME" ]; then
  echo "$(date) - ⚠️ NetBIOSName alterado: $CURRENT_NETBIOS ➡️ $EXPECTED_HOSTNAME" >> "$LOG"
  defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$EXPECTED_HOSTNAME"
  CHANGED=1
fi

if [ "$CHANGED" -eq 1 ]; then
  echo "$(date) - ✅ Se corrigieron cambios de hostname" >> "$LOG"
  dscacheutil -flushcache
  killall -HUP mDNSResponder 2>/dev/null
else
  echo "$(date) - 🟢 Todos los valores están correctos" >> "$LOG"
fi
EOF

chmod 755 "$PAYLOAD_DIR/usr/local/bin/reaffirm_hostname.sh"
chown root:wheel "$PAYLOAD_DIR/usr/local/bin/reaffirm_hostname.sh"

# --------- LaunchDaemon plist ---------
cat > "$BUILD_DIR/Library/LaunchDaemons/com.itau.hostname_reaffirm.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.itau.hostname_reaffirm</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/reaffirm_hostname.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>2100</integer> <!-- cada 35 minutos -->
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/hostname_reaffirm.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/hostname_reaffirm.log</string>
</dict>
</plist>
EOF

# --------- Copiar plist y ajustar permisos ---------
mkdir -p "$PAYLOAD_DIR/Library/LaunchDaemons"
cp "$BUILD_DIR/Library/LaunchDaemons/com.itau.hostname_reaffirm.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"

chmod 644 "$PAYLOAD_DIR/Library/LaunchDaemons/com.itau.hostname_reaffirm.plist"
chown root:wheel "$PAYLOAD_DIR/Library/LaunchDaemons/com.itau.hostname_reaffirm.plist"

# --------- Crear paquete -----------
echo "📦 Construyendo paquete..."
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$PKG_VERSION" \
  --install-location "/" \
  "$PKG_NAME-$PKG_VERSION.pkg"

if [ $? -eq 0 ]; then
  echo "✅ Paquete creado: $PKG_NAME-$PKG_VERSION.pkg"
  echo "📂 Ubicación: $(pwd)/$PKG_NAME-$PKG_VERSION.pkg"
else
  echo "❌ Error al crear paquete"
  exit 1
fi

# --------- Limpieza -----------
rm -rf "$BUILD_DIR"
echo "✨ Proceso completado."
