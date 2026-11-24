# Migrations

Esta carpeta es la fuente única de cambios versionados del esquema de base de
datos. Las migraciones deben poder aplicarse en el orden establecido por la
herramienta de migración y dejar el esquema reproducible desde cero.

## Reglas

- Cada cambio debe identificar el dominio propietario de las tablas afectadas.
- Mantener el orden y el formato reconocidos por la herramienta existente.
- No renumerar, reescribir ni eliminar migraciones que puedan haberse aplicado.
  Los cambios posteriores deben hacerse mediante nuevas migraciones compatibles.
- Evitar que dos migraciones distintas sean dueñas del mismo objeto de esquema.
- Probar las migraciones tanto desde una base vacía como desde la versión
  anterior que corresponda.
- Limitar los datos iniciales a valores de referencia necesarios; no usar
  migraciones para cargar datos operativos.

La carpeta [`infrastructure/database/`](../infrastructure/database/) puede
contener configuración operativa de PostgreSQL, pero no una copia de estas
migraciones.
