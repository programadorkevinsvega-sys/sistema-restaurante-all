# Estándar de timeouts, reintentos y backpressure

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Evitar que fallos parciales o lentitud de dependencias se conviertan en fallos en cascada.

## Requisitos

- Toda llamada remota debe tener deadline o timeout explícito.
- El timeout debe considerar el presupuesto total de la operación y no reiniciarse ilimitadamente en cada salto.
- Propagar cancelación cuando el llamador ya no necesite el resultado.
- Reintentar solo errores transitorios y operaciones idempotentes o protegidas por clave de idempotencia.
- Usar backoff exponencial con jitter y límites de intentos/tiempo.
- Respetar Retry-After y límites del proveedor cuando existan.
- Evitar reintentos en cascada en múltiples capas sin presupuesto coordinado.
- Implementar circuit breaker o mecanismo de aislamiento cuando una dependencia degradada pueda agotar recursos.
- Limitar concurrencia, colas, payloads y tiempo de espera.
- Aplicar backpressure y rechazar trabajo de forma controlada antes de agotar memoria o conexiones.
- Separar fallos de negocio permanentes de fallos técnicos transitorios.
- Registrar motivo, intento, latencia y resultado sin generar cardinalidad excesiva.

## Presupuesto de latencia

Definir presupuesto extremo a extremo, distribuirlo entre dependencias y reservar tiempo para respuesta y limpieza. Las operaciones críticas deben tener objetivos explícitos y pruebas de carga.

## Verificación

Pruebas de latencia, timeouts, cancelación, fallos parciales, recuperación, tormentas de reintentos, saturación y degradación controlada.
