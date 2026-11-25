# Estándar de límites de dominio y ownership

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Asignar cada regla, dato y operación a un propietario inequívoco y evitar duplicación de autoridad.

## Requisitos

- Cada concepto de negocio debe tener un propietario principal.
- El propietario define invariantes, ciclo de vida, persistencia y contratos de escritura.
- Otros dominios consumen capacidades mediante contratos, no replican la autoridad.
- Los datos derivados o proyecciones deben identificar su fuente, retraso permitido y mecanismo de reconstrucción.
- Los términos compartidos deben tener definiciones explícitas; una palabra igual no implica que dos dominios compartan el mismo modelo.
- Los procesos que abarcan varios dominios deben declarar quién es propietario del proceso y quién es propietario de cada efecto.
- Las operaciones administrativas no transfieren ownership del dominio.
- Las reglas de negocio no deben residir en BFF, gateway, frontend o infraestructura genérica.

## Descubrimiento de límites

Usar lenguaje ubicuo, eventos de negocio, invariantes, flujos de trabajo, responsabilidades y frecuencia de cambio. Validar límites con escenarios de error y cambios futuros.

## Antipatrones

- Modelo de dominio compartido y mutable.
- Tablas maestras con múltiples escritores.
- Duplicación de reglas de negocio.
- Servicio central que conoce y modifica datos privados de todos los dominios.
- Asignar ownership por conveniencia del frontend.

## Verificación

Matriz de ownership, contratos por dominio, pruebas de límites y revisión de dependencias.
