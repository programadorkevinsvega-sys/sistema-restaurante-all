# Arquitectura de Restaurant OS

La arquitectura del repositorio se organiza en cuatro procesos independientes.
La propiedad de módulos está definida por ADR-0008: Admin Platform Backend
contiene PLATFORM; Public Backend contiene los demás módulos de negocio; los
dos BFF son procesos de composición sin propiedad de dominios ni datos.

1. Admin Platform Backend.
2. Admin BFF.
3. Public BFF.
4. Public Backend.

Los BFF son procesos separados de sus backends. Los módulos viven en
`backend/<backend-propietario>/modules/<modulo>/`; `crates/` se reserva para
capacidades técnicas neutrales, contratos versionados y adaptadores. Cada
módulo mantiene ownership exclusivo de su schema, rol, migraciones e historial
SQLx.

## Documentos vigentes

- [Estándar general](./engineering-standard.md): reglas obligatorias de arquitectura y estructura.
- [Arquitectura de Restaurant OS](./restaurant-os-architecture.md): especialización de los cuatro procesos, dominios, datos y comunicación.
- [Diseño de crates y dependencias](./crate-architecture.md): diseño técnico aceptado mediante ADR-0009.
- [Estrategia técnica de identificadores UUIDv7 y PostgreSQL](./identifier-strategy.md): política vigente de UUIDv7 vinculada a ADR-0012 Accepted; no significa que la generación o migración esté implementada.
- [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md): especificación operativa vigente de clúster single-writer, replicación física, failover, routing consciente de consistencia, TLS, backups PITR y observabilidad, conforme a ADR-0012 Accepted.
- [Redis Cluster, TLS y operación de caché distribuida](./redis-cache-operations.md): especificación operativa vigente conforme a ADR-0016 Accepted; cubre topología cluster, TLS/ACL, cache-aside, ownership, invalidación durable, consistencia, degradación, observabilidad y pruebas; no representa infraestructura desplegada.
- [NATS Core y JetStream en clúster](./nats-core-jetstream-cluster.md): especificación vigente de clúster NATS, quorum, JetStream R=3 para streams críticos, TLS, aislamiento por cuentas, backups, recuperación y observabilidad, conforme a ADR-0017 Accepted; no representa infraestructura desplegada.
- [Estrategia técnica de consistencia distribuida y Sagas](./distributed-transaction-consistency.md): especificación técnica vinculada a ADR-0013 Accepted; no representa implementación.
- [Operación de Transactional Outbox e Inbox](./transactional-outbox-inbox-operations.md): especificación técnica vinculada a ADR-0003, ADR-0013 y ADR-0015; desarrolla secuencias por agregado, recuperación de huecos, DLQ, backpressure, límites, alertas e intervención; no representa implementación.
- [Estrategia técnica de observabilidad integral](./observability-strategy.md): especificación vigente vinculada a ADR-0015 Accepted; no representa instrumentación ni infraestructura desplegada.
- [Reglas de implementación](../engineering/implementation-rules.md): reglas operativas de implementación.
- [Estándar documental](../engineering/documentation-quality-and-security-standard.md): exactitud, seguridad, README, enlaces, revisión y validación documental.
- [Seguridad de contraseñas y autenticación](../security/password-and-authentication.md): especificación técnica vinculada a ADR-0011 Accepted; no representa implementación.
- [ADRs](../adr/README.md): índice de decisiones aceptadas y propuestas. ADR-0018 propone el marco de privacidad, retención, documentación legal y consentimiento como puerta de lanzamiento; aún no está aceptado ni implementado.
- [Requisitos](../../requisitos.md): fuente de verdad de responsabilidades de dominios y carpetas.
- [Roadmap](../../ROADMAP.md): fases y entregables.

La presencia de estas carpetas o documentos no demuestra que los procesos,
crates, infraestructura o despliegues estén implementados.
