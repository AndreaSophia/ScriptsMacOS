#!/bin/bash
# =============================================================================
# Meridian — logging/logger.sh
# Responsabilidad: API centralizada de logging. Todos los componentes usan
# estas funciones. Nadie escribe a logs directamente.
#
# Niveles: DEBUG < INFO < WARN < ERROR < AUDIT
# AUDIT es especial: siempre se escribe, nunca se filtra, es append-only.
# =============================================================================

# Variables que el caller debe haber definido antes de usar el logger:
#   MERIDIAN_LOG_FILE  — ruta al archivo diagnostic.log de esta ejecución
#   MERIDIAN_AUDIT_LOG — ruta al audit.log (por defecto en ~/.meridian/audit.log)
#   MERIDIAN_DEBUG     — "1" para activar logs DEBUG en consola

# Colores — solo si stdout es terminal interactiva
if [ -t 1 ]; then
  _L_RST='\033[0m';    _L_BOLD='\033[1m'
  _L_CYAN='\033[0;36m';  _L_BCYAN='\033[1;36m'
  _L_GREEN='\033[0;32m'; _L_BGREEN='\033[1;32m'
  _L_YELLOW='\033[0;33m'; _L_RED='\033[0;31m'
  _L_GRAY='\033[0;90m';  _L_WHITE='\033[1;37m'
  _L_MAGENTA='\033[0;35m'
else
  _L_RST=''; _L_BOLD=''; _L_CYAN=''; _L_BCYAN=''
  _L_GREEN=''; _L_BGREEN=''; _L_YELLOW=''; _L_RED=''
  _L_GRAY=''; _L_WHITE=''; _L_MAGENTA=''
fi

# =============================================================================
# _log_write <level> <component> <message>
# Función base — no llamar directamente, usar las funciones públicas
# =============================================================================
_log_write() {
  local level="$1"
  local component="$2"
  local msg="$3"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Escribir al archivo de log de la sesión
  if [ -n "${MERIDIAN_LOG_FILE:-}" ]; then
    printf '%s [%-5s] [%s] %s\n' "$ts" "$level" "$component" "$msg" \
      >> "${MERIDIAN_LOG_FILE}" 2>/dev/null
  fi
}

# =============================================================================
# log_debug <component> <message>
# Solo visible en consola cuando MERIDIAN_DEBUG=1
# =============================================================================
log_debug() {
  local component="$1"
  local msg="$2"
  _log_write "DEBUG" "$component" "$msg"
  if [ "${MERIDIAN_DEBUG:-0}" = "1" ]; then
    printf "  ${_L_GRAY}[D] [%s] %s${_L_RST}\n" "$component" "$msg"
  fi
}

# =============================================================================
# log_info <component> <message>
# =============================================================================
log_info() {
  local component="$1"
  local msg="$2"
  _log_write "INFO " "$component" "$msg"
  printf "  ${_L_CYAN}·${_L_RST}  [%s] %s\n" "$component" "$msg"
}

# =============================================================================
# log_ok <component> <message>
# =============================================================================
log_ok() {
  local component="$1"
  local msg="$2"
  _log_write "OK   " "$component" "$msg"
  printf "  ${_L_BGREEN}✓${_L_RST}  [%s] %s\n" "$component" "$msg"
}

# =============================================================================
# log_warn <component> <message>
# =============================================================================
log_warn() {
  local component="$1"
  local msg="$2"
  _log_write "WARN " "$component" "$msg"
  printf "  ${_L_YELLOW}!${_L_RST}  [%s] %s\n" "$component" "$msg"
}

# =============================================================================
# log_error <component> <message>
# =============================================================================
log_error() {
  local component="$1"
  local msg="$2"
  _log_write "ERROR" "$component" "$msg"
  printf "  ${_L_RED}✗${_L_RST}  [%s] %s\n" "$component" "$msg" >&2
}

# =============================================================================
# log_step <message>
# Para marcar el inicio de una etapa mayor (sin componente)
# =============================================================================
log_step() {
  local msg="$1"
  _log_write "STEP " "engine" "$msg"
  printf "\n${_L_BCYAN}  ▶  %s${_L_RST}\n" "$msg"
}

# =============================================================================
# log_audit <component> <action> <detail>
# AUDIT es especial: append-only, nunca filtrado, siempre escrito.
# Registra toda acción con efecto en el sistema.
# =============================================================================
log_audit() {
  local component="$1"
  local action="$2"
  local detail="$3"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local operator="${SUDO_USER:-$(whoami 2>/dev/null || echo 'unknown')}"
  local hostname
  hostname="$(hostname -s 2>/dev/null || echo 'unknown')"

  local audit_log="${MERIDIAN_AUDIT_LOG:-${HOME}/.meridian/audit.log}"

  # Crear directorio si no existe
  mkdir -p "$(dirname "$audit_log")" 2>/dev/null

  # Formato: TSZ|AUDIT|operator|hostname|component|action|detail
  printf '%s|AUDIT|%s|%s|%s|%s|%s\n' \
    "$ts" "$operator" "$hostname" "$component" "$action" "$detail" \
    >> "$audit_log" 2>/dev/null

  # También al log de sesión
  _log_write "AUDIT" "$component" "${action}: ${detail}"

  # Consola — visible siempre para acciones auditadas
  printf "  ${_L_MAGENTA}⚑${_L_RST}  [AUDIT] [%s] %s: %s\n" \
    "$component" "$action" "$detail"
}

# =============================================================================
# logger_init <session_log_path> — Inicializa el logger para una sesión
# Crea el archivo de log con cabecera.
# =============================================================================
logger_init() {
  local log_path="$1"
  MERIDIAN_LOG_FILE="$log_path"
  export MERIDIAN_LOG_FILE

  {
    printf '# Meridian diagnostic.log\n'
    printf '# Session: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '# Host: %s\n' "$(hostname -s 2>/dev/null || echo 'unknown')"
    printf '# User: %s\n' "${SUDO_USER:-$(whoami 2>/dev/null)}"
    printf '# Version: %s\n' "${MERIDIAN_VERSION:-unknown}"
    printf '#\n'
  } > "${MERIDIAN_LOG_FILE}" 2>/dev/null || {
    printf "  ${_L_RED}✗${_L_RST}  [logger] No se pudo crear el archivo de log: %s\n" \
      "$log_path" >&2
    return 1
  }
}
