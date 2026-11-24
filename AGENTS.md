# Instrucciones para agentes

Antes de proponer o modificar arquitectura, leer en este orden:

1. [Estándar general](docs/architecture/engineering-standard.md)
2. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
3. [Reglas de implementación](docs/engineering/implementation-rules.md)
4. [Estándar de calidad, seguridad y mantenimiento documental](docs/engineering/documentation-quality-and-security-standard.md)
5. [ADRs aceptados y propuestos aplicables](docs/adr/README.md)
6. [Seguridad de contraseñas y autenticación](docs/security/password-and-authentication.md), cuando la tarea afecte IDENTITY o autenticación
7. [Requisitos](requisitos.md) y [Roadmap](ROADMAP.md)
8. [Configuración de protección de main en GitHub](docs/engineering/github-protection-setup.md)

Al crear o modificar documentación, cumplir además el [Estándar de calidad, seguridad y mantenimiento documental](docs/engineering/documentation-quality-and-security-standard.md). Respetar precedencia: el estándar general es obligatorio; la arquitectura de Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo; las reglas de implementación están subordinadas. No resolver contradicciones por inferencia: proponer ADR y esperar aprobación explícita.

Un agente puede analizar y proponer, pero no aprobar decisiones de producto, aceptar ADRs, fusionar PRs, desplegar ni ejecutar acciones irreversibles sin autorización explícita. No afirmar que una regla está implementada o verificada sin evidencia. Los cambios de documentación arquitectónica se integran mediante PR a main. CODEOWNERS identifica responsables, pero la revisión de code owners solo es obligatoria si un Ruleset o branch protection de GitHub activa expresamente ese requisito. Consultar [Configuración de protección de main](docs/engineering/github-protection-setup.md); no afirmar que está activa sin verificarla.
