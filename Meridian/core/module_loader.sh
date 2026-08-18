#!/bin/bash
# =============================================================================
# Meridian — core/module_loader.sh
# Descubre módulos, valida manifests y ejecuta diagnósticos en aislamiento.
# Compatible con Bash 3.2/macOS sin dependencias GNU.
# =============================================================================

_manifest_get() {
  local manifest="$1" key="$2"
  grep "^${key}:" "$manifest" 2>/dev/null | \
    sed "s/^${key}:[[:space:]]*//" | \
    sed 's/^["'"'"']//' | sed 's/["'"'"']$//' | \
    tr -d '\r' | head -1
}

# Lee listas YAML simples en formato bloque o inline y devuelve CSV.
# Soporta:
#   dependencies:
#     - foo
#     - bar
# y dependencies: [foo, bar]
# El schema de Meridian mantiene deliberadamente listas escalares simples para
# poder parsearlas con las herramientas BSD incluidas en macOS.
_manifest_get_list_csv() {
  local manifest="$1" key="$2" raw item out=""

  raw="$(awk -v key="$key" '
    $0 ~ "^" key ":[[:space:]]*\\[" {
      line=$0
      sub("^" key ":[[:space:]]*\\[", "", line)
      sub("\\][[:space:]]*$", "", line)
      n=split(line, values, ",")
      for (i=1; i<=n; i++) print values[i]
      exit
    }
    $0 ~ "^" key ":[[:space:]]*$" { in_list=1; next }
    in_list && $0 ~ "^[[:space:]]*-[[:space:]]*" {
      line=$0
      sub("^[[:space:]]*-[[:space:]]*", "", line)
      print line
      next
    }
    in_list && $0 ~ "^[[:space:]]*$" { next }
    in_list { exit }
  ' "$manifest" 2>/dev/null)"

  while IFS= read -r item; do
    item="$(printf '%s\n' "$item" | tr -d "\"'\r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$item" ] && continue
    if [ -n "$out" ]; then out="${out},${item}"; else out="$item"; fi
  done <<EOF
$raw
EOF

  printf '%s\n' "$out"
}

_manifest_validate() {
  local manifest="$1" module_dir="$2" errors=0 field val
  local id name description category version author criticality requires_root timeout repairable dependencies

  # Mantener el runtime alineado con contracts/IModule.md. Estos campos son
  # parte del contrato, no meras recomendaciones de documentación.
  for field in id name description category version author criticality requires_root timeout_seconds; do
    val="$(_manifest_get "$manifest" "$field")"
    if [ -z "$val" ]; then
      log_warn "module_loader" "Manifest inválido en '$(basename "$module_dir")': campo '$field' faltante"
      errors=$((errors + 1))
    fi
  done

  id="$(_manifest_get "$manifest" id)"
  name="$(_manifest_get "$manifest" name)"
  description="$(_manifest_get "$manifest" description)"
  category="$(_manifest_get "$manifest" category)"
  version="$(_manifest_get "$manifest" version)"
  author="$(_manifest_get "$manifest" author)"
  criticality="$(_manifest_get "$manifest" criticality)"
  requires_root="$(_manifest_get "$manifest" requires_root)"
  timeout="$(_manifest_get "$manifest" timeout_seconds)"
  repairable="$(_manifest_get "$manifest" repairable)"
  dependencies="$(_manifest_get_list_csv "$manifest" dependencies)"

  # El directorio y el ejecutable de diagnóstico forman parte de la identidad
  # del módulo registrado. No seguimos symlinks aquí: un destino mutable podría
  # cambiar después del discovery y, en módulos root, terminar ejecutándose con
  # privilegios elevados fuera del árbol esperado de Meridian.
  if [ -L "$module_dir" ]; then
    log_warn "module_loader" "Módulo '$(basename "$module_dir")': directorio symlink no permitido"
    errors=$((errors + 1))
  fi

  # id: snake_case y consistente con el nombre del directorio. El registry
  # depende de IDs deterministas; aceptar aliases silenciosos hace ambiguo el
  # lookup de módulos, reglas y reparaciones.
  if [ -n "$id" ]; then
    printf '%s\n' "$id" | grep -qE '^[a-z][a-z0-9_]*$' || {
      log_warn "module_loader" "Módulo '$(basename "$module_dir")': id='$id' no es snake_case válido"
      errors=$((errors + 1))
    }
    if [ "$id" != "$(basename "$module_dir")" ]; then
      log_warn "module_loader" "Módulo '$(basename "$module_dir")': id='$id' no coincide con el directorio"
      errors=$((errors + 1))
    fi
  fi

  if [ -n "$name" ] && [ "${#name}" -gt 60 ]; then
    log_warn "module_loader" "Módulo '$id': name excede 60 caracteres"
    errors=$((errors + 1))
  fi
  if [ -n "$description" ] && [ "${#description}" -gt 200 ]; then
    log_warn "module_loader" "Módulo '$id': description excede 200 caracteres"
    errors=$((errors + 1))
  fi

  case "$category" in
    security|edr|mdm|network|storage|performance|system|apps|developer) ;;
    *)
      log_warn "module_loader" "Módulo '$id': category='$category' no válida"
      errors=$((errors + 1))
      ;;
  esac

  # El contrato MVP usa semver estricto X.Y.Z para módulos.
  printf '%s\n' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    log_warn "module_loader" "Módulo '$id': version='$version' no cumple semver X.Y.Z"
    errors=$((errors + 1))
  }

  case "$criticality" in low|medium|high|critical) ;; *)
    log_warn "module_loader" "Módulo '$id': criticality='$criticality' no válido"
    errors=$((errors + 1));;
  esac

  case "$requires_root" in true|false) ;; *)
    log_warn "module_loader" "Módulo '$id': requires_root='$requires_root' no válido"
    errors=$((errors + 1));;
  esac

  printf '%s\n' "$timeout" | grep -qE '^[1-9][0-9]*$' || {
    log_warn "module_loader" "Módulo '$id': timeout_seconds='$timeout' no válido"
    errors=$((errors + 1))
  }

  # dependencies es una lista de module_id. Validamos estructura aquí; la
  # existencia y los ciclos se resuelven después de que el registry completo
  # ha sido construido, dentro del engine.
  if [ -n "$dependencies" ]; then
    local dep seen="" dep_ids=()
    IFS=',' read -r -a dep_ids <<< "$dependencies"
    for dep in "${dep_ids[@]}"; do
      printf '%s\n' "$dep" | grep -qE '^[a-z][a-z0-9_]*$' || {
        log_warn "module_loader" "Módulo '$id': dependency='$dep' no es un module_id válido"
        errors=$((errors + 1))
        continue
      }
      if [ "$dep" = "$id" ]; then
        log_warn "module_loader" "Módulo '$id': no puede depender de sí mismo"
        errors=$((errors + 1))
      fi
      case "$seen" in
        *"|${dep}|"*)
          log_warn "module_loader" "Módulo '$id': dependency duplicada '$dep'"
          errors=$((errors + 1))
          ;;
        *) seen="${seen}|${dep}|" ;;
      esac
    done
  fi

  # repairable es opcional por compatibilidad; ausencia equivale a false.
  case "$repairable" in
    true|false|"") ;;
    *)
      log_warn "module_loader" "Módulo '$id': repairable='$repairable' no válido"
      errors=$((errors + 1))
      ;;
  esac

  if [ ! -f "${module_dir}/diagnose.sh" ]; then
    log_warn "module_loader" "Módulo '$id': falta diagnose.sh"
    errors=$((errors + 1))
  elif [ -L "${module_dir}/diagnose.sh" ]; then
    log_warn "module_loader" "Módulo '$id': diagnose.sh no puede ser symlink"
    errors=$((errors + 1))
  fi

  if [ "$repairable" = "true" ]; then
    if [ ! -f "${module_dir}/precheck.sh" ]; then
      log_warn "module_loader" "Módulo '$id': repairable=true pero falta precheck.sh"
      errors=$((errors + 1))
    fi
    if [ ! -f "${module_dir}/repair.sh" ]; then
      log_warn "module_loader" "Módulo '$id': manifest dice repairable=true pero falta repair.sh"
      errors=$((errors + 1))
    fi
    if [ ! -f "${module_dir}/validate.sh" ]; then
      log_warn "module_loader" "Módulo '$id': repairable=true pero falta validate.sh"
      errors=$((errors + 1))
    fi
  else
    if [ -f "${module_dir}/repair.sh" ]; then
      log_warn "module_loader" "Módulo '$id': repair.sh presente pero repairable no es true"
      errors=$((errors + 1))
    fi
  fi

  # IModule exige validate.sh siempre que exista repair.sh, independientemente
  # de cómo haya sido declarado el manifest.
  if [ -f "${module_dir}/repair.sh" ] && [ ! -f "${module_dir}/validate.sh" ]; then
    log_warn "module_loader" "Módulo '$id': repair.sh presente pero falta validate.sh"
    errors=$((errors + 1))
  fi
  if [ -f "${module_dir}/repair.sh" ] && [ ! -f "${module_dir}/precheck.sh" ]; then
    log_warn "module_loader" "Módulo '$id': repair.sh presente pero falta precheck.sh"
    errors=$((errors + 1))
  fi

  [ "$errors" -eq 0 ]
}

module_loader_discover() {
  local base_dir="$1" loaded=0 rejected=0 manifest module_dir
  local id name category version criticality requires_root timeout dependencies

  if [ ! -d "$base_dir" ]; then
    log_error "module_loader" "Directorio de módulos no encontrado: $base_dir"
    return 1
  fi

  log_info "module_loader" "Escaneando módulos en: $base_dir"

  while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue
    module_dir="$(dirname "$manifest")"

    if ! _manifest_validate "$manifest" "$module_dir"; then
      log_warn "module_loader" "Módulo rechazado: $module_dir"
      rejected=$((rejected + 1))
      continue
    fi

    id="$(_manifest_get "$manifest" id)"
    name="$(_manifest_get "$manifest" name)"
    category="$(_manifest_get "$manifest" category)"
    version="$(_manifest_get "$manifest" version)"
    criticality="$(_manifest_get "$manifest" criticality)"
    requires_root="$(_manifest_get "$manifest" requires_root)"
    timeout="$(_manifest_get "$manifest" timeout_seconds)"
    dependencies="$(_manifest_get_list_csv "$manifest" dependencies)"

    if registry_add "$id" "$name" "$category" "$version" "$criticality" "$module_dir" "$requires_root" "$timeout" "$dependencies"; then
      log_ok "module_loader" "Módulo cargado: ${id} (${category}) v${version}"
      loaded=$((loaded + 1))
    fi
  done < <(find "$base_dir" -name manifest.yaml -type f 2>/dev/null | sort)

  log_info "module_loader" "Carga completada: ${loaded} módulos registrados, ${rejected} rechazados"
  return 0
}

# Ejecuta diagnose.sh como source dentro de un subshell. El canal de datos
# (DiagnosticResult) viaja por un archivo separado de stdout, para que cualquier
# printf/echo del módulo no pueda corromper la serialización.
#
# IMPORTANTE: no se confía en `set -e` para detectar fallos de infraestructura.
# Esta función se invoca desde una condición y Bash puede suprimir errexit en ese
# contexto. Cada paso crítico del worker devuelve un código explícito 70-76.
_module_execute_isolated() {
  local module_id="$1" module_dir="$2" evidence_dir="$3" timeout_seconds="$4"
  local tmp_base="${TMPDIR:-/tmp}" result_file stdout_file

  result_file="$(mktemp "${tmp_base%/}/meridian_module_result.XXXXXX")" || return 1
  stdout_file="$(mktemp "${tmp_base%/}/meridian_module_stdout.XXXXXX")" || {
    rm -f "$result_file"
    return 1
  }

  (
    if ! source "${MERIDIAN_CORE_DIR}/result_model.sh"; then
      exit 70
    fi
    if ! source "${MERIDIAN_LOGGING_DIR}/logger.sh"; then
      exit 71
    fi

    export MERIDIAN_MODULE_DIR="$module_dir"
    export MERIDIAN_EVIDENCE_DIR="$evidence_dir"
    export MERIDIAN_LOG_FILE="${MERIDIAN_LOG_FILE:-/dev/null}"
    export MERIDIAN_TEST_MODE="${MERIDIAN_TEST_MODE:-0}"
    export MERIDIAN_FIXTURE_DIR="${MERIDIAN_FIXTURE_DIR:-}"

    if ! result_init; then
      exit 72
    fi
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(_manifest_get "${module_dir}/manifest.yaml" version)"
    if [ -z "$RESULT_MODULE_VERSION" ]; then
      exit 73
    fi

    if ! result_time_start; then
      exit 74
    fi
    local module_rc
    if source "${module_dir}/diagnose.sh" >"$stdout_file" 2>>"${MERIDIAN_LOG_FILE:-/dev/null}"; then
      module_rc=0
    else
      module_rc=$?
    fi
    if ! result_time_end; then
      exit 75
    fi

    if [ "$module_rc" -ne 0 ] && [ "${RESULT_EXIT_CODE:-0}" -eq 0 ] 2>/dev/null; then
      RESULT_EXIT_CODE="$module_rc"
    fi

    if ! result_serialize > "$result_file"; then
      exit 76
    fi
    exit "$module_rc"
  ) &

  local pid=$! elapsed=0 module_rc
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ] 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      [ -s "$stdout_file" ] && cat "$stdout_file" >&2
      rm -f "$result_file" "$stdout_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if wait "$pid"; then
    module_rc=0
  else
    module_rc=$?
  fi

  [ -s "$stdout_file" ] && cat "$stdout_file" >&2
  cat "$result_file" 2>/dev/null
  rm -f "$result_file" "$stdout_file"
  return "$module_rc"
}

module_loader_run() {
  local module_id="$1" evidence_dir="$2"
  local module_dir requires_root timeout module_evidence_dir serialized_result rc

  if ! registry_exists "$module_id"; then
    log_error "module_loader" "Módulo no registrado: $module_id"
    return 1
  fi

  module_dir="$(registry_get_path "$module_id")"
  requires_root="$(registry_get_field "$module_id" 7)"
  timeout="$(registry_get_field "$module_id" 8)"
  timeout="${timeout:-30}"

  if ! privilege_check_module "$module_id" "$requires_root"; then
    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
    RESULT_STATUS="SKIP"
    RESULT_SEVERITY="INFO"
    RESULT_TITLE="Módulo omitido por privilegios insuficientes"
    RESULT_DESCRIPTION="El módulo requiere root y el diagnóstico no corre como root."
    RESULT_EXPLANATION="Ejecutar con sudo para obtener este diagnóstico."
    RESULT_RISK="N/A"
    RESULT_SUGGESTED_ACTION="sudo meridian"
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXECUTION_TIME_MS="0"
    RESULT_EXIT_CODE="0"
    result_serialize
    return 0
  fi

  module_evidence_dir="${evidence_dir}/${module_id}"
  if [ -L "$module_evidence_dir" ]; then
    log_error "module_loader" "Directorio de evidencia symlink rechazado para '${module_id}'"
    return 1
  fi
  if ! mkdir -p "$module_evidence_dir" 2>/dev/null; then
    log_error "module_loader" "No se pudo crear evidencia para '${module_id}': $module_evidence_dir"
    return 1
  fi
  log_info "module_loader" "Ejecutando módulo: ${module_id} (timeout: ${timeout}s)"

  if serialized_result="$(_module_execute_isolated "$module_id" "$module_dir" "$module_evidence_dir" "$timeout")"; then
    rc=0
  else
    rc=$?
  fi

  if [ "$rc" -eq 124 ]; then
    result_init
    RESULT_MODULE_ID="$module_id"
    RESULT_MODULE_VERSION="$(registry_get_field "$module_id" 4)"
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_TITLE="Módulo excedió el tiempo máximo de ejecución"
    RESULT_DESCRIPTION="El diagnóstico no completó en ${timeout} segundos."
    RESULT_EXPLANATION="Posible bloqueo esperando recursos del sistema o red."
    RESULT_RISK="El estado del módulo es desconocido."
    RESULT_SUGGESTED_ACTION="Reintentar y revisar diagnostic.log."
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_EXIT_CODE="124"
    RESULT_RAW_OUTPUT=""
    result_serialize
    return 0
  fi

  # Los códigos 70-76 están reservados para la infraestructura del worker y
  # solo se interpretan así cuando no existe un DiagnosticResult serializado.
  # Un diagnose.sh que retorne, por ejemplo, 70 pero sí produzca resultado sigue
  # tratándose como un fallo normal del módulo y se normaliza más abajo.
  if [ -z "$serialized_result" ] && [ "$rc" -ge 70 ] 2>/dev/null && [ "$rc" -le 76 ] 2>/dev/null; then
    log_error "module_loader" "Infraestructura del worker falló para '${module_id}' (rc=${rc})"
    return 1
  fi

  if [ -z "$serialized_result" ]; then
    log_error "module_loader" "Módulo '${module_id}' no produjo DiagnosticResult"
    return 1
  fi

  # Framing inválido no debe caer a result_validate con RESULT_* residuales del
  # caller. Deserialización y validación son dos fronteras distintas y ambas
  # deben superarse antes de aceptar cualquier dato producido por un módulo.
  if ! result_deserialize "$serialized_result"; then
    log_error "module_loader" "Módulo '${module_id}' produjo framing DiagnosticResult inválido"
    return 1
  fi
  if ! result_validate; then
    log_error "module_loader" "Módulo '${module_id}' produjo un DiagnosticResult inválido"
    return 1
  fi

  if [ "$rc" -ne 0 ]; then
    # Un script que terminó en error no puede conservar una reparación parcial
    # como autorizable. Normalizar a un estado interno, no reparable y validado,
    # antes de devolver el resultado al engine.
    RESULT_STATUS="ERROR"
    RESULT_SEVERITY="HIGH"
    RESULT_EXIT_CODE="$rc"
    RESULT_TITLE="Error interno del módulo"
    RESULT_REPAIRABLE="false"
    RESULT_REPAIR_RISK="NONE"
    RESULT_REPAIR_ID=""
    RESULT_RULE_TRIGGERED=""
    if ! result_validate; then
      log_error "module_loader" "Módulo '${module_id}' produjo un estado de error imposible de normalizar"
      return 1
    fi
    result_serialize
    return 0
  fi

  printf '%s\n' "$serialized_result"
  return 0
}
