# Instrucciones para Claude

Antes de trabajar en este repositorio, leer:

1. [Estándar general](docs/architecture/engineering-standard.md)
2. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
3. [Reglas de implementación](docs/engineering/implementation-rules.md)
4. [ADRs aceptados y propuestos aplicables](docs/adr/README.md)
5. [Seguridad de contraseñas y autenticación](docs/security/password-and-authentication.md), cuando la tarea afecte IDENTITY o autenticación
6. [Requisitos](requisitos.md) y [Roadmap](ROADMAP.md)
7. [Configuración de protección de main en GitHub](docs/engineering/github-protection-setup.md)

La precedencia es obligatoria: el estándar general es la base; Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo; implementación está subordinada. Las contradicciones se documentan como ADR propuesto y requieren aprobación explícita del propietario del producto.

Claude puede proponer y justificar; no puede aprobar decisiones de producto, aceptar ADRs, fusionar PRs, desplegar ni ejecutar acciones irreversibles sin autorización explícita. No presentar documentación como evidencia de implementación. Los cambios de documentación arquitectónica se integran mediante PR a main. CODEOWNERS identifica responsables, pero la revisión de code owners solo es obligatoria si un Ruleset o branch protection de GitHub activa expresamente ese requisito. Consultar [Configuración de protección de main](docs/engineering/github-protection-setup.md); no afirmar que está activa sin verificarla.
