#!/bin/bash
# Meridian — core/result_aggregator.sh
# Acumula DiagnosticResult v2 sin mutar el resultado global durante lecturas.
# Invariante: existe como máximo un resultado canónico por module_id.

_AGGREGATOR_RESULTS=""
_AGGREGATOR_COUNT=0

# _aggregator_contains_module_id <module_id>
# Comprueba identidad sin deserializar ni mutar RESULT_* del caller.
_aggregator_contains_module_id() {
  local target="${1:-}" line id
  [ -n "$target" ] || return 1

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_aggregator_field "$line" 1)"
    [ "$id" = "$target" ] && return 0
  done < <(aggregator_get_all)

  return 1
}

aggregator_add() {
  if ! result_validate; then
    log_error "aggregator" "Resultado del módulo '${RESULT_MODULE_ID}' rechazado por fallo de validación"
    return 1
  fi

  # El aggregator representa estado actual, no historial. Una segunda
  # observación del mismo módulo debe entrar únicamente por la operación
  # explícita de reemplazo post-validación.
  if _aggregator_contains_module_id "$RESULT_MODULE_ID"; then
    log_error "aggregator" "Resultado canónico duplicado rechazado: ${RESULT_MODULE_ID}"
    return 1
  fi

  local serialized
  serialized="$(result_serialize)" || return 1
  if [ -n "$_AGGREGATOR_RESULTS" ]; then
    _AGGREGATOR_RESULTS="${_AGGREGATOR_RESULTS}"$'\n'"${serialized}"
  else
    _AGGREGATOR_RESULTS="$serialized"
  fi
  _AGGREGATOR_COUNT=$((_AGGREGATOR_COUNT + 1))
  log_debug "aggregator" "Resultado aceptado: ${RESULT_MODULE_ID} → ${RESULT_STATUS} [${RESULT_SEVERITY}]"
  return 0
}

# aggregator_replace_current_by_module_id
# Reemplaza el resultado canónico de RESULT_MODULE_ID sin aumentar el total.
# Se usa tras una validación post-reparación: el audit log conserva el historial,
# mientras reporting/resúmenes deben reflejar el estado actual del módulo.
aggregator_replace_current_by_module_id() {
  if ! result_validate; then
    log_error "aggregator" "Resultado de reemplazo '${RESULT_MODULE_ID}' rechazado por fallo de validación"
    return 1
  fi

  local target="$RESULT_MODULE_ID" replacement line id rebuilt="" replaced=0
  replacement="$(result_serialize)" || return 1

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_aggregator_field "$line" 1)"
    if [ "$id" = "$target" ]; then
      # Si por corrupción previa existiera más de una copia, no ocultar la
      # anomalía promoviendo silenciosamente múltiples registros.
      replaced=$((replaced + 1))
      line="$replacement"
    fi
    if [ -n "$rebuilt" ]; then
      rebuilt="${rebuilt}"$'\n'"${line}"
    else
      rebuilt="$line"
    fi
  done < <(aggregator_get_all)

  if [ "$replaced" -ne 1 ]; then
    log_error "aggregator" "Se esperaba exactamente un resultado canónico para ${target}; encontrados: ${replaced}"
    return 1
  fi

  _AGGREGATOR_RESULTS="$rebuilt"
  log_debug "aggregator" "Resultado canónico actualizado: ${RESULT_MODULE_ID} → ${RESULT_STATUS} [${RESULT_SEVERITY}]"
  return 0
}

aggregator_get_all() {
  [ -n "$_AGGREGATOR_RESULTS" ] && printf '%s\n' "$_AGGREGATOR_RESULTS"
}

aggregator_count() {
  printf '%s\n' "$_AGGREGATOR_COUNT"
}

# Lee un campo del formato DiagnosticResult v2 directamente, evitando que
# consultas/resúmenes sobrescriban las variables RESULT_* del caller.
_aggregator_field() {
  local line="$1" field="$2"
  _result_field "$line" "$field"
}

# aggregator_get_by_module_id <module_id>
# Devuelve el único DiagnosticResult canónico del módulo sin mutar RESULT_*.
aggregator_get_by_module_id() {
  local target="${1:-}" line id match="" matches=0
  [ -n "$target" ] || return 1

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_aggregator_field "$line" 1)"
    if [ "$id" = "$target" ]; then
      match="$line"
      matches=$((matches + 1))
    fi
  done < <(aggregator_get_all)

  [ "$matches" -eq 1 ] || return 1
  printf '%s\n' "$match"
}

aggregator_count_by_status() {
  local target="$1" count=0 line status
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    status="$(_aggregator_field "$line" 5)"
    [ "$status" = "$target" ] && count=$((count + 1))
  done < <(aggregator_get_all)
  printf '%s\n' "$count"
}

aggregator_count_by_severity() {
  local target="$1" count=0 line severity
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    severity="$(_aggregator_field "$line" 6)"
    [ "$severity" = "$target" ] && count=$((count + 1))
  done < <(aggregator_get_all)
  printf '%s\n' "$count"
}

aggregator_get_worst_severity() {
  local worst="INFO" priority=0 line sev p
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    sev="$(_aggregator_field "$line" 6)"
    p=0
    case "$sev" in
      INFO) p=0 ;;
      LOW) p=1 ;;
      MEDIUM) p=2 ;;
      HIGH) p=3 ;;
      CRITICAL) p=4 ;;
      *) continue ;;
    esac
    if [ "$p" -gt "$priority" ]; then
      priority="$p"
      worst="$sev"
    fi
  done < <(aggregator_get_all)
  printf '%s\n' "$worst"
}

aggregator_summary() {
  printf 'total=%s pass=%s warn=%s fail=%s skip=%s error=%s worst_severity=%s' \
    "$(aggregator_count)" "$(aggregator_count_by_status PASS)" \
    "$(aggregator_count_by_status WARN)" "$(aggregator_count_by_status FAIL)" \
    "$(aggregator_count_by_status SKIP)" "$(aggregator_count_by_status ERROR)" \
    "$(aggregator_get_worst_severity)"
}

aggregator_reset() {
  _AGGREGATOR_RESULTS=""
  _AGGREGATOR_COUNT=0
}
