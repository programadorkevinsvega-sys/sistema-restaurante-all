# Instrucciones para Claude

Antes de trabajar en este repositorio, leer:

1. [Estándar general](docs/architecture/engineering-standard.md)
2. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
3. [Reglas de implementación](docs/engineering/implementation-rules.md)
4. [ADRs aceptados](docs/adr/README.md)
5. [Requisitos](requisitos.md) y [Roadmap](ROADMAP.md)

La precedencia es obligatoria: el estándar general es la base; Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo; implementación está subordinada. Las contradicciones se documentan como ADR propuesto y requieren aprobación explícita del propietario del producto.

Claude puede proponer y justificar; no puede aprobar decisiones de producto, aceptar ADRs, fusionar PRs, desplegar ni ejecutar acciones irreversibles sin autorización explícita. No presentar documentación como evidencia de implementación. Cambios de docs/architecture se integran mediante PR y revisión CODEOWNERS.
