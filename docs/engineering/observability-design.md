# Estrategia de observabilidad — subfase 0.8

**Estado:** diseño aprobado — subfase 0.8
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.8
**Autoridad:** ADR-0004, ADR-0015
**Base:** [Estrategia técnica de observabilidad integral](../architecture/observability-strategy.md)
**Documentos relacionados:**

- [Catálogo de eventos auditables](./audit-events-catalog.md)
- [Matriz de alertas](./alert-matrix.md)
- [Runbooks de respuesta a incidentes](./incident-response-runbooks.md)

---

## 1. Propósito

Concreta el diseño de instrumentación para los cuatro procesos de Restaurant OS.
Es un diseño; no instala SDKs, Collectors, exporters ni dashboards.

---

## 2. Stack de observabilidad

| Componente | Rol | Notas |
|---|---|---|
| OpenTelemetry SDK (Rust) | Instrumentación en los cuatro procesos | Crate `opentelemetry` + exporters |
| OpenTelemetry Collector | Recepción, filtrado, redacción y exportación | Desplegado en zona `observability` |
| Prometheus | Scraping y almacenamiento de métricas | Pull desde procesos y exporters |
| Alertmanager | Agrupación, deduplicación y enrutamiento de alertas | — |
| Loki | Ingesta y consulta de logs estructurados | — |
| Tempo | Almacenamiento y consulta de trazas | — |
| Grafana | Dashboards, exploración y correlación | Acceso solo desde zona `ops` |
| Exporters | pg_exporter, redis_exporter, nats_exporter, node_exporter | Cuentas de solo lectura |

---

## 3. Atributos de identidad de servicio

Cada señal (log, métrica, traza) lleva estos atributos:

| Atributo | Valor |
|---|---|
| `service.name` | `admin-platform-backend` / `admin-bff` / `public-bff` / `public-backend` |
| `service.namespace` | `restaurant-os` |
| `service.version` | Commit SHA o tag desplegado |
| `deployment.environment` | `production` / `staging` / `development` |
| `module` | Módulo propietario cuando aplique (atributo acotado, no label de métrica) |

No incluir como atributos: `tenant_id`, `user_id`, `email`, IDs de pedido, tokens ni payloads.

---

## 4. Instrumentación por capa

### 4.1 HTTP (BFF)

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por request: método, ruta normalizada, status, duración |
| Métrica | `http_requests_total{method, route, status}`, `http_request_duration_seconds` |
| Log | Entrada por request: método, ruta, status, duración, `request_id`, `trace_id` |

Ruta normalizada: sin IDs en la ruta (ej. `/v1/catalog/products/:id`, no el UUID real).

### 4.2 gRPC (entre procesos)

| Señal | Qué instrumentar |
|---|---|
| Traza | Span cliente y servidor: servicio, método, status gRPC, duración |
| Métrica | `grpc_client_requests_total`, `grpc_server_requests_total`, duración por método |
| Log | Errores y operaciones lentas; no loguear payloads |

### 4.3 Módulos (operaciones de dominio)

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por operación de aplicación: nombre de operación estable, resultado |
| Métrica | `module_operations_total{module, operation, result}`, duración |
| Log | Errores con `trace_id`, `request_id`, módulo y operación; sin datos de negocio sensibles |

### 4.4 PostgreSQL (por pool de módulo)

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por consulta: nombre de operación normalizado, duración, éxito/error |
| Métrica | Conexiones (max, open, idle, acquired), tiempo de adquisición, errores, consultas lentas (agregado) |
| Exporter | `pg_exporter` con rol `monitoring_reader`; sin DDL ni escritura |

No incluir SQL dinámico, parámetros ni valores como atributos de span o labels.

### 4.5 NATS Core y JetStream

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por publicación/consumo: subject normalizado, resultado |
| Métrica | Mensajes publicados/consumidos, latencia, errores, consumer lag, pending ACK |
| Propagación | `traceparent` en metadata del mensaje (ADR-0004) |

### 4.6 Redis

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por operación: familia de comando, duración |
| Métrica | Hit/miss, latencia, errores; via `redis_exporter` con ACL de solo lectura |

### 4.7 Workers y Outbox/Inbox

| Señal | Qué instrumentar |
|---|---|
| Traza | Span por mensaje procesado; link al span original del productor si aplica |
| Métrica | Workers activos, mensajes procesados, reintentos, DLQ, antigüedad de Outbox pendiente |
| Log | Errores con `event_id`, `tenant_id` (solo operativamente necesario), resultado |

---

## 5. Propagación W3C Trace Context

Conforme a ADR-0004, `traceparent` se propaga en:

- Headers HTTP (`traceparent`, `tracestate`).
- Metadata gRPC.
- Envelope de mensajes NATS/JetStream (`metadata.traceparent`).
- Registros Outbox/Inbox (campo `metadata.trace_id`).

No reconstruir ni reemplazar un contexto válido entrante. Para operaciones asíncronas que inician una nueva traza, usar **span links** para representar causalidad sin forzar una única traza artificial.

---

## 6. Logs estructurados — esquema mínimo

```json
{
  "timestamp": "2026-11-25T10:00:00.123Z",
  "level": "ERROR",
  "message": "operation_failed",
  "service": "public-backend",
  "module": "sales",
  "operation": "create_order",
  "result": "failed",
  "error_code": "domain.rule_violation",
  "trace_id": "00-...",
  "span_id": "...",
  "request_id": "01932e4a-...",
  "duration_ms": 45
}
```

**Nunca incluir en logs:** contraseñas, tokens, cookies, hashes de credenciales, datos de pago, payloads completos, secretos de proveedores, SQL con parámetros reales.

---

## 7. Redacción en el Collector

El Collector aplica redacción antes de exportar a Loki/Tempo:

- Patrones de tokens Bearer, API keys, DSN strings.
- Números de tarjeta (regex PAN).
- Emails cuando no sean necesarios operativamente.
- Atributos en allowlist explícita; todo lo demás se descarta o redacta.

---

## 8. Muestreo de trazas

| Tipo de traza | Estrategia |
|---|---|
| Errores (cualquier status ≥ 500 / gRPC error) | 100% |
| Operaciones críticas (pagos, cobros, login) | 100% |
| Latencia anómala (p99 > umbral) | 100% |
| Resto en producción | Probabilístico configurable (ej. 10%) |
| Desarrollo / staging | 100% |

El muestreo nunca altera el procesamiento de negocio.

---

## 9. Dashboards mínimos requeridos

| Dashboard | Señales |
|---|---|
| Sistema general | Disponibilidad, tráfico, errores y latencia p99 por proceso |
| Cuatro procesos | Salud, saturación y dependencias de cada proceso |
| PostgreSQL | Pools por módulo, conexiones, locks, deadlocks, lag de réplica |
| NATS/JetStream | Streams, consumers, lag, pending ACK, redeliveries |
| Redis | Memoria, hit ratio, latencia, evictions |
| Workers / mensajería | Outbox/Inbox backlog, antigüedad, DLQ, Sagas requiriendo intervención |
| Observabilidad | Salud del Collector, ingestión, almacenamiento y retención |

---

## 10. Retención

| Señal | Producción | Staging | Desarrollo |
|---|---|---|---|
| Métricas | A definir por política (mín. 30 días) | 7 días | 2 días |
| Logs | A definir por política y regulación | 7 días | 2 días |
| Trazas | A definir (mín. 7 días) | 3 días | 1 día |

Los valores exactos se aprueban como parte de la política de retención conforme a ADR-0018.

---

## 11. Estado de implementación

Diseño aprobado. No existen SDKs configurados, Collectors desplegados, exporters
instalados ni dashboards creados. La implementación comienza en la fase de
despliegue de infraestructura base (subfase 0.7 completa).
