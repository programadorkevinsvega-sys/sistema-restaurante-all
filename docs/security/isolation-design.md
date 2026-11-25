# Diseño de aislamiento por módulo y proceso

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0001, ADR-0008, ADR-0010, ADR-0021, ADR-0028
**Documentos relacionados:**
- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Contrato de contexto autenticado](./authenticated-context-contract.md)

---

## 1. Propósito

Define el aislamiento multi-tenant y entre módulos en PostgreSQL, procesos y mensajería.
Los SQL históricos existentes son la base de datos diseñada para cada módulo y contienen
estructuras que deberán trasladarse a las rutas canónicas y corregirse cuando corresponda.
Este documento no crea ni modifica tablas, roles, políticas RLS, SQL ni código.

## 2. Aislamiento en PostgreSQL

### 2.1 Schema por módulo

Cada módulo tiene un schema PostgreSQL propio. Ningún módulo consulta, escribe ni referencia
tablas de otro módulo.

| Módulo | Schema | Backend propietario |
|---|---|---|
| PLATFORM | `platform` | Admin Platform Backend |
| IDENTITY | `identity` | Public Backend |
| ORGANIZATION | `organization` | Public Backend |
| CATALOG | `catalog` | Public Backend |
| SALES | `sales` | Public Backend |
| PAYMENTS | `payments` | Public Backend |
| CASH | `cash` | Public Backend |
| KITCHEN | `kitchen` | Public Backend |
| INVENTORY | `inventory` | Public Backend |
| PROCUREMENT | `procurement` | Public Backend |
| PRODUCTION | `production` | Public Backend |
| BILLING | `billing` | Public Backend |
| FINANCE | `finance` | Public Backend |
| WORKFORCE | `workforce` | Public Backend |
| CUSTOMERS | `customers` | Public Backend |
| INTEGRATIONS | `integrations` | Public Backend |
| AUTOMATION | `automation` | Public Backend |
| ANALYTICS | `analytics` | Public Backend |
| AUDIT | `audit` | Public Backend |
| REPORTING | `reporting` | Public Backend |

**Regla arquitectónica:** no se permiten FKs entre schemas de módulos distintos, vistas que
cruzan schemas propietarios ni joins directos entre schemas en consultas de aplicación.

**Nota de auditoría de SQL histórico:** la inspección read-only identificó referencias entre
schemas/módulos en el SQL histórico de IDENTITY. Son incompatibles con ADR-0001 y deben
inventariarse y corregirse al preparar la distribución canónica de migraciones. No se modifican
ni reescriben ahora los archivos históricos; cualquier corrección futura debe conservar
trazabilidad y considerar si el SQL ya fue aplicado en algún entorno.

### 2.2 Roles PostgreSQL por módulo

Cada módulo tiene dos roles separados:

| Rol | Permisos | Uso |
|---|---|---|
| `<modulo>_migrator` | CREATE, ALTER, DROP sobre su schema; sin acceso a schemas ajenos | Solo durante migraciones |
| `<modulo>_runtime` | SELECT, INSERT, UPDATE, DELETE sobre tablas de su schema; sin DDL | Aplicación normal |

Los roles de sistema `backup_reader` y `monitoring_reader` tienen alcance separado y mínimo.
Los nombres exactos y el script de provisión se definen en 0.6. La documentación no demuestra
que esos roles existan en una instancia PostgreSQL.

### 2.3 Row-Level Security (RLS)

Todas las tablas que contienen datos de tenant deben aplicar RLS. Los SQL históricos ya
contienen DDL RLS en determinados módulos/tablas; la cobertura completa debe auditarse contra
el inventario real de tablas y columnas tenant-scoped. La presencia de DDL en Git no acredita
que se haya ejecutado ni que proteja una base desplegada.

Patrón de política:

```sql
CREATE POLICY tenant_isolation ON <schema>.<tabla>
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

El `tenant_id` lo establece el módulo propietario a partir del contexto autenticado validado,
usando `SET LOCAL app.tenant_id` dentro de la transacción. Nunca procede del payload del cliente.

Reglas:
- RLS activo y forzado cuando corresponda en todas las tablas tenant-scoped.
- `SET LOCAL` por transacción; nunca `SET SESSION` para el tenant.
- Roles migrator con `BYPASSRLS` solo en ventanas controladas y sin credenciales runtime.
- El acceso excepcional de plataforma a datos de negocio requiere autorización explícita del
  módulo propietario y trazabilidad en AUDIT; no se concede por el rol PostgreSQL de PLATFORM.

### 2.4 Pools separados

Cada módulo tiene su propio pool configurado con su rol `*_runtime`. El presupuesto y la
configuración se desarrollan en 0.6.

## 3. Aislamiento entre procesos

Admin Platform Backend y Public Backend tienen credenciales PostgreSQL separadas. Los BFF no
tienen acceso a PostgreSQL de negocio.

| Proceso | Acceso |
|---|---|
| Admin Platform Backend | Solo schema `platform` |
| Public Backend | Schemas de los 19 módulos de negocio, cada uno con rol `*_runtime` |
| Admin BFF | Ninguno |
| Public BFF | Ninguno |

Toda comunicación entre procesos usa gRPC con mTLS y contexto autenticado firmado conforme
al contrato de contexto y ADR-0028. No hay conexiones PostgreSQL cruzadas entre backends.

## 4. Secretos por proceso y entorno

Cada proceso tiene credenciales propias y separadas por entorno. Conforme a ADR-0028:
AWS Secrets Manager administra secretos operativos que deban existir; AWS KMS custodia claves
privadas de firma; AWS IAM concede permisos mínimos a workloads. No se instalará Vault
autogestionado. La plataforma de ejecución y gestión concreta de certificados mTLS se define
en 0.7.

## 5. Mensajería y workers

Cada módulo publica solo en sus subjects autorizados. Outbox/Inbox son propiedad de cada
módulo. Cada worker usa identidad propia y ACL NATS limitadas; no hereda la sesión humana
originadora ni obtiene permisos globales.

## 6. Verificación de aislamiento

| Prueba | Tipo | Fase |
|---|---|---|
| Consulta entre schemas propietarios distintos debe fallar | Integración | 0.6 |
| `SET LOCAL app.tenant_id` aísla filas entre tenants | Integración | 0.6 |
| `SET SESSION` no persiste tenant entre transacciones del pool | Integración | 0.6 |
| Worker sin tenant/contexto válido no ejecuta operación | Seguridad | 0.4/0.6 |
| BFF sin acceso a PostgreSQL de negocio | Integración | 0.7 |
| Subject NATS de otro módulo no permite publicar | Integración | 0.9 |
| Firma, audiencia, emisor y mTLS se validan entre procesos | Seguridad | 0.4/0.7 |

## 7. Estado de diseño e implementación

Los SQL históricos contienen tablas y DDL de seguridad/RLS para determinados módulos, pero
no se ha acreditado aquí su aplicación en una instancia ni la provisión de roles runtime/
migrator, pools, credenciales NATS o controles de aplicación. La cobertura RLS y las
referencias cruzadas entre schemas requieren auditoría completa en 0.6. No se modifican SQL
históricos en esta subfase documental. La implementación y verificación se realizan en 0.6,
0.7 y 0.9 según el control.
