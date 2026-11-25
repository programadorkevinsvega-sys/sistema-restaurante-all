# Contratos de eventos y política de fallback seguro — subfase 0.9

**Estado:** diseño aprobado — subfase 0.9
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.9
**Autoridad:** ADR-0003, ADR-0004, ADR-0007, ADR-0013, ADR-0017
**Documentos relacionados:**

- [Diseño NATS](./nats-design.md)
- [Diseño Outbox/Inbox/Saga](./outbox-inbox-saga-design.md)
- [Diseño Redis Cluster](./redis-design.md)

---

## 1. Propósito

Define la estructura estándar de los contratos de eventos durables (JetStream) y las
reglas de fallback seguro para Redis, NATS y proveedores externos.

---

## 2. Estructura del envelope de evento

Todo evento durable publicado por un módulo en JetStream sigue este envelope.
El contrato concreto de cada evento (su `payload`) es propiedad del módulo publicador.

```json
{
  "event_id": "01932e4a-7c3f-7000-9f5b-3d2e1a4b5c6d",
  "event_type": "order.created",
  "schema_version": "v1",
  "producer_module": "sales",
  "aggregate_type": "order",
  "aggregate_id": "01932e4b-...",
  "event_sequence": 1,
  "aggregate_version": 1,
  "occurred_at": "2026-11-25T10:00:00.000Z",
  "tenant_id": "01932e4c-...",
  "correlation_id": "01932e4d-...",
  "causation_id": "01932e4e-...",
  "saga_id": null,
  "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  "payload": { }
}
```text
**Reglas del envelope:**

- `event_id`: UUIDv7; clave de idempotencia para los consumidores.
- `event_type`: nombre estable en `{recurso}.{evento}` (ej. `order.created`).
- `schema_version`: empieza en `v1`; incrementar al romper compatibilidad.
- `producer_module`: identificador del módulo propietario; nunca el BFF.
- `event_sequence`: secuencia monotónica dentro del agregado; `null` si no aplica orden.
- `occurred_at`: instante informativo; no es mecanismo de orden transaccional.
- `tenant_id`: presente cuando la operación es acotada a tenant.
- `traceparent`: W3C Trace Context obligatorio conforme a ADR-0004.
- `payload`: datos mínimos necesarios para el consumidor; sin secretos, tokens ni datos completos de pago.

---

## 3. Versionado y evolución de contratos

| Tipo de cambio | Acción |
|---|---|
| Campo opcional nuevo | Misma `schema_version`; consumidores ignoran campos desconocidos |
| Campo obligatorio nuevo o renombrado | Nueva `schema_version` (`v2`); periodo de coexistencia `v1` y `v2` |
| Campo eliminado | Nueva `schema_version`; deprecar en `v1` antes de eliminar |
| Cambio de tipo de campo | Nueva `schema_version` |

Durante coexistencia:

- El productor publica en ambas versiones (o publica `v2` y un transformer publica `v1`).
- Los consumidores migran a `v2` antes de que `v1` sea retirada.
- La retirada de una versión requiere confirmación de que todos los consumidores migraron.

---

## 4. Catálogo de eventos iniciales

Eventos mínimos que se implementan en las primeras subfases de Fase 1:

| Evento | Subject | Productor | Consumidores iniciales |
|---|---|---|---|
| `tenant.created.v1` | `prod.platform.tenant.tenant.created.v1` | PLATFORM | IDENTITY, ORGANIZATION |
| `tenant.suspended.v1` | `prod.platform.tenant.tenant.suspended.v1` | PLATFORM | IDENTITY |
| `user.created.v1` | `prod.public.identity.user.created.v1` | IDENTITY | AUDIT |
| `user.role_assigned.v1` | `prod.public.identity.user.role_assigned.v1` | IDENTITY | AUDIT |
| `order.created.v1` | `prod.public.sales.order.created.v1` | SALES | INVENTORY, KITCHEN, AUDIT |
| `payment.captured.v1` | `prod.public.payments.payment.captured.v1` | PAYMENTS | SALES, BILLING, AUDIT |
| `inventory.adjustment.v1` | `prod.public.inventory.inventory.adjustment.v1` | INVENTORY | AUDIT |
| `cache.invalidate.catalog.v1` | `prod.public.cache.invalidate.catalog.v1` | CATALOG | Worker invalidación CATALOG |

Este catálogo se expande en cada subfase de módulo. No se inventan eventos sin un
caso de uso concreto y un consumidor definido.

---

## 5. Política de fallback seguro

### 5.1 Fallback cuando Redis no está disponible

| Situación | Acción |
|---|---|
| GET Redis timeout (> 50 ms) | Continuar a PostgreSQL; sin error al cliente |
| Error de conexión Redis | Abrir circuit breaker; PostgreSQL con límite de concurrencia |
| Circuit breaker abierto | Solo PostgreSQL; calentamiento gradual cuando Redis restaure |
| Caché fría post-failover | Regeneración gradual; límite de concurrencia por módulo |

La escritura de negocio nunca depende de que Redis esté disponible.
Un fallo de Redis no produce error 500 en operaciones de lectura elegibles.

### 5.2 Fallback cuando NATS/JetStream no está disponible

| Situación | Acción |
|---|---|
| Fallo de publicación JetStream | El Outbox permanece en PostgreSQL; el dispatcher reintentará |
| JetStream sin quorum | No confirmar publicaciones que no alcancen la garantía requerida |
| NATS Core falla | Las señales efímeras se pierden; la aplicación reconstruye el estado desde fuente autoritativa |
| Consumer no puede conectar | El Outbox acumula; los mensajes no se pierden mientras PostgreSQL esté disponible |

La indisponibilidad de NATS no borra el Outbox ni bloquea las transacciones de negocio.
Los procesos no dependen de NATS para confirmar sus propias transacciones locales.

### 5.3 Fallback cuando un proveedor externo no está disponible

| Situación | Acción |
|---|---|
| PSP no responde | Mantener el pedido en estado `payment_pending`; reintentar con backoff |
| Proveedor de email/SMS no responde | Encolar en Outbox; reintentar; no bloquear el flujo de negocio |
| Webhook de integración falla | Registrar fallo en INTEGRATIONS; notificar al tenant; reintento configurable |
| Resultado incierto (timeout PSP) | No asumir éxito ni fallo; consultar estado por `operation_id` antes de compensar |

Los proveedores externos son fronteras no confiables; sus respuestas se validan antes de mapear o persistir.

---

## 6. Reglas de idempotencia en consumidores

| Regla | Descripción |
|---|---|
| Verificar Inbox antes de ejecutar | Si `event_id` ya está en la tabla Inbox, devolver éxito silencioso |
| Inbox + efecto en la misma transacción | Ambos se confirman o ninguno |
| ACK al broker después del commit | No antes; si el ACK se pierde, el redelivery detecta duplicado por Inbox |
| No depender del orden de llegada | Usar `event_sequence` y `aggregate_version` cuando el orden importe |
| Resultado incierto ante timeout | Consultar estado del paso; no asumir fallo; no compensar prematuramente |

---

## 7. Estado de implementación

Diseño aprobado. No existen eventos publicados, consumers configurados, contratos
Protobuf generados ni código de consumidor implementado. Los contratos concretos
de cada evento se implementan módulo a módulo a partir de la Fase 1.
