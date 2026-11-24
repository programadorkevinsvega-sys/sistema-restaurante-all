# ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

Outbox por sí solo no resuelve escalado horizontal. Varias réplicas pueden duplicar consumo/publicación o ejecutar el mismo job. Estado relevante en memoria se pierde al reiniciar.

## Decisión

1. Aplicación stateless desde el día uno; sesiones, estado relevante y trabajo durable en almacenamiento compartido.
2. Eventos durables escritos en Outbox en la misma transacción que el cambio de negocio.
3. Sin broker, dispatcher con FOR UPDATE SKIP LOCKED, lotes acotados y leases recuperables. Con broker, confirmación durable y grupos de consumidores.
4. Consumidores con Inbox/deduplicación por consumidor y event_id; Inbox y efectos persistentes en la misma transacción local.
5. Entrega at-least-once e idempotencia; no exactly-once extremo a extremo.
6. Efectos externos con claves idempotentes, Outbox adicional o reconciliación/compensación.
7. Jobs periódicos multi-réplica con advisory lock PostgreSQL, lease exclusivo recuperable o elección de líder.
8. Jobs con checkpoints, límites de concurrencia/lotes y recuperación tras caída.
9. Health/readiness, graceful shutdown, timeouts y backpressure.

## Consecuencias

Workers reanudables y seguros ante duplicados. PostgreSQL puede bastar inicialmente sin broker. Se requieren pruebas en los límites entre commit, publicación, confirmación y ACK. El estado efímero nunca es la única copia de trabajo durable.

## Alternativas

Outbox sin Inbox: rechazado por efectos duplicados. Cron por réplica sin coordinación: rechazado. Bus en memoria multi-réplica para eventos durables: rechazado.

## Estado de implementación

Decisión aceptada; reglas o tablas Outbox no demuestran que workers, Inbox, locks o despliegue multi-réplica estén implementados.
