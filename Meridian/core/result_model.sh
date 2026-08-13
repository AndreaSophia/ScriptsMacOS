#!/bin/bash
# =============================================================================
# Meridian — core/result_model.sh
# Modelo central DiagnosticResult.
# Compatible con Bash 3.2/macOS sin dependencias GNU.
# =============================================================================

readonly _VALID_STATUSES="PASS WARN FAIL SKIP ERROR"
readonly _VALID_SEVERITIES="INFO LOW MEDIUM HIGH CRITICAL"
readonly _VALID_REPAIR_RISKS="NONE LOW MEDIUM HIGH CRITICAL"

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

result_validate() {
  local errors=0 field val s status_ok sev_ok risk_ok

  for field in RESULT_MODULE_ID RESULT_MODULE_VERSION RESULT_TIMESTAMP \
               RESULT_HOSTNAME RESULT_STATUS RESULT_SEVERITY RESULT_TITLE \
               RESULT_DESCRIPTION RESULT_EXPLANATION RESULT_RISK \
               RESULT_SUGGESTED_ACTION; do
    eval "val=\${$field:-}"
    if [ -z "$val" ]; then
      echo "[result_validate] ERROR: campo obligatorio vacío: $field" >&2
      errors=$((errors + 1))
    fi
  done

  status_ok=0
  for s in $_VALID_STATUSES; do
    [ "$RESULT_STATUS" = "$s" ] && status_ok=1 && break
  done
  [ "$status_ok" -eq 1 ] || {
    echo "[result_validate] ERROR: STATUS inválido: ${RESULT_STATUS}" >&2
    errors=$((errors + 1))
  }

  sev_ok=0
  for s in $_VALID_SEVERITIES; do
    [ "$RESULT_SEVERITY" = "$s" ] && sev_ok=1 && break
  done
  [ "$sev_ok" -eq 1 ] || {
    echo "[result_validate] ERROR: SEVERITY inválida: ${RESULT_SEVERITY}" >&2
    errors=$((errors + 1))
  }

  risk_ok=0
  for s in $_VALID_REPAIR_RISKS; do
    [ "$RESULT_REPAIR_RISK" = "$s" ] && risk_ok=1 && break
  done
  [ "$risk_ok" -eq 1 ] || {
    echo "[result_validate] ERROR: REPAIR_RISK inválido: ${RESULT_REPAIR_RISK}" >&2
    errors=$((errors + 1))
  }

  case "$RESULT_REPAIRABLE" in true|false) ;; *)
    echo "[result_validate] ERROR: REPAIRABLE debe ser true|false" >&2
    errors=$((errors + 1));;
  esac

  if [ "$RESULT_REPAIRABLE" = "true" ] && [ -z "$RESULT_REPAIR_ID" ]; then
    echo "[result_validate] ERROR: repairable=true sin repair_id" >&2
    errors=$((errors + 1))
  fi

  echo "$RESULT_EXECUTION_TIME_MS" | grep -qE '^[0-9]+$' || {
    echo "[result_validate] ERROR: execution_time_ms no entero" >&2
    errors=$((errors + 1))
  }
  echo "$RESULT_EXIT_CODE" | grep -qE '^-?[0-9]+$' || {
    echo "[result_validate] ERROR: exit_code no entero" >&2
    errors=$((errors + 1))
  }

  [ "$errors" -eq 0 ]
}

# Escape reversible para transportar texto arbitrario en una sola línea.
# Se escapa % primero para evitar colisiones, luego CR/LF y |.
_result_encode() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  s="${s//|/%7C}"
  printf '%s' "$s"
}

_result_decode() {
  local s="$1"
  s="${s//%7C/|}"
  s="${s//%0A/$'\n'}"
  s="${s//%0D/$'\r'}"
  s="${s//%25/%}"
  printf '%s' "$s"
}

# Formato interno v2: 19 campos separados por un único |.
# Como cada | de contenido se codifica como %7C, el split es determinista.
result_serialize() {
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$(_result_encode "$RESULT_MODULE_ID")" \
    "$(_result_encode "$RESULT_MODULE_VERSION")" \
    "$(_result_encode "$RESULT_TIMESTAMP")" \
    "$(_result_encode "$RESULT_HOSTNAME")" \
    "$(_result_encode "$RESULT_STATUS")" \
    "$(_result_encode "$RESULT_SEVERITY")" \
    "$(_result_encode "$RESULT_TITLE")" \
    "$(_result_encode "$RESULT_DESCRIPTION")" \
    "$(_result_encode "$RESULT_EXPLANATION")" \
    "$(_result_encode "$RESULT_RISK")" \
    "$(_result_encode "$RESULT_SUGGESTED_ACTION")" \
    "$(_result_encode "$RESULT_REPAIRABLE")" \
    "$(_result_encode "$RESULT_REPAIR_RISK")" \
    "$(_result_encode "$RESULT_REPAIR_ID")" \
    "$(_result_encode "$RESULT_EXECUTION_TIME_MS")" \
    "$(_result_encode "$RESULT_EXIT_CODE")" \
    "$(_result_encode "$RESULT_RAW_OUTPUT")" \
    "$(_result_encode "$RESULT_RULE_TRIGGERED")" \
    "$(_result_encode "$RESULT_EVIDENCE")"
}

_result_field() {
  local line="$1" field="$2" raw
  raw="$(printf '%s\n' "$line" | cut -d'|' -f"$field")"
  _result_decode "$raw"
}

result_deserialize() {
  local line="$1"
  RESULT_MODULE_ID="$(_result_field "$line" 1)"
  RESULT_MODULE_VERSION="$(_result_field "$line" 2)"
  RESULT_TIMESTAMP="$(_result_field "$line" 3)"
  RESULT_HOSTNAME="$(_result_field "$line" 4)"
  RESULT_STATUS="$(_result_field "$line" 5)"
  RESULT_SEVERITY="$(_result_field "$line" 6)"
  RESULT_TITLE="$(_result_field "$line" 7)"
  RESULT_DESCRIPTION="$(_result_field "$line" 8)"
  RESULT_EXPLANATION="$(_result_field "$line" 9)"
  RESULT_RISK="$(_result_field "$line" 10)"
  RESULT_SUGGESTED_ACTION="$(_result_field "$line" 11)"
  RESULT_REPAIRABLE="$(_result_field "$line" 12)"
  RESULT_REPAIR_RISK="$(_result_field "$line" 13)"
  RESULT_REPAIR_ID="$(_result_field "$line" 14)"
  RESULT_EXECUTION_TIME_MS="$(_result_field "$line" 15)"
  RESULT_EXIT_CODE="$(_result_field "$line" 16)"
  RESULT_RAW_OUTPUT="$(_result_field "$line" 17)"
  RESULT_RULE_TRIGGERED="$(_result_field "$line" 18)"
  RESULT_EVIDENCE="$(_result_field "$line" 19)"
}

result_time_start() {
  _RESULT_TIME_START="$(date +%s 2>/dev/null || echo 0)"
}

result_time_end() {
  local end diff
  end="$(date +%s 2>/dev/null || echo 0)"
  diff=$(( end - ${_RESULT_TIME_START:-0} ))
  [ "$diff" -lt 0 ] 2>/dev/null && diff=0
  RESULT_EXECUTION_TIME_MS=$(( diff * 1000 ))
}
