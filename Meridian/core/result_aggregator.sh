#!/bin/bash
# Meridian — core/result_aggregator.sh
# Acumula DiagnosticResult v2 sin mutar el resultado global durante lecturas.

_AGGREGATOR_RESULTS=""
_AGGREGATOR_COUNT=0

aggregator_add() {
  if ! result_validate; then
    log_error "aggregator" "Resultado del módulo '${RESULT_MODULE_ID}' rechazado por fallo de validación"
    return 1
  fi

  local serialized
  serialized="$(result_serialize)"
  if [ -n "$_AGGREGATOR_RESULTS" ]; then
    _AGGREGATOR_RESULTS="${_AGGREGATOR_RESULTS}"$'\n'"${serialized}"
  else
    _AGGREGATOR_RESULTS="$serialized"
  fi
  _AGGREGATOR_COUNT=$((_AGGREGATOR_COUNT + 1))
  log_debug "aggregator" "Resultado aceptado: ${RESULT_MODULE_ID} → ${RESULT_STATUS} [${RESULT_SEVERITY}]"
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
# Devuelve el último DiagnosticResult del módulo sin mutar RESULT_*.
# El último resultado es el canónico si una sesión llega a registrar más de
# una observación del mismo módulo (por ejemplo, futuras re-ejecuciones).
aggregator_get_by_module_id() {
  local target="$1" line id match=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id="$(_aggregator_field "$line" 1)"
    [ "$id" = "$target" ] && match="$line"
  done < <(aggregator_get_all)

  [ -n "$match" ] || return 1
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
