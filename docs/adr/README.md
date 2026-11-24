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
- [ADR-0012: UUID versión 7 como identificador técnico global y PostgreSQL estable actual](./0012-uuid-v7-global-identifiers-and-postgresql.md)
- [ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos](./0013-distributed-transactions-and-saga-consistency.md)
- [ADR-0014: Baja de tenants y conservación de datos de clientes](./0014-tenant-deletion-and-customer-data-preservation.md)

El diseño técnico de crates y dependencias está en [Diseño de crates y dependencias](../architecture/crate-architecture.md). La estrategia técnica de UUIDv7 y PostgreSQL está en [Estrategia técnica de identificadores UUIDv7 y PostgreSQL](../architecture/identifier-strategy.md). La estrategia técnica de consistencia distribuida está en [Estrategia técnica de consistencia distribuida y Sagas](../architecture/distributed-transaction-consistency.md).

Los ADR están aceptados como decisiones arquitectónicas; su aceptación no significa que sus componentes, controles, pools, Sagas, migraciones o código ya estén implementados.
