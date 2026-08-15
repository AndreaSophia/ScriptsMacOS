#!/bin/bash
# =============================================================================
# Meridian — core/privilege_manager.sh
# Responsabilidad: verificar privilegios antes de ejecutar módulos o reparaciones.
# Principio: mínimo privilegio — cada módulo declara lo que necesita.
# =============================================================================

privilege_check_root() {
  if [ "${EUID:-$(id -u 2>/dev/null)}" -eq 0 ]; then
    return 0
  fi
  return 1
}

privilege_require_root() {
  if ! privilege_check_root; then
    printf "\n"
    printf "  \033[0;31m[✗]\033[0m  Meridian requiere privilegios de administrador.\n"
    printf "        Ejecuta: \033[1msudo meridian\033[0m\n\n"
    exit 1
  fi
}

privilege_check_module() {
  local module_id="$1"
  local requires_root="$2"

  # --test es un sandbox de fixtures: los módulos no deben consultar ni
  # modificar el sistema real. Por diseño, un fixture debe poder ejercitar
  # también módulos cuyo manifest declara requires_root=true sin elevar
  # privilegios. Las reparaciones continúan bloqueadas por MERIDIAN_TEST_MODE
  # en repair_engine.
  if [ "${MERIDIAN_TEST_MODE:-0}" = "1" ]; then
    return 0
  fi

  if [ "$requires_root" = "true" ] && ! privilege_check_root; then
    log_warn "privilege_manager" \
      "Módulo '${module_id}' requiere root — se omite (SKIP)"
    return 1
  fi

  return 0
}

# En el MVP solo LOW y MEDIUM son ejecutables.
# HIGH y CRITICAL quedan bloqueados hasta que exista una política explícita
# de reparación avanzada y cobertura de tests suficiente.
privilege_check_repair() {
  local repair_risk="$1"

  case "$repair_risk" in
    NONE|LOW|MEDIUM)
      return 0
      ;;
    HIGH)
      log_error "privilege_manager" \
        "Reparaciones de riesgo HIGH están bloqueadas en el MVP."
      return 1
      ;;
    CRITICAL)
      log_error "privilege_manager" \
        "Reparaciones de riesgo CRITICAL están bloqueadas en el MVP."
      return 1
      ;;
    *)
      log_error "privilege_manager" \
        "Nivel de riesgo desconocido: '${repair_risk}'"
      return 1
      ;;
  esac
}

privilege_get_current_user() {
  if [ -n "${SUDO_USER:-}" ]; then
    echo "$SUDO_USER"
  else
    whoami 2>/dev/null || echo "unknown"
  fi
}
