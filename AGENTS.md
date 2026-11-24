# Instrucciones para agentes

Antes de proponer o modificar arquitectura, leer en este orden:

1. [Estándar general](docs/architecture/engineering-standard.md)
2. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
3. [Reglas de implementación](docs/engineering/implementation-rules.md)
4. [ADRs aceptados](docs/adr/README.md)
5. [Requisitos](requisitos.md) y [Roadmap](ROADMAP.md)

Respetar precedencia: el estándar general es obligatorio; la arquitectura de Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo; las reglas de implementación están subordinadas. No resolver contradicciones por inferencia: proponer ADR y esperar aprobación explícita.

Un agente puede analizar y proponer, pero no aprobar decisiones de producto, aceptar ADRs, fusionar PRs, desplegar ni ejecutar acciones irreversibles sin autorización explícita. No afirmar que una regla está implementada o verificada sin evidencia. Los cambios en docs/architecture requieren revisión CODEOWNERS y PR a main.
