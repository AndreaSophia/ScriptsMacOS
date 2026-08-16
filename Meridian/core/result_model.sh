#!/bin/bash
# =============================================================================
# Meridian — core/result_model.sh
# Modelo central DiagnosticResult.
# Compatible con Bash 3.2/macOS sin dependencias GNU.
# =============================================================================

readonly _VALID_STATUSES="PASS WARN FAIL SKIP ERROR"
readonly _VALID_SEVERITIES="INFO LOW MEDIUM HIGH CRITICAL"
readonly _VALID_REPAIR_RISKS="NONE LOW MEDIUM HIGH CRITICAL"
readonly _RESULT_V2_FIELDS=19

# DiagnosticResult es una frontera canónica que puede ejecutarse dentro de un
# proceso privilegiado. Las utilidades auxiliares no se resuelven mediante un
# PATH heredado/controlable por el caller.
_RESULT_DATE="/bin/date"
_RESULT_HOSTNAME="/bin/hostname"
_RESULT_GREP="/usr/bin/grep"
_RESULT_CUT="/usr/bin/cut"
_RESULT_AWK="/usr/bin/awk"

_result_require_system_tools() {
  local tool
  for tool in "$_RESULT_DATE" "$_RESULT_HOSTNAME" "$_RESULT_GREP" "$_RESULT_CUT" "$_RESULT_AWK"; do
    [ -x "$tool" ] || {
      printf '%s\n' "[result_model] ERROR: utilidad requerida no disponible: $tool" >&2
      return 1
    }
  done
  return 0
}

result_init() {
  RESULT_MODULE_ID=""
  RESULT_MODULE_VERSION=""
  RESULT_TIMESTAMP="$("$_RESULT_DATE" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s\n' '1970-01-01T00:00:00Z')"
  RESULT_HOSTNAME="$("$_RESULT_HOSTNAME" -s 2>/dev/null || printf '%s\n' 'unknown')"
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

  _result_require_system_tools || return 1

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

  printf '%s\n' "$RESULT_MODULE_ID" | "$_RESULT_GREP" -qE '^[a-z][a-z0-9_]*$' || {
    echo "[result_validate] ERROR: module_id inválido: ${RESULT_MODULE_ID}" >&2
    errors=$((errors + 1))
  }

  printf '%s\n' "$RESULT_MODULE_VERSION" | "$_RESULT_GREP" -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "[result_validate] ERROR: module_version debe ser semver X.Y.Z: ${RESULT_MODULE_VERSION}" >&2
    errors=$((errors + 1))
  }

  printf '%s\n' "$RESULT_TIMESTAMP" | "$_RESULT_GREP" -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || {
    echo "[result_validate] ERROR: timestamp no cumple ISO8601 UTC: ${RESULT_TIMESTAMP}" >&2
    errors=$((errors + 1))
  }

  if [ "${#RESULT_TITLE}" -gt 80 ]; then
    echo "[result_validate] ERROR: title excede 80 caracteres" >&2
    errors=$((errors + 1))
  fi

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

  if [ "$RESULT_STATUS" = "PASS" ]; then
    case "$RESULT_SEVERITY" in
      INFO|LOW) ;;
      *)
        echo "[result_validate] ERROR: PASS requiere severity INFO|LOW (actual: ${RESULT_SEVERITY})" >&2
        errors=$((errors + 1))
        ;;
    esac
  fi

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

  if [ "$RESULT_REPAIRABLE" = "true" ]; then
    if [ -z "$RESULT_REPAIR_ID" ]; then
      echo "[result_validate] ERROR: repairable=true sin repair_id" >&2
      errors=$((errors + 1))
    elif ! printf '%s\n' "$RESULT_REPAIR_ID" | "$_RESULT_GREP" -qE '^[a-z][a-z0-9_]*$'; then
      echo "[result_validate] ERROR: repair_id inválido: ${RESULT_REPAIR_ID}" >&2
      errors=$((errors + 1))
    fi
    if [ "$RESULT_REPAIR_RISK" = "NONE" ]; then
      echo "[result_validate] ERROR: repairable=true requiere repair_risk distinto de NONE" >&2
      errors=$((errors + 1))
    fi
  elif [ "$RESULT_REPAIRABLE" = "false" ]; then
    if [ "$RESULT_REPAIR_RISK" != "NONE" ]; then
      echo "[result_validate] ERROR: repairable=false requiere repair_risk=NONE" >&2
      errors=$((errors + 1))
    fi
    if [ -n "$RESULT_REPAIR_ID" ]; then
      echo "[result_validate] ERROR: repairable=false requiere repair_id vacío" >&2
      errors=$((errors + 1))
    fi
  fi

  echo "$RESULT_EXECUTION_TIME_MS" | "$_RESULT_GREP" -qE '^[0-9]+$' || {
    echo "[result_validate] ERROR: execution_time_ms no entero" >&2
    errors=$((errors + 1))
  }
  echo "$RESULT_EXIT_CODE" | "$_RESULT_GREP" -qE '^-?[0-9]+$' || {
    echo "[result_validate] ERROR: exit_code no entero" >&2
    errors=$((errors + 1))
  }

  [ "$errors" -eq 0 ]
}

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
  raw="$(printf '%s\n' "$line" | "$_RESULT_CUT" -d'|' -f"$field")"
  _result_decode "$raw"
}

# Valida el framing antes de mutar RESULT_*. Dado que todo pipe de contenido
# se codifica como %7C, un registro v2 válido tiene exactamente 19 campos.
# Rechazar campos extra evita truncar silenciosamente payloads corruptos.
_result_v2_frame_valid() {
  local line="$1" count
  [ -n "$line" ] || return 1
  _result_require_system_tools || return 1
  count="$(printf '%s\n' "$line" | "$_RESULT_AWK" -F'|' '{print NF}')"
  [ "$count" -eq "$_RESULT_V2_FIELDS" ] 2>/dev/null
}

result_deserialize() {
  local line="$1"
  if ! _result_v2_frame_valid "$line"; then
    echo "[result_deserialize] ERROR: framing DiagnosticResult v2 inválido" >&2
    return 1
  fi

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
  return 0
}

result_time_start() {
  _RESULT_TIME_START="$("$_RESULT_DATE" +%s 2>/dev/null || printf '%s\n' 0)"
}

result_time_end() {
  local end diff
  end="$("$_RESULT_DATE" +%s 2>/dev/null || printf '%s\n' 0)"
  diff=$(( end - ${_RESULT_TIME_START:-0} ))
  [ "$diff" -lt 0 ] 2>/dev/null && diff=0
  RESULT_EXECUTION_TIME_MS=$(( diff * 1000 ))
}
