# Architecture Decision Records

Cada decisión se registra en un ADR independiente. El flujo es Proposed → Accepted. Una sugerencia de agente o un cambio documental sin aprobación explícita no constituye aceptación.

Cada ADR incluye contexto, decisión, alternativas, consecuencias, fechas y aprobación. Toda desviación del estándar registra motivo, alcance, riesgos, mitigaciones y condición de revisión.

## Decisiones aceptadas

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](./0001-postgres-module-ownership-and-migrations.md)
- [ADR-0002: OpenAPI, Protobuf y código generado](./0002-openapi-protobuf-generated-clients.md)
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](./0003-stateless-outbox-inbox-and-jobs.md)
- [ADR-0004: W3C Trace Context en todos los contratos](./0004-w3c-trace-context.md)
- [ADR-0005: Contratos Protobuf y gRPC desde el inicio (topología sustituida parcialmente por ADR-0007)](./0005-grpc-contracts-from-day-one.md)
- [ADR-0006: AI como capacidad transversal sin schema propio en esta etapa](./0006-ai-cross-cutting-capability-no-owned-schema.md)
- [ADR-0007: Cuatro backends independientes y comunicación](./0007-four-independent-backends-and-communication.md)
- [ADR-0008: Distribución de módulos entre los cuatro procesos](./0008-module-ownership-across-four-processes.md)
- [ADR-0009: Límites de crates y dirección de dependencias](./0009-crate-boundaries-and-dependencies.md)
- [ADR-0010: PostgreSQL Connection Pooling y gestión de recursos](./0010-postgresql-connection-pooling-and-resource-management.md)
- [ADR-0011: Protección de contraseñas y controles de autenticación](./0011-password-hashing-and-authentication-security.md)
- [ADR-0012: UUIDv7 global y PostgreSQL como plataforma HA con réplicas de lectura](./0012-uuid-v7-global-identifiers-and-postgresql.md)
- [ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos](./0013-distributed-transactions-and-saga-consistency.md)
- [ADR-0014: Baja de tenants y conservación de datos de clientes](./0014-tenant-deletion-and-customer-data-preservation.md)
- [ADR-0015: Observabilidad integral de aplicaciones e infraestructura](./0015-integrated-observability-platform.md)
- [ADR-0016: Redis Cluster, TLS y caché distribuida de consultas](./0016-redis-cluster-tls-and-query-caching.md)
- [ADR-0017: NATS Core y JetStream en clúster de alta disponibilidad](./0017-nats-core-jetstream-ha-cluster.md)
- [ADR-0018: Privacidad, retención de datos, términos legales y consentimiento de cookies](./0018-privacy-data-retention-legal-terms-and-cookie-consent.md)

## Decisiones propuestas

- [ADR-0019: Validación de entradas, contratos y protección de integridad de datos](./0019-input-validation-and-data-integrity.md) — define validación en todas las fronteras, reglas por módulo, tipos, formatos, límites, normalización, errores, archivos, URLs, seguridad multi-tenant, concurrencia y pruebas.

El diseño técnico de crates y dependencias está en [Diseño de crates y dependencias](../architecture/crate-architecture.md). La estrategia técnica de UUIDv7 está en [Estrategia técnica de identificadores UUIDv7 y PostgreSQL](../architecture/identifier-strategy.md), y la operación de alta disponibilidad y réplicas está en [PostgreSQL HA y réplicas de lectura](../architecture/postgresql-ha-and-read-replicas.md). La estrategia técnica de consistencia distribuida está en [Estrategia técnica de consistencia distribuida y Sagas](../architecture/distributed-transaction-consistency.md). La estrategia técnica de observabilidad está en [Estrategia técnica de observabilidad integral](../architecture/observability-strategy.md). La operación de caché está en [Redis Cluster, TLS y operación de caché distribuida](../architecture/redis-cache-operations.md). La operación de mensajería está en [NATS Core y JetStream en clúster](../architecture/nats-core-jetstream-cluster.md).

Los ADR aceptados son decisiones arquitectónicas aprobadas; los ADR propuestos requieren aprobación explícita. La aceptación de un ADR no significa que sus componentes, controles, infraestructura, migraciones o código estén implementados.
