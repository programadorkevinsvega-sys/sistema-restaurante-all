# Arquitectura de Restaurant OS

La arquitectura del repositorio se organiza en cuatro procesos independientes,
cada uno con módulos propios:

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
- [Reglas de implementación](../engineering/implementation-rules.md): reglas operativas de implementación.
- [ADRs aceptados](../adr/README.md): decisiones arquitectónicas aprobadas.
- [Requisitos](../../requisitos.md): fuente de verdad de responsabilidades de dominios y carpetas.
- [Roadmap](../../ROADMAP.md): fases y entregables.

La presencia de carpetas o documentos no demuestra que los procesos, crates,
infraestructura o despliegues estén implementados.
