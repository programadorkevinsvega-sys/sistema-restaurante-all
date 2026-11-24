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
