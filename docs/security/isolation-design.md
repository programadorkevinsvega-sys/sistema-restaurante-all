# Diseño de aislamiento por módulo y proceso

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0001, ADR-0008, ADR-0010, ADR-0021
**Documentos relacionados:**

- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Contrato de contexto autenticado](./authenticated-context-contract.md)

---

## 1. Propósito

Define el aislamiento multi-tenant y entre módulos en PostgreSQL, procesos y mensajería.
Los SQL históricos existentes son la base de datos diseñada para cada módulo y contienen
estructuras que deberán trasladarse a las rutas canónicas y corregirse cuando corresponda.
Este documento no crea ni modifica tablas, roles, políticas RLS, SQL ni código.

---

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

**Regla arquitectónica:** no se permiten FKs entre schemas de módulos distintos, vistas que cruzan schemas propietarios ni joins directos entre schemas en consultas de aplicación.

**Nota de auditoría de SQL histórico:** la inspección read-only identificó referencias entre schemas/módulos en el SQL histórico de IDENTITY. Son incompatibles con ADR-0001 y deben inventariarse y corregirse al preparar la distribución canónica de migraciones. No se modifican ni reescriben ahora los archivos históricos; cualquier corrección futura debe conservar trazabilidad y considerar si el SQL ya fue aplicado en algún entorno.

### 2.2 Roles PostgreSQL por módulo

Cada módulo tiene dos roles separados:

| Rol | Permisos | Uso |
|---|---|---|
| `<modulo>_migrator` | CREATE, ALTER, DROP sobre su schema; sin acceso a schemas ajenos | Solo durante migraciones |
| `<modulo>_runtime` | SELECT, INSERT, UPDATE, DELETE sobre tablas de su schema; sin DDL | Conexiones de aplicación en ejecución normal |

Adicionalmente, roles de sistema:

| Rol | Permisos | Uso |
|---|---|---|
| `backup_reader` | SELECT sobre todos los schemas | Solo para backup lógico |
| `monitoring_reader` | SELECT sobre pg\_stat\_* y schemas de observabilidad | Solo para monitoreo |

Los nombres exactos y el script de provisión se definen en la subfase 0.6. La revisión de SQL históricos no sustituye la provisión y verificación de estos roles; no se debe inferir que existen en una instancia PostgreSQL por aparecer en documentación.

### 2.3 Row-Level Security (RLS)

Todas las tablas que contienen datos de tenant deben aplicar RLS. Los SQL históricos ya contienen DDL RLS en determinados módulos/tablas; la cobertura completa debe auditarse contra el inventario real de tablas y columnas tenant-scoped. La presencia de DDL en Git no acredita que se haya ejecutado ni que proteja una base desplegada. La política base es:

```sql
-- Patrón de política RLS por tenant (diseño; no ejecutar)
CREATE POLICY tenant_isolation ON <schema>.<tabla>
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

El `tenant_id` del contexto lo establece la capa de aplicación antes de ejecutar cualquier
consulta, usando `SET LOCAL app.tenant_id = $1` dentro de la transacción. Nunca viene
del payload del cliente.

**Reglas de RLS:**

- RLS activo en todas las tablas con columna `tenant_id`.
- El valor de `app.tenant_id` lo establece el módulo propietario a partir del contexto
  autenticado validado, antes de cualquier consulta de la transacción.
- Nunca se usa `SET SESSION` para el tenant; siempre `SET LOCAL` dentro de la transacción
  para que el valor no persista entre transacciones del mismo pool.
- Los roles de migración (`*_migrator`) tienen `BYPASSRLS` solo durante la ejecución de
  migraciones en ventanas controladas; se revoca después.
- Para operaciones de plataforma que requieren acceso a múltiples tenants (reportes de
  plataforma, baja de tenant), se usa el rol de plataforma con permisos explícitos y
  trazabilidad completa en AUDIT.

### 2.4 Pools de conexiones separados

Cada módulo tiene su propio pool de conexiones, configurado con el rol `*_runtime`
correspondiente. No existe un pool compartido entre módulos.

Esto se desarrolla en detalle en la subfase 0.6 con el presupuesto de conexiones.

---

## 3. Aislamiento entre procesos

### 3.1 Sin acceso compartido a PostgreSQL entre procesos

Admin Platform Backend y Public Backend tienen credenciales PostgreSQL separadas.
Admin BFF y Public BFF no tienen acceso a PostgreSQL de negocio en ningún caso.

| Proceso | Acceso a PostgreSQL |
|---|---|
| Admin Platform Backend | Solo schema `platform` vía rol `platform_runtime` |
| Public Backend | Schemas de los 19 módulos de negocio, cada uno con su rol `*_runtime` |
| Admin BFF | Ninguno |
| Public BFF | Ninguno |

### 3.2 Comunicación entre procesos

Toda comunicación entre procesos usa gRPC con mTLS. No existen conexiones directas a
PostgreSQL cruzadas entre Admin Platform Backend y Public Backend.

Señales efímeras: NATS Core. Eventos durables: NATS JetStream con Outbox/Inbox.

### 3.3 Secretos por proceso y entorno

Cada proceso tiene credenciales propias: DSN de PostgreSQL, subjects NATS autorizados,
claves de API de proveedores y certificados TLS. No se comparten secretos entre procesos
ni entre entornos. Conforme a ADR-0023, AWS Secrets Manager administra secretos operativos,
AWS KMS custodia claves privadas de firma y AWS IAM otorga permisos mínimos a workloads.
La gestión concreta de certificados mTLS se define en 0.7.

---

## 4. Aislamiento en mensajería

### 4.1 Subjects NATS por módulo

Cada módulo publica en subjects con prefijo de su propiedad:
`<backend>.<modulo>.<evento>.<version>` — ej. `public.sales.order_created.v1`.

Un módulo no publica en subjects de otro módulo. Los consumidores se suscriben solo a los
subjects que les corresponden según su contrato explícito.

### 4.2 Outbox/Inbox por módulo

Cada módulo tiene su propia tabla Outbox e Inbox dentro de su schema. No existe una tabla
Outbox compartida entre módulos.

El dispatcher del Outbox lee solo del schema del módulo que lo posee.

### 4.3 Identidad de worker en NATS

Cada worker tiene credenciales NATS propias con permisos de publish/subscribe acotados
a los subjects que necesita. No existe una cuenta NATS con acceso total para workers.

---

## 5. Verificación de aislamiento

Antes de cualquier despliegue productivo, se ejecutarán las siguientes pruebas:

| Prueba | Tipo | Fase |
|---|---|---|
| Consulta directa entre schemas de módulos distintos debe fallar | Integración | 0.6 |
| `SET LOCAL app.tenant_id` aísla correctamente filas entre tenants | Integración | 0.6 |
| `SET SESSION` no persiste el tenant entre transacciones del pool | Integración | 0.6 |
| Worker sin `tenant_id` no puede ejecutar operación de negocio | Seguridad | 0.4/0.6 |
| BFF sin acceso a PostgreSQL de negocio (error de conexión esperado) | Integración | 0.7 |
| Subject NATS de un módulo no admite publicación de otro módulo | Integración | 0.9 |

---

## 6. Estado de implementación

Diseño aprobado. Los SQL históricos contienen tablas y DDL de seguridad/RLS para determinados módulos, pero no se ha acreditado su aplicación en una instancia ni la provisión de roles runtime/migrator, pools, credenciales NATS o controles de aplicación. La cobertura RLS y las referencias cruzadas entre schemas requieren auditoría completa en 0.6. No se modifican SQL históricos en esta subfase documental. La implementación y verificación se realizan en 0.6, 0.7 y 0.9 según el control.
