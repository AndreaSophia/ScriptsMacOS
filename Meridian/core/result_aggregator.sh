#!/bin/bash
# Meridian — core/result_aggregator.sh
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
}

aggregator_get_all() { printf '%s\n' "$_AGGREGATOR_RESULTS" | grep -v '^$'; }
aggregator_count() { printf '%s\n' "$_AGGREGATOR_COUNT"; }

aggregator_count_by_status() {
  local target="$1" count=0 line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    result_deserialize "$line"
    [ "$RESULT_STATUS" = "$target" ] && count=$((count + 1))
  done < <(aggregator_get_all)
  printf '%s\n' "$count"
}

aggregator_count_by_severity() {
  local target="$1" count=0 line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    result_deserialize "$line"
    [ "$RESULT_SEVERITY" = "$target" ] && count=$((count + 1))
  done < <(aggregator_get_all)
  printf '%s\n' "$count"
}

aggregator_get_worst_severity() {
  local worst="INFO" priority=0 line sev p
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    result_deserialize "$line"
    sev="$RESULT_SEVERITY"
    p=0
    case "$sev" in INFO) p=0;; LOW) p=1;; MEDIUM) p=2;; HIGH) p=3;; CRITICAL) p=4;; esac
    if [ "$p" -gt "$priority" ]; then priority="$p"; worst="$sev"; fi
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

aggregator_reset() { _AGGREGATOR_RESULTS=""; _AGGREGATOR_COUNT=0; }
