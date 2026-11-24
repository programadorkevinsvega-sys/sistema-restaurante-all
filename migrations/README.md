# Migraciones por módulo

## Regla normativa

Las migraciones pertenecen exclusivamente al módulo propietario. La ruta canónica para **nuevas** migraciones es:

```text
backend/<backend>/modules/<modulo>/migrations/
```

Cada módulo mantiene, sin excepción:

- Un schema PostgreSQL propio.
- Un rol de migración dedicado y limitado a su schema.
- Un directorio de migraciones propio en la ruta canónica.
- Una tabla de historial SQLx exclusiva, schema-qualified dentro de su propio schema, por ejemplo `identity._sqlx_migrations`.
- Una secuencia de versiones independiente dentro de su historial.

**Está prohibido compartir una tabla `_sqlx_migrations` entre módulos.** No se exige que las versiones sean globalmente únicas entre módulos, porque cada módulo consulta y actualiza únicamente su propio historial. No ejecutar directorios de distintos módulos contra una misma tabla de historial.

## Configuración SQLx

SQLx utiliza `_sqlx_migrations` como nombre predeterminado. Cada runner/módulo debe configurar explícitamente su directorio y el nombre schema-qualified de su tabla, por ejemplo:

```toml
[migrate]
migrations-dir = "backend/<backend>/modules/identity/migrations"
table-name = "identity._sqlx_migrations"
```

`sqlx::migrate!()` y SQLx CLI pueden leer la configuración aplicable al crate. Un `Migrator` construido manualmente debe configurar explícitamente su tabla; no se debe asumir que hereda automáticamente `sqlx.toml`. La compatibilidad exacta debe comprobarse contra la versión SQLx y SQLx CLI fijada en los manifests/lockfile del proyecto antes de implementar runners.

## Ubicaciones históricas conservadas

La carpeta raíz `migrations/` contiene migraciones históricas existentes. Se conservan en su ubicación actual y no se mueven, renombran, reescriben ni eliminan en esta corrección documental. La siguiente tabla documenta su correspondencia funcional; no convierte esos archivos en la ubicación canónica para nuevas migraciones.

| Ubicación histórica | Módulo propietario |
|---|---|
| `migrations/modulo_0_admin_plataforma_postgresql.sql` | PLATFORM |
| `migrations/modulo_1_organization_postgresql.sql` | ORGANIZATION |
| `migrations/modulo_2_identity_usuarios_seguridad_postgresql.sql` | IDENTITY |
| `migrations/modulo_3_catalog_postgresql.sql` | CATALOG |
| `migrations/modulo_4_sales_postgresql.sql` | SALES |
| `migrations/modulo_5_kitchen_postgresql.sql` | KITCHEN |
| `migrations/modulo_6_inventory_postgresql.sql` | INVENTORY |
| `migrations/modulo_7_procurement_postgresql.sql` | PROCUREMENT |
| `migrations/modulo_8_production_postgresql.sql` | PRODUCTION |
| `migrations/modulo_9_procurement_operaciones_postgresql.sql` | PROCUREMENT |
| `migrations/modulo_10_payments_postgresql.sql` | PAYMENTS |
| `migrations/modulo_11_cash_postgresql.sql` | CASH |
| `migrations/modulo_12_customers_postgresql.sql` | CUSTOMERS |
| `migrations/modulo_13_workforce_postgresql.sql` | WORKFORCE |
| `migrations/modulo_14_finance_postgresql.sql` | FINANCE |
| `migrations/modulo_15_billing_postgresql.sql` | BILLING |
| `migrations/modulo_16_automation_postgresql.sql` | AUTOMATION |
| `migrations/modulo_17_integrations_postgresql.sql` | INTEGRATIONS |
| `migrations/modulo_18_analytics_postgresql.sql` | ANALYTICS |
| `migrations/modulo_19_audit_postgresql.sql` | AUDIT |
| `migrations/modulo_20_reporting_postgresql.sql` | REPORTING |

Los prefijos históricos `modulo_N` identifican lotes/secuencia histórica, no una identidad técnica permanente. El lote 9 también pertenece a PROCUREMENT; no se renumera ni se deduce de él un dominio adicional.

## Reglas de ejecución y seguridad

- Ejecutar migraciones desde un proceso controlado de despliegue, no desde cada réplica de la aplicación.
- Cada runner usa únicamente el rol y el historial del módulo que migra.
- El rol de runtime no tiene DDL ni privilegios globales.
- No ejecutar todos los directorios bajo un historial compartido.
- No renumerar, reescribir ni eliminar migraciones que puedan haberse aplicado.
- Si una migración ya se aplicó en algún entorno, cualquier corrección posterior se realiza mediante una migración nueva y compatible; nunca editando el archivo histórico.
- Probar cada módulo desde una base vacía y desde las versiones anteriores que el proyecto declare compatibles.
- FKs, joins y consultas directas solo dentro del límite del mismo módulo. Las referencias entre módulos usan IDs estables y contratos.

Ver [ADR-0001](../docs/adr/0001-postgres-module-ownership-and-migrations.md) y [Reglas de implementación](../docs/engineering/implementation-rules.md#2-postgresql-roles-y-migraciones-sqlx).
