# Infrastructure

Recursos para ejecutar, desplegar y operar Restaurant OS. Describe el entorno técnico; no implementa negocio.

- docker/: servicios y configuración reproducible para desarrollo y pruebas locales.
- database/: aprovisionamiento y operación PostgreSQL, roles, respaldos. Los cambios versionados del esquema pertenecen a migraciones de cada módulo.
- monitoring/: recolección de telemetría, dashboards y alertas.
- deployment/: configuración de despliegue por entorno.

## Topología objetivo de aplicación

- `api-server`: proceso backend que aloja el monolito modular y expone gRPC.
- `bff`: proceso independiente que consume `api-server` por gRPC y expone HTTP/OpenAPI a los frontends.
- Docker Compose debe representar ambos como dos servicios de aplicación separados. Esta topología es el objetivo arquitectónico; no se afirma que esté desplegada hasta verificar los manifiestos y su ejecución.

Docker facilita entornos reproducibles, pero no demuestra escalabilidad. El despliegue horizontal requiere aplicación stateless, estado compartido, Outbox/Inbox, idempotencia y coordinación de jobs. No guardar secretos en archivos versionados. Ver [Arquitectura](../docs/architecture/restaurant-os-architecture.md).