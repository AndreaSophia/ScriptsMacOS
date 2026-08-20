# Meridian 1.1 Remedy RC2 — prueba controlada en Mac corporativo

Este procedimiento valida instalación y diagnóstico. No habilita ni revoca
Secure Token y no repara MDM, Falcon, Umbrella, Forcepoint o certificados.

## 1. Construcción en el Mac de desarrollo

```bash
cd ~/Documents/GitHub/ScriptsMacOS
git switch develop/meridian-remedy-1.1
git pull --ff-only
/bin/bash Meridian/tests/run_all.sh
/bin/bash Meridian/dist/build_pkg.sh
pkgutil --payload-files Meridian/dist/Meridian-1.1.0-remedy-rc3.pkg | grep -E '(^|/)\._|(^|/)\.DS_Store$'
shasum -a 256 Meridian/dist/Meridian-1.1.0-remedy-rc3.pkg
```

La regresión debe terminar 40/40. La consulta de metadata no debe imprimir
nada. Guardar el SHA-256 y transferir el PKG mediante un canal corporativo
autorizado. El paquete RC no está firmado salvo que se use `--sign` con una
identidad `Developer ID Installer` válida.

## 2. Verificación previa en el Mac corporativo

No continuar sin autorización para instalar software de prueba. Sustituir la
ruta y el hash por los valores reales:

```bash
PKG="$HOME/Downloads/Meridian-1.1.0-remedy-rc3.pkg"
shasum -a 256 "$PKG"
pkgutil --check-signature "$PKG"
```

El SHA-256 debe coincidir exactamente con el obtenido en desarrollo. Si la
política corporativa exige firma y el paquete figura sin firmar, detener la
prueba; no evadir Gatekeeper ni controles MDM.

## 3. Instalación autorizada

```bash
sudo /usr/sbin/installer -pkg "$PKG" -target /
pkgutil --pkg-info com.itau.apple.meridian
/usr/bin/readlink /usr/local/bin/meridian
/bin/cat /usr/local/lib/meridian/VERSION
/usr/local/bin/meridian --help
```

Se espera el symlink `/usr/local/lib/meridian/meridian`, versión
`1.1.0-remedy-rc3` y ayuda funcional.

## 4. Diagnóstico Secure Token solamente

```bash
sudo /usr/local/bin/meridian --module secure_token
```

## 5. Precheck Remedy no destructivo

```bash
sudo /bin/bash /usr/local/lib/meridian/modules/security/secure_token/precheck.sh
printf 'precheck_rc=%s\n' "$?"
```

En el escenario corporativo validado se espera `disabled_targets=2` y código
`0`. El precheck no solicita credenciales aparte de la autorización normal de
`sudo`, no otorga tokens y no modifica cuentas.

Registrar la ruta del reporte publicada por Meridian y conservar
`Executive_Report.txt`, `results.json`, `diagnostic.log`, la evidencia
`secure_token_detail.txt` y el ZIP de sesión. No introducir contraseñas en
Meridian ni ejecutar comandos `sysadminctl -secureTokenOn/-secureTokenOff`.

## 6. Consultas manuales read-only para contraste

```bash
/usr/bin/dscl . -read /Users/LCLAdmin RecordName UniqueID
/usr/bin/dscl . -read /Users/AdminCMDB RecordName UniqueID
/usr/sbin/sysadminctl -secureTokenStatus LCLAdmin
/usr/sbin/sysadminctl -secureTokenStatus AdminCMDB
```

Los nombres pueden materializarse en minúsculas; Meridian 1.1 los compara sin
distinguir mayúsculas y conserva el RecordName observado en la evidencia.

## Criterio de salida

- instalación correcta y versión RC2 confirmada;
- diagnóstico finaliza sin modificar el sistema;
- las tres cuentas requeridas aparecen como REQUIRED;
- DISABLED/MISSING/UNKNOWN se reporta, no se repara;
- ninguna contraseña aparece en reportes, evidencia o logs;
- cualquier bloqueo de firma, permisos o política detiene la prueba.
