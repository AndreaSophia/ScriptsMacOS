#!/bin/bash
# =============================================================================
# Meridian — ui/tui/menu.sh
# Responsabilidad: menús de selección para el usuario.
# Degrada automáticamente a texto plano si gum no está disponible.
# La UI no contiene lógica de negocio.
# =============================================================================

# =============================================================================
# tui_banner — Pantalla de bienvenida
# =============================================================================
tui_banner() {
  # `clear` puede fallar cuando TERM no existe (Workspace ONE, SSH no
  # interactivo, launchd). Con el entrypoint en `set -e`, eso no debe abortar
  # una sesión de diagnóstico.
  if [ -t 1 ] && [ -n "${TERM:-}" ] && command -v clear >/dev/null 2>&1; then
    clear 2>/dev/null || true
  fi

  printf "\n"
  printf "  \033[1;36m══════════════════════════════════════════════════\033[0m\n"
  printf "  \033[1;36m  Meridian\033[0m\n"
  printf "  \033[0;90m  %s\033[0m\n" "${MERIDIAN_ORG:-Apple Platform Team}"
  printf "  \033[0;90m  v%s\033[0m\n" "${MERIDIAN_VERSION:-1.0.0-mvp}"
  printf "  \033[1;36m══════════════════════════════════════════════════\033[0m\n"
  printf "\n"
}

# =============================================================================
# tui_menu_main — Menú principal de selección de módulos
# Retorna el ID o lista de IDs seleccionados, o "all" para todos
# =============================================================================
tui_menu_main() {
  local available_ids
  available_ids="$(registry_get_all_ids)"
  local count
  count="$(registry_count)"

  if [ "$count" -eq 0 ]; then
    log_error "tui" "No hay módulos disponibles"
    return 1
  fi

  # Un menú no tiene semántica válida sin stdin interactivo. El entrypoint
  # normalmente evita llegar aquí en modo headless, pero conservamos esta
  # defensa para callers que reutilicen la TUI directamente.
  if [ ! -t 0 ]; then
    log_warn "tui" "stdin no interactivo; se seleccionan todos los módulos"
    printf '%s\n' "all"
    return 0
  fi

  printf "  \033[1;37m¿Qué diagnóstico deseas ejecutar?\033[0m\n\n"

  if command -v gum >/dev/null 2>&1; then
    _tui_menu_gum "$available_ids"
  else
    _tui_menu_plain "$available_ids"
  fi
}

# =============================================================================
# _tui_menu_gum <ids_list> — Menú con gum (multi-select con colores)
# =============================================================================
_tui_menu_gum() {
  local ids_list="$1"
  local options=()

  options+=("Todos los módulos")
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    local name
    name="$(registry_get_field "$id" 2)"
    local cat
    cat="$(registry_get_field "$id" 3)"
    options+=("${id} — ${name} [${cat}]")
  done < <(echo "$ids_list")

  local selected
  selected="$(printf '%s\n' "${options[@]}" | \
    gum choose --no-limit --header "Selecciona módulos (ESPACIO para marcar, ENTER para confirmar):")"

  if echo "$selected" | grep -q "Todos los módulos"; then
    echo "all"
  else
    echo "$selected" | awk '{print $1}'
  fi
}

# =============================================================================
# _tui_menu_plain <ids_list> — Menú de texto plano (sin dependencias)
# =============================================================================
_tui_menu_plain() {
  local ids_list="$1"
  local index=1
  local items=()

  printf "  0) Todos los módulos\n"

  while IFS= read -r id; do
    [ -z "$id" ] && continue
    local name
    name="$(registry_get_field "$id" 2)"
    local cat
    cat="$(registry_get_field "$id" 3)"
    printf "  %s) %s — %s [%s]\n" "$index" "$id" "$name" "$cat"
    items+=("$id")
    index=$((index + 1))
  done < <(echo "$ids_list")

  printf "\n"
  printf "  Opción (0 para todos, o números separados por espacio): "
  local reply
  read -r reply

  if [ "$reply" = "0" ] || [ -z "$reply" ]; then
    echo "all"
    return
  fi

  local selected_ids=""
  for num in $reply; do
    if echo "$num" | grep -qE '^[0-9]+$'; then
      local idx=$(( num - 1 ))
      if [ $idx -ge 0 ] && [ $idx -lt ${#items[@]} ]; then
        selected_ids="${selected_ids} ${items[$idx]}"
      fi
    fi
  done

  echo "$selected_ids" | xargs
}

# =============================================================================
# tui_separator — Línea divisoria
# =============================================================================
tui_separator() {
  printf "  \033[0;90m──────────────────────────────────────────────────\033[0m\n"
}
