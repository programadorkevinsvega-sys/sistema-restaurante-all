# Arquitectura de Restaurant OS

**Estado:** vigente. **Base:** [Estándar general](./engineering-standard.md). **Requisitos:** [requisitos.md](../../requisitos.md). **Fases:** [ROADMAP.md](../../ROADMAP.md).

## 1. Propósito

Especializa el estándar para Restaurant OS. No puede reducir sus garantías. Las instrucciones operativas están en [Reglas de implementación](../engineering/implementation-rules.md).

## 2. Precedencia documental

1. Estándar general: mínimo obligatorio.
2. Arquitectura de Restaurant OS: puede especializar o endurecerlo, nunca debilitarlo.
3. Reglas de implementación: operacionalizan los anteriores, no los redefinen.
4. ADR aceptados: registran decisiones concretas y desviaciones autorizadas.

Una contradicción no se resuelve por interpretación del agente. Se propone un ADR y requiere aprobación humana explícita. Toda desviación debe registrar fecha, motivo, alcance, consecuencias, mitigación y responsable. Ningún documento inferior puede anular silenciosamente una regla superior.

## 3. Estilo arquitectónico

- Monolito modular Rust inicialmente, preparado para separar módulos por razón medible.
- PostgreSQL compartido inicialmente, con ownership y permisos por módulo.
- Stateless y multi-réplica desde el inicio.
- No crear microservicios, brokers o infraestructura por moda.
- La composición se realiza en un punto controlado.
- La ubicación física del crate no cambia la propiedad lógica del dominio.

## 4. Dominios

Core: PLATFORM, IDENTITY, ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, INVENTORY, PROCUREMENT, BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS, AUDIT y REPORTING. tenancy es soporte, no dominio propietario.

Restaurant vertical: KITCHEN y PRODUCTION. Consume contratos de Core y no recrea ni escribe entidades propietarias de Core.

## 5. Persistencia y ownership

- Cada módulo posee un schema PostgreSQL y sus objetos.
- Cada módulo tiene rol PostgreSQL dedicado con privilegios limitados a su schema. Separar identidad de migración y runtime; runtime sin DDL ni privilegios globales.
- Cada módulo mantiene su directorio de migraciones y su tabla de historial SQLx exclusiva, schema-qualified (por ejemplo, `identity._sqlx_migrations`). Nunca se comparte una tabla de historial entre módulos. La ruta canónica futura es `backend/<backend>/modules/<modulo>/migrations/`; las ubicaciones existentes se documentan como históricas.
- FKs y consultas directas solo dentro del mismo límite de propiedad. No FKs, joins, vistas ni consultas directas entre schemas de módulos distintos.
- Referencias cross-module mediante IDs estables y contratos. Proyecciones locales solo si son propiedad del consumidor y se alimentan por eventos.
- No reescribir migraciones históricas potencialmente aplicadas; usar migraciones nuevas y plan de transición.

## 6. APIs, contratos y frontends

- OpenAPI es la fuente de verdad HTTP; Protobuf versionado es la fuente de verdad gRPC.
- OpenAPI genera tipos/clientes HTTP para frontends y BFF; Protobuf genera stubs/tipos gRPC para backends y BFF.
- El código generado no se edita a mano. CI regenera y falla si hay diferencias con el generado versionado.
- Frontends independientes consumen contratos; no alojan reglas autoritativas. La autorización efectiva es backend.
- `api-server` aloja los módulos backend y expone gRPC. El BFF es un proceso independiente que consume gRPC y expone HTTP/OpenAPI a los frontends.
- Docker Compose define dos servicios de aplicación objetivo: `api-server` y `bff`. Esta topología no implica microservicios por módulo ni afirma que el despliegue ya esté implementado.
- gRPC entre `api-server` y BFF es obligatorio desde el inicio. Solo se difiere el transporte gRPC para módulos internos que comparten el proceso `api-server`.

## 7. Comunicación y ejecución asíncrona

- Consulta/comando local mediante contrato/puerto entre módulos dentro de `api-server`; gRPC entre `api-server` y BFF desde el inicio y entre servicios separados.
- Hechos ya ocurridos mediante eventos durables versionados.
- Outbox atómico con el cambio de negocio.
- Sin broker, dispatcher con FOR UPDATE SKIP LOCKED; con broker, confirmaciones durables y grupos de consumidores.
- Inbox/deduplicación e idempotencia en la misma transacción local que los efectos persistentes.
- Efectos externos con claves idempotentes, Outbox adicional o reconciliación/compensación.
- Jobs periódicos con advisory lock PostgreSQL, lease exclusivo recuperable o elección de líder.
- No prometer exactly-once extremo a extremo.

## 8. Stateless y escalado

No mantener sesiones, colas durables ni estado de negocio solo en memoria local. Usar almacenamiento compartido, readiness/liveness, apagado ordenado, límites de concurrencia, recuperación de leases y despliegues graduales compatibles. Docker facilita entornos reproducibles, pero no demuestra escalabilidad: también hacen falta estado externo, pools acotados, coordinación de jobs, Outbox/Inbox, idempotencia y observabilidad.

## 9. Observabilidad

OpenTelemetry y W3C Trace Context. traceparent es el portador canónico; tracestate se propaga cuando aplique. trace_id es el componente trace-id de traceparent y no se cambia al continuar el flujo. Propagar por headers HTTP, metadata gRPC y envelope de eventos (traceparent y tracestate opcional), incluidos Outbox/Inbox/workers. La traza no sustituye tenant, actor, autorización ni idempotencia.

## 10. ADR aceptados

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](../adr/0001-postgres-module-ownership-and-migrations.md)
- [ADR-0002: OpenAPI, Protobuf y código generado](../adr/0002-openapi-protobuf-generated-clients.md)
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](../adr/0003-stateless-outbox-inbox-and-jobs.md)
- [ADR-0004: W3C Trace Context en todos los contratos](../adr/0004-w3c-trace-context.md)
- [ADR-0005: Contratos Protobuf y gRPC desde el inicio](../adr/0005-grpc-contracts-from-day-one.md)
- [ADR-0006: AI como capacidad transversal sin schema propio en esta etapa](../adr/0006-ai-cross-cutting-capability-no-owned-schema.md)

## 11. Estado de implementación

Son decisiones arquitectónicas, no evidencia de que crates, roles, generadores, CI, telemetría o despliegues estén implementados. Informar por separado lo planificado, implementado y verificado.
