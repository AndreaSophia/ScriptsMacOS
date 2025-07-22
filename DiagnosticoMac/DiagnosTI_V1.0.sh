#!/bin/bash

# 🕵️‍♀️ Inspector Digital Nivel Safiye 9000

clear
echo "🧠🔍 Iniciando escaneo del sistema... ¡Detectando traidores, infiltrados y espíritus corruptos! 🧙‍♀️"

sleep 2

echo -e "\n📦 Buscando herramientas de control..."

declare -a tools=("Cisco Umbrella" "Forescout" "Forcepoint" "CrowdStrike Falcon" "GlobalProtect VPN")
declare -a agents=("com.cisco.anyconnect" "com.forescout.secureconnector" "com.forcepoint.endpoint" "com.crowdstrike.falcon.Agent" "com.paloaltonetworks.gp")

for i in "${!agents[@]}"; do
    if launchctl list | grep -q "${agents[$i]}"; then
        echo "✅ ${tools[$i]} está presente. Sabe todo lo que haces, incluso cuando bostezas."
    else
        echo "❌ ${tools[$i]} no fue encontrado. Hoy tienes un poquito más de libertad."
    fi
done

sleep 1
echo -e "\n🔐 Verificando estado de encriptación con FileVault..."

FV_STATUS=$(fdesetup status)
echo "🔎 $FV_STATUS"
[[ "$FV_STATUS" =~ "On" ]] && echo "✅ Encriptado. Tus secretos están guardados bajo 7 llaves." || echo "⚠️ FileVault está desactivado. Aquí se cuece algo sospechoso..."

sleep 1
echo -e "\n👤 Detectando tipo de cuenta..."

CURRENT_USER=$(stat -f %Su /dev/console)
IS_MOBILE=$(dscl . read /Users/$CURRENT_USER | grep "OriginalNodeName")

if [[ -n "$IS_MOBILE" ]]; then
    echo "🧳 $CURRENT_USER es una cuenta *móvil*. Lleva sus cosas en la mochila del sistema."
else
    echo "🏠 $CURRENT_USER es una cuenta *local*. Vive aquí. Paga arriendo en permisos UNIX."
fi

sleep 1
echo -e "\n🛡️ Revisando estado del Secure Token..."

TOKEN_STATUS=$(sysadminctl -secureTokenStatus "$CURRENT_USER" 2>&1)
echo "🔍 $TOKEN_STATUS"

if echo "$TOKEN_STATUS" | grep -q "ENABLED"; then
    echo "✅ Secure Token activo. Puede abrir puertas digitales sin romperlas."
else
    echo "🧨 Secure Token inactivo. Este usuario necesita ayuda divina o al menos root access."
fi

sleep 1
echo -e "\n📲 Verificando presencia y salud del MDM..."

if profiles status -type enrollment | grep -q "Enrolled: Yes"; then
    echo "✅ MDM está activo. El equipo obedece... ¿por ahora?"
    MDM_SERVER=$(profiles show -type enrollment | grep ServerURL)
    echo "🌐 MDM conectado a: $MDM_SERVER"
else
    echo "❌ No hay MDM. Este Mac vive sin ley, como vaquero del oeste."
fi

# Analizar posible corrupción MDM
echo -e "\n🧪 Analizando corrupción de MDM..."

if [ ! -d "/var/db/ConfigurationProfiles" ] || [ ! -f "/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord" ]; then
    echo "⚠️ Posibles signos de corrupción en el alma del MDM."
else
    echo "✅ Estructura del MDM parece estable (por ahora)."
fi

sleep 1
echo -e "\n🧼 Escaneando sistema en busca de rarezas sistémicas..."

# Buscar errores comunes del sistema
SYS_ERRORS=$(log show --predicate 'eventMessage CONTAINS "MDM"' --info --last 1h | grep -i error)

if [[ -n "$SYS_ERRORS" ]]; then
    echo "⚠️ Se detectaron errores recientes asociados a MDM:"
    echo "$SYS_ERRORS"
else
    echo "✅ Sin errores graves de MDM en el último rato. Silencio... demasiado silencio."
fi

echo -e "\n✅ Escaneo completo. El equipo ha sido inspeccionado por el Inspector Safiye 9000."

echo -e "\n💡 Recomendación: si todo falla, café fuerte, rezo profundo y 'sudo reboot' con estilo."

