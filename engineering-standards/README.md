# Engineering Standards Library

**Versión:** 0.1.0  
**Estado:** Borrador inicial para revisión  
**Idioma principal:** español  
**Propósito:** biblioteca tecnológica y metodológica reutilizable entre proyectos.

## Propósito

Esta biblioteca reúne estándares de ingeniería de software independientes de un producto concreto. Define principios, requisitos, controles, alternativas, antipatrones y pruebas de conformidad para diseñar, construir, operar y evolucionar sistemas de software profesionales.

No es una arquitectura de referencia única ni una receta tecnológica universal. Cada proyecto debe evaluar su contexto, criticidad, escala, obligaciones regulatorias, equipo, presupuesto y modelo operativo antes de adoptar los estándares.

## Principios de uso

1. Los estándares describen requisitos y resultados; no fuerzan una tecnología salvo que el documento se identifique expresamente como estándar tecnológico.
2. La aplicabilidad se determina por riesgo y contexto, no por moda ni por tamaño aislado.
3. Los requisitos obligatorios de un estándar adoptado deben convertirse en controles, tareas y evidencias verificables.
4. Una excepción debe ser explícita, limitada, aprobada, mitigada y revisable.
5. Adoptar un estándar no demuestra que esté implementado ni que el sistema sea conforme.
6. Los ADR de cada proyecto registran las decisiones concretas y no deben copiarse mecánicamente desde esta biblioteca.
7. Los estándares se mantienen independientes de cualquier repositorio consumidor y no contienen nombres, dominios, módulos, topologías o reglas exclusivas de un producto.

## Estructura

| Área | Contenido |
|---|---|
| 00-governance | Gobierno, ADR, ciclo de vida y excepciones. |
| 01-architecture | Modularidad, dominios y límites de servicios. |
| 02-data-management | Ownership, persistencia, migraciones, identificadores y multi-tenancy. |
| 03-distributed-systems | Outbox, Inbox, Sagas, mensajería, idempotencia y trabajos. |
| 04-apis-and-contracts | Contratos, versionado y errores. |
| 05-application-security | Seguridad, validación, identidad, secretos, archivos y abuso. |
| 06-infrastructure-security | Redes, cifrado de transporte y contenedores. |
| 07-resilience-and-recovery | Timeouts, reintentos, alta disponibilidad y recuperación. |
| 08-performance-and-capacity | Caché, pools y capacidad. |
| 09-observability | Logs, métricas, trazas y alertas. |
| 10-privacy-and-data-protection | Privacidad y ciclo de vida de datos. |
| 11-testing-and-quality | Estrategia de pruebas y calidad. |
| 12-devsecops | SDLC, CI/CD y cadena de suministro. |
| 13-project-adaptation | Perfil de proyecto y evaluación de conformidad. |

## Cómo empezar con un proyecto

1. Completar la ficha de perfil del proyecto.
2. Clasificar cada estándar como obligatorio, condicional o no aplicable, justificando la decisión.
3. Identificar requisitos aplicables y asignar responsables.
4. Registrar en ADR las elecciones tecnológicas y arquitectónicas concretas.
5. Crear una matriz de trazabilidad requisito-control-prueba-evidencia.
6. Revisar conformidad antes de hitos de lanzamiento y periódicamente durante la operación.

## Lenguaje normativo

Los términos **DEBE**, **NO DEBE**, **OBLIGATORIO**, **DEBERÍA**, **NO DEBERÍA** y **PUEDE** se interpretan conforme a la sección de lenguaje normativo de [GOVERNANCE.md](./GOVERNANCE.md). Un requisito solo es exigible cuando el estándar ha sido adoptado por el proyecto y resulta aplicable.

## Estado y límites

La versión 0.1.0 es una primera biblioteca estructurada y redactada para revisión. No es una certificación, norma legal, auditoría externa ni garantía de seguridad. Las referencias a tecnologías son ejemplos sujetos a validación de versiones, soporte, licencias y amenazas actuales.

## Navegación

- [Matriz de trazabilidad de procedencia](./SOURCE-TRACEABILITY.md)

- [Gobernanza](./GOVERNANCE.md)
- [Versionado](./VERSIONING.md)
- [Registro de cambios](./CHANGELOG.md)
- [Proceso de adopción](./13-project-adaptation/project-adoption-and-conformance.md)
- [Plantilla de perfil de proyecto](./13-project-adaptation/project-profile-template.md)
- [Plantilla de ADR](./00-governance/architecture-decision-record-standard.md)
- [Plantilla de excepción](./00-governance/standard-exception-and-waiver-process.md)
- [Matriz de conformidad](./13-project-adaptation/conformance-matrix-template.md)

## Procedencia

Esta biblioteca se elaboró a partir de patrones, riesgos y decisiones técnicas documentados en ADR y especificaciones de arquitectura de proyectos previos. Las referencias de procedencia son históricas: **no crean dependencias normativas** y ningún proyecto consumidor necesita incorporar esos documentos originales. Los estándares se han generalizado deliberadamente y deben revisarse de forma independiente.
