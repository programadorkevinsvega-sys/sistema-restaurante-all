# Diseño Outbox / Inbox / Saga

**Estado:** diseño aprobado — subfase 0.6
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.6
**Autoridad:** ADR-0003, ADR-0013
**Base:**

- [Operación de Transactional Outbox e Inbox](./transactional-outbox-inbox-operations.md)
- [Estrategia de consistencia distribuida y Sagas](./distributed-transaction-consistency.md)

---

## 1. Propósito

Concreta el diseño operativo de Outbox, Inbox y Sagas para la implementación.
No crea tablas, workers, ni code; establece la estructura, las reglas y los contratos.

---

## 2. Estructura de la tabla Outbox por módulo

Cada módulo tiene su propia tabla Outbox en su schema. No existe una tabla Outbox global.

```sql
-- Diseño de referencia; no ejecutar sin autorización expresa
-- Ruta canónica: backend/<backend>/modules/<modulo>/migrations/
CREATE TABLE <schema>.outbox (
    id              uuid        NOT NULL DEFAULT uuidv7(),  -- o generado en app
    event_type      text        NOT NULL,
    schema_version  text        NOT NULL,
    aggregate_type  text        NOT NULL,
    aggregate_id    uuid        NOT NULL,
    event_sequence  bigint,                     -- orden dentro del agregado; nullable si no aplica
    tenant_id       uuid        NOT NULL,
    payload         jsonb       NOT NULL,
    metadata        jsonb,                      -- trace_id, correlation_id, causation_id, etc.
    created_at      timestamptz NOT NULL DEFAULT now(),
    published_at    timestamptz,                -- null = pendiente de publicar
    publish_error   text,                       -- último error de publicación si aplica
    CONSTRAINT outbox_pkey PRIMARY KEY (id)
);

CREATE INDEX outbox_pending_idx ON <schema>.outbox (created_at)
    WHERE published_at IS NULL;
```

**Reglas:**

- `id`, cambio de negocio e inserción Outbox van en la misma transacción local.
- `published_at` se actualiza solo después de confirmación durable del broker (JetStream ACK).
- El dispatcher usa `SELECT ... FOR UPDATE SKIP LOCKED` para reclamar filas sin bloquear.
- Las filas publicadas se retienen según política de retención del módulo; no se borran inmediatamente.
- El payload no incluye contraseñas, tokens, datos completos de pago ni secretos.

---

## 3. Estructura de la tabla Inbox por módulo

```sql
-- Diseño de referencia; no ejecutar sin autorización expresa
CREATE TABLE <schema>.inbox (
    id              uuid        NOT NULL DEFAULT uuidv7(),
    event_id        uuid        NOT NULL,       -- ID del mensaje recibido; clave de deduplicación
    event_type      text        NOT NULL,
    schema_version  text        NOT NULL,
    producer_module text        NOT NULL,
    tenant_id       uuid        NOT NULL,
    payload         jsonb       NOT NULL,
    metadata        jsonb,
    received_at     timestamptz NOT NULL DEFAULT now(),
    processed_at    timestamptz,                -- null = pendiente de procesar
    process_error   text,
    CONSTRAINT inbox_pkey PRIMARY KEY (id),
    CONSTRAINT inbox_event_unique UNIQUE (event_id, tenant_id)  -- deduplicación
);

CREATE INDEX inbox_pending_idx ON <schema>.inbox (received_at)
    WHERE processed_at IS NULL;
```

**Reglas:**

- La inserción en Inbox y el efecto de negocio van en la misma transacción local.
- El constraint `UNIQUE (event_id, tenant_id)` detecta duplicados antes de procesar.
- Si el `event_id` ya existe, el consumidor devuelve éxito silencioso sin re-ejecutar el efecto.
- El ACK al broker ocurre después del commit local de Inbox + efecto.
- Mensajes con errores permanentes van a DLQ tras agotar reintentos configurados.

---

## 4. Dispatcher Outbox

El dispatcher es un componente por módulo (no un servicio global) que:

1. Consulta filas pendientes con `SELECT ... FOR UPDATE SKIP LOCKED`.
2. Publica cada mensaje en NATS JetStream en el subject del módulo.
3. Espera confirmación durable del broker (PubAck).
4. Actualiza `published_at` en la misma transacción o en actualización posterior.
5. Aplica backoff exponencial con jitter ante errores transitorios del broker.
6. Registra errores sin exponer payloads sensibles.

**Subjects NATS:** `<backend>.<modulo>.<event_type>.<version>`
Ejemplo: `public.sales.order_created.v1`

Cada módulo publica solo en sus subjects propios. Ningún módulo publica en subjects ajenos.

---

## 5. Saga: estructura de estado

El coordinador de una Saga persiste su estado en su propio schema.

```sql
-- Diseño de referencia; no ejecutar sin autorización expresa
CREATE TABLE <schema>.sagas (
    id              uuid        NOT NULL DEFAULT uuidv7(),
    saga_type       text        NOT NULL,       -- tipo de flujo de negocio
    tenant_id       uuid        NOT NULL,
    state           text        NOT NULL,       -- pending | running | completed | failed | compensating | compensated | intervention_required
    current_step    text,
    context         jsonb       NOT NULL,       -- datos del flujo; sin secretos
    started_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    completed_at    timestamptz,
    CONSTRAINT sagas_pkey PRIMARY KEY (id)
);
```

**Estados de Saga:**

| Estado | Descripción |
|---|---|
| `pending` | Creada; aún no iniciada |
| `running` | En ejecución; pasos en progreso |
| `completed` | Todos los pasos completados exitosamente |
| `failed` | Falló sin compensación posible o no iniciada |
| `compensating` | Ejecutando compensaciones |
| `compensated` | Compensaciones completadas |
| `intervention_required` | Requiere intervención manual; no puede progresar automáticamente |

**Reglas:**

- El coordinador vive en el módulo propietario del proceso de negocio (ej. SALES para flujo de pedido).
- Los participantes (PAYMENTS, INVENTORY, KITCHEN) no conocen la Saga; solo reciben y responden comandos.
- El estado de la Saga se actualiza dentro de transacciones locales del coordinador.
- Cada transición de estado es idempotente respecto al `saga_id`.

---

## 6. Flujo de referencia completo

```
1. Módulo coordinador recibe solicitud
   └── Valida invariantes propios
   └── Crea Saga en estado `pending`
   └── Escribe Outbox con primer comando
   └── Actualiza Saga a `running`
   └── COMMIT (Saga + Outbox en una transacción)

2. Dispatcher publica comando → NATS JetStream

3. Módulo participante consume comando
   └── Registra en Inbox (deduplicación)
   └── Aplica efecto local
   └── Escribe Outbox con evento de resultado
   └── COMMIT (Inbox + efecto + Outbox en una transacción)
   └── ACK al broker

4. Dispatcher del participante publica resultado

5. Coordinador consume resultado
   └── Registra en Inbox
   └── Actualiza estado de Saga
   └── Escribe Outbox con siguiente comando (si hay más pasos)
   └── COMMIT
   └── ACK al broker

6. Repetir hasta completar, fallar o requerir compensación
```

---

## 7. Compensación

- Una compensación es un nuevo comando de negocio; no revierte transacciones.
- Se registra con referencia al paso original y es idempotente.
- El coordinador gestiona el orden de compensaciones en reverso o según las reglas del dominio.
- Si un efecto no puede compensarse, el estado pasa a `intervention_required`.
- Las compensaciones se auditan con el mismo rigor que los efectos originales.

---

## 8. Idempotencia y resultados inciertos

| Situación | Acción |
|---|---|
| Timeout después de enviar comando | No asumir que el participante no ejecutó; consultar por `command_id` |
| Resultado duplicado recibido | Detectar por Inbox; devolver éxito silencioso |
| Redelivery del comando | Detectar por Inbox; sin efecto duplicado |
| Resultado desconocido tras timeout | Esperar redelivery del broker o reconciliar manualmente |

La clave idempotente identifica una intención de negocio concreta. No se reutiliza para intenciones distintas.

---

## 9. Estado de implementación

Diseño aprobado. No existen tablas, workers, dispatchers, consumers ni código implementado.
Cada módulo crea sus tablas Outbox/Inbox como parte de su migración inicial autorizada,
comenzando en la subfase 1.1 (PLATFORM) y 1.3 (IDENTITY).
