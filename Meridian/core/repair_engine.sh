#!/bin/bash
# =============================================================================
# Meridian — core/repair_engine.sh
# Responsabilidad: ejecutar reparaciones con confirmación obligatoria,
# registro en audit log, y llamada posterior al validation engine.
#
# Principios MVP:
#  - Solo LOW y MEDIUM risk en esta versión
#  - Confirmación explícita siempre requerida
#  - Toda acción queda en audit log ANTES de ejecutarse
# =============================================================================

# =============================================================================
# repair_engine_run <module_id> <repair_id> <repair_risk>
# Ciclo completo: mostrar advertencia → confirmar → audit → ejecutar → validar
# =============================================================================
repair_engine_run() {
  local module_id="$1"
  local repair_id="$2"
  local repair_risk="$3"

  # 1. Verificar que la reparación es permitida en esta versión
  if ! privilege_check_repair "$repair_risk"; then
    return 1
  fi

  local module_dir
  module_dir="$(registry_get_path "$module_id")"

  if [ ! -f "${module_dir}/repair.sh" ]; then
    log_error "repair_engine" \
      "repair.sh no encontrado para módulo: $module_id"
    return 1
  fi

  # 2. Mostrar advertencia de reparación
  _repair_show_warning "$module_id" "$repair_id" "$repair_risk"

  # 3. Solicitar confirmación explícita
  if ! _repair_confirm "$repair_risk"; then
    log_info "repair_engine" "Reparación cancelada por el usuario: $repair_id"
    log_audit "repair_engine" "REPAIR_CANCELLED" \
      "module=${module_id} repair_id=${repair_id} risk=${repair_risk}"
    return 0
  fi

  # 4. Registrar intención ANTES de ejecutar (audit log)
  log_audit "repair_engine" "REPAIR_STARTED" \
    "module=${module_id} repair_id=${repair_id} risk=${repair_risk} operator=$(privilege_get_current_user)"

  # 5. Ejecutar repair.sh
  log_step "Ejecutando reparación: ${repair_id}"

  bash "${module_dir}/repair.sh" \
    2>>"${MERIDIAN_LOG_FILE:-/dev/null}"
  local repair_rc=$?

  if [ $repair_rc -eq 0 ]; then
    log_ok "repair_engine" "Reparación completada: ${repair_id}"
    log_audit "repair_engine" "REPAIR_COMPLETED" \
      "module=${module_id} repair_id=${repair_id} rc=0"
  else
    log_error "repair_engine" \
      "Reparación falló: ${repair_id} (rc=${repair_rc})"
    log_audit "repair_engine" "REPAIR_FAILED" \
      "module=${module_id} repair_id=${repair_id} rc=${repair_rc}"
    return 1
  fi

  # 6. Ejecutar validación post-reparación
  validation_engine_run "$module_id"
  return $?
}

# =============================================================================
# _repair_show_warning <module_id> <repair_id> <repair_risk>
# =============================================================================
_repair_show_warning() {
  local module_id="$1"
  local repair_id="$2"
  local repair_risk="$3"

  local module_name
  module_name="$(registry_get_field "$module_id" 2)"

  printf "\n"
  printf "  \033[1;33m⚠  REPARACIÓN SOLICITADA\033[0m\n"
  printf "  ─────────────────────────────────────────\n"
  printf "  Módulo  : %s\n" "$module_name"
  printf "  Acción  : %s\n" "$repair_id"
  printf "  Riesgo  : \033[1m%s\033[0m\n" "$repair_risk"
  printf "  ─────────────────────────────────────────\n"
  printf "\n"
}

# =============================================================================
# _repair_confirm <repair_risk>
# Solicita confirmación al usuario según el nivel de riesgo.
# Retorna 0 si confirmó, 1 si canceló.
# =============================================================================
_repair_confirm() {
  local repair_risk="$1"

  case "$repair_risk" in
    LOW)
      printf "  Esta operación tiene riesgo BAJO. Presiona ENTER para continuar o Ctrl+C para cancelar..."
      read -r _
      return 0
      ;;
    MEDIUM)
      printf "  Esta operación tiene riesgo MEDIO. ¿Deseas continuar? (s/n): "
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
