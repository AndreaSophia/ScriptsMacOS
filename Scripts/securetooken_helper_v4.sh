#!/bin/bash

# =========================================================
# Secure Token Helper v4.0 - Interactive
# Compatible macOS bash 3.2
# Evita error TOKEN_HOLDERS[@]: unbound variable
# =========================================================

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[ERROR] Este script debe ejecutarse con bash."
  echo "Ejecuta: sudo bash $0"
  exit 1
fi

set -u
IFS=$'\n\t'

TARGET_USERS=("LCLAdmin" "AdminCMDB")
DONOR_USER=""
TOKEN_HOLDERS_TEXT=""

LOG_FILE="/var/log/securetoken_helper.log"

# --- Utilidades de salida ---
line() { echo "------------------------------------------------------------"; }
info() {
  echo "[INFO] $1"
  _log "INFO" "$1"
}
warn() {
  echo "[WARN] $1"
  _log "WARN" "$1"
}
err()  {
  echo "[ERROR] $1" >&2
  _log "ERROR" "$1"
}

# --- Log a archivo ---
_log() {
  local level="$1"
  local msg="$2"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "$ts [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Validaciones ---
require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "Ejecuta este script con sudo."
    exit 1
  fi
}

user_exists() {
  id "$1" >/dev/null 2>&1
}

# --- Usuario en consola ---
get_console_user() {
  local user
  user="$(stat -f%Su /dev/console 2>/dev/null || true)"

  case "$user" in
    ""|"root"|"loginwindow") echo "" ;;
    *) echo "$user" ;;
  esac
}

# --- Estado Secure Token ---
get_secure_token_status() {
  local user="$1"
  local output

  if [ -z "$user" ]; then
    echo "NO_USER"
    return
  fi

  if ! user_exists "$user"; then
    echo "NO_EXISTE"
    return
  fi

  output="$(sysadminctl -secureTokenStatus "$user" 2>&1 || true)"

  echo "$output" | grep -qi "ENABLED"  && { echo "ENABLED";  return; }
  echo "$output" | grep -qi "DISABLED" && { echo "DISABLED"; return; }

  echo "UNKNOWN"
}

# --- Gestión de TARGET_USERS ---
target_exists_in_list() {
  local needle="$1"
  local item

  for item in "${TARGET_USERS[@]}"; do
    [ "$item" = "$needle" ] && return 0
  done

  return 1
}

add_target_if_needed() {
  local user="$1"

  [ -z "$user" ] && return 0

  if ! target_exists_in_list "$user"; then
    TARGET_USERS+=("$user")
  fi
}

# --- Prompts ---
prompt_password() {
  local user="$1"
  local pass=""

  read -r -s -p "Password de $user: " pass
  echo >&2
  echo "$pass"
}

prompt_yes_no() {
  local msg="$1"
  local reply=""

  while true; do
    read -r -p "$msg (s/n): " reply
    reply="$(echo "$reply" | tr '[:upper:]' '[:lower:]')"

    case "$reply" in
      s|si|sí) return 0 ;;
      n|no)    return 1 ;;
      *)       echo "Responde s o n." ;;
    esac
  done
}

# --- Mostrar estado ---
show_status_all() {
  local console_user="$1"
  local u

  line
  echo "ESTADO SECURE TOKEN"
  line
  echo "Usuario consola: ${console_user:-NO DETECTADO}"

  for u in "${TARGET_USERS[@]}"; do
    if user_exists "$u"; then
      echo "$u : $(get_secure_token_status "$u")"
    else
      echo "$u : NO EXISTE"
    fi
  done

  line
}

all_existing_targets_enabled() {
  local u
  local found_existing=0

  for u in "${TARGET_USERS[@]}"; do
    if user_exists "$u"; then
      found_existing=1
      if [ "$(get_secure_token_status "$u")" != "ENABLED" ]; then
        return 1
      fi
    fi
  done

  [ "$found_existing" -eq 1 ]
}

press_enter_exit() {
  echo
  line
  echo "$1"
  line
  echo "Presiona Enter para cerrar..."
  read -r _
  exit "${2:-0}"
}

# --- Gestión de holders (sin pipes para evitar subshell en bash 3.2) ---
holder_already_added() {
  local user="$1"

  echo "$TOKEN_HOLDERS_TEXT" | grep -Fxq "$user"
}

add_token_holder() {
  local user="$1"

  if ! holder_already_added "$user"; then
    TOKEN_HOLDERS_TEXT="${TOKEN_HOLDERS_TEXT}${user}
"
  fi
}

build_token_holders() {
  local u

  TOKEN_HOLDERS_TEXT=""

  for u in "${TARGET_USERS[@]}"; do
    if user_exists "$u"; then
      if [ "$(get_secure_token_status "$u")" = "ENABLED" ]; then
        add_token_holder "$u"
      fi
    fi
  done
}

count_token_holders() {
  echo "$TOKEN_HOLDERS_TEXT" | sed '/^$/d' | wc -l | tr -d ' '
}

get_holder_by_number() {
  local num="$1"
  echo "$TOKEN_HOLDERS_TEXT" | sed '/^$/d' | sed -n "${num}p"
}

# --- Elegir donante (sin pipe para que el índice funcione en bash 3.2) ---
choose_donor() {
  local choice=""
  local count=0
  local i=1
  local holder=""

  count="$(count_token_holders)"

  line
  echo "USUARIOS CON SECURE TOKEN DISPONIBLE"
  line

  if [ "$count" -eq 0 ]; then
    err "No hay usuarios con Secure Token. No se puede transferir."
    exit 1
  fi

  # Iterar sin pipe para que el índice incremente correctamente en bash 3.2
  while [ "$i" -le "$count" ]; do
    holder="$(get_holder_by_number "$i")"
    echo "$i) $holder"
    i=$((i + 1))
  done

  line

  while true; do
    read -r -p "Elige el usuario DONANTE de Secure Token [1-$count]: " choice

    if echo "$choice" | grep -Eq '^[0-9]+$'; then
      if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
        DONOR_USER="$(get_holder_by_number "$choice")"
        return 0
      fi
    fi

    echo "Opción inválida. Ingresa un número entre 1 y $count."
  done
}

# --- Validar contraseña del donante ---
validate_donor_password() {
  local donor="$1"
  local pass="$2"
  local result=""

  # Intenta una operación inocua con las credenciales para verificar que son correctas
  result="$(sysadminctl -adminUser "$donor" -adminPassword "$pass" -secureTokenStatus "$donor" 2>&1 || true)"

  if echo "$result" | grep -qi "Could not authenticate\|Authentication failed\|incorrect password"; then
    return 1
  fi

  return 0
}

# --- Transferir token ---
transfer_token() {
  local donor="$1"
  local target="$2"
  local donor_pass="$3"
  local target_pass=""
  local result=""
  local rc=0

  if [ "$donor" = "$target" ]; then
    warn "El donante y el destino son el mismo usuario: $target. Se omite."
    return 0
  fi

  if ! user_exists "$target"; then
    warn "El usuario '$target' no existe. Se omite."
    return 0
  fi

  result="$(get_secure_token_status "$target")"

  if [ "$result" = "ENABLED" ]; then
    info "$target ya tiene Secure Token. Se omite."
    return 0
  fi

  line
  echo "Se entregará Secure Token a: $target"
  line

  target_pass="$(prompt_password "$target")"

  if [ -z "$target_pass" ]; then
    err "Password vacía para $target. Se omite."
    return 1
  fi

  info "Asignando Secure Token a '$target' usando '$donor'..."

  sysadminctl -adminUser "$donor" -adminPassword "$donor_pass" \
              -secureTokenOn "$target" -password "$target_pass"
  rc=$?

  if [ "$rc" -ne 0 ]; then
    err "sysadminctl devolvió error $rc para '$target'."
    return 1
  fi

  sleep 2

  result="$(get_secure_token_status "$target")"

  if [ "$result" = "ENABLED" ]; then
    info "Secure Token asignado correctamente a '$target'."
    _log "INFO" "Secure Token asignado: donor=$donor target=$target"
    return 0
  fi

  err "No se pudo confirmar Secure Token ENABLED para '$target'. Estado: $result"
  _log "ERROR" "Fallo confirmación Secure Token: donor=$donor target=$target estado=$result"
  return 1
}

# --- Main ---
main() {
  require_root

  local console_user=""
  local donor_pass=""
  local u
  local status
  local pending_count=0

  _log "INFO" "=== Inicio ejecución Secure Token Helper v4.0 ==="

  console_user="$(get_console_user)"
  add_target_if_needed "$console_user"

  show_status_all "$console_user"

  if all_existing_targets_enabled; then
    press_enter_exit "Todos los usuarios objetivo existentes ya tienen Secure Token." 0
  fi

  # Mostrar pendientes ANTES de pedir contraseñas
  line
  echo "USUARIOS OBJETIVO SIN SECURE TOKEN"
  line

  for u in "${TARGET_USERS[@]}"; do
    if user_exists "$u"; then
      status="$(get_secure_token_status "$u")"
      if [ "$status" != "ENABLED" ]; then
        echo "- $u : $status"
        pending_count=$((pending_count + 1))
      fi
    fi
  done

  if [ "$pending_count" -eq 0 ]; then
    press_enter_exit "No hay usuarios existentes pendientes." 0
  fi

  line

  if ! prompt_yes_no "¿Quieres entregar Secure Token a los $pending_count usuario(s) listados?"; then
    warn "Operación cancelada por el usuario."
    exit 0
  fi

  # Pedir credenciales solo si el usuario confirmó
  build_token_holders
  choose_donor

  line
  echo "Donante seleccionado: $DONOR_USER"
  line

  donor_pass="$(prompt_password "$DONOR_USER")"

  if [ -z "$donor_pass" ]; then
    err "Password vacía del donante. Abortando."
    exit 1
  fi

  # Validar contraseña del donante antes de continuar
  info "Validando credenciales del donante '$DONOR_USER'..."
  if ! validate_donor_password "$DONOR_USER" "$donor_pass"; then
    err "Contraseña incorrecta para '$DONOR_USER'. Abortando."
    exit 1
  fi
  info "Credenciales del donante validadas."

  for u in "${TARGET_USERS[@]}"; do
    if user_exists "$u"; then
      if [ "$(get_secure_token_status "$u")" != "ENABLED" ]; then
        transfer_token "$DONOR_USER" "$u" "$donor_pass"
      fi
    fi
  done

  echo
  show_status_all "$console_user"

  info "Proceso finalizado. Log en: $LOG_FILE"
  _log "INFO" "=== Fin ejecución ==="
}

main "$@"
