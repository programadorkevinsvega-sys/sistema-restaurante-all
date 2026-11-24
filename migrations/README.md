# Migrations

Las migraciones pertenecen al módulo propietario. Esta carpeta raíz conserva la ubicación histórica de migraciones existentes; para nuevas migraciones, usar un directorio independiente por módulo, sin mezclar ownership ni historiales SQLx.

## Reglas

- Cada módulo posee su schema, su rol PostgreSQL, su directorio de migraciones y su tabla de historial SQLx exclusiva.
- Configurar migrations-dir y table-name por crate en sqlx.toml. El historial debe ser schema-qualified y distinto por módulo; SQLx usa _sqlx_migrations por defecto.
- El rol de migración de cada módulo solo modifica su schema e historial. Runtime no tiene DDL ni privilegios globales.
- No ejecutar todos los directorios bajo un único historial compartido.
- No renumerar, reescribir ni eliminar migraciones que puedan haberse aplicado. Hacer cambios posteriores mediante migraciones nuevas.
- Probar desde una base vacía y desde las versiones anteriores compatibles.
- No duplicar propiedad de objetos. FKs solo dentro del límite del mismo módulo; no FKs entre schemas propietarios distintos.
- infrastructure/database puede contener configuración operativa, no otra fuente de verdad del esquema.

La compatibilidad de la configuración SQLx debe comprobarse contra la versión fijada por Cargo.toml/Cargo.lock antes de implementarla. Ver [ADR-0001](../docs/adr/0001-postgres-module-ownership-and-migrations.md) y [Reglas de implementación](../docs/engineering/implementation-rules.md).