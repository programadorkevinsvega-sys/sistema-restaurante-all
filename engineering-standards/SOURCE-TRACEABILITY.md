# Matriz de trazabilidad de procedencia

**Versión:** 0.1.0 | **Estado:** Draft  
**Propósito:** registrar qué familias de decisiones y documentos técnicos originaron cada estándar general.

## Regla de interpretación

Los identificadores ADR que aparecen abajo son referencias históricas de procedencia. No son dependencias normativas, no deben existir en un proyecto consumidor y no convierten las decisiones locales del proyecto de origen en reglas universales.

La biblioteca generaliza principios, controles y lecciones. Los detalles particulares —tecnologías elegidas, topologías, cantidades de procesos, nombres de módulos, versiones concretas, parámetros operativos y obligaciones jurisdiccionales— permanecen específicos del proyecto que los decidió.

## Trazabilidad ADR → estándares

| ADR de procedencia | Tema original | Estándares generalizados |
|---|---|---|
| ADR-0001 | Ownership de persistencia y migraciones | [Ownership de datos](./02-data-management/data-ownership-and-access-standard.md), [migraciones](./02-data-management/database-schema-and-migration-standard.md) |
| ADR-0002 | Contratos HTTP/RPC y generación | [Diseño de contratos API](./04-apis-and-contracts/api-contract-design-standard.md), [versionado](./04-apis-and-contracts/api-versioning-and-compatibility-standard.md) |
| ADR-0003 | Stateless, Outbox/Inbox y jobs | [Outbox](./03-distributed-systems/transactional-outbox-standard.md), [Inbox](./03-distributed-systems/transactional-inbox-standard.md), [jobs](./03-distributed-systems/background-jobs-and-leases-standard.md) |
| ADR-0004 | Contexto de trazabilidad | [Observabilidad](./09-observability/observability-and-telemetry-standard.md) |
| ADR-0005 | Contratos gRPC | [Diseño de contratos API](./04-apis-and-contracts/api-contract-design-standard.md), [versionado](./04-apis-and-contracts/api-versioning-and-compatibility-standard.md) |
| ADR-0006 | Capacidad transversal y ownership | [Arquitectura modular](./01-software-architecture/modular-architecture-standard.md), [límites de dominio](./01-software-architecture/domain-boundaries-and-ownership-standard.md) |
| ADR-0007 | Procesos independientes y comunicación | [Descomposición de servicios](./01-software-architecture/service-decomposition-standard.md), [mensajería](./03-distributed-systems/messaging-and-event-contracts-standard.md) |
| ADR-0008 | Ownership de módulos | [Límites de dominio](./01-software-architecture/domain-boundaries-and-ownership-standard.md), [ownership de datos](./02-data-management/data-ownership-and-access-standard.md) |
| ADR-0009 | Límites de paquetes y dependencias | [Arquitectura modular](./01-software-architecture/modular-architecture-standard.md) |
| ADR-0010 | Pooling y recursos | [Pooling y presupuesto](./08-performance-and-capacity/connection-pooling-and-resource-budget-standard.md) |
| ADR-0011 | Contraseñas y autenticación | [Autenticación y autorización](./05-application-security/authentication-and-authorization-standard.md), [secretos](./05-application-security/secrets-and-credential-management-standard.md) |
| ADR-0012 | Identificadores y alta disponibilidad de base de datos | [Identificadores](./02-data-management/identifier-strategy-standard.md), [alta disponibilidad](./07-resilience-and-recovery/high-availability-and-failover-standard.md), [backup y DR](./07-resilience-and-recovery/backup-disaster-recovery-and-continuity-standard.md) |
| ADR-0013 | Consistencia distribuida y Sagas | [Sagas](./03-distributed-systems/saga-and-distributed-consistency-standard.md), [Outbox](./03-distributed-systems/transactional-outbox-standard.md), [Inbox](./03-distributed-systems/transactional-inbox-standard.md), [idempotencia](./03-distributed-systems/idempotency-standard.md) |
| ADR-0014 | Baja de tenants y conservación de datos | [Aislamiento multi-tenant](./02-data-management/multi-tenant-data-isolation-standard.md), [privacidad y ciclo de vida](./10-privacy-and-data-protection/privacy-and-personal-data-lifecycle-standard.md) |
| ADR-0015 | Observabilidad integral | [Observabilidad y telemetría](./09-observability/observability-and-telemetry-standard.md) |
| ADR-0016 | Caché distribuida y seguridad | [Caché distribuida](./08-performance-and-capacity/distributed-caching-standard.md), [cifrado de transporte](./06-infrastructure-security/transport-encryption-and-certificate-standard.md) |
| ADR-0017 | Mensajería durable y alta disponibilidad | [Mensajería](./03-distributed-systems/messaging-and-event-contracts-standard.md), [alta disponibilidad](./07-resilience-and-recovery/high-availability-and-failover-standard.md) |
| ADR-0018 | Privacidad, retención, términos y cookies | [Privacidad y ciclo de vida](./10-privacy-and-data-protection/privacy-and-personal-data-lifecycle-standard.md) |
| ADR-0019 | Validación e integridad de entradas | [Validación e integridad](./05-application-security/input-validation-and-data-integrity-standard.md), [contratos API](./04-apis-and-contracts/api-contract-design-standard.md) |
| ADR-0020 | Marco de seguridad y defensa en profundidad | [Baseline de seguridad](./05-application-security/application-security-baseline-standard.md) |
| ADR-0021 | RBAC/ABAC y aislamiento | [Autenticación y autorización](./05-application-security/authentication-and-authorization-standard.md), [aislamiento multi-tenant](./02-data-management/multi-tenant-data-isolation-standard.md) |
| ADR-0022 | Seguridad de frontend, sesiones y APIs | [Baseline de seguridad](./05-application-security/application-security-baseline-standard.md), [autenticación](./05-application-security/authentication-and-authorization-standard.md), [abuso de APIs](./05-application-security/api-abuse-and-rate-protection-standard.md) |
| ADR-0023 | Infraestructura, red, secretos y criptografía | [Segmentación de red](./06-infrastructure-security/network-segmentation-and-egress-standard.md), [TLS](./06-infrastructure-security/transport-encryption-and-certificate-standard.md), [secretos](./05-application-security/secrets-and-credential-management-standard.md) |
| ADR-0024 | Desarrollo seguro y supply chain | [SDLC seguro](./12-devsecops/secure-software-development-lifecycle-standard.md), [CI/CD y supply chain](./12-devsecops/ci-cd-and-software-supply-chain-standard.md) |
| ADR-0025 | Abuso, bots, DDoS y extracción | [Protección contra abuso de APIs](./05-application-security/api-abuse-and-rate-protection-standard.md) |
| ADR-0026 | Auditoría, detección e incidentes | [Observabilidad](./09-observability/observability-and-telemetry-standard.md), [SDLC seguro](./12-devsecops/secure-software-development-lifecycle-standard.md) |
| ADR-0027 | Archivos y almacenamiento de objetos | [Carga y procesamiento de archivos](./05-application-security/file-upload-and-content-processing-standard.md), [privacidad](./10-privacy-and-data-protection/privacy-and-personal-data-lifecycle-standard.md) |

## Contenido deliberadamente no convertido en regla universal

No se han convertido en mandatos generales:

- Una cantidad fija de procesos, backends, módulos o servicios.
- Un lenguaje, framework, base de datos o broker obligatorio para todo proyecto.
- Un formato único de identificadores.
- Una versión concreta de PostgreSQL, Redis, NATS u otra tecnología.
- Una topología fija de nodos, réplicas, shards o regiones.
- Valores universales de RPO, RTO, SLO, TTL, conexiones, memoria o capacidad.
- Reglas de dominio específicas de un producto.
- Plazos legales, bases jurídicas, textos contractuales o consentimiento de una jurisdicción particular.

Estos aspectos requieren perfil de proyecto, investigación vigente, análisis de riesgos, ADR y dimensionamiento.

## Revisión de cobertura

La matriz cubre ADR-0001 a ADR-0027 como fuentes de aprendizaje. La cobertura no significa que cada decisión local se haya convertido en requisito universal. Los estándares deben mantenerse independientes y revisarse por separado.
