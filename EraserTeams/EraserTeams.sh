#!/bin/bash

# 💻 Purga Divina de Microsoft Teams
# ✨ Por Safiye, ejecutado con honor por Mike – técnico confiable, valiente, y obediente al guion.

clear
echo "💼 Operación: ELIMINAR TEAMS"
echo "🛠️ Ejecutado por Mike, quien lleva café en una mano y fe en la otra."
echo "==============================================================="
echo "🎧 Objetivo: Quitar Teams, su sombra, sus rastros y ese driver de sonido que arruina todo."
echo "==============================================================="
sleep 2

# 🧘 Cerrar Teams
echo "📴 Cerrando Teams como un profesional de IT... sin juicio, solo pkill."
pkill -f "Microsoft Teams" >/dev/null 2>&1
sleep 1

# 🗑️ Borrar apps
echo "🧹 Eliminando la app principal de /Applications..."
sudo rm -rf /Applications/Microsoft\ Teams.app
echo "🧹 Eliminando la app local de ~/Applications..."
rm -rf ~/Applications/Microsoft\ Teams.app

# 🔍 Borrar datos de usuario
echo "🧼 Purificando el perfil de usuario..."
rm -rf ~/Library/Application\ Support/Microsoft/Teams
rm -rf ~/Library/Caches/com.microsoft.teams
rm -rf ~/Library/Logs/Microsoft\ Teams
rm -rf ~/Library/Preferences/com.microsoft.teams.plist
rm -rf ~/Library/Cookies/com.microsoft.teams.binarycookies
rm -rf ~/Library/Saved\ Application\ State/com.microsoft.teams.savedState
rm -f ~/Library/LaunchAgents/com.microsoft.teams.*

# 🎧 Eliminar driver de sonido
echo "🔇 Eliminando el TeamsAudioDevice.driver con respeto, pero sin pena."
sudo rm -rf /Library/Audio/Plug-Ins/HAL/TeamsAudioDevice.driver

# 📝 Log
LOG="/var/log/teams_purge_by_mike.log"
echo "$(date) - Mike purgó Teams y su espíritu auditivo. El sistema está limpio." | sudo tee -a "$LOG"

# 🧠 Recordatorio con estilo
echo ""
echo "✅ Teams eliminado. El sistema ha sido bendecido por el poder de Bash y del sudo."
echo "⚠️ Por directiva de Safiye, este equipo será reiniciado ahora mismo."

sleep 5
echo "🔁 Reiniciando en 10 segundos. Respira hondo, Mike..."
sleep 10

sudo shutdown -r now
