# Estándar de estrategia de pruebas y puertas de calidad

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Demostrar que el sistema satisface requisitos funcionales, de seguridad, datos, rendimiento y operación con evidencia reproducible.

## Niveles de prueba

- Unitarias: reglas puras, invariantes, cálculos y transiciones.
- Integración: interacción real con persistencia, brokers, caches, almacenamiento y proveedores controlados.
- Contrato: compatibilidad de APIs, eventos y consumidores.
- E2E: recorridos completos por fronteras reales.
- Seguridad: autorización, aislamiento, entradas, secretos, dependencias y configuración.
- Rendimiento y resiliencia: carga, estrés, soak, failover y recuperación.
- Operativas: despliegue, backup/restore, rollback/roll-forward e incidentes.

## Requisitos

- Cada requisito crítico debe tener una o más pruebas y evidencia asociada.
- Las pruebas deben ejecutarse en CI con datos sintéticos y entornos reproducibles.
- Las pruebas de integración deben validar fronteras reales, no solo mocks, cuando la propiedad dependa de infraestructura.
- Los tests deben ser deterministas o aislar y documentar fuentes de flakiness.
- Los fallos no deben ocultarse mediante reintentos ciegos del pipeline.
- Los fixtures no deben contener secretos ni datos personales reales.
- Los criterios de salida deben incluir defectos abiertos, riesgos residuales y excepciones.
- Las pruebas negativas y de abuso deben ser parte del diseño, no añadirse únicamente tras un incidente.
- Los resultados deben identificar commit, versión, entorno, configuración y artefactos relevantes.

## Puertas de calidad

Una liberación crítica no debe avanzar si existen fallos críticos de seguridad, fugas de datos, pérdida/duplicación financiera, violaciones de integridad o incumplimiento de SLO sin aceptación formal y mitigación.

## Cobertura

La cobertura de líneas es una señal auxiliar, no prueba de corrección. Priorizar cobertura de decisiones, invariantes, límites y escenarios de fallo.

## Verificación

Reportes CI, pruebas de contrato, pruebas de regresión, evidencia de recuperación y matriz requisito-prueba.
