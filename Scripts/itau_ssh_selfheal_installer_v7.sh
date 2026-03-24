#!/bin/sh
set -eu
# Itaú SSH Self-Heal Installer - v7
# - Crea o actualiza la cuenta local AdminCMDB
# - Habilita SSH (Remote Login)
# - Genera hostkeys si faltan
# - Configura sshd_config para permitir SOLO AdminCMDB desde IPs/CIDR autorizados
# - Instala un LaunchDaemon que verifica y repara cada X minutos
#
# Nota:
# La contraseña base64 configurada es: SVRBVTIwMjQ=
# Decodificada corresponde a: ITAU2024

# --- CONFIGURACIÓN ---
ALLOWED_USER="AdminCMDB"
ENCODED_PASSWORD="SVRBVTIwMjQ="
HIDE_USER="1"
START_INTERVAL_SECONDS=300

ALLOWED_SOURCES="
10.181.15.125
10.181.15.128
10.181.15.184
10.181.15.185
10.181.15.39
10.181.15.57
10.191.50.0/25
"

SSH_CONFIG="/etc/ssh/sshd_config"
GUARD_SCRIPT="/usr/local/bin/itau_ssh_guard.sh"
PLIST_PATH="/Library/LaunchDaemons/com.itau.ssh.guard.plist"
LOG_OUT="/var/log/itau_ssh_guard.log"
LOG_ERR="/var/log/itau_ssh_guard.err"
TAG="itau-ssh-installer"

log() {
    /usr/bin/logger -t "$TAG" "$*"
    /bin/echo "$*"
}

require_root() {
    if [ "$(/usr/bin/id -u)" -ne 0 ]; then
        log "ERROR: ejecutar como root."
        exit 1
    fi
}

get_password() {
    /bin/echo "$ENCODED_PASSWORD" | /usr/bin/base64 -d
}

ensure_admin_user() {
    PASSWORD="$(get_password)"

    if /usr/bin/id "$ALLOWED_USER" >/dev/null 2>&1; then
        log "Usuario $ALLOWED_USER ya existe. Actualizando password..."
        /usr/bin/dscl . -passwd "/Users/$ALLOWED_USER" "$PASSWORD" || {
            log "ERROR: no se pudo actualizar la password de $ALLOWED_USER"
            exit 1
        }
    else
        log "Creando usuario administrador $ALLOWED_USER..."

        /usr/sbin/sysadminctl -addUser "$ALLOWED_USER" \
            -fullName "Admin CMDB" \
            -password "$PASSWORD" >/dev/null 2>&1 || {
            log "ERROR: no se pudo crear el usuario $ALLOWED_USER"
            exit 1
        }

        # Asegurar grupo admin
        /usr/sbin/dseditgroup -o edit -a "$ALLOWED_USER" -t user admin || {
            log "ERROR: no se pudo agregar $ALLOWED_USER al grupo admin"
            exit 1
        }

        # Forzar shell
        /usr/bin/dscl . -create "/Users/$ALLOWED_USER" UserShell /bin/zsh || true

        # Asegurar home correcto
        /usr/bin/dscl . -create "/Users/$ALLOWED_USER" NFSHomeDirectory "/Users/$ALLOWED_USER" || true

        # Crear carpeta home si no existe
        /bin/mkdir -p "/Users/$ALLOWED_USER" || true
        /usr/sbin/chown -R "$ALLOWED_USER":staff "/Users/$ALLOWED_USER" || true

        # Ocultar usuario
        if [ "$HIDE_USER" = "1" ]; then
            /usr/bin/dscl . -create "/Users/$ALLOWED_USER" IsHidden 1 || true
        fi
    fi

    # Validar grupo primario staff
    /usr/bin/dscl . -create "/Users/$ALLOWED_USER" PrimaryGroupID 20 || true

    # Validar shell y home
    /usr/bin/dscl . -create "/Users/$ALLOWED_USER" UserShell /bin/zsh || true
    /usr/bin/dscl . -create "/Users/$ALLOWED_USER" NFSHomeDirectory "/Users/$ALLOWED_USER" || true

    # Validar full name
    /usr/bin/dscl . -create "/Users/$ALLOWED_USER" RealName "Admin CMDB" || true

    # Garantizar membresía admin aunque ya existiera
    if ! /usr/bin/dsmemberutil checkmembership -U "$ALLOWED_USER" -G admin | /usr/bin/grep -q "is a member"; then
        log "Corrigiendo membresía admin para $ALLOWED_USER..."
        /usr/sbin/dseditgroup -o edit -a "$ALLOWED_USER" -t user admin || {
            log "ERROR: no se pudo corregir grupo admin para $ALLOWED_USER"
            exit 1
        }
    fi

    # Permitir acceso por SSH
    /usr/sbin/dseditgroup -o edit -a "$ALLOWED_USER" -t user com.apple.access_ssh >/dev/null 2>&1 || true

    log "Usuario $ALLOWED_USER listo."
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
    TMP="/tmp/.itau_ssh_negated.$$"
    NEG=""
    /bin/rm -f "$TMP" 2>/dev/null || true

    while IFS= read -r src; do
        [ -z "$src" ] && continue
        if [ -z "$NEG" ]; then
            NEG="!${src}"
        else
            NEG="${NEG},!${src}"
        fi
    done <<EOF
$ALLOWED_SOURCES
EOF

    /bin/echo "$NEG" > "$TMP"
    /bin/cat "$TMP"
    /bin/rm -f "$TMP" 2>/dev/null || true
}

apply_ssh_config() {
    [ -f "$SSH_CONFIG" ] || {
        log "ERROR: no existe $SSH_CONFIG"
        exit 1
    }

    if [ ! -f "${SSH_CONFIG}.backup" ]; then
        /bin/cp "$SSH_CONFIG" "${SSH_CONFIG}.backup"
        log "Backup creado: ${SSH_CONFIG}.backup"
    fi

    /usr/bin/sed -i.bak '/^# BEGIN Managed by Itaú SSH AdminCMDB$/,/^# END Managed by Itaú SSH AdminCMDB$/d' "$SSH_CONFIG"

    NEGATED_ALLOWED="$(build_negated_list)"
    [ -n "$NEGATED_ALLOWED" ] || {
        log "ERROR: lista permitida vacía"
        exit 1
    }

    {
        /bin/echo "# BEGIN Managed by Itaú SSH AdminCMDB"
        /bin/echo "PermitRootLogin no"
        /bin/echo "PasswordAuthentication yes"
        /bin/echo "PubkeyAuthentication yes"
        /bin/echo "ChallengeResponseAuthentication no"
        /bin/echo "KbdInteractiveAuthentication no"
        /bin/echo "UsePAM yes"
        /bin/echo "MaxAuthTries 3"
        /bin/echo "LoginGraceTime 30"
        /bin/echo "AllowUsers ${ALLOWED_USER}"
        /bin/echo ""
        /bin/echo "Match User ${ALLOWED_USER} Address ${NEGATED_ALLOWED}"
        /bin/echo "  DenyUsers ${ALLOWED_USER}"
        /bin/echo ""
        /bin/echo "# END Managed by Itaú SSH AdminCMDB"
    } >> "$SSH_CONFIG"

    ensure_hostkeys

    /usr/sbin/sshd -t || {
        log "ERROR: validación de sshd_config falló"
        exit 1
    }
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

log() {
    /usr/bin/logger -t "$TAG" "$*"
    /bin/echo "$*"
}

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
    if ! /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
        if [ -f "$SSH_LAUNCHD_PLIST" ]; then
            log "sshd no visible en launchd. Bootstrap: $SSH_LAUNCHD_PLIST"
            /bin/launchctl bootstrap system "$SSH_LAUNCHD_PLIST" >/dev/null 2>&1 || true
        else
            log "WARN: no existe $SSH_LAUNCHD_PLIST."
        fi
    fi
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
        log "Detectado: falta bloque gestionado en sshd_config."
    fi

    if ! config_sane; then
        NEED_FIX=1
        log "Detectado: configuración SSH inválida."
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
    log "Aplicando configuración SSH y cuenta AdminCMDB..."

    ensure_admin_user
    enable_remote_login
    ensure_hostkeys
    apply_ssh_config
    install_guard_script
    install_plist
    load_daemon

    log "OK: instalación completada. Usuario: ${ALLOWED_USER}. Intervalo: ${START_INTERVAL_SECONDS}s."
}

main