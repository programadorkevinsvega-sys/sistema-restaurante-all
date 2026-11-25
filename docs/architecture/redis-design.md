# Diseño de Redis Cluster y política de caché — subfase 0.9

**Estado:** diseño aprobado — subfase 0.9
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.9
**Autoridad:** ADR-0016
**Base:** [Redis Cluster, TLS y operación de caché](./redis-cache-operations.md)
**Documentos relacionados:**

- [Diseño NATS](./nats-design.md)
- [Diseño PostgreSQL HA](./postgresql-ha-design.md)
- [Presupuesto de conexiones](./connection-budget.md)

---

## 1. Topología objetivo

- Redis Cluster con mínimo 3 primarios y 1 réplica por primario (6 nodos).
- Distribución de primarios entre dominios de fallo independientes.
- TLS obligatorio en todas las conexiones (cliente, replicación, cluster bus).
- ACL separada por proceso/módulo; sin usuario `default` habilitado.
- Endpoints en zona `data` (red privada); sin exposición pública.

---

## 2. ACL por proceso

| Usuario ACL | Proceso | Comandos permitidos | Prefijo de claves |
|---|---|---|---|
| `platform_cache` | Admin Platform Backend | GET, SET, DEL, EXPIRE, EXISTS, TTL | `prod:cache:platform:*` |
| `identity_cache` | Public Backend / IDENTITY | GET, SET, DEL, EXPIRE, EXISTS, TTL | `prod:cache:identity:*` |
| `catalog_cache` | Public Backend / CATALOG | GET, SET, DEL, EXPIRE, EXISTS, TTL | `prod:cache:catalog:*` |
| `analytics_cache` | Public Backend / ANALYTICS | GET, SET, DEL, EXPIRE, EXISTS, TTL | `prod:cache:analytics:*` |
| `reporting_cache` | Public Backend / REPORTING | GET, SET, DEL, EXPIRE, EXISTS, TTL | `prod:cache:reporting:*` |
| `invalidator` | Worker de invalidación | DEL, EXISTS | `prod:cache:*` (invalidación cross-módulo cuando aplique) |
| `monitoring` | redis_exporter | INFO, LATENCY, CLIENT, MEMORY, CLUSTER, SLOWLOG | Sin acceso a claves de negocio |

Módulos sin pool de caché no tienen usuario ACL en Redis.

---

## 3. Formato de clave

```text
{env}:cache:{modulo}:{operacion}:v{version}:{scope}:{digest}
```text
| Segmento | Descripción |
|---|---|
| `{env}` | `prod` / `staging` / `dev` |
| `{modulo}` | Módulo propietario en minúsculas |
| `{operacion}` | Nombre estable de la operación (ej. `list_products`) |
| `v{version}` | Versión del esquema del resultado cacheado |
| `{scope}` | Hash del contexto: `tenant_id` + filtros que cambian el resultado |
| `{digest}` | Hash de los parámetros de la consulta |

**Reglas:**

- Sin PII, tokens, contraseñas ni datos sensibles en claro en la clave.
- El `{scope}` incluye `tenant_id` siempre; nunca compartir entrada entre tenants.
- Longitud máxima de clave: 512 bytes; preferir < 128 bytes.
- Valores serializados con formato versionado (ej. MessagePack o JSON con campo `_v`).

---

## 4. Catálogo de consultas cacheables

Consultas elegibles iniciales. Cada una tiene TTL, staleness máxima y evento de invalidación.

| Módulo | Operación | TTL | Staleness máxima | Evento de invalidación |
|---|---|---|---|---|
| CATALOG | `list_products` | 60 s | 60 s | `catalog.product.created/updated/deleted.v1` |
| CATALOG | `get_product` | 120 s | 120 s | `catalog.product.updated/deleted.v1` |
| CATALOG | `list_categories` | 300 s | 300 s | `catalog.category.created/updated/deleted.v1` |
| ANALYTICS | `dashboard_summary` | 300 s | 300 s | Ninguno (expiración por TTL) |
| REPORTING | `report_data` | 600 s | 600 s | Ninguno (expiración por TTL) |
| IDENTITY | `user_permissions` | 30 s | 30 s | `identity.user.role_assigned/revoked.v1` |

Los TTL son punto de partida; se ajustan con métricas de hit ratio y carga.
TTL con jitter: `TTL_base × (1 + random(0, 0.1))` para evitar expiraciones sincronizadas.

---

## 5. Flujo cache-aside por módulo

```text
1. Verificar autorización (siempre en módulo propietario, nunca en caché)
2. Construir clave determinista con scope de tenant/usuario/permisos
3. GET Redis (timeout corto: 50ms)
4. HIT → validar versión y tenant scope → retornar
5. MISS → consultar PostgreSQL (fuente autoritativa)
6. SET Redis con TTL + jitter (si la política permite cachear este resultado)
7. Retornar resultado
```text
**Reglas críticas:**

- Paso 1 siempre ocurre; nunca saltar autorización porque haya HIT en caché.
- Si Redis falla en paso 3: continuar al paso 5 sin error al cliente.
- Nunca escribir la caché dentro de una transacción PostgreSQL.
- Una carga iniciada antes de una invalidación no puede reinsertar el valor obsoleto
  si ya llegó el evento de invalidación (verificar versión antes de SET).

---

## 6. Invalidación durable

La invalidación de caché sigue el patrón Outbox → JetStream → Worker:

1. El módulo confirma cambio de negocio + intención de invalidación en Outbox (misma transacción).
2. El dispatcher publica al subject `prod.public.cache.invalidate.{modulo}.{recurso}.v1`.
3. El consumer `CACHE_invalidator_{modulo}` consume el mensaje desde el stream `CACHE_INVALIDATION`.
4. El worker ejecuta `DEL` sobre las claves afectadas (idempotente).
5. ACK al broker después de confirmar la invalidación.

**Por qué no usar solo NATS Core para invalidaciones:**
La pérdida de un mensaje Core dejaría datos obsoletos más allá de la staleness tolerada.
JetStream garantiza entrega durable y redelivery.

---

## 7. Fallback seguro

Cuando Redis no está disponible:

| Escenario | Comportamiento |
|---|---|
| Timeout de conexión (> 50ms) | Continuar directamente a PostgreSQL |
| Error de conexión | Abrir circuit breaker; seguir a PostgreSQL con límite de concurrencia |
| Circuit breaker abierto | Responder desde PostgreSQL; no intentar Redis hasta que el breaker se cierre |
| Caché fría tras failover | Calentamiento gradual; no avalancha simultánea de regeneraciones |

El fallback a PostgreSQL está limitado por el presupuesto de conexiones del pool.
Un pico de misses no puede agotar el pool SQLx del módulo.

---

## 8. Parámetros operativos pendientes de dimensionamiento

| Parámetro | Se fija con |
|---|---|
| Memoria por nodo y número de shards | Perfil de tráfico y TTL medidos |
| `maxmemory-policy` | Pruebas de eviction en staging (candidato: `allkeys-lfu`) |
| Timeout de cliente | Latencia p99 de Redis en staging |
| Umbral de circuit breaker | Tasa de errores medida |
| TTL exacto por operación | Hit ratio medido en staging |
| Conexiones máximas por usuario ACL | Instancias × threads del proceso |

---

## 9. Estado de implementación

Diseño aprobado. No existen nodos Redis desplegados, usuarios ACL creados, clientes
configurados ni consultas cacheadas. La implementación comienza con el aprovisionamiento
de infraestructura y los crates de los módulos elegibles.
