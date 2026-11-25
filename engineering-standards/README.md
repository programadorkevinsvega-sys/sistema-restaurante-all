# Engineering Standards Library

**Versión:** 0.3.0  
**Estado:** Draft ampliado para revisión  
**Idioma principal:** español  
**Propósito:** marco de estándares de ingeniería reutilizable entre proyectos.

## Propósito y regla de uso

Esta biblioteca reúne estándares independientes de un producto concreto para diseñar, construir, probar, desplegar, operar y evolucionar sistemas de software. No es una arquitectura única ni una receta tecnológica universal.

**Antes de iniciar cualquier diseño comprometido o implementación, todo agente DEBE ejecutar el [Protocolo obligatorio de consulta y adopción](./AGENT-STANDARDS-ADOPTION-PROTOCOL.md), recorrer el [Catálogo maestro](./MASTER-STANDARDS-CATALOG.md), el [inventario exhaustivo y matriz de cobertura](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md) completo y crear el [Registro de adopción del proyecto](./PROJECT-STANDARDS-ADOPTION-REGISTER.md).** No se permite omitir estándares sin registrar estado y justificación.

## Principios

1. No imponer tecnologías sin contexto ni evaluación de alternativas.
2. Determinar aplicabilidad por alcance, amenaza, criticidad, regulación y capacidad operativa.
3. Convertir requisitos adoptados en controles, tareas, pruebas y evidencias.
4. Registrar explícitamente adopciones, adaptaciones, aplazamientos, no aplicabilidad, rechazos, pendientes y brechas.
5. Una excepción debe tener dueño, justificación, mitigación, aprobación y vencimiento.
6. Adoptar un estándar no demuestra implementación ni conformidad.
7. No alterar decisiones ya aprobadas de un proyecto consumidor sin su proceso formal.
8. Mantener esta biblioteca neutral e independiente de los repositorios que la utilicen.

## Áreas

| Área | Contenido |
|---|---|
| 00-governance | Gobernanza, ADR, ciclo de vida y excepciones. |
| 01-software-architecture | Modularidad, dominios y descomposición. |
| 02-data-management | Ownership, persistencia, migraciones, identificadores y multi-tenancy. |
| 03-distributed-systems | Outbox, Inbox, Sagas, mensajería, idempotencia y jobs. |
| 04-apis-and-contracts | Contratos, versionado y errores. |
| 05-application-security | Seguridad de aplicaciones, identidad, validación, archivos y abuso. |
| 06-infrastructure-security | Redes, cifrado, claves y contenedores. |
| 07-resilience-and-recovery | Timeouts, reintentos, HA, backups y recuperación. |
| 08-performance-and-capacity | Caché, pools, capacidad y carga. |
| 09-observability | Logs, métricas, trazas y alertas. |
| 10-privacy-and-data-protection | Privacidad y ciclo de vida de datos. |
| 11-testing-and-quality | Estrategia de pruebas y puertas de calidad. |
| 12-devsecops | SDLC, CI/CD y cadena de suministro. |
| 13-project-adaptation | Perfil, adopción y conformidad. |
| 14-specialized-engineering | Frontend, móvil, accesibilidad, IA/ML, IoT, cloud, SRE, FinOps y especialidades. |

La taxonomía completa, los IDs estables, el inventario de documentos y la matriz inicial de cobertura están en el [inventario exhaustivo](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md) y el [Catálogo maestro](./MASTER-STANDARDS-CATALOG.md). Una referencia relacionada no demuestra cobertura suficiente; una brecha debe declararse.

## Inicio obligatorio de un proyecto

1. Leer catálogo, inventario exhaustivo y protocolo.
2. Completar el [perfil de proyecto](./13-project-adaptation/project-profile-template.md).
3. Recorrer cada familia y estándar, sin saltos.
4. Crear el [registro de adopción](./PROJECT-STANDARDS-ADOPTION-REGISTER.md).
5. Formalizar decisiones materiales mediante ADR.
6. Vincular requisitos con controles, pruebas y evidencias mediante la [matriz de conformidad](./13-project-adaptation/conformance-matrix-template.md).
7. Revalidar al cambiar alcance, riesgos, regulación, tecnología o modelo operativo.

## Navegación principal

- [Catálogo maestro de estándares](./MASTER-STANDARDS-CATALOG.md)
- [Inventario exhaustivo y matriz de cobertura](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md)
- [Criterios de calidad y revisión de estándares](./STANDARD-DOCUMENT-QUALITY-AND-REVIEW-CHECKLIST.md)
- [Protocolo obligatorio para agentes](./AGENT-STANDARDS-ADOPTION-PROTOCOL.md)
- [Registro de adopción por proyecto](./PROJECT-STANDARDS-ADOPTION-REGISTER.md)
- [Gobernanza](./GOVERNANCE.md)
- [Versionado](./VERSIONING.md)
- [Changelog](./CHANGELOG.md)
- [Trazabilidad de procedencia](./SOURCE-TRACEABILITY.md)
- [Proceso de adopción y conformidad](./13-project-adaptation/project-adoption-and-conformance.md)
- [Perfil de proyecto](./13-project-adaptation/project-profile-template.md)
- [Plantilla ADR](./00-governance/architecture-decision-record-standard.md)
- [Proceso de excepciones](./00-governance/standard-exception-and-waiver-process.md)

## Lenguaje normativo y límites

Los términos DEBE, NO DEBE, DEBERÍA, NO DEBERÍA y PUEDE se interpretan conforme a [GOVERNANCE.md](./GOVERNANCE.md). Un requisito es exigible cuando el estándar ha sido adoptado y resulta aplicable, sin perjuicio de obligaciones legales o contractuales no dispensables.

Esta biblioteca no es certificación, norma legal ni garantía de seguridad. Las versiones, recomendaciones y referencias técnicas deben verificarse al adoptarlas. Los ADR de procedencia son referencias históricas y no dependencias normativas.
