#!/bin/bash
# =============================================================================
# Meridian — logging/logger.sh
# API centralizada de logging.
# =============================================================================

# Toda la presentación del logger se emite por stderr. La decisión de usar
# colores debe seguir ese mismo canal para no inyectar ANSI cuando stdout sea
# interactivo pero stderr esté redirigido (o viceversa).
if [ -t 2 ]; then
  _L_RST='\033[0m'; _L_BOLD='\033[1m'; _L_CYAN='\033[0;36m'; _L_BCYAN='\033[1;36m'
  _L_GREEN='\033[0;32m'; _L_BGREEN='\033[1;32m'; _L_YELLOW='\033[0;33m'; _L_RED='\033[0;31m'
  _L_GRAY='\033[0;90m'; _L_WHITE='\033[1;37m'; _L_MAGENTA='\033[0;35m'
else
  _L_RST=''; _L_BOLD=''; _L_CYAN=''; _L_BCYAN=''; _L_GREEN=''; _L_BGREEN=''
  _L_YELLOW=''; _L_RED=''; _L_GRAY=''; _L_WHITE=''; _L_MAGENTA=''
fi

_log_write() {
  local level="$1" component="$2" msg="$3" ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [ -n "${MERIDIAN_LOG_FILE:-}" ]; then
    printf '%s [%-5s] [%s] %s\n' "$ts" "$level" "$component" "$msg" \
      >> "${MERIDIAN_LOG_FILE}" 2>/dev/null || true
  fi
}

log_debug() {
  local component="$1" msg="$2"
  _log_write "DEBUG" "$component" "$msg"
  if [ "${MERIDIAN_DEBUG:-0}" = "1" ]; then
    printf "  ${_L_GRAY}[D] [%s] %s${_L_RST}\n" "$component" "$msg" >&2
  fi
}

log_info() {
  local component="$1" msg="$2"
  _log_write "INFO" "$component" "$msg"
  printf "  ${_L_CYAN}·${_L_RST}  [%s] %s\n" "$component" "$msg" >&2
}

log_ok() {
  local component="$1" msg="$2"
  _log_write "OK" "$component" "$msg"
  printf "  ${_L_BGREEN}✓${_L_RST}  [%s] %s\n" "$component" "$msg" >&2
}

log_warn() {
  local component="$1" msg="$2"
  _log_write "WARN" "$component" "$msg"
  printf "  ${_L_YELLOW}!${_L_RST}  [%s] %s\n" "$component" "$msg" >&2
}

log_error() {
  local component="$1" msg="$2"
  _log_write "ERROR" "$component" "$msg"
  printf "  ${_L_RED}✗${_L_RST}  [%s] %s\n" "$component" "$msg" >&2
}

log_step() {
  local msg="$1"
  _log_write "STEP" "engine" "$msg"
  printf "\n${_L_BCYAN}  ▶  %s${_L_RST}\n" "$msg" >&2
}

_default_audit_log() {
  if [ "${EUID:-$(id -u 2>/dev/null || echo 1)}" -eq 0 ]; then
    printf '%s\n' '/Library/Logs/Meridian/audit.log'
  else
    printf '%s\n' "${HOME}/.meridian/audit.log"
  fi
}

# Producción privilegiada siempre escribe en la ubicación corporativa fija.
# Un environment override controlado por el caller no debe convertir el logger
# en una primitiva de append/chmod arbitraria ejecutándose como root. El override
# se conserva para ejecución no privilegiada y para el sandbox de fixtures.
_resolve_audit_log() {
  local euid
  euid="${EUID:-$(id -u 2>/dev/null || echo 1)}"
  if [ "$euid" -eq 0 ] && [ "${MERIDIAN_TEST_MODE:-0}" != "1" ]; then
    printf '%s\n' '/Library/Logs/Meridian/audit.log'
  else
    printf '%s\n' "${MERIDIAN_AUDIT_LOG:-$(_default_audit_log)}"
  fi
}

# Audit es un formato de un registro por línea separado por '|'. Codificamos
# contenido antes de escribirlo para que valores controlados por módulos no
# puedan inyectar columnas ni registros adicionales. El orden importa: primero
# '%' para que la decodificación futura pueda ser reversible.
_audit_encode() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//|/%7C}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}

log_audit() {
  local component="$1" action="$2" detail="$3" ts operator hostname audit_log audit_dir euid
  local operator_safe hostname_safe component_safe action_safe detail_safe
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  operator="${SUDO_USER:-$(whoami 2>/dev/null || echo 'unknown')}"
  hostname="$(hostname -s 2>/dev/null || echo 'unknown')"
  euid="${EUID:-$(id -u 2>/dev/null || echo 1)}"
  audit_log="$(_resolve_audit_log)" || return 1
  audit_dir="$(dirname "$audit_log")"

  mkdir -p "$audit_dir" 2>/dev/null || {
    _log_write "ERROR" "logger" "No se pudo crear directorio de auditoría: $audit_dir"
    return 1
  }

  # Nunca seguir symlinks en el destino de auditoría. Incluso en modo no-root,
  # un symlink convertiría el append y chmod posteriores en operaciones sobre
  # un objeto distinto del que Meridian cree estar auditando.
  if [ -L "$audit_log" ]; then
    _log_write "ERROR" "logger" "Destino de audit log rechazado por ser symlink: $audit_log"
    return 1
  fi

  if [ "$euid" -eq 0 ] && [ "$audit_dir" = "/Library/Logs/Meridian" ]; then
    chown root:admin "$audit_dir" 2>/dev/null || {
      _log_write "ERROR" "logger" "No se pudo asegurar ownership del directorio de auditoría: $audit_dir"
      return 1
    }
    chmod 750 "$audit_dir" 2>/dev/null || {
      _log_write "ERROR" "logger" "No se pudo asegurar permisos del directorio de auditoría: $audit_dir"
      return 1
    }
  fi

  operator_safe="$(_audit_encode "$operator")"
  hostname_safe="$(_audit_encode "$hostname")"
  component_safe="$(_audit_encode "$component")"
  action_safe="$(_audit_encode "$action")"
  detail_safe="$(_audit_encode "$detail")"

  printf '%s|AUDIT|%s|%s|%s|%s|%s\n' \
    "$ts" "$operator_safe" "$hostname_safe" "$component_safe" "$action_safe" "$detail_safe" \
    >> "$audit_log" 2>/dev/null || {
      _log_write "ERROR" "logger" "No se pudo escribir audit log: $audit_log"
      return 1
    }

  if [ "$euid" -eq 0 ] && [ "$audit_log" = "/Library/Logs/Meridian/audit.log" ]; then
    chown root:admin "$audit_log" 2>/dev/null || {
      _log_write "ERROR" "logger" "No se pudo asegurar ownership del audit log: $audit_log"
      return 1
    }
    chmod 640 "$audit_log" 2>/dev/null || {
      _log_write "ERROR" "logger" "No se pudo asegurar permisos del audit log: $audit_log"
      return 1
    }
  fi

  _log_write "AUDIT" "$component" "${action}: ${detail}"
  printf "  ${_L_MAGENTA}⚑${_L_RST}  [AUDIT] [%s] %s: %s\n" \
    "$component" "$action" "$detail" >&2
}

logger_init() {
  local log_path="$1" log_dir
  log_dir="$(dirname "$log_path")"
  mkdir -p "$log_dir" 2>/dev/null || return 1

  MERIDIAN_LOG_FILE="$log_path"
  export MERIDIAN_LOG_FILE

  {
    printf '# Meridian diagnostic.log\n'
    printf '# Session: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '# Host: %s\n' "$(hostname -s 2>/dev/null || echo 'unknown')"
    printf '# User: %s\n' "${SUDO_USER:-$(whoami 2>/dev/null || echo 'unknown')}"
    printf '# Version: %s\n' "${MERIDIAN_VERSION:-unknown}"
    printf '#\n'
  } > "${MERIDIAN_LOG_FILE}" 2>/dev/null || {
    printf "  ${_L_RED}✗${_L_RST}  [logger] No se pudo crear el archivo de log: %s\n" \
      "$log_path" >&2
    return 1
  }

  chmod 600 "${MERIDIAN_LOG_FILE}" 2>/dev/null || true
  return 0
}
