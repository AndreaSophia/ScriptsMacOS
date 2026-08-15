#!/bin/bash
# =============================================================================
# Meridian — ui/tui/confirm_dialog.sh
# Responsabilidad: diálogos de confirmación para acciones con efecto.
# No contiene lógica de negocio — solo captura de respuesta del usuario.
#
# Invariante de seguridad:
#   una reparación requiere una sesión interactiva real. En ejecución headless
#   (Workspace ONE, launchd, SSH sin TTY, stdin cerrado) la confirmación falla
#   de forma segura y nunca autoriza cambios por defecto.
# =============================================================================

# =============================================================================
# tui_confirm_repair <module_name> <repair_id> <repair_risk> <description>
# Muestra el diálogo de confirmación de reparación.
# Retorna 0 si el usuario confirmó, 1 si canceló o no existe TTY interactiva.
# =============================================================================
tui_confirm_repair() {
  local module_name="$1"
  local repair_id="$2"
  local repair_risk="$3"
  local description="$4"

  # Las reparaciones nunca se autorizan desde stdin no interactivo. Esto evita
  # que un pipe, EOF o ejecución MDM pueda transformarse accidentalmente en una
  # confirmación válida.
  if [ ! -t 0 ]; then
    printf "  [repair] Confirmación bloqueada: se requiere una sesión interactiva.\n" >&2
    return 1
  fi

  local risk_color
  case "$repair_risk" in
    LOW)    risk_color='\033[0;32m' ;;
    MEDIUM) risk_color='\033[0;33m' ;;
    *)      return 1 ;;
  esac

  printf "\n"
  printf "  \033[1;33m⚠  REPARACIÓN SOLICITADA\033[0m\n"
  printf "  ──────────────────────────────────────────────\n"
  printf "  Módulo      : \033[1m%s\033[0m\n" "$module_name"
  printf "  Operación   : %s\n" "$repair_id"
  printf "  Descripción : %s\n" "$description"
  printf "  Riesgo      : ${risk_color}\033[1m%s\033[0m\n" "$repair_risk"
  printf "  ──────────────────────────────────────────────\n\n"

  # LOW: confirmación explícita simple. MEDIUM: token fuerte. No usamos una
  # semántica diferente cuando gum está instalado; la política debe ser única.
  _tui_confirm_plain "$repair_risk"
}

# =============================================================================
# _tui_confirm_plain <repair_risk> — Confirmación en texto plano
# =============================================================================
_tui_confirm_plain() {
  local repair_risk="$1"
  local reply=""

  case "$repair_risk" in
    LOW)
      printf "  ¿Confirmas esta operación de riesgo BAJO? (s/n): "
      IFS= read -r reply || return 1
      reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
      [ "$reply" = "s" ] || [ "$reply" = "si" ] || [ "$reply" = "sí" ]
      ;;
    MEDIUM)
      printf "  Riesgo MEDIO. Escribe \033[1mCONFIRMAR\033[0m para proceder: "
      IFS= read -r reply || return 1
      [ "$reply" = "CONFIRMAR" ]
      ;;
    *)
      return 1
      ;;
  esac
}

# =============================================================================
# tui_press_enter <message> — Pausa con mensaje
# =============================================================================
tui_press_enter() {
  local msg="${1:-Presiona ENTER para continuar...}"

  # Una pausa de UI no debe bloquear jobs headless.
  [ -t 0 ] || return 0

  printf "\n  %s" "$msg"
  IFS= read -r _ || return 1
  printf "\n"
}
