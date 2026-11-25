# Estándar de idempotencia

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Garantizar que la repetición de comandos, solicitudes, mensajes o trabajos no duplique efectos no deseados.

## Requisitos

- Identificar operaciones con efectos no idempotentes y protegerlas explícitamente.
- Definir ámbito, propietario, vigencia y formato de claves de idempotencia.
- Asociar clave con identidad autenticada, operación y contexto relevante para evitar colisiones entre usuarios o tenants.
- Persistir estado y resultado suficiente para responder a repeticiones de forma coherente.
- Detectar reutilización de la misma clave con payload distinto.
- Definir estados en progreso, completado, fallido recuperable y resultado incierto.
- No liberar una clave antes del horizonte de repetición y recuperación definido.
- En efectos externos, guardar referencia del proveedor y reconciliar antes de repetir cuando el resultado sea ambiguo.
- Los mensajes deben combinar idempotencia de negocio con Inbox y deduplicación cuando corresponda.

## Verificación

Pruebas concurrentes con la misma clave, reintentos después de timeout, payload conflictivo, caída en cada frontera y replay.
