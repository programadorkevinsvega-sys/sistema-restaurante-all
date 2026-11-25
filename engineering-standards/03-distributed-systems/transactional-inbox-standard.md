# Estándar Transactional Inbox

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Procesar mensajes repetidos de manera segura y evitar que la entrega al menos una vez cause efectos de negocio duplicados.

## Requisitos

- El consumidor debe registrar la identidad del mensaje en una Inbox o mecanismo durable equivalente.
- La deduplicación y el efecto de negocio deben confirmarse en la misma transacción local cuando comparten persistencia.
- El ACK al broker debe ocurrir después del commit durable.
- Una repetición del mismo mensaje no debe repetir el efecto.
- La clave de deduplicación debe tener ámbito definido: consumidor, suscripción, tipo de efecto y productor según corresponda.
- La retención de deduplicación debe cubrir el horizonte real de replay, redrive y recuperación.
- Un mensaje con el mismo ID y contenido incompatible debe tratarse como anomalía, no como duplicado inocuo.
- Los errores transitorios deben reintentarse; los permanentes deben ir a cuarentena con evidencia.
- El consumidor debe validar esquema, versión, productor autorizado y contexto antes de procesar.
- El procesamiento debe tolerar mensajes duplicados y, cuando aplique, fuera de orden.

## Idempotencia de negocio

La Inbox no sustituye claves de idempotencia en comandos ni invariantes de dominio. Un mismo efecto puede llegar por rutas diferentes; el dominio debe proteger sus invariantes.

## Verificación

Pruebas de redelivery, crash antes/después del commit, ACK perdido, replay histórico, mensajes fuera de orden y retención expirada.
