# Matriz de ownership, contratos y dependencias

**Estado:** diseño documental de la subfase 0.1; no representa implementación.  
**Ámbito:** los 20 módulos canónicos y los cuatro procesos de Restaurant OS.  
**Fuentes normativas:** ADR-0001, ADR-0002, ADR-0005, ADR-0007, ADR-0008 y ADR-0009; `requisitos.md`; estándares de arquitectura.

## 1. Propósito y precedencia

Este documento consolida la propiedad de módulos, sus límites de persistencia y la ubicación de sus contratos. No crea módulos, no asigna dependencias funcionales que no hayan sido justificadas y no modifica decisiones aceptadas.

La precedencia es obligatoria: los ADR Accepted gobiernan las decisiones arquitectónicas; `requisitos.md` es la fuente de verdad de requisitos, ownership y ubicación física; los estándares desarrollan esas decisiones; este catálogo las hace trazables. La topología histórica de dos procesos descrita en ADR-0005 está sustituida parcialmente por ADR-0007. Se conserva únicamente la obligación de definir Protobuf versionado y usar gRPC en las fronteras entre procesos.

## 2. Procesos y ownership

| Proceso independiente | Responsabilidad | Módulos propietarios |
|---|---|---|
| Admin Platform Backend | Backend SaaS y ciclo de vida de la plataforma | PLATFORM |
| Admin BFF | Composición y exposición HTTP/OpenAPI administrativa | Ninguno |
| Public BFF | Composición y exposición HTTP/OpenAPI pública y operativa | Ninguno |
| Public Backend | Backend de los dominios de negocio | Los otros 19 módulos canónicos |

Los BFF no poseen dominios, schemas PostgreSQL ni tablas de negocio. Una interfaz administrativa no cambia el propietario de los datos: la operación debe llegar al contrato del módulo propietario.

## 3. Inventario módulo → proceso → persistencia → contratos

Los schemas indicados se corresponden con los nombres observados en las migraciones históricas existentes. Su presencia en SQL histórico no significa que los roles, permisos, migraciones nuevas o runners estén provisionados.

Para cada módulo:

- El rol PostgreSQL debe ser dedicado y limitado a su schema. Se separan las identidades de migración y runtime; los nombres físicos de esos roles deben fijarse en el diseño operativo de PostgreSQL, sin inventarlos en este catálogo.
- El historial SQLx es exclusivo y schema-qualified: `<schema>._sqlx_migrations`.
- La ruta canónica para migraciones nuevas es `backend/<backend-propietario>/modules/<modulo>/migrations/`. Los archivos listados como históricos permanecen en `migrations/` y no se mueven ni reescriben en esta subfase.
- El crate público Rust del módulo vive en `backend/<backend-propietario>/modules/<modulo>/contracts/`.
- La fuente Protobuf vive en `contracts/protobuf/<backend-propietario>/<modulo>/v1/`; Protobuf define contratos gRPC, no reemplaza el contrato público local.

| Módulo | Proceso propietario | Schema histórico | Migración(es) histórica(s) | Historial SQLx objetivo |
|---|---|---|---|---|
| PLATFORM | Admin Platform Backend | `platform` | `modulo_0_admin_plataforma_postgresql.sql` | `platform._sqlx_migrations` |
| IDENTITY | Public Backend | `identity` | `modulo_2_identity_usuarios_seguridad_postgresql.sql` | `identity._sqlx_migrations` |
| ORGANIZATION | Public Backend | `organization` | `modulo_1_organization_postgresql.sql` | `organization._sqlx_migrations` |
| CATALOG | Public Backend | `catalog` | `modulo_3_catalog_postgresql.sql` | `catalog._sqlx_migrations` |
| SALES | Public Backend | `sales` | `modulo_4_sales_postgresql.sql` | `sales._sqlx_migrations` |
| PAYMENTS | Public Backend | `payments` | `modulo_10_payments_postgresql.sql` | `payments._sqlx_migrations` |
| CASH | Public Backend | `cash` | `modulo_11_cash_postgresql.sql` | `cash._sqlx_migrations` |
| KITCHEN | Public Backend | `kitchen` | `modulo_5_kitchen_postgresql.sql` | `kitchen._sqlx_migrations` |
| INVENTORY | Public Backend | `inventory` | `modulo_6_inventory_postgresql.sql` | `inventory._sqlx_migrations` |
| PROCUREMENT | Public Backend | `procurement` | `modulo_7_procurement_postgresql.sql`; `modulo_9_procurement_operaciones_postgresql.sql` | `procurement._sqlx_migrations` |
| PRODUCTION | Public Backend | `production` | `modulo_8_production_postgresql.sql` | `production._sqlx_migrations` |
| BILLING | Public Backend | `billing` | `modulo_15_billing_postgresql.sql` | `billing._sqlx_migrations` |
| FINANCE | Public Backend | `finance` | `modulo_14_finance_postgresql.sql` | `finance._sqlx_migrations` |
| WORKFORCE | Public Backend | `workforce` | `modulo_13_workforce_postgresql.sql` | `workforce._sqlx_migrations` |
| CUSTOMERS | Public Backend | `customers` | `modulo_12_customers_postgresql.sql` | `customers._sqlx_migrations` |
| INTEGRATIONS | Public Backend | `integrations` | `modulo_17_integrations_postgresql.sql` | `integrations._sqlx_migrations` |
| AUTOMATION | Public Backend | `automation` | `modulo_16_automation_postgresql.sql` | `automation._sqlx_migrations` |
| ANALYTICS | Public Backend | `analytics` | `modulo_18_analytics_postgresql.sql` | `analytics._sqlx_migrations` |
| AUDIT | Public Backend | `audit` | `modulo_19_audit_postgresql.sql` | `audit._sqlx_migrations` |
| REPORTING | Public Backend | `reporting` | `modulo_20_reporting_postgresql.sql` | `reporting._sqlx_migrations` |

La ubicación de cada crate de contrato y de cada fuente Protobuf se obtiene aplicando las rutas canónicas anteriores al backend y módulo de la fila. No se crean aquí manifests, crates, archivos Protobuf, schemas, roles ni migraciones.

## 4. Catálogo y ownership de contratos/eventos

Cada módulo es propietario de su contrato público y de los eventos que publica. Los consumidores dependen únicamente de contratos públicos; nunca importan implementaciones internas, entidades de dominio ni modelos SQL de otro módulo.

Conforme a ADR-0005, ADR-0009 y el estándar de ingeniería, cada uno de los 20 módulos mantiene desde el inicio un crate público Rust `<modulo>-contracts` y un contrato Protobuf versionado equivalente a su interfaz pública, aunque la primera implementación sea local. Esto no obliga a transportar por gRPC las llamadas entre módulos del mismo backend: esas llamadas usan puertos/traits y el adaptador local. gRPC se utiliza en las fronteras entre procesos, conforme a ADR-0007. OpenAPI es la fuente de verdad de las superficies HTTP expuestas por los BFF; los BFF componen y traducen contratos, pero no adquieren ownership de los módulos ni de sus datos.

| Tipo de interacción | Mecanismo autorizado | Condición |
|---|---|---|
| Consulta/comando entre módulos del mismo backend | Puerto/trait del contrato público y adaptador local | DTO públicos; sin imports internos ni acceso a tablas ajenas |
| Solicitud/respuesta entre procesos | gRPC con Protobuf versionado | La frontera y el contrato pertenecen al proceso/módulo propietario |
| Superficie HTTP de BFF | OpenAPI versionado | OpenAPI es la fuente de verdad HTTP; el BFF no adquiere ownership de dominio ni persistencia |
| Señal efímera entre procesos | NATS Core | No se usa cuando se requiere durabilidad |
| Evento durable entre procesos | NATS JetStream | Outbox/Inbox, ACK, reintentos y consumidor idempotente según ADR aplicables |

No se inventa un grafo de dependencias ni un inventario de eventos futuros. Cada contrato/evento concreto se registra cuando exista un caso de uso aprobado y debe incluir, como mínimo:

- Identificador y versión del contrato/evento.
- Módulo productor y propietario.
- Consumidores autorizados y justificación del caso de uso.
- Semántica síncrona/efímera/durable.
- Ubicación de la fuente y política de compatibilidad.
- Clave de idempotencia y tratamiento de duplicados cuando aplique.
- Clasificación de datos y reglas de redacción/minimización.
- Pruebas de contrato y evidencia de compatibilidad.

Los nombres de eventos sugeridos en comentarios de migraciones históricas son pistas de diseño, no contratos aprobados ni autorización para publicar eventos.

## 5. Matriz de dependencias permitidas y prohibidas

### Permitidas

1. Un módulo consume capacidades ajenas únicamente mediante el contrato público del módulo propietario.
2. Los módulos que comparten backend pueden usar adaptadores locales que implementen los mismos puertos que los adaptadores gRPC.
3. Las llamadas síncronas entre procesos usan gRPC/Protobuf versionado.
4. Los eventos durables usan el mecanismo Outbox/Inbox y mensajería durable aprobado.
5. Un consumidor puede mantener proyecciones propias alimentadas por contratos/eventos; la proyección pertenece al consumidor y no sustituye la fuente autoritativa.
6. Toda dependencia entre módulos debe justificarse por un caso de uso, contrato, dirección de dependencia y propietario explícito.

### Prohibidas

- Importar domain, application, adapters, infrastructure, repositorios o modelos internos de otro módulo.
- Consultar, modificar o unir directamente tablas de otro módulo.
- Crear FKs, vistas o joins entre schemas propietarios distintos.
- Compartir tablas de historial SQLx o credenciales globales de migración/runtime.
- Hacer que un BFF consulte PostgreSQL de negocio o se convierta en propietario de datos.
- Crear un bus global o dependencia implícita que oculte qué módulo consume a cuál.
- Deducir dependencias por el orden de lotes, prefijos históricos `modulo_N` o proximidad de carpetas.
- Convertir una llamada local en permiso para saltarse contratos públicos.

## 6. Checklist de revisión arquitectónica

Antes de aceptar un cambio de arquitectura, contrato o dependencia, verificar:

- [ ] El módulo y su propietario coinciden con ADR-0008 y `requisitos.md`.
- [ ] El cambio no duplica ni reasigna un módulo.
- [ ] El contrato pertenece al módulo proveedor y no expone entidades ni modelos SQL.
- [ ] La dirección de dependencia está justificada por un caso de uso concreto.
- [ ] El transporte corresponde a la frontera y semántica de la interacción.
- [ ] No existen FKs, joins, vistas ni consultas directas entre schemas propietarios.
- [ ] No se concede persistencia de negocio a ningún BFF.
- [ ] La evolución del contrato mantiene versionado y compatibilidad.
- [ ] Los eventos tienen productor propietario, consumidores explícitos e idempotencia cuando aplique.
- [ ] Los datos sensibles están clasificados y no se filtran a contratos, eventos, logs o trazas.
- [ ] Los cambios de ownership o desviaciones cuentan con ADR Proposed y aprobación antes de implementarse.
- [ ] La documentación, índices y referencias cruzadas quedan sincronizados.

## 7. Límites y pendientes de esta subfase

- Los nombres exactos de roles PostgreSQL y su provisión se concretarán en el diseño operativo de datos/infraestructura; este documento exige roles separados y dedicados, pero no declara que existan.
- La topología de cuatro procesos y ownership están aceptados documentalmente; los cuatro binarios y sus despliegues no se consideran implementados por este catálogo.
- Los contratos Protobuf, contratos Rust y esquemas de eventos concretos se crearán con las tareas de implementación autorizadas; este catálogo no los inventa ni los genera.
- La existencia de migraciones SQL históricas no autoriza moverlas, reescribirlas ni ejecutarlas.
- Esta subfase no implementa código, crates, endpoints, CI, infraestructura, roles, schemas ni migraciones.

## 8. Referencias normativas

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](../adr/0001-postgres-module-ownership-and-migrations.md)
- [ADR-0002: OpenAPI, Protobuf y código generado](../adr/0002-openapi-protobuf-generated-clients.md)
- [ADR-0005: Contratos Protobuf y gRPC desde el inicio](../adr/0005-grpc-contracts-from-day-one.md)
- [ADR-0007: Cuatro backends independientes y comunicación](../adr/0007-four-independent-backends-and-communication.md)
- [ADR-0008: Distribución de módulos entre cuatro procesos](../adr/0008-module-ownership-across-four-processes.md)
- [ADR-0009: Límites de crates y dirección de dependencias](../adr/0009-crate-boundaries-and-dependencies.md)
- [Estándar general de arquitectura](./engineering-standard.md)
- [Arquitectura de Restaurant OS](./restaurant-os-architecture.md)
- [Diseño de crates y dependencias](./crate-architecture.md)
- [Reglas de implementación](../engineering/implementation-rules.md)
- [Requisitos generales](../../requisitos.md)
- [Plan maestro de ejecución](../planning/master-execution-plan.md)
