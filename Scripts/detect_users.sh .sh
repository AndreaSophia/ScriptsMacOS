#!/bin/bash
# detect_users_intune.sh
# Inventario de usuarios "humanos" en macOS y clasificación LOCAL vs DOMINIO_AD
# Output en 1 línea JSON para recolección desde Intune (exportable a Excel)
# Compatible con bash 3.2 (macOS nativo)

set -euo pipefail

# ---- Configuración ----
EXCLUDE_USERS_REGEX='^(admincmdb|lcladmin|compartido|shared|administrator|root|daemon|nobody|_.*)$'
MIN_UID=501

# ---- Datos del equipo ----
HOSTNAME="$(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname)"
SERIAL="$(/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | /usr/bin/awk -F': ' '/Serial Number/{print $2; exit}')"
[[ -n "${SERIAL:-}" ]] || SERIAL="UNKNOWN"

# ---- Detección REAL de AD binding ----
AD_BOUND="NO"
AD_DOMAIN=""

AD_INFO="$(/usr/sbin/dsconfigad -show 2>/dev/null || true)"
AD_DOMAIN="$(echo "$AD_INFO" | /usr/bin/awk -F': ' '/Active Directory Domain/{print $2; exit}')"

if [[ -n "${AD_DOMAIN:-}" ]]; then
  AD_BOUND="YES"
fi

# ---- Clasificación de usuario (conservadora) ----
classify_user() {
  local u="$1"
  local original_node
  original_node="$(/usr/bin/dscl . -read "/Users/$u" OriginalNodeName 2>/dev/null | /usr/bin/sed 's/^OriginalNodeName: //' || true)"

  if echo "$original_node" | /usr/bin/grep -qi "Active Directory"; then
    echo "DOMINIO_AD"
  else
    echo "LOCAL"
  fi
}

# ---- Obtener usuarios "humanos" ----
USERS=()

while IFS= read -r u; do
  [[ -n "$u" ]] || continue

  if echo "$u" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/egrep -q "$EXCLUDE_USERS_REGEX"; then
    continue
  fi

  home="$(/usr/bin/dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}' || true)"
  [[ -n "${home:-}" ]] || continue
  [[ "$home" == /Users/* ]] || continue
  [[ -d "$home" ]] || continue

  USERS+=("$u")
done < <(
  /usr/bin/dscl . -list /Users UniqueID 2>/dev/null \
  | /usr/bin/awk -v min_uid="$MIN_UID" '$2 >= min_uid {print $1}' \
  | /usr/bin/sort -u
)

# ---- Construir JSON (una sola línea) ----
USERS_JSON="[]"
if [[ "${#USERS[@]}" -gt 0 ]]; then
  tmp=""
  for u in "${USERS[@]}"; do
    t="$(classify_user "$u")"
    u_escaped="$(echo "$u" | /usr/bin/sed 's/"/\\"/g')"
    t_escaped="$(echo "$t" | /usr/bin/sed 's/"/\\"/g')"

    [[ -n "$tmp" ]] && tmp="${tmp},"
    tmp="${tmp}{\"name\":\"${u_escaped}\",\"type\":\"${t_escaped}\"}"
  done
  USERS_JSON="[${tmp}]"
fi

# ---- Output para Intune (stdout capturable/exportable) ----
echo "{\"hostname\":\"$HOSTNAME\",\"serial\":\"$SERIAL\",\"ad_bound\":\"$AD_BOUND\",\"ad_domain\":\"${AD_DOMAIN:-}\",\"users\":$USERS_JSON}"
exit 0
