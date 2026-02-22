#!/bin/sh
set -eu

# Itaú SSH Self-Heal Installer (single file) - v5 (LaunchDaemon-safe + sshd enable/bootstrap)
# - Habilita SSH (Remote Login)
# - Genera hostkeys si faltan (ssh-keygen -A)
# - Configura sshd_config para permitir SOLO AdminCMDB desde IPs/CIDR autorizados
# - Instala un LaunchDaemon que verifica y repara cada X minutos
# - FIX v5: el guard ahora hace enable de com.openssh.sshd y, si no existe en launchd, intenta bootstrap desde /System/Library/LaunchDaemons/ssh.plist
# - Desarrollo: Andrea Ramos - UEM macOS - Itaú Chile

ALLOWED_USER="AdminCMDB"
START_INTERVAL_SECONDS=300  # 5 min

ALLOWED_SOURCES="
10.181.15.125
10.181.15.128
10.181.15.184
10.181.15.185
10.181.15.39
10.181.15.57
10.191.50.0/28
"

SSH_CONFIG="/etc/ssh/sshd_config"
GUARD_SCRIPT="/usr/local/bin/itau_ssh_guard.sh"
PLIST_PATH="/Library/LaunchDaemons/com.itau.ssh.guard.plist"
LOG_OUT="/var/log/itau_ssh_guard.log"
LOG_ERR="/var/log/itau_ssh_guard.err"

log() { /usr/bin/logger -t itau-ssh-installer "$*"; /bin/echo "$*"; }

require_root() {
  if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    log "ERROR: ejecutar como root."
    exit 1
  fi
}

enable_remote_login() {
  /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
}

ensure_hostkeys() {
  if ! /bin/ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    log "No hay hostkeys. Generando con: /usr/bin/ssh-keygen -A"
    /usr/bin/ssh-keygen -A >/dev/null 2>&1
  fi
  /usr/sbin/chown root:wheel /etc/ssh/ssh_host_*_key 2>/dev/null || true
  /bin/chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
  /usr/sbin/chown root:wheel /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
  /bin/chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

build_negated_list() {
  NEG=""
  /bin/echo "$ALLOWED_SOURCES" | while IFS= read -r src; do
    [ -z "$src" ] && continue
    if [ -z "$NEG" ]; then
      NEG="!${src}"
    else
      NEG="${NEG},!${src}"
    fi
    /bin/echo "$NEG" > /tmp/.itau_ssh_negated.$$ 2>/dev/null || true
  done
  /bin/cat /tmp/.itau_ssh_negated.$$ 2>/dev/null || true
  /bin/rm -f /tmp/.itau_ssh_negated.$$ 2>/dev/null || true
}

apply_ssh_config() {
  [ -f "$SSH_CONFIG" ] || { log "ERROR: no existe $SSH_CONFIG"; exit 1; }

  if [ ! -f "${SSH_CONFIG}.backup" ]; then
    /bin/cp "$SSH_CONFIG" "${SSH_CONFIG}.backup"
    log "Backup creado: ${SSH_CONFIG}.backup"
  fi

  /usr/bin/sed -i.bak '/^# Managed by Itaú SSH AdminCMDB$/d' "$SSH_CONFIG"
  /usr/bin/sed -i.bak '/^PermitRootLogin[[:space:]]/d' "$SSH_CONFIG"
  /usr/bin/sed -i.bak '/^PasswordAuthentication[[:space:]]/d' "$SSH_CONFIG"
  /usr/bin/sed -i.bak '/^AllowUsers[[:space:]]/d' "$SSH_CONFIG"
  /usr/bin/sed -i.bak '/^Match[[:space:]]User[[:space:]]'"$ALLOWED_USER"'/,/^$/d' "$SSH_CONFIG"

  NEGATED_ALLOWED="$(build_negated_list)"
  [ -n "$NEGATED_ALLOWED" ] || { log "ERROR: lista permitida vacía"; exit 1; }

  {
    /bin/echo "# Managed by Itaú SSH AdminCMDB"
    /bin/echo "PermitRootLogin no"
    /bin/echo "PasswordAuthentication yes"
    /bin/echo "AllowUsers ${ALLOWED_USER}"
    /bin/echo ""
    /bin/echo "Match User ${ALLOWED_USER} Address ${NEGATED_ALLOWED}"
    /bin/echo "  DenyUsers ${ALLOWED_USER}"
    /bin/echo ""
  } >> "$SSH_CONFIG"

  ensure_hostkeys
  /usr/sbin/sshd -t
}

install_guard_script() {
  log "Instalando guard script en $GUARD_SCRIPT"
  /bin/mkdir -p /usr/local/bin
  /bin/mkdir -p /var/log

  /bin/cat > "$GUARD_SCRIPT" <<'EOF'
#!/bin/sh
set -eu

ALLOWED_USER="AdminCMDB"
SSH_CONFIG="/etc/ssh/sshd_config"
TAG="itau-ssh-guard"
SSH_LAUNCHD_PLIST="/System/Library/LaunchDaemons/ssh.plist"

log() { /usr/bin/logger -t "$TAG" "$*"; /bin/echo "$*"; }

is_ssh_on() {
  /usr/sbin/systemsetup -getremotelogin 2>/dev/null | /usr/bin/grep -qi "On"
}

config_has_marker() {
  /usr/bin/grep -q "Managed by Itaú SSH AdminCMDB" "$SSH_CONFIG" 2>/dev/null
}

ensure_hostkeys() {
  if ! /bin/ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    log "No hay hostkeys. Generando con: /usr/bin/ssh-keygen -A"
    /usr/bin/ssh-keygen -A >/dev/null 2>&1
  fi
  /usr/sbin/chown root:wheel /etc/ssh/ssh_host_*_key 2>/dev/null || true
  /bin/chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
  /usr/sbin/chown root:wheel /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
  /bin/chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

config_sane() {
  /usr/bin/grep -q "^AllowUsers[[:space:]]${ALLOWED_USER}$" "$SSH_CONFIG" 2>/dev/null || return 1
  /usr/bin/grep -q "^PermitRootLogin[[:space:]]no" "$SSH_CONFIG" 2>/dev/null || return 1
  ensure_hostkeys
  /usr/sbin/sshd -t >/dev/null 2>&1 || return 1
  return 0
}

ensure_sshd_service() {
  # Si el servicio no está registrado, intenta bootstrap desde el plist del sistema.
  if ! /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
    if [ -f "$SSH_LAUNCHD_PLIST" ]; then
      log "sshd no visible en launchd. Bootstrap: $SSH_LAUNCHD_PLIST"
      /bin/launchctl bootstrap system "$SSH_LAUNCHD_PLIST" >/dev/null 2>&1 || true
    else
      log "WARN: no existe $SSH_LAUNCHD_PLIST (baseline podría haberlo removido)."
    fi
  fi

  # Asegura enabled (si está disabled=true, kickstart no sirve)
  /bin/launchctl enable system/com.openssh.sshd >/dev/null 2>&1 || true
}

repair_minimal() {
  /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
  ensure_hostkeys
  ensure_sshd_service
  /bin/launchctl kickstart -k system/com.openssh.sshd >/dev/null 2>&1 || true
}

main() {
  NEED_FIX=0

  if ! is_ssh_on; then
    NEED_FIX=1
    log "Detectado: Remote Login OFF."
  fi

  if ! config_has_marker; then
    NEED_FIX=1
    log "Detectado: marcador ausente."
  fi

  if ! config_sane; then
    NEED_FIX=1
    log "Detectado: sshd_config inválido / hostkeys faltantes."
  fi

  if [ "$NEED_FIX" -eq 1 ]; then
    log "Reparando (mínimo)..."
    repair_minimal
    log "Reparación ejecutada."
  fi
}

main
EOF

  /bin/chmod 755 "$GUARD_SCRIPT"
  /usr/sbin/chown root:wheel "$GUARD_SCRIPT"
}

install_plist() {
  log "Instalando LaunchDaemon en $PLIST_PATH"
  /bin/cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.itau.ssh.guard</string>

  <key>ProgramArguments</key>
  <array>
    <string>${GUARD_SCRIPT}</string>
  </array>

  <key>StartInterval</key>
  <integer>${START_INTERVAL_SECONDS}</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${LOG_OUT}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_ERR}</string>
</dict>
</plist>
EOF

  /usr/sbin/chown root:wheel "$PLIST_PATH"
  /bin/chmod 644 "$PLIST_PATH"
}

load_daemon() {
  log "Cargando daemon..."
  /bin/launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
  /bin/launchctl bootstrap system "$PLIST_PATH"
  /bin/launchctl enable system/com.itau.ssh.guard
  /bin/launchctl kickstart -k system/com.itau.ssh.guard
}

main() {
  require_root
  log "Aplicando configuración SSH (primera vez)..."
  enable_remote_login
  ensure_hostkeys
  apply_ssh_config
  install_guard_script
  install_plist
  load_daemon
  log "OK: Self-healing SSH instalado. Usuario: ${ALLOWED_USER}. Intervalo: ${START_INTERVAL_SECONDS}s."
}

main
