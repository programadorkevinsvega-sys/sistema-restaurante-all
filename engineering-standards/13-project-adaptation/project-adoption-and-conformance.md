# Estándar de adopción y conformidad de proyectos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Aplicar la biblioteca de forma proporcional al riesgo y demostrar qué requisitos están adoptados y cumplidos.

## Proceso

1. Completar el perfil del proyecto.
2. Clasificar criticidad, datos, exposición, escala, regulación y capacidad operativa.
3. Revisar cada estándar y determinar aplicabilidad.
4. Adoptar versiones concretas y registrar responsable.
5. Convertir requisitos aplicables en controles, tareas y pruebas.
6. Crear ADR para decisiones tecnológicas y arquitectónicas específicas.
7. Registrar excepciones con vencimiento y controles compensatorios.
8. Verificar conformidad en diseño, antes de producción y durante operación.
9. Reevaluar ante cambios de arquitectura, amenazas, regulación, escala o incidentes.

## Niveles de adopción

- **Base:** requisitos esenciales de gobernanza, seguridad, calidad, datos y operación.
- **Elevado:** sistemas expuestos, multiusuario, integraciones relevantes o datos sensibles.
- **Crítico:** operaciones financieras, salud, seguridad física, infraestructura esencial o alto impacto regulatorio.
- **Distribuido:** cuando existen múltiples procesos, brokers, consistencia eventual o fallos de red como condición normal.

Estos perfiles orientan el análisis; no sustituyen el juicio de riesgo ni constituyen certificaciones.

## Reglas contra la sobreingeniería

- No adoptar clústeres, microservicios, brokers o controles complejos sin necesidad demostrable.
- No reducir controles esenciales solo porque el sistema sea pequeño.
- Priorizar controles por amenaza, impacto y costo.
- Preferir soluciones gestionadas cuando reduzcan riesgo operativo sin crear dependencia inaceptable.
- Registrar por qué una capacidad no aplica y cuándo debe reevaluarse.

## Evidencia

La conformidad requiere configuración, pruebas, resultados, auditorías, runbooks y responsables. Una política escrita o un ADR no prueba implementación.

## Revisión

Revisar al menos en cada release mayor y ante cambios significativos de riesgo, arquitectura o regulación.
