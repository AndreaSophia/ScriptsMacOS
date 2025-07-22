#!/bin/bash
LOG="/var/log/audio_watchdog.log"
echo "[$(date)] 🔍 Iniciando verificación de audio..." >> "$LOG"

sleep 10

get_audio_count() {
    system_profiler SPAudioDataType | grep "Output Device:" | wc -l
}

AUDIO_COUNT=$(get_audio_count)

if [ "$AUDIO_COUNT" -eq 0 ]; then
    echo "[$(date)] ⚠️ No se detectaron dispositivos de salida. Reiniciando coreaudiod." >> "$LOG"
    killall coreaudiod
    launchctl kickstart -k system/com.apple.audio.coreaudiod
    sleep 5
    AUDIO_COUNT=$(get_audio_count)
    if [ "$AUDIO_COUNT" -eq 0 ]; then
