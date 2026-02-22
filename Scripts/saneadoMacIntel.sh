#!/bin/zsh
# mac_saneador_diagnostico.sh
# Diagnóstico + saneamiento básico para macOS (Intel/Apple Silicon)
# Seguro para uso personal/corporativo (no toca agentes ni servicios críticos)

set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
OUT_DIR="$HOME/Scripts/out/saneador_${TS}"
REPORT_TXT="$OUT_DIR/reporte.txt"
REPORT_JSON="$OUT_DIR/reporte.json"

mkdir -p "$OUT_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$REPORT_TXT"
}

section() {
  printf '\n===== %s =====\n' "$*" | tee -a "$REPORT_TXT"
}

cmd_out() {
  local title="$1"
  shift
  section "$title"
  {
    echo "\$ $*"
    "$@"
  } >> "$REPORT_TXT" 2>&1 || true
}

human_kb() {
  # Convierte KB a GB aprox
  local kb="${1:-0}"
  awk -v kb="$kb" 'BEGIN { printf "%.2f", kb/1024/1024 }'
}

# ---------- Inicio ----------
: > "$REPORT_TXT"
log "Inicio saneador/diagnóstico macOS"
log "Host: $HOST"
log "Salida: $OUT_DIR"

# ---------- Identidad ----------
section "IDENTIDAD DEL EQUIPO"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo "N/A")"
OS_BUILD="$(sw_vers -buildVersion 2>/dev/null || echo "N/A")"
MODEL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}')"
MODEL_ID="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/{print $2; exit}')"
CHIP="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip|Processor Name/{print $2; exit}')"
SERIAL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2; exit}')"
MEMORY="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Memory/{print $2; exit}')"
LOGGED_USER="$(stat -f%Su /dev/console 2>/dev/null || whoami)"

{
  echo "Hostname: $HOST"
  echo "Usuario logueado: $LOGGED_USER"
  echo "macOS: $OS_VER ($OS_BUILD)"
  echo "Modelo: $MODEL"
  echo "Model Identifier: $MODEL_ID"
  echo "Chip/CPU: $CHIP"
  echo "RAM: $MEMORY"
  echo "Serial: $SERIAL"
} | tee -a "$REPORT_TXT"

# ---------- Disco ----------
section "DISCO Y ESPACIO"
DF_LINE="$(df -Pk / | tail -1)"
DISK_TOTAL_KB="$(echo "$DF_LINE" | awk '{print $2}')"
DISK_USED_KB="$(echo "$DF_LINE" | awk '{print $3}')"
DISK_FREE_KB="$(echo "$DF_LINE" | awk '{print $4}')"
DISK_USE_PCT="$(echo "$DF_LINE" | awk '{print $5}' | tr -d '%')"

DISK_TOTAL_GB="$(human_kb "$DISK_TOTAL_KB")"
DISK_USED_GB="$(human_kb "$DISK_USED_KB")"
DISK_FREE_GB="$(human_kb "$DISK_FREE_KB")"

{
  echo "Total: ${DISK_TOTAL_GB} GB"
  echo "Usado: ${DISK_USED_GB} GB"
  echo "Libre: ${DISK_FREE_GB} GB"
  echo "Uso: ${DISK_USE_PCT}%"
} | tee -a "$REPORT_TXT"

cmd_out "DISKUTIL INFO /" diskutil info /

# ---------- Memoria ----------
section "MEMORIA"
cmd_out "VM_STAT" vm_stat
cmd_out "TOP MEMORIA (snapshot)" top -l 1 -o rsize -n 15

# ---------- CPU ----------
section "CPU"
cmd_out "TOP CPU (snapshot)" top -l 1 -o cpu -n 20

# ---------- Procesos pesados conocidos ----------
section "PROCESOS CLAVE (si existen)"
{
  ps aux | egrep -i 'mdm|intune|company portal|workspace|hub|omnissa|crowdstrike|falcon|qualys|cisco|umbrella|globalprotect|paloalto|onedrive|dropbox|google drive|teams|zoom|slack|chrome|mds|mdworker' | grep -v egrep || true
} >> "$REPORT_TXT"

# ---------- Launch agents/daemons no Apple ----------
section "LAUNCH ITEMS NO-APPLE (referencia)"
{
  echo "--- launchctl list | no com.apple ---"
  launchctl list 2>/dev/null | grep -v com.apple || true
  echo
  echo "--- /Library/LaunchAgents ---"
  ls -lah /Library/LaunchAgents 2>/dev/null || true
  echo
  echo "--- /Library/LaunchDaemons ---"
  ls -lah /Library/LaunchDaemons 2>/dev/null || true
} >> "$REPORT_TXT"

# ---------- Login Items (best effort) ----------
section "LOGIN ITEMS (AppleScript best effort)"
osascript -e 'tell application "System Events" to get the name of every login item' >> "$REPORT_TXT" 2>/dev/null || echo "No se pudieron listar login items por AppleScript (permiso/versión)." >> "$REPORT_TXT"

# ---------- Red y DNS ----------
cmd_out "RED: networksetup -listallhardwareports" networksetup -listallhardwareports
cmd_out "DNS: scutil --dns" scutil --dns
cmd_out "RUTAS: netstat -rn" netstat -rn

# ---------- MDM / perfiles (si aplica) ----------
section "MDM / PERFILES"
{
  profiles status -type enrollment 2>&1 || true
  echo
  profiles list 2>&1 || true
} >> "$REPORT_TXT"

# ---------- Salud disco (SMART si aplica) ----------
section "SMART / SALUD DE DISCO"
{
  diskutil info disk0 2>/dev/null | grep -Ei 'SMART|Device / Media Name|Solid State|Protocol|Internal' || true
} >> "$REPORT_TXT"

# ---------- Archivos grandes del usuario ----------
section "ARCHIVOS GRANDES EN HOME (>500MB)"
{
  find "$HOME" -xdev -type f -size +500M 2>/dev/null | head -n 100
} >> "$REPORT_TXT"

# ---------- Directorios más pesados del usuario ----------
section "DIRECTORIOS MÁS PESADOS EN HOME (top 30)"
{
  du -xhd 1 "$HOME" 2>/dev/null | sort -hr | head -n 30
} >> "$REPORT_TXT"

# ---------- SANEAMIENTO BÁSICO (seguro) ----------
section "SANEAMIENTO BÁSICO"
FREED_NOTES=()

# 1) Papelera del usuario (seguro)
TRASH_PATH="$HOME/.Trash"
if [[ -d "$TRASH_PATH" ]]; then
  TRASH_SIZE_BEFORE="$(du -sk "$TRASH_PATH" 2>/dev/null | awk '{print $1}')"
  if [[ "${TRASH_SIZE_BEFORE:-0}" -gt 0 ]]; then
    rm -rf "$TRASH_PATH"/* "$TRASH_PATH"/.[!.]* "$TRASH_PATH"/..?* 2>/dev/null || true
    TRASH_SIZE_AFTER="$(du -sk "$TRASH_PATH" 2>/dev/null | awk '{print $1}')"
    FREED_KB=$(( ${TRASH_SIZE_BEFORE:-0} - ${TRASH_SIZE_AFTER:-0} ))
    FREED_GB="$(human_kb "$FREED_KB")"
    FREED_NOTES+=("Papelera vaciada: ~${FREED_GB} GB liberados")
    echo "✔ Papelera vaciada (~${FREED_GB} GB)" | tee -a "$REPORT_TXT"
  else
    echo "• Papelera ya estaba vacía" | tee -a "$REPORT_TXT"
  fi
fi

# 2) Logs de usuario antiguos (conservador)
USER_LOGS="$HOME/Library/Logs"
if [[ -d "$USER_LOGS" ]]; then
  LOGS_BEFORE="$(du -sk "$USER_LOGS" 2>/dev/null | awk '{print $1}')"
  # Borra logs > 14 días solo del usuario
  find "$USER_LOGS" -type f -mtime +14 -delete 2>/dev/null || true
  LOGS_AFTER="$(du -sk "$USER_LOGS" 2>/dev/null | awk '{print $1}')"
  FREED_KB=$(( ${LOGS_BEFORE:-0} - ${LOGS_AFTER:-0} ))
  if [[ "$FREED_KB" -gt 0 ]]; then
    FREED_GB="$(human_kb "$FREED_KB")"
    FREED_NOTES+=("Logs de usuario (>14 días): ~${FREED_GB} GB liberados")
    echo "✔ Logs de usuario antiguos limpiados (~${FREED_GB} GB)" | tee -a "$REPORT_TXT"
  else
    echo "• Logs de usuario: sin cambios relevantes" | tee -a "$REPORT_TXT"
  fi
fi

# 3) Cachés de usuario (solo listar grandes, NO borrar automático)
CACHE_DIR="$HOME/Library/Caches"
if [[ -d "$CACHE_DIR" ]]; then
  echo "• Cachés de usuario detectadas (NO se borran automático por seguridad)." | tee -a "$REPORT_TXT"
  echo "  Top caches grandes:" | tee -a "$REPORT_TXT"
  du -xhd 1 "$CACHE_DIR" 2>/dev/null | sort -hr | head -n 15 >> "$REPORT_TXT" || true
fi

# ---------- Revisión post saneamiento ----------
section "ESPACIO POST-SANEAMIENTO"
DF_LINE2="$(df -Pk / | tail -1)"
DISK_USED_KB2="$(echo "$DF_LINE2" | awk '{print $3}')"
DISK_FREE_KB2="$(echo "$DF_LINE2" | awk '{print $4}')"
DISK_USE_PCT2="$(echo "$DF_LINE2" | awk '{print $5}' | tr -d '%')"

DISK_FREE_GB2="$(human_kb "$DISK_FREE_KB2")"
{
  echo "Libre ahora: ${DISK_FREE_GB2} GB"
  echo "Uso ahora: ${DISK_USE_PCT2}%"
} | tee -a "$REPORT_TXT"

# ---------- Recomendaciones automáticas ----------
section "RECOMENDACIONES AUTOMÁTICAS"

RECS=()

if [[ "$DISK_USE_PCT2" -ge 90 ]]; then
  RECS+=("CRÍTICO: Disco sobre 90%. Libera espacio (ideal: dejar >20% libre).")
elif [[ "$DISK_USE_PCT2" -ge 85 ]]; then
  RECS+=("ALTO: Disco sobre 85%. El rendimiento puede degradarse.")
else
  RECS+=("Disco OK: uso bajo 85%.")
fi

# Presión de memoria (heurística simple con vm_stat)
PAGE_SIZE="$(vm_stat | head -1 | awk '{gsub(/\./,"",$8); print $8}')"
[[ -z "${PAGE_SIZE:-}" ]] && PAGE_SIZE=4096
PAGES_FREE="$(vm_stat | awk '/Pages free/ {gsub("\\.","",$3); print $3}')"
PAGES_SPEC="$(vm_stat | awk '/Pages speculative/ {gsub("\\.","",$3); print $3}')"
FREE_BYTES=$(( (${PAGES_FREE:-0} + ${PAGES_SPEC:-0}) * PAGE_SIZE ))
FREE_MB=$(( FREE_BYTES / 1024 / 1024 ))

if [[ "$FREE_MB" -lt 500 ]]; then
  RECS+=("RAM presionada: memoria libre muy baja (~${FREE_MB} MB). Cierra apps pesadas (Chrome/Teams/Zoom) y revisa agentes.")
else
  RECS+=("Memoria razonable en snapshot (~${FREE_MB} MB libres).")
fi

# Spotlight indexando (puede ser temporal)
if ps aux | grep -E '[m]ds|[m]dworker' >/dev/null 2>&1; then
  RECS+=("Spotlight indexando (mds/mdworker) detectado. Puede ralentizar temporalmente.")
fi

# Procesos pesados comunes
if ps aux | grep -i '[c]hrome' >/dev/null 2>&1; then
  RECS+=("Chrome activo: revisa pestañas/extensiones si notas lentitud.")
fi
if ps aux | grep -i '[t]eams' >/dev/null 2>&1; then
  RECS+=("Teams activo: en Intel suele consumir bastante RAM/CPU.")
fi

for r in "${RECS[@]}"; do
  echo "- $r" | tee -a "$REPORT_TXT"
done

# ---------- JSON resumen ----------
section "JSON RESUMEN"
cat > "$REPORT_JSON" <<JSON
{
  "timestamp": "$TS",
  "hostname": "$HOST",
  "user": "$LOGGED_USER",
  "macos_version": "$OS_VER",
  "macos_build": "$OS_BUILD",
  "model": "$MODEL",
  "model_identifier": "$MODEL_ID",
  "chip_or_cpu": "$CHIP",
  "memory": "$MEMORY",
  "serial": "$SERIAL",
  "disk": {
    "total_gb": "$DISK_TOTAL_GB",
    "used_gb_before": "$DISK_USED_GB",
    "free_gb_before": "$DISK_FREE_GB",
    "use_percent_before": "$DISK_USE_PCT",
    "free_gb_after": "$DISK_FREE_GB2",
    "use_percent_after": "$DISK_USE_PCT2"
  },
  "recommendations_count": "${#RECS[@]}"
}
JSON

echo "Reporte JSON: $REPORT_JSON" | tee -a "$REPORT_TXT"
echo "Reporte TXT:  $REPORT_TXT" | tee -a "$REPORT_TXT"

# ---------- Fin ----------
log "Finalizado"
echo
echo "✅ Listo. Revisa:"
echo "   $REPORT_TXT"
echo "   $REPORT_JSON"
echo
echo "Tip: si quieres, el siguiente paso es una versión 'fase 2' que proponga acciones específicas según el reporte (sin tocar agentes corporativos críticos)."