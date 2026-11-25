# Changelog

Todos los cambios relevantes de la biblioteca se registran aquí. El formato sigue una adaptación de Keep a Changelog y versionado semántico.

## [0.3.0] - 2026-11-25

### Added

- Inventario exhaustivo con IDs estables para los 66 estándares documentales y los 92 temas de descubrimiento (158 filas evaluables).

- Matriz inicial de cobertura que identifica documentos relacionados y brechas conocidas sin equiparar referencias con cobertura suficiente.

- Criterios mínimos de profundidad técnica, evidencias, referencias y revisión especializada para estándares.

### Changed

- Separación estricta entre aplicabilidad y estado de adopción; corrección de la plantilla de perfil, registro y matriz de conformidad.

- Protocolo de agentes reforzado para exigir una fila por cada ID, revisión completa, ausencia de omisiones y tratamiento explícito de brechas.

- README y navegación actualizados para incluir el inventario y los criterios de calidad.

### Notes

- Todos los documentos siguen en Draft; estas mejoras no equivalen a aprobación ni conformidad.

## [0.2.0] - 2026-11-25

### Added

- Catálogo maestro de disciplinas y temas para revisión exhaustiva.

- Protocolo obligatorio de consulta, selección y adopción de estándares para agentes.

- Registro de adopción de estándares por proyecto con estados explícitos, justificaciones, responsables, excepciones, pendientes y evidencias.

- Área 14 de ingeniería especializada con estándares de frontend, accesibilidad, internacionalización, móvil, offline-first, búsqueda, object storage, integraciones/webhooks, pagos, tiempo real/streaming, IA/agentes, ML/MLOps, IoT, cloud, infraestructura como código, Kubernetes, SRE/SLO, FinOps, licencias, documentación, feature flags y UX.

- Regla de que ningún estándar ni familia puede omitirse sin estado, justificación y reevaluación cuando cambie el contexto.

- Enlaces principales desde README y navegación de adaptación a proyectos.

### Changed

- README principal actualizado para hacer obligatorio el recorrido del catálogo y el protocolo antes de iniciar diseño comprometido o implementación.

- Área de adaptación ampliada para referenciar catálogo, protocolo y registro.

### Notes

- La biblioteca continúa en estado Draft para revisión; añadir documentos no equivale a aprobarlos.

- La nueva taxonomía es exhaustiva como mecanismo de descubrimiento, pero se mantiene abierta a nuevas disciplinas y brechas.

- No se modifica ni sustituye ningún ADR o artefacto de producto del repositorio consumidor.

## [0.1.0] - 2026-11-25

### Added

- Estructura inicial de la biblioteca de estándares de ingeniería.

- Modelo de gobernanza, lenguaje normativo, versionado y adopción.

- Estándares de arquitectura, datos, sistemas distribuidos, APIs, seguridad de aplicaciones y frontend, seguridad de bases de datos, infraestructura, cifrado y claves, resiliencia, rendimiento, observabilidad, privacidad, calidad y DevSecOps.

- Estándares específicos de auditoría y respuesta a incidentes.

- Plantillas de perfil de proyecto, ADR, excepción y matriz de conformidad.

### Notes

- Todos los documentos se publican inicialmente como borrador para revisión.

- La biblioteca no modifica ni reemplaza decisiones de ningún proyecto de origen.
