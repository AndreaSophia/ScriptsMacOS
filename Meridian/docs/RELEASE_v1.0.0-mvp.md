# Cierre verificado de Meridian v1.0.0-mvp

Verificado el 2026-08-18 sin modificar `main` ni el tag.

- Tag anotado: `v1.0.0-mvp`
- Objeto tag: `9c502c0dacf0182bbd770249dee44236dd84d639`
- Commit objetivo: `df7f76cda47cd32552ef7b00f4f947b9e126e25b`
- Mensaje: `test(secure-token): require materialized evidence artifact`
- Rama de release remota: `origin/release/v1.0.0-mvp` en el mismo commit
- `main` observado: `e0379ac0f0c59b48cb3bd5fa51a845a1f6320344`
- Rama post-MVP: `develop/meridian-remedy-1.1`, creada desde el commit del tag

## Regresión de cierre

En el entorno aislado de desarrollo se ejecutaron 39 suites: 37 pasaron. Las dos
restantes (`test_entrypoint_stderr.sh` y `test_headless_entrypoint.sh`) fallaron
porque el sandbox no permite crear la sesión esperada bajo `~/Desktop`; no hubo
fallos del core, del módulo Secure Token ni de sus fronteras de seguridad.

La ejecución final de release y cualquier acción que dependa de macOS, hardware,
Secure Enclave, FileVault o credenciales deben validarse en un Mac real.

## Alcance congelado

La rama 1.1 incorpora únicamente Meridian Remedy. No se añaden reparaciones para
MDM, CrowdStrike Falcon, Cisco Umbrella, Forcepoint ni certificados. Esos
componentes administrados permanecen en diagnóstico solamente.
