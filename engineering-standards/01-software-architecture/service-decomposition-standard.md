# Estándar de descomposición de servicios

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Determinar cuándo una capacidad debe ejecutarse como proceso o servicio independiente y cuándo conviene mantenerla dentro de un proceso modular.

## Criterios de separación

La separación física debe justificarse por uno o más factores medibles:

- Escalado independiente por perfil de carga.
- Aislamiento de fallos o requisitos de seguridad.
- Ciclos de despliegue y disponibilidad diferentes.
- Límites organizacionales y ownership operacional real.
- Requisitos regulatorios o de residencia.
- Tecnología o recursos de ejecución incompatibles.
- Necesidad de limitar blast radius.

## Costos que deben evaluarse

- Latencia y fallos de red.
- Consistencia eventual y coordinación distribuida.
- Observabilidad y diagnóstico más complejos.
- Despliegue, configuración, secretos y certificados.
- Capacidad del equipo para operar el servicio.
- Costos de infraestructura y guardias.
- Compatibilidad de contratos y migraciones.

## Requisitos

- Cada servicio DEBE tener propietario, propósito, SLO, dependencias y modelo de datos identificados.
- La comunicación entre servicios debe usar contratos versionados.
- No se deben compartir bases de datos como mecanismo de integración.
- La separación no debe crear llamadas síncronas en cascada sin límites.
- Los servicios deben degradarse de forma controlada ante indisponibilidad de dependencias.
- La extracción debe incluir plan de datos, tráfico, rollback, observabilidad y seguridad.

## Regla de decisión

Si el beneficio no puede medirse o el equipo no puede operar la distribución, se DEBERÍA mantener la capacidad modular dentro del proceso existente y reevaluar cuando cambien las condiciones.

## Verificación

ADR de descomposición, análisis de costo/beneficio, mapa de dependencias, SLO y pruebas de fallos de red.
