#!/bin/bash
# =============================================================================
# Meridian — core/privilege_manager.sh
# Responsabilidad: verificar privilegios antes de ejecutar módulos o reparaciones.
# Principio: mínimo privilegio — cada módulo declara lo que necesita.
# =============================================================================

# Esta capa se ejecuta también dentro de procesos privilegiados. No resolvemos
# utilidades de identidad desde PATH: un entorno heredado de sudo/MDM no debe
# poder sustituir id(1) o whoami(1) por ejecutables controlados por otro usuario.
_PRIVILEGE_ID_BIN="/usr/bin/id"
_PRIVILEGE_WHOAMI_BIN="/usr/bin/whoami"

_privilege_require_identity_tools() {
  if [ ! -x "$_PRIVILEGE_ID_BIN" ]; then
    printf '[privilege_manager] utilidad del sistema no disponible: %s\n' "$_PRIVILEGE_ID_BIN" >&2
    return 1
  fi
  if [ ! -x "$_PRIVILEGE_WHOAMI_BIN" ]; then
    printf '[privilege_manager] utilidad del sistema no disponible: %s\n' "$_PRIVILEGE_WHOAMI_BIN" >&2
    return 1
  fi
  return 0
}

privilege_check_root() {
  # Bash define EUID normalmente; el fallback mantiene la función usable en
  # shells de test, pero nunca ejecuta id(1) desde PATH.
  if [ -n "${EUID+x}" ]; then
    [ "$EUID" -eq 0 ] 2>/dev/null
    return $?
  fi

  [ -x "$_PRIVILEGE_ID_BIN" ] || return 1
  if [ "$("$_PRIVILEGE_ID_BIN" -u 2>/dev/null)" = "0" ]; then
    return 0
  fi
  return 1
}

# Las funciones del core no terminan el proceso por su cuenta. Esta frontera
# informa el requisito y devuelve error; el entrypoint/caller decide si aborta,
# preservando la misma separación que engine_init y los services.
privilege_require_root() {
  if ! privilege_check_root; then
    printf '\n' >&2
    printf '  [✗]  Meridian requiere privilegios de administrador.\n' >&2
    printf '       Ejecuta: sudo meridian\n\n' >&2
    return 1
  fi
  return 0
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

# En el MVP solo LOW y MEDIUM son riesgos ejecutables.
# NONE significa explícitamente "no existe reparación" en IDiagnosticResult y
# por tanto nunca debe autorizar una acción si esta función se invoca de forma
# aislada. HIGH y CRITICAL quedan bloqueados hasta que exista una política
# explícita de reparación avanzada y cobertura de tests suficiente.
privilege_check_repair() {
  local repair_risk="$1"

  case "$repair_risk" in
    LOW|MEDIUM)
      return 0
      ;;
    NONE)
      log_error "privilege_manager" \
        "repair_risk=NONE no representa una reparación ejecutable."
      return 1
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
  if ! _privilege_require_identity_tools; then
    printf '%s\n' "unknown"
    return 1
  fi

  if [ -n "${SUDO_USER:-}" ] && "$_PRIVILEGE_ID_BIN" -u "$SUDO_USER" >/dev/null 2>&1; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  "$_PRIVILEGE_WHOAMI_BIN" 2>/dev/null || {
    printf '%s\n' "unknown"
    return 1
  }
}
