# Restaurant OS

Plataforma SaaS para la gestión y operación integral de restaurantes, con soporte para múltiples empresas, marcas y sucursales.

## Estado del proyecto

El repositorio se encuentra en la etapa de definición y consolidación de arquitectura, requisitos y documentación. Las decisiones arquitectónicas aceptadas no implican que los binarios, módulos, infraestructura o integraciones estén implementados o desplegados.

## Arquitectura de aplicación

La arquitectura define cuatro procesos independientes:

1. **Admin Platform Backend:** propietario del módulo PLATFORM, responsable del ciclo de vida SaaS de la plataforma.
2. **Admin BFF:** composición y exposición HTTP/OpenAPI para interfaces administrativas; no posee dominios ni persistencia de negocio.
3. **Public BFF:** composición y exposición HTTP/OpenAPI para interfaces públicas y operativas; no posee dominios ni persistencia de negocio.
4. **Public Backend:** propietario de los demás módulos de negocio canónicos.

Los módulos de negocio mantienen ownership exclusivo de su lógica, contratos, schema PostgreSQL, rol, migraciones e historial SQLx. No existen tablas de historial compartidas entre módulos.

## Decisiones y tecnologías arquitectónicas

Las decisiones vigentes se registran en ADRs. Entre ellas:

- Rust y un Cargo workspace raíz con cuatro binarios independientes.
- PostgreSQL como plataforma de persistencia, con topología HA single-writer y réplicas de lectura.
- UUIDv7 como estándar global para identificadores UUID.
- SQLx con pooling separado por identidad de módulo y routing de lectura/escritura según consistencia.
- gRPC + Protobuf versionado para solicitudes/respuestas entre procesos.
- NATS Core para señales efímeras y JetStream para mensajería durable.
- Transactional Outbox/Inbox, idempotencia y Sagas para consistencia distribuida.
- Redis Cluster con TLS y ACL para caché distribuida de consultas elegibles.
- OpenTelemetry y la plataforma de observabilidad definida en ADR-0015.

Estas son decisiones documentadas, no una afirmación de que las tecnologías estén instaladas, configuradas o desplegadas.

## Documentación principal

- [Requisitos funcionales y matriz de responsabilidades](requisitos.md)
- [Roadmap del producto y secuencia de construcción](ROADMAP.md)
- [Prompt maestro para tareas de implementación](PROMPT_MAESTRO.md)
- [Índice de ADRs aceptados](docs/adr/README.md)
- [Índice de arquitectura](docs/architecture/README.md)
- [Estándar general de arquitectura](docs/architecture/engineering-standard.md)
- [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
- [Diseño de crates y dependencias](docs/architecture/crate-architecture.md)
- [Reglas de implementación](docs/engineering/implementation-rules.md)
- [Estándar de calidad y seguridad documental](docs/engineering/documentation-quality-and-security-standard.md)
- [Gobernanza y protección de main](docs/engineering/github-protection-setup.md)

## Reglas de contribución importantes

- No cambiar ownership de módulos ni decisiones Accepted sin el proceso de gobernanza y un ADR aprobado.
- No importar implementaciones internas ni consultar directamente datos de otro módulo.
- No modificar, crear ni ejecutar archivos SQL o migraciones sin autorización expresa.
- Mantener diferenciados los cuatro procesos, sus responsabilidades y sus ciclos de despliegue.
- Documentar el estado real: decisión aprobada, especificación vigente, implementación y despliegue son estados distintos.
- Usar Pull Requests para revisar cambios y verificar los controles de GitHub que estén efectivamente configurados.

## Estructura de alto nivel

- apps/: paquetes de los cuatro binarios de aplicación.
- backend/: módulos agrupados por su backend propietario.
- contracts/protobuf/: fuente única de contratos Protobuf versionados.
- crates/: adaptadores y capacidades técnicas neutrales.
- packages/: paquetes compartidos de frontend y tooling.
- docs/: ADRs, arquitectura, seguridad y reglas de ingeniería.
- infrastructure/: definición de infraestructura y despliegue.
- migrations/: archivos SQL históricos; no es la ubicación canónica de nuevas migraciones.

Consulta los documentos enlazados antes de modificar cualquier área del repositorio.
