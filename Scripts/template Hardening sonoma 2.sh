#!/bin/sh

#4 - Habilitar fecha y hora automatica
sudo systemsetup -setnetworktimeserver  159.68.124.162
sudo systemsetup -setusingnetworktime on

#7 - Deshabilitar evento remotos
sudo systemsetup -setremoteappleevents off setremoteappleevents: Off

#8 - Deshabilitar la opcion de compartir internet
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int 0

#9 - Deshabilitar compartir impresoras
sudo cupsctl --no-share-printers

#10 - Deshabilitar lectores de discos externos
sudo launchctl disable system/com.apple.ODSAgent 

#12 - Deshabilitar fileshare
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist

#13 - Deshabilitar administracion remota ARD
sudo /System/Library/CoreSerCEHM9727es/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop

#14 - Deshabilitar el caching de contenido
sudo AssetCacheManagerUtil deactivate

#17 - Habilitar Gatekeeper
sudo spctl --master-enable

#19 - Habilitar los servicios de localizacion
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.locationd.plist

#20 - Deshabilitar el envio de datos de diagnostico a apple
sudo defaults write /Library/Application\Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false
sudo chmod 644 /Library/Application\Support/CrashReporter/DiagnosticMessagesHistory.plist
sudo chgrp admin /Library/Application\Support/CrashReporter/DiagnosticMessagesHistory.plist

#22 - Deshabilitar el encendido por red
sudo pmset -a womp 0 

#23 - Deshabilitar power nap
sudo pmset -a powernap 0

#25 - Revisar la configuracion de uso de Siri
sudo launchctl start com.apple.driver.eficheck
sudo defaults read com.apple.Siri Status

#26 - Habilitar logs de seguridad
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist

#29 - Controlar el acceso a los logs del sistema
sudo chown -R root:wheel /etc/security/audit_control
sudo chmod -R -o-rw /etc/security/audit_control
sudo chown -R root:wheel /var/audit/
sudo chmod -R -o-rw /var/audit/

#30 - Habilitar el log de firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on

#31 - Deshabilitar Bonjour
sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true

#32 - Deshabilitar el server http
sudo launchctl disable system/org.apache.httpd

#33 - Deshabilitar el server NFS
sudo launchctl disable system/com.apple.nfsd
sudo rm /etc/exports

#38 - Deshabilitar el usuario Root
dsenableroot -d

#39 - Deshabilitar el login de usuarios automatico
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser

#41 - Habilitar  la hibernacion en el sistema operativo
sudo pmset -a standbydelaylow 600
sudo pmset -a standbydelayhigh 600
sudo pmset -a highstandbythreshold 90
sudo pmset -a destroyfvkeyonstandby 1
sudo pmset -a hibernatemode 25

#42 - requerir contraseña de administrador para acceder a las preferencias del sistema
sudo sh -c "security authorizationdb read system.preferences > /tmp/system.preferences.plist"
sudo defaults write /tmp/system.preferences.plist shared -bool false
sudo sh -c "security authorizationdb write system.preferences < /tmp/system.preferences.plist"

#43 - Prevenir a los usuarios acceder a las sesiones activas de otros usuarios
sudo security authorizationdb read system.login.screensaver 2>&1 | /usr/bin/grep -c 'use-login-window-ui' 

#44 - Crear mensaje para la pantalla de login
sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "custom.message"

#47 - Deshabilitar el cambio rapido de usuarios
sudo defaults write /Library/Preferences/.GlobalPreferences MultipleSessionEnabled -bool false

#48 - Activar validacion de librerias
sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool false
sudo defaults write /Library/Preferences/com.apple.AppleFileServer guestAccess -bool false

#49 - Deshabilitar el login como invitado
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

#50 - Deshabilitar permitir a los usuarios invitados a los directorios compartidos
sudo defaults write /Library/Preferences/com.apple.AppleFileServer guestAccess -bool false
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server AllowGuestAccess -bool false

#51 - Eliminar el directorio home de los usuarios invitados
sudo rm -R /Users/Guest 



###CONTROLES CON USERNAME


#2 - Mostrar icono de bluetooth
sudo -u CEHM9727 defaults -currentHost write com.apple.controlcenter.plist Bluetooth -int 18

#3 - Mostrar icono de WiFi
sudo -u CEHM9727 defaults -currentHost write com.apple.controlcenter.plist WiFi -int 18

#11 - Deshabilitar compartir archivos por bluetooth
sudo -u CEHM9727 defaults -currentHost write com.apple.Bluetooth PrefKeySerCEHM9727esEnabled -bool false

#21 - Limitar el uso de datos para publicidad
sudo -u CEHM9727 defaults -currentHost write /Users/CEHM9727/Library/Preferences/com.apple.Adlib.plist allowApplePersonalizedAdvertising -bool false

#24 - Habilitar secure keyboard entry en el terminal
sudo -u CEHM9727 defaults write -app Terminal SecureKeyboardEntry -bool true

#34 - Verificar los permisos de las carpetas de usuario
sudo chmod -R og-rw /Users/CEHM9727

#37 - Bloquear el administrador de contraseñas cuando la pantalla esta apagada
sudo -u CEHM9727 security set-keychain-settings -l /Users/CEHM9727/Library/Keychains/login.keychain

#46 - Evitar la pista de contraseña
sudo dscl . -delete /Users/CEHM9727 hint
sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0

#52 - Mostrar las extensiones de los archivos
sudo -u CEHM9727 defaults write /Users/CEHM9727/Library/Preferences/.GlobalPreferences.plist AppleShowAllExtensions -bool true

#53 - Deshabilitar la ejecucion automatica de archivos confiables
sudo -u CEHM9727 defaults write /Users/CEHM9727/Library/Application\ Scripts/com.apple.Safari AutoOpenSafeDownloads -bool false


