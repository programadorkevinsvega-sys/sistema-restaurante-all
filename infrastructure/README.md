# Infrastructure

Esta carpeta contiene los recursos para ejecutar, desplegar y operar
Restaurant OS. Describe y configura el entorno técnico; no implementa
funcionalidades de negocio.

## Contenido

- [`docker/`](./docker/): servicios y configuración para desarrollo y pruebas
  locales mediante contenedores.
- [`database/`](./database/): aprovisionamiento y operación de la base de
  datos, como configuración de instancias, roles operativos y respaldos.
  Los cambios versionados del esquema pertenecen a [`migrations/`](../migrations/).
- [`monitoring/`](./monitoring/): configuración de recolección de telemetría,
  dashboards, alertas y herramientas de observabilidad.
- [`deployment/`](./deployment/): configuración e infraestructura para
  desplegar los componentes por entorno.

## Límites

- No incluir reglas de negocio ni implementaciones Rust de adaptadores.
- No duplicar migraciones ni mantener una segunda fuente de verdad para el
  esquema de PostgreSQL.
- No guardar secretos en archivos versionados; usar referencias a un gestor de
  secretos.
- Mantener explícitas las diferencias entre desarrollo, pruebas y producción.
