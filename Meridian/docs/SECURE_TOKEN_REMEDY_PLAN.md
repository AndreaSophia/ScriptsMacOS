# Secure Token Remedy — candidato pendiente de Mac real

Objetivo de política: el usuario productivo actual, `LCLAdmin` y `AdminCMDB`
deben existir según la política corporativa y reportar Secure Token habilitado.

El módulo permanece `repairable: false`. No se incluye aún `repair.sh` porque
`sysadminctl -secureTokenOn` requiere autorización y credenciales apropiadas, y
su comportamiento debe verificarse físicamente en las versiones de macOS y el
hardware objetivo. Meridian no almacenará, generará, copiará ni pasará
contraseñas por argumentos, variables de entorno, stdin automatizado o archivos.

## Validación requerida antes de habilitarlo

1. Probar el precheck con usuario de consola válido y las tres identidades.
2. Confirmar el flujo interactivo nativo autorizado por la organización.
3. Probar éxito, cancelación, credencial incorrecta y sesión sin autoridad.
4. Verificar nuevamente las tres cuentas y el estado FileVault/preboot.
5. Determinar si existe rollback real. Revocar un Secure Token puede afectar al
   último usuario habilitado y no debe asumirse reversible.
6. Ejecutar la regresión completa en Bash 3.2 sobre Intel y Apple Silicon.

Hasta completar esas pruebas, cualquier incumplimiento se limita a evidencia y
recomendación operativa; el framework falla cerrado antes de toda mutación.
