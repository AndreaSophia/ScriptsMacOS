#!/bin/zsh
set -euo pipefail

echo "=== FASE 2 - AJUSTE RENDIMIENTO DIARIO ==="
echo "Fecha: $(date)"
echo

echo "[1] Snapshot de memoria"
vm_stat | egrep "Pages free|Pages active|Pages inactive|Pages occupied by compressor|Swapouts" || true
echo

echo "[2] Top RAM"
top -l 1 -o rsize -n 12 | head -n 25
echo

echo "[3] Procesos Spotlight"
ps aux | egrep 'mds|mdworker|mdbulkimport' | grep -v grep || echo "Sin indexación activa"
echo

echo "[4] Cerrar apps visuales opcionales (si están abiertas)"
for app in "Dynamic Wallpaper" "App Store"; do
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
done
echo "✔ Apps opcionales cerradas"
echo

echo "[5] Recordatorio"
echo "- Quita Dynamic Wallpaper del inicio de sesión"
echo "- Decide si Warp y SoundSource realmente van al inicio"
echo "- Si Spotlight está indexando, espera o pausa temporalmente con: sudo mdutil -i off /"
echo "- Reanuda luego con: sudo mdutil -i on /"