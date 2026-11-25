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
backend/<backend-propietario>/modules/<modulo>/; crates/ se reserva para
capacidades técnicas neutrales, contratos versionados y adaptadores. Cada
módulo mantiene ownership exclusivo de su schema, rol, migraciones e historial
SQLx.

## Documentos vigentes

- [Estándar general](./engineering-standard.md): reglas obligatorias de arquitectura y estructura.
- [Arquitectura de Restaurant OS](./restaurant-os-architecture.md): especialización de los cuatro procesos, dominios, datos y comunicación.
- [Diseño de crates y dependencias](./crate-architecture.md): diseño técnico aceptado mediante ADR-0009.
- [Estrategia técnica de identificadores UUIDv7 y PostgreSQL](./identifier-strategy.md): política vigente de UUIDv7 vinculada a ADR-0012 Accepted; no significa que la generación o migración esté implementada.
- [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md): especificación operativa vigente conforme a ADR-0012 Accepted; no representa infraestructura desplegada.
- [Redis Cluster, TLS y operación de caché distribuida](./redis-cache-operations.md): especificación vigente conforme a ADR-0016 Accepted; no representa infraestructura desplegada.
- [NATS Core y JetStream en clúster](./nats-core-jetstream-cluster.md): especificación vigente conforme a ADR-0017 Accepted; no representa infraestructura desplegada.
- [Estrategia técnica de consistencia distribuida y Sagas](./distributed-transaction-consistency.md): especificación vinculada a ADR-0013 Accepted; no representa implementación.
- [Operación de Transactional Outbox e Inbox](./transactional-outbox-inbox-operations.md): especificación vinculada a ADR-0003, ADR-0013 y ADR-0015; no representa implementación.
- [Estrategia técnica de observabilidad integral](./observability-strategy.md): especificación vinculada a ADR-0015 Accepted; no representa instrumentación ni infraestructura desplegada.
- [Reglas de implementación](../engineering/implementation-rules.md): reglas operativas de implementación.
- [Estándar documental](../engineering/documentation-quality-and-security-standard.md): exactitud, seguridad, README, enlaces, revisión y validación documental.
- [Seguridad de contraseñas y autenticación](../security/password-and-authentication.md): especificación técnica vinculada a ADR-0011 Accepted; no representa implementación.
- [ADRs](../adr/README.md): índice de decisiones aceptadas y propuestas. ADR-0018 está Accepted; ADR-0019 se encuentra en PR #26 abierto; ADR-0020 a ADR-0027 son propuestas de seguridad pendientes de aprobación.
- [Requisitos](../../requisitos.md): fuente de verdad de responsabilidades de dominios y carpetas.
- [Roadmap](../../ROADMAP.md): fases y entregables.

## ADR de seguridad propuestos

- [ADR-0020: Marco integral de seguridad y defensa en profundidad](../adr/0020-integral-security-and-defense-in-depth.md).
- [ADR-0021: Autorización, RBAC/ABAC y aislamiento multi-tenant](../adr/0021-authorization-rbac-abac-and-tenant-isolation.md).
- [ADR-0022: Seguridad del frontend, navegador, sesiones y APIs de borde](../adr/0022-frontend-browser-session-and-api-security.md).
- [ADR-0023: Seguridad de infraestructura, redes, secretos y criptografía](../adr/0023-infrastructure-network-secrets-and-cryptography-security.md).
- [ADR-0024: Desarrollo seguro, CI/CD y cadena de suministro de software](../adr/0024-secure-development-cicd-and-software-supply-chain.md).
- [ADR-0025: Protección contra abuso de APIs, bots, DDoS y extracción de datos](../adr/0025-api-abuse-bots-ddos-and-data-exfiltration-protection.md).
- [ADR-0026: Auditoría de seguridad, detección y respuesta a incidentes](../adr/0026-security-audit-detection-and-incident-response.md).
- [ADR-0027: Seguridad de archivos, documentos y almacenamiento de objetos](../adr/0027-secure-file-document-and-object-storage-handling.md).

La presencia de documentos no demuestra que los procesos, crates, controles,
infraestructura o despliegues estén implementados.
