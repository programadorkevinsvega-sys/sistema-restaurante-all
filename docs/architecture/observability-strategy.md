# Estrategia técnica de observabilidad integral

**Estado:** especificación propuesta vinculada a [ADR-0015](../adr/0015-integrated-observability-platform.md).  
**Ámbito:** los cuatro procesos, módulos, workers, PostgreSQL, NATS Core/JetStream, Redis y recursos de infraestructura.  
**Decisiones relacionadas:** ADR-0003, ADR-0004, ADR-0007, ADR-0010, ADR-0013 y ADR-0015.

## 1. Objetivo

La observabilidad debe responder tres preguntas: logs, qué ocurrió; métricas, cuándo comenzó el problema y cuánto afecta; trazas, qué pasos recorrió una operación y dónde consumió tiempo o falló.

Debe cubrir aplicaciones y dependencias, no solo endpoints HTTP. Una petición puede atravesar un BFF, un backend, varios módulos, PostgreSQL, Redis, NATS/JetStream, workers y proveedores externos.

Esta especificación no cambia ownership de módulos, schemas, roles, migraciones ni datos. No habilita consultas cruzadas entre schemas.

## 2. Arquitectura lógica

| Componente | Responsabilidad |
|---|---|
| OpenTelemetry SDK/API | Instrumentación y convenciones comunes. |
| OpenTelemetry Collector | Recepción, procesamiento, filtrado, batching y exportación. |
| Prometheus | Scraping y almacenamiento de métricas. |
| Alertmanager | Agrupar, deduplicar y enrutar alertas. |
| Loki | Ingesta y consulta de logs estructurados. |
| Tempo | Almacenamiento y consulta de trazas distribuidas. |
| Grafana | Dashboards, exploración y correlación entre fuentes. |
| Exporters | Métricas específicas de PostgreSQL, Redis, NATS y host/contenedor. |

Flujo lógico:

~~~text
Admin Platform Backend ─┐
Admin BFF ───────────────┤
Public BFF ──────────────┼── OpenTelemetry ── Collector ──┬── Tempo (traces)
Public Backend ──────────┤                                ├── Loki (logs)
Workers / jobs ──────────┘                                └── Prometheus (metrics*)

PostgreSQL ── exporter / métricas ────────────────> Prometheus
Redis ─────── exporter / métricas ────────────────> Prometheus
NATS Core ─── exporter / monitoring ──────────────> Prometheus
JetStream ─── métricas de streams/consumers ──────> Prometheus
Host/containers ── exporters ─────────────────────> Prometheus

Prometheus ─┐
Loki ───────┼── Grafana
Tempo ──────┘

Prometheus alert rules ── Alertmanager ── canales de notificación
~~~

metrics* indica que las métricas de aplicación podrán exponerse para scraping de Prometheus o enviarse mediante un pipeline compatible; el mecanismo final se fijará al seleccionar versiones y topología. No duplicar recolección sin razón operativa.

## 3. Identidad de servicio y atributos comunes

Cada señal identificará de forma consistente:

- service.name: nombre estable del proceso desplegable.
- service.namespace: agrupación del producto/entorno según convención definida.
- service.version: versión o commit desplegado cuando esté disponible.
- deployment.environment: entorno.
- module: módulo propietario cuando aplique, como atributo acotado.
- operation: nombre normalizado, nunca valores dinámicos.
- trace_id y span_id: solo para logs/trazas; nunca como etiquetas de métricas.

Los nombres definitivos se mantendrán en un catálogo de servicios para evitar alias diferentes entre señales, dashboards y alertas.

No añadir nombres, emails, tokens, IDs de usuario, IDs de pedido o payloads como atributos automáticamente. Tenant ID solo se incluirá cuando exista necesidad operativa aprobada, con controles de acceso y sin usarlo como label de métricas de alta cardinalidad.

## 4. Logs

### 4.1 Esquema mínimo

Los logs serán estructurados y contendrán, según disponibilidad:

- timestamp UTC;
- severity/level;
- mensaje o nombre de evento estable;
- service, environment y module;
- operation y resultado;
- trace_id y span_id;
- request_id, correlation_id y causation_id;
- saga_id, command_id o event_id cuando corresponda;
- código de error normalizado y duración cuando aplique.

No duplicar payloads completos. Los errores deben ser útiles sin revelar datos privados.

### 4.2 Niveles y uso

- ERROR: operación fallida que requiere diagnóstico.
- WARN: condición anómala recuperable, degradación o reintento.
- INFO: transición operativa relevante.
- DEBUG/TRACE: diagnóstico temporal, deshabilitado o limitado en producción por defecto.

Evitar logs por cada iteración de polling o mensaje exitoso si generan ruido; usar métricas para volumen y tasas. Los logs no reemplazan auditoría de negocio.

### 4.3 Protección

Redactar secretos y datos personales antes de exportar. Nunca registrar contraseñas, access/refresh tokens, cookies, claves, credenciales, números completos de tarjetas ni secretos de proveedores. Evitar SQL con parámetros, bodies HTTP y payloads NATS sin sanitización.

## 5. Métricas de aplicaciones y procesos

Usar RED para servicios: Rate, Errors, Duration. Usar USE para recursos: Utilization, Saturation, Errors.

Cobertura mínima por proceso y módulo:

- solicitudes HTTP/gRPC: volumen, status, duración, timeouts y concurrencia;
- operaciones de módulos: duración y resultado por operación normalizada;
- runtime: CPU, memoria, threads/tasks, pausas y reinicios según runtime;
- workers: activos, capacidad, duración, fallos, reintentos y backlog;
- dependencias: latencia, errores, timeouts y disponibilidad;
- BFF: solicitudes entrantes y llamadas salientes por destino lógico;
- jobs: ejecuciones, duración, vencimientos y fallos.

### 5.1 PostgreSQL y SQLx

Por cada pool lógico de módulo, sin fusionar pools:

- conexiones máximas, abiertas, idle y adquiridas;
- solicitudes esperando conexión;
- tiempo de adquisición y timeouts;
- conexiones descartadas y errores;
- transacciones y duración;
- consultas lentas agregadas y errores;
- locks, deadlocks y esperas;
- checkpoints, WAL, vacuum/autovacuum, bloat/capacidad y replicación si existe.

Usar métricas PostgreSQL y vistas estadísticas adecuadas a la versión objetivo. pg_stat_statements puede evaluarse para análisis agregado de consultas, manteniendo parámetros sensibles fuera de logs y resultados. Habilitar extensiones/configuración se decidirá durante implementación y no autoriza editar SQL en esta fase.

No instrumentar consultas con labels que contengan SQL dinámico, parámetros, IDs o texto libre. Las métricas de pool deben identificar módulo y proceso con cardinalidad acotada.

### 5.2 NATS Core y JetStream

NATS Core:

- conexiones y reconexiones;
- suscripciones;
- mensajes y bytes entrantes/salientes;
- errores, slow consumers y actividad del servidor;
- CPU, memoria y capacidad.

JetStream, además:

- streams y consumers;
- mensajes y bytes almacenados;
- límites y uso de almacenamiento;
- pending/unacknowledged;
- delivered, acked y redelivered;
- consumer lag y antigüedad del mensaje más antiguo pendiente;
- errores de publicación/consumo, expiraciones y advisories;
- estado de réplicas/cluster cuando aplique.

Los nombres de streams/consumers son dimensiones acotadas y controladas. No crear una serie por mensaje, evento, tenant o ID de proceso. Exporters y endpoints administrativos se restringirán a red privada.

### 5.3 Redis

Cuando Redis esté presente:

- disponibilidad y latencia de comandos;
- conexiones, clientes bloqueados y errores;
- memoria usada, fragmentación y límites;
- hit/miss de caché;
- expiraciones y evictions;
- operaciones por familia de comandos, con nombres acotados;
- persistencia, snapshots/AOF y errores;
- replicación/failover cuando aplique.

No capturar valores, claves sensibles ni comandos completos con argumentos. El exporter usará ACL de solo lectura limitada a las métricas necesarias.

### 5.4 Host y contenedores

Medir CPU, memoria, disco, filesystem, I/O, red, límites/cgroups, reinicios, OOM kills y salud de contenedores. Los exporters identificarán host/instancia sin publicar topología privada en endpoints públicos.

## 6. Trazas distribuidas

### 6.1 Instrumentación

Crear spans para entrada/salida HTTP, servidor/cliente gRPC, operaciones relevantes de módulos y adaptadores, consultas PostgreSQL, comandos Redis, publicación/consumo NATS Core y JetStream, Outbox, Inbox, workers y proveedores externos.

Evitar un span por cada función trivial o acceso interno sin valor diagnóstico. Usar nombres de operación estables y atributos semánticos compatibles con OpenTelemetry.

### 6.2 Propagación

Aplicar ADR-0004: W3C Trace Context por headers HTTP, metadata gRPC y envelopes de mensajes. Outbox/Inbox y workers conservarán el contexto. No reconstruir traceparent desde IDs propios ni reemplazar un contexto válido.

Para procesos asíncronos que no deban continuar la misma traza, usar span links y correlation/causation IDs para representar causalidad sin forzar una única traza artificial.

### 6.3 Muestreo

Configurar sampling por entorno y volumen. Priorizar trazas con errores, latencias anómalas y operaciones críticas mediante políticas compatibles con la arquitectura Collector/Tempo elegida. El muestreo nunca alterará el procesamiento de negocio. No prometer que todas las peticiones tendrán una traza almacenada.

## 7. Dashboards y alertas

Dashboards iniciales:

1. Vista del sistema: disponibilidad, tráfico, errores y latencia por proceso.
2. Cuatro procesos: salud y saturación de Admin Platform Backend, Admin BFF, Public BFF y Public Backend.
3. Módulos: operaciones, errores, duración y dependencias por módulo.
4. PostgreSQL: salud, pools por módulo, conexiones, locks, deadlocks, consultas y capacidad.
5. NATS/JetStream: conexiones, streams, consumers, backlog, pending ACK, redeliveries, lag y almacenamiento.
6. Redis: disponibilidad, memoria, hit ratio, latencia, evictions y conexiones.
7. Workers y mensajería: Outbox/Inbox, jobs, reintentos, DLQ/cuarentena y procesos estancados.
8. Observabilidad: Collector, Prometheus, Alertmanager, Loki, Tempo, Grafana, ingestión y almacenamiento.

Alertas candidatas:

- tasa de errores o latencia por encima de SLO;
- proceso o dependencia no disponible;
- saturación/agotamiento de pool SQLx;
- bloqueos/deadlocks o consultas lentas sostenidas;
- JetStream con lag, pending ACK, redelivery o almacenamiento creciente;
- Outbox/Inbox con antigüedad o backlog anómalo;
- worker sin progreso o Saga que requiere intervención;
- Redis con memoria crítica, evictions inesperadas o latencia elevada;
- pérdida de ingestión o falta de datos de telemetría;
- filesystem/almacenamiento próximo a agotarse.

Los umbrales se derivarán de SLOs, carga medida y criticidad; no se fijan valores arbitrarios. Toda alerta tendrá severidad, propietario, runbook y condición de resolución.

## 8. Seguridad, aislamiento y cardinalidad

- Scraping y endpoints de diagnóstico solo por redes privadas y con autenticación donde corresponda.
- Exporters con cuentas de monitoreo de mínimo privilegio.
- PostgreSQL: rol de monitoreo separado, solo estadísticas autorizadas; sin DDL ni escritura.
- Redis: usuario ACL dedicado.
- NATS: credenciales de monitoreo y endpoints administrativos protegidos.
- Dashboards y exploración con RBAC; no todos los operadores necesitan acceso a logs/trazas con datos de tenant.
- Redactar datos sensibles antes de ingestión, no solo en el dashboard.
- No usar IDs únicos, valores libres, URLs completas, SQL dinámico ni nombres arbitrarios como labels.
- Separar ambientes y aplicar retención según clasificación.

## 9. Resiliencia y costos

- SDKs y Collectors usarán buffers/colas acotados, batching, timeouts, límites de memoria y backpressure.
- La indisponibilidad de telemetría no debe provocar indisponibilidad de flujos de negocio.
- Definir política de descarte al alcanzar límites; priorizar señales críticas y evitar crecimiento ilimitado.
- Muestrear trazas según error/latencia/entorno y limitar spans.
- Controlar volumen de logs y cardinalidad de métricas.
- Establecer retención separada para métricas, logs y trazas.
- Monitorear ingestión, retrasos, errores, colas, disco y salud de la plataforma.

## 10. Pruebas de aceptación futuras

Antes de considerar observabilidad implementada, demostrar:

1. Una solicitud HTTP puede seguirse desde el BFF al backend, módulo y dependencias.
2. W3C se conserva a través de gRPC, NATS, Outbox/Inbox y workers.
3. Una traza localiza el span lento en PostgreSQL, Redis o proveedor externo.
4. Los logs asociados se encuentran desde trace ID sin exponer secretos ni datos personales.
5. Las métricas identifican degradación y saturación sin cardinalidad descontrolada.
6. PostgreSQL, Redis, NATS Core y JetStream muestran métricas de salud/capacidad y alertan ante fallos relevantes.
7. Las credenciales de exporters no permiten modificar datos ni administrar servicios.
8. Dashboards y consultas respetan aislamiento de acceso entre entornos y tenants.
9. Si Collector o backend de telemetría falla, el negocio sigue con límites de buffering y descarte.
10. Se verifica carga y costo de instrumentación bajo tráfico representativo.

## 11. Estado

Esta especificación es propuesta y no demuestra despliegue ni implementación. No crear contenedores, manifests, exporters, crates, dependencias, dashboards, alertas, roles PostgreSQL ni configuraciones en esta fase. Cualquier cambio de SQL/migraciones requiere autorización expresa y tarea separada.
