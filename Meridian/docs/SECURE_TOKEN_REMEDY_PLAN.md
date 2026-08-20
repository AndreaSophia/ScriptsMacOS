# Secure Token Remedy — RC3 listo para validación controlada

Objetivo de política: el usuario productivo actual, `LCLAdmin` y `AdminCMDB`
deben existir según la política corporativa y reportar Secure Token habilitado.

El diagnóstico fue validado en un Mac corporativo el 2026-08-18: usuario
productivo UID 502 ENABLED, LCLAdmin UID 501 DISABLED y AdminCMDB UID 503
DISABLED. La comparación case-insensitive de RecordName produjo dos hallazgos
correctos y materializó evidencia sin secretos.

RC3 habilita una única reparación HIGH, `grant_required_secure_tokens`, solo
cuando el usuario productivo ya tiene token y LCLAdmin/AdminCMDB existen como
administradores con estado conocido. Las cuentas ya habilitadas se omiten, lo
que permite reintentar un éxito parcial. MISSING o UNKNOWN sigue bloqueado.
`sysadminctl` recibe `-password -` y `-adminPassword -`, por lo que
macOS solicita los secretos interactivamente; Meridian no los almacena,
automatiza ni escribe en argumentos, variables de entorno, logs o archivos.

La ejecución autorizada es:

```text
sudo meridian --repair secure_token
```

Exige una TTY, el texto exacto `AUTORIZO SECURE TOKEN` y verifica cada objetivo
inmediatamente. No puede ejecutarse desde MDM, launchd o un pipe.

## Validación requerida antes de habilitarlo

1. Instalar RC3 en el Mac corporativo y repetir el precheck no destructivo.
2. Ejecutar la reparación desde Terminal con una sesión productiva iniciada.
3. Validar éxito, cancelación, credencial incorrecta y sesión sin autoridad.
4. Verificar nuevamente las tres cuentas y el estado FileVault/preboot.
5. Repetir la prueba en las versiones de macOS y arquitecturas objetivo.

No existe rollback automático: revocar un Secure Token puede afectar FileVault
y al último usuario habilitado. Ante acción o validación fallida, Meridian
audita `ROLLBACK_UNAVAILABLE` y detiene el flujo; cualquier reversión requiere
un procedimiento corporativo manual autorizado.
