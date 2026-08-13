# IDiagnosticResult — Contrato de Resultado de Diagnóstico

Todo módulo de Meridian DEBE retornar exactamente este modelo de datos.
Ningún módulo puede devolver datos fuera de esta estructura.

## Campos obligatorios

| Campo              | Tipo    | Valores posibles                              | Descripción |
|--------------------|---------|-----------------------------------------------|-------------|
| `module_id`        | string  | snake_case, único por módulo                  | Identificador del módulo |
| `module_version`   | string  | semver "X.Y.Z"                                | Versión del módulo |
| `timestamp`        | string  | ISO8601 "YYYY-MM-DDTHH:MM:SSZ"                | Momento de ejecución |
| `hostname`         | string  | hostname -s                                   | Equipo diagnosticado |
| `status`           | enum    | PASS \| WARN \| FAIL \| SKIP \| ERROR         | Estado del diagnóstico |
| `severity`         | enum    | INFO \| LOW \| MEDIUM \| HIGH \| CRITICAL     | Nivel de severidad |
| `title`            | string  | frase corta, max 80 chars                     | Título del hallazgo |
| `description`      | string  | qué se encontró (sin juicios)                 | Descripción objetiva |
| `explanation`      | string  | por qué importa, contexto                     | Explicación técnica |
| `risk`             | string  | consecuencias si no se resuelve               | Evaluación de riesgo |
| `suggested_action` | string  | qué hacer (sin ejecutar nada)                 | Acción recomendada |
| `repairable`       | boolean | true \| false                                 | Si existe función de reparación |
| `repair_risk`      | enum    | LOW \| MEDIUM \| HIGH \| CRITICAL \| NONE     | Riesgo de la reparación |
| `execution_time_ms`| integer | milisegundos enteros positivos                | Duración del diagnóstico |
| `exit_code`        | integer | código de salida del diagnóstico              | 0=éxito, otro=error |
| `raw_output`       | string  | salida cruda del sistema, para evidencia      | Datos sin procesar |

## Campos opcionales

| Campo              | Tipo    | Descripción |
|--------------------|---------|-------------|
| `repair_id`        | string  | Referencia a la función de reparación |
| `rule_triggered`   | string  | ID de la regla que enriqueció este resultado |
| `evidence`         | string  | Datos adicionales en formato "key=value\n..." |

## Serialización en Bash

Los campos se transmiten como variables con prefijo `RESULT_`:

```bash
RESULT_MODULE_ID="filevault"
RESULT_MODULE_VERSION="1.0.0"
RESULT_TIMESTAMP="2026-08-03T16:41:00Z"
RESULT_HOSTNAME="MacBook-Pro"
RESULT_STATUS="FAIL"
RESULT_SEVERITY="CRITICAL"
RESULT_TITLE="FileVault deshabilitado"
RESULT_DESCRIPTION="El cifrado de disco FileVault está desactivado en este equipo."
RESULT_EXPLANATION="FileVault protege los datos del disco ante acceso físico no autorizado."
RESULT_RISK="Datos del disco accesibles si el equipo es robado o perdido."
RESULT_SUGGESTED_ACTION="Habilitar FileVault desde Preferencias del Sistema > Privacidad y Seguridad."
RESULT_REPAIRABLE="true"
RESULT_REPAIR_RISK="LOW"
RESULT_EXECUTION_TIME_MS="245"
RESULT_EXIT_CODE="0"
RESULT_RAW_OUTPUT="FileVault is Off."
RESULT_REPAIR_ID="filevault_enable"
RESULT_RULE_TRIGGERED="filevault_disabled"
RESULT_EVIDENCE=""
```

## Invariantes que el engine verifica

1. `status` y `severity` son siempre enums válidos
2. Si `status=PASS`, entonces `severity` debe ser `INFO` o `LOW`
3. Si `repairable=true`, debe existir `repair_id` no vacío
4. `execution_time_ms` es siempre un entero >= 0
5. Ningún campo obligatorio puede ser vacío — usar "N/A" si no aplica
