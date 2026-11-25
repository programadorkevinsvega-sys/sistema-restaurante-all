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
- [Matriz de ownership, contratos y dependencias](./module-ownership-contracts-and-dependencies.md): catálogo de los 20 módulos, sus procesos propietarios, schemas históricos, rutas de contratos y reglas de dependencias para la subfase 0.1.
- [Estrategia técnica de identificadores UUIDv7 y PostgreSQL](./identifier-strategy.md): política vigente de UUIDv7 vinculada a ADR-0012 Accepted; no significa que la generación o migración esté implementada.
- [Diseño de PostgreSQL HA y réplicas](./postgresql-ha-design.md): topología, schemas, roles, RLS y routing; entregable de subfase 0.6.
- [Presupuesto de conexiones](./connection-budget.md): estructura de pools por proceso/módulo/réplica y parámetros a dimensionar; entregable de subfase 0.6.
- [Estrategia UUIDv7 y transición](./uuid-strategy.md): reglas de generación, usos prohibidos y plan de transición por módulo; entregable de subfase 0.6.
- [Diseño Outbox/Inbox/Saga](./outbox-inbox-saga-design.md): esquemas de tablas, dispatcher, estados de Saga y flujo de referencia; entregable de subfase 0.6.
- [Plan backup/restore/PITR](./backup-restore-plan.md): estrategia de backup, PITR, runbooks y verificación periódica; entregable de subfase 0.6.
- [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md): especificación operativa vigente conforme a ADR-0012 Accepted; no representa infraestructura desplegada.
- [Redis Cluster, TLS y operación de caché distribuida](./redis-cache-operations.md): especificación vigente conforme a ADR-0016 Accepted; no representa infraestructura desplegada.
- [NATS Core y JetStream en clúster](./nats-core-jetstream-cluster.md): especificación vigente conforme a ADR-0017 Accepted; no representa infraestructura desplegada.
- [Estrategia técnica de consistencia distribuida y Sagas](./distributed-transaction-consistency.md): especificación vinculada a ADR-0013 Accepted; no representa implementación.
- [Operación de Transactional Outbox e Inbox](./transactional-outbox-inbox-operations.md): especificación vinculada a ADR-0003, ADR-0013 y ADR-0015; no representa implementación.
- [Estrategia técnica de observabilidad integral](./observability-strategy.md): especificación vinculada a ADR-0015 Accepted; no representa instrumentación ni infraestructura desplegada.
- [Reglas de implementación](../engineering/implementation-rules.md): reglas operativas de implementación.
- [Estándar documental](../engineering/documentation-quality-and-security-standard.md): exactitud, seguridad, README, enlaces, revisión y validación documental.
- [Seguridad de contraseñas y autenticación](../security/password-and-authentication.md): especificación técnica vinculada a ADR-0011 Accepted; no representa implementación.
- [Modelo de amenazas](../security/threat-model.md): inventario de activos, actores, fronteras y amenazas STRIDE; entregable de subfase 0.3.
- [Matriz amenaza/control/fase](../security/threat-control-matrix.md): controles asignados por amenaza, tipo, fase y estado; entregable de subfase 0.3.
- [Registro de riesgos residuales](../security/residual-risk-register.md): riesgos abiertos con fase de cierre y propietario; entregable de subfase 0.3.
- [Baseline de seguridad por proceso](../security/security-baseline-per-process.md): controles mínimos requeridos por proceso antes de producción; entregable de subfase 0.3.
- [Modelo de identidad y autorización](../security/identity-and-authorization-model.md): tipos de identidad, RBAC+ABAC, sesiones y revocación; entregable de subfase 0.4.
- [Matriz rol/atributo/acción/ámbito](../security/rbac-abac-matrix.md): roles del sistema, atributos ABAC y acciones por dominio; entregable de subfase 0.4.
- [Contrato de contexto autenticado](../security/authenticated-context-contract.md): campos, semántica y reglas de propagación del contexto entre procesos y módulos; entregable de subfase 0.4.
- [Diseño de aislamiento por módulo y proceso](../security/isolation-design.md): schemas PostgreSQL, roles, RLS, pools, mensajería y verificación; entregable de subfase 0.4.
- [Casos negativos de autorización](../security/authorization-negative-cases.md): escenarios de rechazo obligatorios para todo endpoint y operación protegida; entregable de subfase 0.4.
- [Validación de entradas y contratos de datos](./input-validation-and-data-contracts.md): especificación técnica vigente conforme a ADR-0019 Accepted; no representa validadores ni middleware implementados.
- [Catálogo de reglas y formatos de validación](../engineering/validation-rules-catalog.md): reglas mínimas por tipo de dato; entregable de subfase 0.5.
- [Plantilla de contrato de entrada](../engineering/input-contract-template.md): estructura mínima por operación antes de implementar; entregable de subfase 0.5.
- [Catálogo de errores públicos](../engineering/public-error-catalog.md): códigos estables HTTP/gRPC para todas las fronteras; entregable de subfase 0.5.
- [Checklist de revisión de validación](../engineering/validation-review-checklist.md): ítems obligatorios antes de aprobar cualquier PR con fronteras de entrada; entregable de subfase 0.5.
- [Matriz de pruebas negativas y fuzzing](../engineering/validation-negative-test-matrix.md): 54 casos negativos mínimos y áreas de fuzz testing; entregable de subfase 0.5.
- [ADRs](../adr/README.md): índice de decisiones aceptadas. ADR-0001 a ADR-0027 están Accepted; la aceptación no implica implementación.
- [Requisitos](../../requisitos.md): fuente de verdad de responsabilidades de dominios y carpetas.
- [Roadmap](../../ROADMAP.md): fases funcionales y entregables generales.
- [Plan maestro de ejecución detallado](../planning/master-execution-plan.md): subfases, tareas, dependencias, ADR, entregables, pruebas y puertas de avance.
- [Modelo de red y matriz de flujos](../infrastructure/network-model.md): zonas, flujos permitidos y egress por proceso; entregable de subfase 0.7.
- [Política de secretos](../infrastructure/secrets-policy.md): ciclo de vida, separación por proceso/módulo/entorno y reglas de uso; entregable de subfase 0.7.
- [Baseline de contenedores](../infrastructure/container-baseline.md): controles mínimos por imagen y contenedor antes de desplegar; entregable de subfase 0.7.
- [Política TLS/criptográfica](../infrastructure/tls-crypto-policy.md): TLS por frontera, certificados, cifrado en reposo y gestión de claves; entregable de subfase 0.7.
- [Runbooks de rotación](../infrastructure/rotation-runbooks.md): procedimientos de rotación programada y de emergencia; entregable de subfase 0.7.
- [Estrategia de observabilidad](../engineering/observability-design.md): instrumentación por capa, stack, propagación W3C, dashboards y retención; entregable de subfase 0.8.
- [Catálogo de eventos auditables](../engineering/audit-events-catalog.md): eventos por módulo con evidencia mínima y criticidad; entregable de subfase 0.8.
- [Matriz de alertas](../engineering/alert-matrix.md): alertas con severidad, señal, umbral, propietario y runbook; entregable de subfase 0.8.
- [Runbooks de respuesta a incidentes](../engineering/incident-response-runbooks.md): procedimientos INC-01 a INC-SEC-02 para incidentes operativos y de seguridad; entregable de subfase 0.8.
- [Plan de respuesta y ejercicios](../engineering/incident-response-plan.md): ciclo de respuesta, severidades, responsables y ejercicios antes de producción; entregable de subfase 0.8.
- [Diseño NATS Core y JetStream](./nats-design.md): topología, cuentas, subjects, streams, consumers, DLQ y cuarentena; entregable de subfase 0.9.
- [Diseño Redis Cluster y caché](./redis-design.md): topología, ACL, formato de clave, cache-aside, invalidación durable y fallback; entregable de subfase 0.9.
- [Diseño object storage y archivos](./object-storage-design.md): buckets por módulo, metadata, URLs presignadas, pipeline de validación y cuarentena; entregable de subfase 0.9.
- [Contratos de eventos y fallback](./event-contracts.md): envelope estándar, versionado, catálogo inicial y política de fallback seguro; entregable de subfase 0.9.

## ADR de seguridad aceptados

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
