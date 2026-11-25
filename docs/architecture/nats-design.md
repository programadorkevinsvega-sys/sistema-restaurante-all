# Diseño de NATS Core y JetStream — subfase 0.9

**Estado:** diseño aprobado — subfase 0.9
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.9
**Autoridad:** ADR-0003, ADR-0017
**Base:** [NATS Core y JetStream en clúster](./nats-core-jetstream-cluster.md)
**Documentos relacionados:**

- [Diseño Redis Cluster](./redis-design.md)
- [Diseño Outbox/Inbox/Saga](./outbox-inbox-saga-design.md)

---

## 1. Topología objetivo

```text
Cliente (proceso)
      │  TLS 1.2+
      ▼
┌─────────────────────────────────────┐
│          NATS Cluster (3 nodos)     │
│  NATS-1 (JetStream, dominio A)      │
│  NATS-2 (JetStream, dominio B)      │
│  NATS-3 (JetStream, dominio C)      │
│         quorum Raft                 │
└─────────────────────────────────────┘
```text
- 3 nodos mínimos; cada uno en dominio de fallo independiente.
- JetStream habilitado en todos los nodos.
- Streams críticos con R=3 (réplicas en los 3 dominios).
- Clientes conocen múltiples endpoints; sin dependencia de un nodo fijo.

---

## 2. Cuentas NATS por proceso

Cada proceso y cada tipo de worker tienen una cuenta NATS independiente.
No existen credenciales administrativas compartidas para operaciones rutinarias.

| Cuenta | Proceso / Worker | Propósito |
|---|---|---|
| `account.admin-platform` | Admin Platform Backend | Publicar/consumir subjects de PLATFORM |
| `account.public-backend` | Public Backend | Publicar/consumir subjects de módulos de negocio |
| `account.admin-bff` | Admin BFF | Señales efímeras (Core únicamente) |
| `account.public-bff` | Public BFF | Señales efímeras (Core únicamente) |
| `account.outbox-platform` | Dispatcher Outbox PLATFORM | Publicar en subjects de PLATFORM |
| `account.outbox-public` | Dispatcher Outbox Public Backend | Publicar en subjects de módulos |
| `account.worker-{modulo}` | Workers Inbox por módulo | Consumir subjects del módulo propio |
| `account.ops` | Monitoreo y administración | Solo endpoints de monitoreo; sin pub/sub de negocio |

Los BFF usan exclusivamente NATS Core (señales efímeras); no publican ni consumen en JetStream de negocio.

---

## 3. Convención de subjects

Formato: `{env}.{backend}.{modulo}.{recurso}.{evento}.{version}`

| Segmento | Descripción |
|---|---|
| `{env}` | `prod` / `staging` / `dev` |
| `{backend}` | `platform` / `public` |
| `{modulo}` | Módulo propietario en minúsculas (ej. `sales`, `payments`) |
| `{recurso}` | Tipo de agregado (ej. `order`, `payment`) |
| `{evento}` | Nombre del evento en pasado (ej. `created`, `captured`) |
| `{version}` | `v1`, `v2`, etc. |

**Ejemplos:**

```text
prod.public.sales.order.created.v1
prod.public.payments.payment.captured.v1
prod.platform.tenant.tenant.suspended.v1
```text
**Reglas:**

- Sin PII, `tenant_id`, `user_id` ni valores libres como segmentos.
- El módulo propietario del evento define y controla su subject.
- Ningún módulo publica en subjects de otro módulo.
- Los subjects de señales efímeras (Core) usan el prefijo `signal.`.

---

## 4. Catálogo de streams JetStream

Cada stream tiene ficha documentada. Esta tabla es la lista mínima inicial;
se expande con los módulos que se implementan.

| Stream | Subjects | Retención | Réplicas | Propietario |
|---|---|---|---|---|
| `PLATFORM_EVENTS` | `prod.platform.>` | Limits (90 días) | R=3 | PLATFORM |
| `SALES_EVENTS` | `prod.public.sales.>` | Limits (30 días) | R=3 | SALES |
| `PAYMENTS_EVENTS` | `prod.public.payments.>` | Limits (90 días) | R=3 | PAYMENTS |
| `INVENTORY_EVENTS` | `prod.public.inventory.>` | Limits (30 días) | R=3 | INVENTORY |
| `IDENTITY_EVENTS` | `prod.public.identity.>` | Limits (30 días) | R=3 | IDENTITY |
| `KITCHEN_EVENTS` | `prod.public.kitchen.>` | Limits (7 días) | R=3 | KITCHEN |
| `CACHE_INVALIDATION` | `prod.public.cache.invalidate.>` | WorkQueue | R=3 | Módulo propietario del dato |

Los valores de retención son punto de partida; se ajustan con carga medida y política de datos.

---

## 5. Consumidores durables por módulo

Cada módulo consumidor tiene un consumer durable con nombre estable.

| Consumer | Stream | Módulo consumidor | Filtro de subject |
|---|---|---|---|
| `INVENTORY_consume_sales` | `SALES_EVENTS` | INVENTORY | `prod.public.sales.order.created.>` |
| `KITCHEN_consume_sales` | `SALES_EVENTS` | KITCHEN | `prod.public.sales.order.created.>` |
| `PAYMENTS_consume_sales` | `SALES_EVENTS` | PAYMENTS | `prod.public.sales.order.confirmed.>` |
| `AUDIT_consume_payments` | `PAYMENTS_EVENTS` | AUDIT | `prod.public.payments.>` |
| `CACHE_invalidator_{modulo}` | `CACHE_INVALIDATION` | Módulo afectado | Subject de su propio dominio |

Los consumidores se crean con:

- `ack_policy: explicit` — ACK manual después del commit local.
- `max_deliver: N` — límite de reintentos antes de DLQ (valor por módulo).
- `ack_wait: T` — tiempo máximo antes de redelivery (valor por módulo/latencia).
- `max_ack_pending: M` — mensajes en vuelo simultáneos.

---

## 6. DLQ y cuarentena de mensajes

Mensajes que agotan `max_deliver` van a un consumer de cuarentena:

```text
STREAM_DLQ_{NOMBRE_STREAM}
```text
Cada módulo tiene responsable designado que revisa la DLQ periódicamente.
El redrive requiere:

1. Identificar y corregir la causa raíz.
2. Verificar idempotencia del consumer.
3. Reenviar con la misma `event_id` (clave idempotente).
4. Registrar el redrive en AUDIT con actor y motivo.

---

## 7. Parámetros operativos pendientes de dimensionamiento

| Parámetro | Se fija con |
|---|---|
| `max_deliver` por consumer | Latencia medida y criticidad del flujo |
| `ack_wait` por consumer | Tiempo real de procesamiento en staging |
| Retención exacta por stream | Política de datos y regulación por jurisdicción |
| Max payload size | Contratos Protobuf y red |
| Conexiones máximas por cuenta | Instancias del proceso × conexiones por instancia |
| Umbral de lag para alerta | Throughput y capacidad de drenaje medidos |

---

## 8. Estado de implementación

Diseño aprobado. No existen nodos NATS desplegados, streams creados, consumers
configurados, cuentas emitidas ni credenciales generadas. La implementación
comienza en la subfase de aprovisionamiento de infraestructura.
