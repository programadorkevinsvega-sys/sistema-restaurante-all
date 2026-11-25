# Diseño de PostgreSQL HA y réplicas — subfase 0.6

**Estado:** diseño aprobado — subfase 0.6
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.6
**Autoridad:** ADR-0001, ADR-0010, ADR-0012, ADR-0021
**Base:** [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md)
**Documentos relacionados:**

- [Presupuesto de conexiones](./connection-budget.md)
- [Estrategia UUIDv7](./uuid-strategy.md)
- [Diseño Outbox/Inbox/Saga](./outbox-inbox-saga-design.md)
- [Plan backup/restore/PITR](./backup-restore-plan.md)

---

## 1. Propósito

Concreta la topología, roles, routing y controles operativos de PostgreSQL para Restaurant OS.
Es un diseño; no despliega nodos, ni crea roles, credenciales ni configuración.

---

## 2. Topología objetivo

```text
                    Gestor HA (Patroni o equivalente)
                               |
              ┌────────────────┴────────────────┐
              │                                 │
     Endpoint escritura                Endpoint lectura
              │                                 │
       PostgreSQL Primary              Réplicas hot standby
              │                          /            \
       ┌──────┴──────┐          Standby síncrono   Standby(s) asíncronos
       WAL streaming  WAL streaming
```

- **Primario:** único nodo que acepta escrituras.
- **Standby síncrono:** al menos uno; requerido para commits críticos con durabilidad garantizada.
- **Standbys asíncronos:** uno o más; destinados a lectura elegible y recuperación con RPO explícito.
- **Gestor HA:** Patroni o equivalente; responsable de fencing, promoción y publicación de endpoints.
- **Versión objetivo:** PostgreSQL 19.0.

---

## 3. Schemas y roles por módulo

Cada módulo tiene exactamente dos roles PostgreSQL y un schema propio.

| Módulo | Schema | Rol migración | Rol runtime |
|---|---|---|---|
| PLATFORM | `platform` | `platform_migrator` | `platform_runtime` |
| IDENTITY | `identity` | `identity_migrator` | `identity_runtime` |
| ORGANIZATION | `organization` | `organization_migrator` | `organization_runtime` |
| CATALOG | `catalog` | `catalog_migrator` | `catalog_runtime` |
| SALES | `sales` | `sales_migrator` | `sales_runtime` |
| PAYMENTS | `payments` | `payments_migrator` | `payments_runtime` |
| CASH | `cash` | `cash_migrator` | `cash_runtime` |
| KITCHEN | `kitchen` | `kitchen_migrator` | `kitchen_runtime` |
| INVENTORY | `inventory` | `inventory_migrator` | `inventory_runtime` |
| PROCUREMENT | `procurement` | `procurement_migrator` | `procurement_runtime` |
| PRODUCTION | `production` | `production_migrator` | `production_runtime` |
| BILLING | `billing` | `billing_migrator` | `billing_runtime` |
| FINANCE | `finance` | `finance_migrator` | `finance_runtime` |
| WORKFORCE | `workforce` | `workforce_migrator` | `workforce_runtime` |
| CUSTOMERS | `customers` | `customers_migrator` | `customers_runtime` |
| INTEGRATIONS | `integrations` | `integrations_migrator` | `integrations_runtime` |
| AUTOMATION | `automation` | `automation_migrator` | `automation_runtime` |
| ANALYTICS | `analytics` | `analytics_migrator` | `analytics_runtime` |
| AUDIT | `audit` | `audit_migrator` | `audit_runtime` |
| REPORTING | `reporting` | `reporting_migrator` | `reporting_runtime` |

**Roles de sistema adicionales:**

| Rol | Permisos | Uso |
|---|---|---|
| `backup_reader` | `SELECT` en todos los schemas | Solo backup lógico |
| `monitoring_reader` | `SELECT` en `pg_stat_*` | Solo monitoreo |
| `replication_user` | `REPLICATION` | Solo replicación física |

**Reglas de roles:**

- `*_migrator`: DDL sobre su propio schema; sin acceso a schemas ajenos; `BYPASSRLS` solo durante ventanas de migración controladas.
- `*_runtime`: DML sobre tablas de su schema; sin DDL; sin acceso a schemas ajenos; RLS activo.
- Ningún rol de runtime tiene permisos sobre schemas de otros módulos.
- Credenciales separadas por entorno (producción, staging, desarrollo).

---

## 4. Row-Level Security (RLS)

Todas las tablas con columna `tenant_id` tienen RLS activo.

**Patrón de política:**

```sql
-- Diseño; no ejecutar sin autorización expresa
ALTER TABLE <schema>.<tabla> ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON <schema>.<tabla>
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

**Reglas de RLS:**

- El valor de `app.tenant_id` lo establece el módulo propietario con `SET LOCAL` dentro de la transacción, derivado del contexto autenticado validado.
- Nunca `SET SESSION`; siempre `SET LOCAL` para que el valor no persista entre transacciones del pool.
- Los roles `*_migrator` tienen `BYPASSRLS` solo durante la ejecución controlada de migraciones.
- Para operaciones multi-tenant de plataforma (baja de tenant, reportes globales), se usa el rol de plataforma con permisos explícitos y trazabilidad en AUDIT.

---

## 5. Routing de lectura/escritura

| Tipo de operación | Nodo destino | Justificación |
|---|---|---|
| Escrituras, comandos, transacciones | Primario | Único nodo que acepta escrituras |
| Autorización, sesiones, permisos | Primario | Consistencia inmediata requerida |
| Pagos, cobros, saldos, caja | Primario | Consistencia financiera crítica |
| Disponibilidad de inventario para decisión | Primario | Determina escritura inmediata |
| Idempotencia y deduplicación | Primario | Debe reflejar escrituras recientes |
| Lectura posterior a escritura propia | Primario | Read-your-writes |
| Reporting, dashboards, analítica | Réplica elegible | Toleran staleness declarada |
| Búsquedas y listados no críticos | Réplica elegible | Alta frecuencia, staleness aceptable |
| Exploración histórica | Réplica elegible | Frescura declarada explícitamente |

La clasificación `SELECT` no convierte automáticamente una consulta en elegible para réplica.
La semántica del negocio determina el routing, no el verbo SQL.

---

## 6. Migraciones

- Se ejecutan contra el primario únicamente.
- Cada módulo mantiene su directorio `backend/<backend>/modules/<modulo>/migrations/`.
- El historial SQLx es `<schema>._sqlx_migrations`; exclusivo por módulo.
- Una migración se aplica una sola vez por módulo/versión; nunca por nodo.
- Las réplicas reciben cambios de esquema por replicación física.
- Este documento no autoriza ejecutar migraciones ni modificar SQL.

---

## 7. Estado de implementación

Diseño aprobado. No existen nodos desplegados, roles creados, políticas RLS activas,
pools configurados ni credenciales emitidas. La implementación comienza en la fase de
despliegue de infraestructura (subfase 0.7).
