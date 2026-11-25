# Estándar de infraestructura como código y automatización de plataforma

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a infraestructura provisionada o configurada mediante código y pipelines.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Mantener infraestructura declarativa versionada, revisada y reproducible; evitar cambios manuales no registrados.
- Separar módulos reutilizables, configuración por entorno y secretos; no incluir credenciales en state ni repositorios.
- Proteger state, locking, cifrado, control de acceso, versionado y recuperación.
- Revisar planes/diffs antes de aplicar; exigir aprobación para producción y recursos críticos.
- Aplicar policy as code, validación, lint, pruebas y escaneo de configuración insegura.
- Definir importación y reconciliación de recursos existentes; evitar drift silencioso.
- Usar despliegues idempotentes y cambios pequeños con rollback/forward plan.
- Probar módulos, entornos efímeros, destrucción segura y recuperación del control plane.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.
- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.
- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.
- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.
- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.
