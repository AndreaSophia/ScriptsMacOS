# IModule — Contrato de Módulo

Todo módulo de Meridian DEBE cumplir este contrato para ser cargado por el Module Loader.
Un módulo que no cumpla este contrato es rechazado en carga, no en ejecución.

## Estructura de directorios obligatoria

```
modules/<category>/<module_id>/
├── manifest.yaml      ← OBLIGATORIO
├── diagnose.sh        ← OBLIGATORIO
├── repair.sh          ← OPCIONAL (obligatorio si repairable=true en manifest)
└── validate.sh        ← OPCIONAL (obligatorio si repair.sh existe)
```

## manifest.yaml — Schema

```yaml
# Campos obligatorios
id:               string          # snake_case, único en el registry y coincidente con el directorio
name:             string          # nombre legible, max 60 chars
description:      string          # qué diagnostica, max 200 chars
category:         string          # security|edr|mdm|network|storage|performance|system|apps|developer
version:          string          # semver "X.Y.Z"
author:           string
criticality:      string          # low|medium|high|critical
requires_root:    boolean
timeout_seconds:  integer         # entero positivo, máximo tiempo de ejecución

# Campos opcionales
repairable:       boolean         # true exige repair.sh + validate.sh; ausente equivale a false
min_os_version:   string          # "14.0" — omitir si no hay restricción
architectures:    list            # [arm64, x86_64] — omitir para ambos
dependencies:     list            # IDs de módulos requeridos — omitir si ninguno
tags:             list            # etiquetas para filtrado
```

### Invariantes del manifest

1. `id` debe ser snake_case, único y coincidir con el nombre del directorio del módulo.
2. `version` debe usar el formato semver estricto `X.Y.Z` en el MVP.
3. `timeout_seconds` debe ser un entero mayor que cero.
4. Si `repairable=true`, deben existir `repair.sh` y `validate.sh`.
5. Si existe `repair.sh`, `repairable` debe ser `true` y debe existir `validate.sh`.
6. Un módulo no reparable no debe incluir `repair.sh`; la capacidad de modificar el sistema nunca se infiere implícitamente por la presencia de un archivo.

## diagnose.sh — Contrato de función

El script debe:
1. Exportar todas las variables `RESULT_*` al finalizar
2. Retornar exit code 0 si el diagnóstico se completó (independiente del estado del sistema)
3. Retornar exit code 1 SOLO si el diagnóstico no pudo ejecutarse por error interno
4. No producir output en stdout — toda salida va a las variables RESULT_*
5. No modificar el estado del sistema bajo ninguna circunstancia
6. Respetar la variable `MERIDIAN_TEST_MODE=1` para usar fixtures en lugar de comandos reales

## repair.sh — Contrato de función (si aplica)

1. Recibe el contexto del DiagnosticResult vía variables de entorno
2. Produce un exit code 0 (éxito) o 1 (fallo)
3. Registra cada acción en stderr para el audit log
4. No solicita confirmación — la confirmación es responsabilidad del Repair Engine
5. Debe ser idempotente: ejecutarlo dos veces no produce un estado diferente al ejecutarlo una vez

## validate.sh — Contrato de función (si aplica)

1. Idéntico a diagnose.sh en estructura
2. Se ejecuta después de repair.sh
3. Devuelve un DiagnosticResult independiente que el engine compara con el resultado pre-reparación
4. Si el status es PASS, la reparación se considera exitosa

## Variables de entorno que el engine provee al módulo

```bash
MERIDIAN_MODULE_DIR      # ruta absoluta al directorio del módulo
MERIDIAN_EVIDENCE_DIR    # dónde guardar archivos de evidencia
MERIDIAN_LOG_FILE        # ruta al log de esta ejecución
MERIDIAN_TEST_MODE       # "1" si se ejecuta en modo test con fixtures
MERIDIAN_FIXTURE_DIR     # ruta a fixtures cuando TEST_MODE=1
```

## Regla de oro

Un módulo es responsable exclusivamente de inspeccionar una cosa.
Si un módulo necesita saber el estado de otro módulo, debe declararlo como dependencia.
El engine resuelve el orden de ejecución. El módulo no decide cuándo corre.
