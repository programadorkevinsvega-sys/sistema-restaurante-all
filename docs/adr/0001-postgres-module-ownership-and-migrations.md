# ADR-0001: Ownership PostgreSQL y migraciones por módulo

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

Restaurant OS inicia con PostgreSQL compartido y módulos con ownership independiente. “Cada módulo gestiona sus migraciones” no es verificable si comparten historial SQLx o credenciales globales.

SQLx usa por defecto `_sqlx_migrations`. Su configuración permite cambiar `table-name` y `migrations-dir` mediante `sqlx.toml` para `sqlx::migrate!()` y SQLx CLI. Cada módulo debe apuntar a una tabla schema-qualified distinta dentro de su propio schema. Un `Migrator` construido manualmente no hereda automáticamente esa configuración y debe configurar su tabla explícitamente. Los historiales son independientes: la unicidad de versión se exige dentro de cada historial, no globalmente entre módulos.

## Decisión

1. Cada módulo posee un schema y sus objetos.
2. Cada módulo tiene rol PostgreSQL dedicado, limitado a su schema. Workers, jobs y pruebas respetan el ownership.
3. Separar identidad de migración y runtime; runtime sin DDL ni privilegios globales.
4. Cada módulo mantiene directorio e historial SQLx independiente y exclusivo; está prohibido compartir la tabla `_sqlx_migrations` entre módulos.
5. La ruta canónica para nuevas migraciones es `backend/<backend>/modules/<modulo>/migrations/`; las ubicaciones existentes se conservan como históricas.
6. Configurar por módulo `migrations-dir` y `table-name` schema-qualified exclusivo, p. ej. `identity._sqlx_migrations`.
7. `sqlx::migrate!()`/CLI usan `sqlx.toml`; un `Migrator` manual configura su tabla explícitamente.
8. El rol de migración modifica solo su schema y su tabla de historial.
9. Las versiones de migración son independientes por módulo porque cada uno tiene su propio historial.
10. Migraciones aplicadas no se reescriben ni renombran; transición mediante plan y pruebas.
11. FKs y consultas directas dentro del mismo límite de propiedad; no FKs ni joins entre schemas distintos.

## Consecuencias

Se requiere inventario módulo → schema → rol → `backend/<backend>/modules/<modulo>/migrations/` → tabla de historial y un paso de despliegue que ejecute cada historial por módulo. Más operación, pero ownership verificable.

## Verificación SQLx

La documentación oficial actual describe migrate.table-name, migrations-dir, el valor por defecto _sqlx_migrations y configuración por crate. También documenta dangerous_set_table_name para Migrator manual. Referencias: [migrate macro](https://docs.rs/sqlx/latest/sqlx/macro.migrate.html), [Migrator](https://docs.rs/sqlx/latest/sqlx/migrate/struct.Migrator.html), [configuración](https://docs.rs/sqlx/latest/sqlx/_config/_reference/index.html).

**Limitación:** no se encontró Cargo.toml ni Cargo.lock en la raíz inspeccionada del repositorio. No se puede confirmar versión SQLx fijada ni compatibilidad con una versión concreta. Antes de implementar, fijar versión y comprobar SQLx y CLI correspondientes.

## Alternativas

- Historial compartido: rechazado; mezcla estados, permisos y ownership de módulos. Cada módulo conserva su propia tabla `_sqlx_migrations`.
- Rol global: rechazado, no impone ownership.
- Roles por módulo con historial compartido: insuficiente.

## Estado de implementación

Decisión aceptada; roles, directorios, configuración y CI aún requieren implementación y evidencia.
