#!/bin/bash

# 🪄 El Exorcista de MDM: por Safiye

clear
echo "🧹💀 Iniciando el EXORCISMO DIGITAL 💀🧹"
echo "------------------------------------------------------------"
echo "⚠️ Este script eliminará TODO rastro de MDM conocido por la humanidad..."
echo "⚙️ Verificará Secure Tokens y reiniciará el alma del Mac."
echo "🧠 Técnico: mantén la calma y respira, estás a salvo."
echo "------------------------------------------------------------"
sleep 3

# Función para mostrar mensajes divertidos
function say {
  echo -e "\n🧙 $1"
  sleep 2
}

say "Invocando a los demonios ocultos en el sistema…"

# Eliminar perfiles MDM
PROFILES=$(profiles -P | grep "attribute: name:" | awk -F ": " '{print $2}')

if [[ -n "$PROFILES" ]]; then
    for profile in $PROFILES; do
        say "⚔️ Exorcizando perfil: $profile"
        profiles -R -p "$profile" 2>/dev/null
    done
else
    say "😇 No se encontraron perfiles... El demonio ya había huido."
fi

# Eliminar directorios y rastros
say "🔥 Eliminando rastros digitales oscuros…"
rm -rf /var/db/ConfigurationProfiles/*
rm -rf /Library/Managed\ Preferences/*
rm -rf /Library/Application\ Support/Microsoft/Intune*
rm -rf /Library/Intune*
rm -rf /Library/Preferences/com.microsoft.*
rm -rf /Library/LaunchDaemons/com.microsoft.*
rm -rf /private/var/db/MDMEnrollment
rm -rf /private/var/db/lockdown/*

say "🧼 Mac purificado. Procediendo a verificar los Secure Tokens..."

# Verificar Secure Token del usuario actual
CURRENT_USER=$(stat -f "%Su" /dev/console)

TOKEN_STATUS=$(sysadminctl -secureTokenStatus "$CURRENT_USER" 2>&1)
echo "$TOKEN_STATUS"

if echo "$TOKEN_STATUS" | grep -q "ENABLED"; then
    say "🛡️ El usuario $CURRENT_USER ya tiene Secure Token activo. No hay nada que hacer."
else
    say "🩹 Reparando Secure Token (si el admin local está presente)..."

    # Asumimos que LCLADMIN tiene token
    admin_user="LCLADMIN"
    admin_pass="IntroduceAquíLaContraseñaSegura"

    sysadminctl -adminUser "$admin_user" -adminPassword "$admin_pass" \
        -secureTokenOn "$CURRENT_USER" -password "-" 2>&1 | tee /tmp/token_repair.log

    say "🔍 Resultado guardado en /tmp/token_repair.log"
fi

say "🌀 Limpieza completada. El alma del Mac ha sido salvada."

# Pedir reinicio
echo ""
read -p "¿Reiniciamos el equipo para renacer en gloria? (y/n): " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    say "🧞‍♂️ Preparando el salto cuántico..."
    sleep 2
    shutdown -r now
else
    say "😌 Has pospuesto el renacimiento… Pero el caos volverá si no lo haces pronto."
fi
