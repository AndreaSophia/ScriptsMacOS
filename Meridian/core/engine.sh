#!/bin/bash
# Meridian — core/engine.sh

# El engine puede ejecutarse como root desde sudo, launchd o MDM. Las utilidades
# usadas para crear sesiones y procesar la frontera de stdout de los módulos no
# se resuelven mediante PATH heredado.
_ENGINE_DIRNAME="/usr/bin/dirname"
_ENGINE_MKDIR="/bin/mkdir"
_ENGINE_MKTEMP="/usr/bin/mktemp"
_ENGINE_TAIL="/usr/bin/tail"
_ENGINE_WC="/usr/bin/wc"
_ENGINE_TR="/usr/bin/tr"
_ENGINE_SED="/usr/bin/sed"
_ENGINE_RM="/bin/rm"

# Estado efímero del resolvedor de dependencias. Se reinicia en cada engine_run.
# Se usan strings delimitados en vez de associative arrays para conservar
# compatibilidad con Bash 3.2 incluido en macOS.
_ENGINE_DEP_RESOLVED=""
_ENGINE_DEP_VISITING=""
_ENGINE_DEP_ORDER=""

_engine_require_system_tools() {
  local tool
  for tool in \
    "$_ENGINE_DIRNAME" \
    "$_ENGINE_MKDIR" \
    "$_ENGINE_MKTEMP" \
    "$_ENGINE_TAIL" \
    "$_ENGINE_WC" \
    "$_ENGINE_TR" \
    "$_ENGINE_SED" \
    "$_ENGINE_RM"; do
    if [ ! -x "$tool" ]; then
      printf '%s\n' "[FATAL] Utilidad de sistema requerida no disponible: $tool" >&2
      return 1
    fi
  done
  return 0
}

engine_init() {
  local output_dir="$1" output_parent

  if [ -z "$output_dir" ]; then
    printf '%s\n' "[FATAL] engine_init requiere un directorio de salida" >&2
    return 1
  fi

  if ! _engine_require_system_tools; then
    return 1
  fi

  # La sesión debe nacer como un directorio nuevo creado por Meridian. Reusar
  # una ruta preexistente permitiría mezclar evidencia entre sesiones y, bajo
  # sudo, podría hacer que el proceso privilegiado escribiera dentro de una ruta
  # preparada previamente por otro usuario. mkdir sin -p nos da una creación
  # atómica: si el nombre ya existe (archivo, directorio o symlink), fallamos.
  output_parent="$("$_ENGINE_DIRNAME" "$output_dir")"
  if [ -L "$output_parent" ]; then
    printf '%s\n' "[FATAL] El directorio padre de salida no puede ser symlink: $output_parent" >&2
    return 1
  fi
  if [ ! -d "$output_parent" ]; then
    if ! "$_ENGINE_MKDIR" -p "$output_parent" 2>/dev/null; then
      printf '%s\n' "[FATAL] No se pudo crear el directorio padre de salida: $output_parent" >&2
      return 1
    fi
  fi
  if [ -e "$output_dir" ] || [ -L "$output_dir" ]; then
    printf '%s\n' "[FATAL] El directorio de sesión ya existe y no será reutilizado: $output_dir" >&2
    return 1
  fi
  if ! "$_ENGINE_MKDIR" "$output_dir" 2>/dev/null; then
    printf '%s\n' "[FATAL] No se pudo crear de forma exclusiva el directorio de sesión: $output_dir" >&2
    return 1
  fi

  export MERIDIAN_OUTPUT_DIR="$output_dir"
  export MERIDIAN_EVIDENCE_DIR="${output_dir}/evidencias"
  export MERIDIAN_CORE_DIR="${MERIDIAN_ROOT}/core"
  export MERIDIAN_LOGGING_DIR="${MERIDIAN_ROOT}/logging"

  # El directorio de evidencia tampoco se reutiliza. Si aparece después de la
  # creación exclusiva de la sesión, tratamos el estado como una carrera o una
  # mutación externa y fallamos cerrado.
  if [ -e "$MERIDIAN_EVIDENCE_DIR" ] || [ -L "$MERIDIAN_EVIDENCE_DIR" ]; then
    printf '%s\n' "[FATAL] El directorio de evidencia ya existe inesperadamente: $MERIDIAN_EVIDENCE_DIR" >&2
    return 1
  fi
  if ! "$_ENGINE_MKDIR" "$MERIDIAN_EVIDENCE_DIR" 2>/dev/null; then
    printf '%s\n' "[FATAL] No se pudo crear el directorio de evidencia: $MERIDIAN_EVIDENCE_DIR" >&2
    return 1
  fi

  registry_reset
  aggregator_reset

  if ! logger_init "${output_dir}/diagnostic.log"; then
    printf '%s\n' "[FATAL] No se pudo inicializar el logger de sesión" >&2
    return 1
  fi

  log_step "Inicializando Meridian v${MERIDIAN_VERSION}"

  log_step "Cargando módulos"
  if ! module_loader_discover "${MERIDIAN_ROOT}/modules"; then
    log_error "engine" "No se pudo completar el descubrimiento de módulos"
    return 1
  fi

  if [ "$(registry_count)" -eq 0 ]; then
    log_error "engine" "No se registraron módulos válidos"
    return 1
  fi

  log_step "Cargando reglas"
  if ! rule_loader_load "${MERIDIAN_ROOT}/rules/definitions"; then
    log_error "engine" "No se pudo completar la carga de reglas"
    return 1
  fi

  return 0
}

_engine_dependency_reset() {
  _ENGINE_DEP_RESOLVED=""
  _ENGINE_DEP_VISITING=""
  _ENGINE_DEP_ORDER=""
}

# DFS topológico sobre el registry. Una dependencia se agrega antes que el
# módulo que la declara. Dependencias inexistentes y ciclos invalidan el plan
# completo antes de ejecutar diagnósticos parciales.
_engine_dependency_visit() {
  local module_id="$1" dependencies dep
  local dep_ids=()

  if ! registry_exists "$module_id"; then
    log_error "engine" "Módulo solicitado no registrado: $module_id"
    return 1
  fi

  case "$_ENGINE_DEP_RESOLVED" in
    *"|${module_id}|"*) return 0 ;;
  esac

  case "$_ENGINE_DEP_VISITING" in
    *"|${module_id}|"*)
      log_error "engine" "Ciclo de dependencias detectado en módulo: $module_id"
      return 1
      ;;
  esac

  _ENGINE_DEP_VISITING="${_ENGINE_DEP_VISITING}|${module_id}|"
  dependencies="$(registry_get_dependencies "$module_id" 2>/dev/null || true)"

  if [ -n "$dependencies" ]; then
    IFS=',' read -r -a dep_ids <<< "$dependencies"
    for dep in "${dep_ids[@]}"; do
      [ -z "$dep" ] && continue
      if ! registry_exists "$dep"; then
        log_error "engine" "Dependencia no registrada: ${module_id} requiere ${dep}"
        _ENGINE_DEP_VISITING="${_ENGINE_DEP_VISITING//|${module_id}|/}"
        return 1
      fi
      if ! _engine_dependency_visit "$dep"; then
        _ENGINE_DEP_VISITING="${_ENGINE_DEP_VISITING//|${module_id}|/}"
        return 1
      fi
    done
  fi

  _ENGINE_DEP_VISITING="${_ENGINE_DEP_VISITING//|${module_id}|/}"
  _ENGINE_DEP_RESOLVED="${_ENGINE_DEP_RESOLVED}|${module_id}|"
  if [ -n "$_ENGINE_DEP_ORDER" ]; then
    _ENGINE_DEP_ORDER="${_ENGINE_DEP_ORDER}"$'\n'"${module_id}"
  else
    _ENGINE_DEP_ORDER="$module_id"
  fi
  return 0
}

_engine_resolve_dependencies() {
  local id
  _engine_dependency_reset

  for id in "$@"; do
    [ -z "$id" ] && continue
    if ! _engine_dependency_visit "$id"; then
      _engine_dependency_reset
      return 1
    fi
  done

  printf '%s\n' "$_ENGINE_DEP_ORDER"
  return 0
}

engine_run() {
  local requested_ids=("$@") module_ids=() id failures=0 ordered

  if [ ${#requested_ids[@]} -eq 0 ]; then
    while IFS= read -r id; do
      [ -n "$id" ] && requested_ids+=("$id")
    done < <(registry_get_all_ids)
  fi
  [ ${#requested_ids[@]} -gt 0 ] || { log_warn "engine" "No hay módulos disponibles"; return 1; }

  if ! ordered="$(_engine_resolve_dependencies "${requested_ids[@]}")"; then
    log_error "engine" "No se pudo construir un plan de ejecución válido por dependencias"
    return 1
  fi

  while IFS= read -r id; do
    [ -n "$id" ] && module_ids+=("$id")
  done <<EOF
$ordered
EOF

  [ ${#module_ids[@]} -gt 0 ] || {
    log_error "engine" "El plan de ejecución quedó vacío"
    return 1
  }

  if [ ${#module_ids[@]} -gt ${#requested_ids[@]} ]; then
    log_info "engine" "El plan incluye dependencias adicionales (${#requested_ids[@]} solicitados → ${#module_ids[@]} a ejecutar)"
  fi

  for id in "${module_ids[@]}"; do
    if ! _engine_run_module "$id"; then
      failures=$((failures + 1))
      log_error "engine" "Fallo interno procesando módulo: $id"
    fi
  done

  [ "$failures" -eq 0 ] || log_warn "engine" "La sesión completó con ${failures} fallo(s) internos de módulo"
  return 0
}

_engine_add_internal_error() {
  local module_id="$1" title="$2" description="$3"
  result_init
  RESULT_MODULE_ID="$module_id"
  RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="$title"
  RESULT_DESCRIPTION="$description"
  RESULT_EXPLANATION="Meridian no pudo obtener o procesar un DiagnosticResult válido para este módulo."
  RESULT_RISK="El estado real del componente permanece desconocido."
  RESULT_SUGGESTED_ACTION="Revisar diagnostic.log y la evidencia del módulo."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_EXIT_CODE="1"
  aggregator_add
}

_engine_run_module() {
  local module_id="$1" module_name serialized run_rc status_icon expected_version line_count
  registry_exists "$module_id" || { log_warn "engine" "Módulo no registrado: $module_id"; return 0; }
  module_name="$(registry_get_field "$module_id" 2)"
  expected_version="$(registry_get_field "$module_id" 4)"
  log_info "engine" "▷ ${module_name} (${module_id})"

  if ! _engine_require_system_tools; then
    log_error "engine" "No están disponibles las utilidades de sistema requeridas por el worker del engine"
    return 1
  fi

  local tmp_base="${TMPDIR:-/tmp}" capture
  capture="$("$_ENGINE_MKTEMP" "${tmp_base%/}/meridian_engine.XXXXXX")" || return 1

  if module_loader_run "$module_id" "$MERIDIAN_EVIDENCE_DIR" >"$capture"; then
    run_rc=0
  else
    run_rc=$?
  fi

  # stdout del loader es una frontera de datos: la última línea es el framing
  # canónico y cualquier línea anterior se conserva como salida diagnóstica.
  # Usamos únicamente binarios del sistema para que un PATH hostil no pueda
  # alterar, ocultar o fabricar el DiagnosticResult que entra al aggregator.
  serialized="$("$_ENGINE_TAIL" -n 1 "$capture" 2>/dev/null)"
  line_count="$("$_ENGINE_WC" -l < "$capture" | "$_ENGINE_TR" -d ' ')"
  case "$line_count" in
    ''|*[!0-9]*)
      "$_ENGINE_RM" -f "$capture"
      log_error "engine" "No se pudo determinar de forma segura el framing de salida del módulo '${module_id}'"
      return 1
      ;;
  esac
  if [ "$line_count" -gt 1 ]; then
    "$_ENGINE_SED" '$d' "$capture" >&2
  fi
  "$_ENGINE_RM" -f "$capture"

  if [ -z "$serialized" ] || [ "$run_rc" -ne 0 ]; then
    log_error "engine" "Módulo '${module_id}' no produjo resultado válido"
    if ! _engine_add_internal_error "$module_id" \
      "Error interno ejecutando el módulo" \
      "El loader terminó con rc=${run_rc} o sin un DiagnosticResult utilizable."; then
      return 1
    fi
    return 0
  fi

  # No evaluar reglas ni mutar el aggregator si el framing v2 está corrupto.
  # result_deserialize valida que existan exactamente los 19 campos canónicos.
  if ! result_deserialize "$serialized"; then
    log_error "engine" "Módulo '${module_id}' produjo framing DiagnosticResult inválido"
    if ! _engine_add_internal_error "$module_id" \
      "DiagnosticResult con framing inválido" \
      "El resultado serializado no cumple el formato canónico v2."; then
      return 1
    fi
    return 0
  fi

  # La identidad del resultado pertenece al módulo solicitado, no al script que
  # pueda haber mutado RESULT_* accidentalmente. Un módulo no puede publicar
  # estado canónico bajo la identidad o versión de otro módulo.
  if [ "$RESULT_MODULE_ID" != "$module_id" ] || [ "$RESULT_MODULE_VERSION" != "$expected_version" ]; then
    log_error "engine" "Módulo '${module_id}' intentó publicar identidad/version ajena: ${RESULT_MODULE_ID} v${RESULT_MODULE_VERSION}"
    if ! _engine_add_internal_error "$module_id" \
      "DiagnosticResult con identidad inconsistente" \
      "El módulo produjo ${RESULT_MODULE_ID} v${RESULT_MODULE_VERSION}; se esperaba ${module_id} v${expected_version}."; then
      return 1
    fi
    return 0
  fi

  rule_engine_evaluate "$module_id"
  if ! aggregator_add; then
    log_error "engine" "Resultado de '${module_id}' rechazado por aggregator"
    if ! _engine_add_internal_error "$module_id" \
      "DiagnosticResult rechazado por el aggregator" \
      "El resultado del módulo no pudo incorporarse a la sesión."; then
      return 1
    fi
    return 0
  fi

  case "$RESULT_STATUS" in PASS) status_icon="✓";; WARN) status_icon="!";; FAIL) status_icon="✗";; SKIP) status_icon="–";; ERROR) status_icon="⚡";; *) status_icon="?";; esac
  log_info "engine" "  ${status_icon} ${RESULT_STATUS} [${RESULT_SEVERITY}] ${RESULT_TITLE}"
  return 0
}

engine_get_results() { aggregator_get_all; }
engine_get_summary() { aggregator_summary; }
