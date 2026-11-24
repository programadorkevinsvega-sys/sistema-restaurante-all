# Infrastructure

Recursos para ejecutar, desplegar y operar Restaurant OS. Describe el entorno técnico; no implementa negocio.

- docker/: servicios y configuración reproducible para desarrollo y pruebas locales.
- database/: aprovisionamiento y operación PostgreSQL, roles, respaldos. Los cambios versionados del esquema pertenecen a migraciones de cada módulo.
- monitoring/: recolección de telemetría, dashboards y alertas.
- deployment/: configuración de despliegue por entorno.

Docker facilita entornos reproducibles, pero no demuestra escalabilidad. El despliegue horizontal requiere aplicación stateless, estado compartido, Outbox/Inbox, idempotencia y coordinación de jobs. No guardar secretos en archivos versionados. Ver [Arquitectura](../docs/architecture/restaurant-os-architecture.md).