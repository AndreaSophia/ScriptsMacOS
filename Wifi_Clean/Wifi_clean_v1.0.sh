#!/bin/bash

clear
echo "🚨 ATENCIÓN, TÉCNICO DESPISTADO 🚨"
echo "========================================"
echo "🔥 BIENVENIDO A:"
echo "    🧼 NetWipe 3000™ - Edición Humillante 🧼"
echo "    ‘Porque a veces el problema SÍ eres tú’"
echo "========================================"
sleep 2

echo ""
echo "📴 APAGANDO EL Wi-Fi... como tus ganas de vivir los lunes."
networksetup -setairportpower en0 off
sleep 2

echo ""
echo "🧽 LIMPIANDO configuraciones antiguas..."
echo "🧻 Porque claramente arrastrabas más mugre que un router del 2003."
rm -fv /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
rm -fv /Library/Preferences/SystemConfiguration/com.apple.network.identification.plist
rm -fv /Library/Preferences/SystemConfiguration/NetworkInterfaces.plist
rm -fv /Library/Preferences/SystemConfiguration/preferences.plist
sleep 1

echo ""
echo "🔁 REZANDO A DHCP para que te perdone..."
ipconfig set en0 DHCP
ipconfig set en0 BOOTP
ipconfig set en0 DHCP
sleep 1

echo ""
echo "🧠 FLUSHING DNS..."
echo "🧠 ...Porque claramente el Mac no era el único confundido."
dscacheutil -flushcache
killall -HUP mDNSResponder
sleep 1

echo ""
echo "📶 ENCENDIENDO Wi-Fi otra vez..."
networksetup -setairportpower en0 on
sleep 2

echo ""
echo "🔧 REINICIANDO servicios de red..."
launchctl unload /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist 2>/dev/null
launchctl load /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist 2>/dev/null
sleep 1

echo ""
echo "📋 MOSTRANDO INTERFACES..."
networksetup -listallhardwareports
sleep 1

echo ""
echo "✅ RED RESTAURADA."
echo "🎉 Si después de esto sigues sin red, te recomiendo probar con:"
echo "    1. Llorar."
echo "    2. Golpear el router (no recomendado pero liberador)."
echo "    3. Llamar a tu mamá."
echo ""
echo "💡 Consejo del día: No culpes al equipo si no sabes usarlo."
echo ""
echo "🧘‍♀️ Reinicia el Mac, y cuando vuelva, actúa como que siempre supiste lo que hacías."
echo ""
echo "========================================"
echo "✨ NetWipe 3000™ - Modo Humillación completado ✨"
echo "    🔌 Red limpia, conciencia sucia. Hasta la próxima."
echo "========================================"
