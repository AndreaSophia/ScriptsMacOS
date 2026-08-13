#!/bin/bash
# =============================================================================
# Meridian — core/privilege_manager.sh
# Responsabilidad: verificar privilegios antes de ejecutar módulos o reparaciones.
# Principio: mínimo privilegio — cada módulo declara lo que necesita.
# =============================================================================

# =============================================================================
# privilege_check_root — Verifica que el proceso corre como root
# Retorna 0 si es root, 1 si no
# =============================================================================
privilege_check_root() {
  if [ "${EUID:-$(id -u 2>/dev/null)}" -eq 0 ]; then
    return 0
  fi
  return 1
}

# =============================================================================
# privilege_require_root — Aborta con mensaje claro si no hay root
# =============================================================================
privilege_require_root() {
  if ! privilege_check_root; then
    printf "\n"
    printf "  \033[0;31m[✗]\033[0m  Meridian requiere privilegios de administrador.\n"
    printf "        Ejecuta: \033[1msudo meridian\033[0m\n\n"
    exit 1
  fi
}

# =============================================================================
# privilege_check_module <module_id> <requires_root>
# Verifica si el módulo puede ejecutarse con los privilegios actuales.
# Retorna 0 si puede ejecutarse, 1 si no.
# =============================================================================
privilege_check_module() {
  local module_id="$1"
  local requires_root="$2"

  if [ "$requires_root" = "true" ] && ! privilege_check_root; then
    log_warn "privilege_manager" \
      "Módulo '${module_id}' requiere root — se omite (SKIP)"
    return 1
  fi

  return 0
}

# =============================================================================
# privilege_check_repair <repair_risk>
# Verifica que el nivel de riesgo de una reparación es aceptable.
# En el MVP: solo permite reparaciones LOW y MEDIUM.
# CRITICAL está bloqueado por política del MVP.
# =============================================================================
privilege_check_repair() {
  local repair_risk="$1"

  case "$repair_risk" in
    NONE|LOW|MEDIUM)
      return 0
      ;;
    HIGH)
      log_warn "privilege_manager" \
        "Reparación de riesgo HIGH requiere confirmación explícita adicional."
      return 0
      ;;
    CRITICAL)
      log_error "privilege_manager" \
        "Reparaciones de riesgo CRITICAL están bloqueadas en esta versión."
      return 1
      ;;
    *)
      log_error "privilege_manager" \
        "Nivel de riesgo desconocido: '${repair_risk}'"
      return 1
      ;;
  esac
}

# =============================================================================
# privilege_get_current_user — Retorna el usuario real (no root) detrás del sudo
# =============================================================================
privilege_get_current_user() {
  if [ -n "${SUDO_USER:-}" ]; then
    echo "$SUDO_USER"
  else
    whoami 2>/dev/null || echo "unknown"
  fi
}
