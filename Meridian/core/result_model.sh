#!/bin/bash
# =============================================================================
# Meridian — core/result_model.sh
# Responsabilidad: definir, inicializar, validar y serializar DiagnosticResult
#
# Este archivo es el único lugar donde se define la estructura de datos central.
# Ningún módulo ni componente puede inventar campos fuera de este contrato.
# =============================================================================

# --- Enums válidos ---
readonly _VALID_STATUSES="PASS WARN FAIL SKIP ERROR"
readonly _VALID_SEVERITIES="INFO LOW MEDIUM HIGH CRITICAL"
readonly _VALID_REPAIR_RISKS="NONE LOW MEDIUM HIGH CRITICAL"

# =============================================================================
# result_init — Inicializa todas las variables RESULT_* con valores por defecto
# Debe llamarse al inicio de cada diagnose.sh antes de asignar valores reales
# =============================================================================
result_init() {
  RESULT_MODULE_ID=""
  RESULT_MODULE_VERSION=""
  RESULT_TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  RESULT_HOSTNAME="$(hostname -s 2>/dev/null || echo 'unknown')"
  RESULT_STATUS="ERROR"
  RESULT_SEVERITY="HIGH"
  RESULT_TITLE="Diagnóstico no completado"
  RESULT_DESCRIPTION="El módulo no completó su ejecución correctamente."
  RESULT_EXPLANATION="N/A"
  RESULT_RISK="N/A"
  RESULT_SUGGESTED_ACTION="Revisar el log del módulo para más detalles."
  RESULT_REPAIRABLE="false"
  RESULT_REPAIR_RISK="NONE"
  RESULT_REPAIR_ID=""
  RESULT_EXECUTION_TIME_MS="0"
  RESULT_EXIT_CODE="0"
  RESULT_RAW_OUTPUT=""
  RESULT_RULE_TRIGGERED=""
  RESULT_EVIDENCE=""
}

# =============================================================================
# result_validate — Verifica que el resultado cumple el contrato IDiagnosticResult
# Retorna 0 si es válido, 1 si no lo es (con mensaje de error en stderr)
# =============================================================================
result_validate() {
  local errors=0

  # Campos obligatorios no vacíos
  for field in RESULT_MODULE_ID RESULT_MODULE_VERSION RESULT_TIMESTAMP \
               RESULT_HOSTNAME RESULT_STATUS RESULT_SEVERITY RESULT_TITLE \
               RESULT_DESCRIPTION RESULT_EXPLANATION RESULT_RISK \
               RESULT_SUGGESTED_ACTION; do
    local val
    eval "val=\${$field:-}"
    if [ -z "$val" ]; then
      echo "[result_validate] ERROR: campo obligatorio vacío: $field" >&2
      errors=$((errors + 1))
    fi
  done

  # Validar enum STATUS
  local status_ok=0
  for s in $_VALID_STATUSES; do
    [ "$RESULT_STATUS" = "$s" ] && status_ok=1 && break
  done
  if [ $status_ok -eq 0 ]; then
    echo "[result_validate] ERROR: RESULT_STATUS='${RESULT_STATUS}' no es válido. Válidos: ${_VALID_STATUSES}" >&2
    errors=$((errors + 1))
  fi

  # Validar enum SEVERITY
  local sev_ok=0
  for s in $_VALID_SEVERITIES; do
    [ "$RESULT_SEVERITY" = "$s" ] && sev_ok=1 && break
  done
  if [ $sev_ok -eq 0 ]; then
    echo "[result_validate] ERROR: RESULT_SEVERITY='${RESULT_SEVERITY}' no es válido. Válidos: ${_VALID_SEVERITIES}" >&2
    errors=$((errors + 1))
  fi

  # Invariante: si repairable=true, repair_id no puede estar vacío
  if [ "${RESULT_REPAIRABLE}" = "true" ] && [ -z "${RESULT_REPAIR_ID}" ]; then
    echo "[result_validate] ERROR: RESULT_REPAIRABLE=true pero RESULT_REPAIR_ID está vacío" >&2
    errors=$((errors + 1))
  fi

  # Invariante: EXECUTION_TIME_MS debe ser un entero
  if ! echo "$RESULT_EXECUTION_TIME_MS" | grep -qE '^[0-9]+$'; then
    echo "[result_validate] ERROR: RESULT_EXECUTION_TIME_MS='${RESULT_EXECUTION_TIME_MS}' no es un entero" >&2
    errors=$((errors + 1))
  fi

  return $errors
}

# =============================================================================
# result_serialize — Serializa el resultado actual en formato de línea delimitada
# Formato: campo1|||valor1|||campo2|||valor2...
# Usado por el aggregator para almacenar resultados en memoria
# =============================================================================
result_serialize() {
  printf '%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s|||%s\n' \
    "$RESULT_MODULE_ID" \
    "$RESULT_MODULE_VERSION" \
    "$RESULT_TIMESTAMP" \
    "$RESULT_HOSTNAME" \
    "$RESULT_STATUS" \
    "$RESULT_SEVERITY" \
    "$RESULT_TITLE" \
    "$RESULT_DESCRIPTION" \
    "$RESULT_EXPLANATION" \
    "$RESULT_RISK" \
    "$RESULT_SUGGESTED_ACTION" \
    "$RESULT_REPAIRABLE" \
    "$RESULT_REPAIR_RISK" \
    "$RESULT_REPAIR_ID" \
    "$RESULT_EXECUTION_TIME_MS" \
    "$RESULT_EXIT_CODE" \
    "$RESULT_RAW_OUTPUT" \
    "$RESULT_RULE_TRIGGERED" \
    "$RESULT_EVIDENCE"
}

# =============================================================================
# result_deserialize <línea_serializada> — Carga una línea serializada en variables RESULT_*
# =============================================================================
result_deserialize() {
  local line="$1"
  local IFS='|||'

  RESULT_MODULE_ID="$(        echo "$line" | cut -d'|' -f1)"
  RESULT_MODULE_VERSION="$(   echo "$line" | cut -d'|' -f4)"
  RESULT_TIMESTAMP="$(        echo "$line" | cut -d'|' -f7)"
  RESULT_HOSTNAME="$(         echo "$line" | cut -d'|' -f10)"
  RESULT_STATUS="$(           echo "$line" | cut -d'|' -f13)"
  RESULT_SEVERITY="$(         echo "$line" | cut -d'|' -f16)"
  RESULT_TITLE="$(            echo "$line" | cut -d'|' -f19)"
  RESULT_DESCRIPTION="$(      echo "$line" | cut -d'|' -f22)"
  RESULT_EXPLANATION="$(      echo "$line" | cut -d'|' -f25)"
  RESULT_RISK="$(             echo "$line" | cut -d'|' -f28)"
  RESULT_SUGGESTED_ACTION="$( echo "$line" | cut -d'|' -f31)"
  RESULT_REPAIRABLE="$(       echo "$line" | cut -d'|' -f34)"
  RESULT_REPAIR_RISK="$(      echo "$line" | cut -d'|' -f37)"
  RESULT_REPAIR_ID="$(        echo "$line" | cut -d'|' -f40)"
  RESULT_EXECUTION_TIME_MS="$(echo "$line" | cut -d'|' -f43)"
  RESULT_EXIT_CODE="$(        echo "$line" | cut -d'|' -f46)"
  RESULT_RAW_OUTPUT="$(       echo "$line" | cut -d'|' -f49)"
  RESULT_RULE_TRIGGERED="$(   echo "$line" | cut -d'|' -f52)"
  RESULT_EVIDENCE="$(         echo "$line" | cut -d'|' -f55)"
}

# =============================================================================
# result_time_start — Inicia el cronómetro de ejecución
# =============================================================================
result_time_start() {
  # macOS date no soporta %3N — usamos segundos como fallback estable
  _RESULT_TIME_START="$(date +%s 2>/dev/null || echo 0)"
}

# =============================================================================
# result_time_end — Calcula la duración y la asigna a RESULT_EXECUTION_TIME_MS
# Nota: en macOS la precisión es de segundos (no milisegundos).
# El campo se expresa en ms por compatibilidad con el contrato IDiagnosticResult.
# =============================================================================
result_time_end() {
  local end
  end="$(date +%s 2>/dev/null || echo 0)"
  local diff=$(( end - ${_RESULT_TIME_START:-0} ))
  # Convertir segundos a ms para cumplir el contrato
  [ "$diff" -lt 0 ] 2>/dev/null && diff=0
  RESULT_EXECUTION_TIME_MS=$(( diff * 1000 ))
}
