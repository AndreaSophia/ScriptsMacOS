#!/bin/bash
# =============================================================================
# Meridian — ui/tui/confirm_dialog.sh
# Responsabilidad: diálogos de confirmación para acciones con efecto.
# No contiene lógica de negocio — solo captura de respuesta del usuario.
# =============================================================================

# =============================================================================
# tui_confirm_repair <module_name> <repair_id> <repair_risk> <description>
# Muestra el diálogo de confirmación de reparación.
# Retorna 0 si el usuario confirmó, 1 si canceló.
# =============================================================================
tui_confirm_repair() {
  local module_name="$1"
  local repair_id="$2"
  local repair_risk="$3"
  local description="$4"

  local risk_color
  case "$repair_risk" in
    LOW)    risk_color='\033[0;32m' ;;
    MEDIUM) risk_color='\033[0;33m' ;;
    HIGH)   risk_color='\033[0;31m' ;;
    *)      risk_color='\033[0m'    ;;
  esac

  printf "\n"
  printf "  \033[1;33m⚠  REPARACIÓN SOLICITADA\033[0m\n"
  printf "  ──────────────────────────────────────────────\n"
  printf "  Módulo      : \033[1m%s\033[0m\n" "$module_name"
  printf "  Operación   : %s\n" "$repair_id"
  printf "  Descripción : %s\n" "$description"
  printf "  Riesgo      : ${risk_color}\033[1m%s\033[0m\n" "$repair_risk"
  printf "  ──────────────────────────────────────────────\n\n"

  if command -v gum >/dev/null 2>&1; then
    gum confirm "¿Deseas ejecutar esta reparación?" && return 0 || return 1
  else
    _tui_confirm_plain "$repair_risk"
  fi
}

# =============================================================================
# _tui_confirm_plain <repair_risk> — Confirmación en texto plano
# =============================================================================
_tui_confirm_plain() {
  local repair_risk="$1"

  case "$repair_risk" in
    LOW)
      printf "  Presiona ENTER para continuar o Ctrl+C para cancelar..."
      read -r _
      return 0
      ;;
    MEDIUM)
      printf "  ¿Confirmas esta operación? (s/n): "
      local reply
      read -r reply
      reply="$(echo "$reply" | tr '[:upper:]' '[:lower:]')"
      [ "$reply" = "s" ] || [ "$reply" = "si" ] || [ "$reply" = "sí" ] && return 0
      return 1
      ;;
    HIGH)
      printf "  Esta operación tiene riesgo ALTO.\n"
      printf "  Escribe \033[1mCONFIRMAR\033[0m para proceder: "
      local reply
      read -r reply
      [ "$reply" = "CONFIRMAR" ] && return 0
      return 1
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
  printf "\n  %s" "$msg"
  read -r _
  printf "\n"
}
