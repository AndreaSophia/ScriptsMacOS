#!/bin/bash
# =============================================================================
# Meridian — core/result_aggregator.sh
# Responsabilidad: acumular DiagnosticResult[] durante una sesión de diagnóstico
# y proveer acceso a los resultados para reporting y display.
# =============================================================================

# Almacenamiento en memoria: cada línea es un resultado serializado
_AGGREGATOR_RESULTS=""
_AGGREGATOR_COUNT=0

# =============================================================================
# aggregator_add — Agrega el resultado actual (variables RESULT_*) al aggregator
# Llama a result_validate() antes de aceptar
# =============================================================================
aggregator_add() {
  if ! result_validate; then
    log_error "aggregator" \
      "Resultado del módulo '${RESULT_MODULE_ID}' rechazado por fallo de validación"
    return 1
  fi

  local serialized
  serialized="$(result_serialize)"
  _AGGREGATOR_RESULTS="${_AGGREGATOR_RESULTS}${serialized}\n"
  _AGGREGATOR_COUNT=$(( _AGGREGATOR_COUNT + 1 ))

  log_debug "aggregator" \
    "Resultado aceptado: ${RESULT_MODULE_ID} → ${RESULT_STATUS} [${RESULT_SEVERITY}]"
  return 0
}

# =============================================================================
# aggregator_get_all — Imprime todos los resultados serializados, uno por línea
# =============================================================================
aggregator_get_all() {
  printf "%b" "$_AGGREGATOR_RESULTS" | grep -v '^$'
}

# =============================================================================
# aggregator_count — Número de resultados acumulados
# =============================================================================
aggregator_count() {
  echo "$_AGGREGATOR_COUNT"
}

# =============================================================================
# aggregator_count_by_status <status> — Cuenta resultados con ese status
# =============================================================================
aggregator_count_by_status() {
  local target_status="$1"
  aggregator_get_all | sed 's/|||//g' | awk -F'' "\$5 == \"${target_status}\"" | wc -l | tr -d ' '
}

# =============================================================================
# aggregator_count_by_severity <severity> — Cuenta resultados con esa severidad
# =============================================================================
aggregator_count_by_severity() {
  local target_severity="$1"
  aggregator_get_all | sed 's/|||//g' | awk -F'' "\$6 == \"${target_severity}\"" | wc -l | tr -d ' '
}

# =============================================================================
# aggregator_get_worst_severity — Retorna la severidad más alta encontrada
# =============================================================================
aggregator_get_worst_severity() {
  local worst="INFO"
  local priority=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local sev
    sev="$(echo "$line" | sed 's/|||//g' | awk -F'' '{print $6}')"

    local p=0
    case "$sev" in
      INFO)     p=0 ;;
      LOW)      p=1 ;;
      MEDIUM)   p=2 ;;
      HIGH)     p=3 ;;
      CRITICAL) p=4 ;;
    esac

    if [ $p -gt $priority ]; then
      priority=$p
      worst="$sev"
    fi
  done < <(aggregator_get_all)

  echo "$worst"
}

# =============================================================================
# aggregator_summary — Resumen de conteos para el reporte final
# =============================================================================
aggregator_summary() {
  local total pass warn fail skip error worst
  total="$(aggregator_count)"
  pass="$(aggregator_count_by_status "PASS")"
  warn="$(aggregator_count_by_status "WARN")"
  fail="$(aggregator_count_by_status "FAIL")"
  skip="$(aggregator_count_by_status "SKIP")"
  error="$(aggregator_count_by_status "ERROR")"
  worst="$(aggregator_get_worst_severity)"

  printf "total=%s pass=%s warn=%s fail=%s skip=%s error=%s worst_severity=%s" \
    "$total" "$pass" "$warn" "$fail" "$skip" "$error" "$worst"
}

# =============================================================================
# aggregator_reset — Limpia todos los resultados acumulados
# Solo para uso en tests
# =============================================================================
aggregator_reset() {
  _AGGREGATOR_RESULTS=""
  _AGGREGATOR_COUNT=0
}
