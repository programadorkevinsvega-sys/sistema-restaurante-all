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
- [Reglas de implementación](../engineering/implementation-rules.md): reglas operativas de implementación.
- [Estándar documental](../engineering/documentation-quality-and-security-standard.md): exactitud, seguridad, README, enlaces, revisión y validación documental.
- [ADRs](../adr/README.md): decisiones aceptadas y propuestas, incluida la distribución de módulos de ADR-0008, los límites de crates de ADR-0009 y la estrategia PostgreSQL propuesta en ADR-0010.
- [Requisitos](../../requisitos.md): fuente de verdad de responsabilidades de dominios y carpetas.
- [Roadmap](../../ROADMAP.md): fases y entregables.

La presencia de estas carpetas o documentos no demuestra que los procesos,
crates, infraestructura o despliegues estén implementados.
