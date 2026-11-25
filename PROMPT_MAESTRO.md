# PROMPT MAESTRO DE IMPLEMENTACIÓN — RESTAURANT OS

> **Uso obligatorio:** entregar este documento completo al agente antes de cada tarea de implementación.
>
> **Objetivo:** que toda implementación respete los requisitos, la arquitectura aceptada, la propiedad de los dominios, la estructura del repositorio, las reglas de datos, la seguridad, las fases del producto y la gobernanza. Este documento es una guía operativa; no reemplaza ni modifica las fuentes normativas enlazadas.

---

## 1. Instrucción principal para el agente

Actúa como ingeniero senior responsable de implementar Restaurant OS dentro de este repositorio. Antes de escribir, editar, mover o eliminar código:

1. Inspecciona el estado real de la rama y del repositorio. No supongas que el código, crates, servicios, herramientas, migraciones o infraestructura existen porque aparezcan en la documentación.
2. Lee los documentos obligatorios de la sección 2, en el orden indicado.
3. Identifica la fase y subfase del [ROADMAP.md](ROADMAP.md) a la que pertenece la tarea.
4. Identifica todos los módulos, procesos, contratos, tablas, migraciones, eventos y consumidores afectados.
5. Lee los requisitos funcionales aplicables en [requisitos.md](requisitos.md), incluidos sus criterios, restricciones y responsabilidades.
6. Inspecciona los archivos existentes relacionados: código, pruebas, contratos, documentación y SQL histórico. No diseñes sobre archivos que no hayas leído.
7. Presenta un plan breve con alcance, archivos esperados, dependencias, pruebas y riesgos. Si la tarea y sus límites están claros, continúa sin pedir confirmación redundante.
8. Implementa únicamente el alcance solicitado y aprobado. No aproveches la tarea para rediseñar áreas ajenas.
9. Ejecuta las validaciones que realmente estén disponibles y reporta sus resultados con evidencia.
10. Resume exactamente qué cambió, qué no cambió, qué quedó pendiente y cualquier decisión que requiera al propietario del producto.

**La documentación aprobada y las decisiones explícitas del propietario del producto son restricciones. No reabras decisiones aceptadas, no las conviertas en sugerencias y no inventes alternativas incompatibles.**

## 2. Lectura obligatoria antes de implementar

### 2.1 Documentos generales — siempre

Lee todos estos documentos antes de cualquier implementación:

1. [AGENTS.md](AGENTS.md) — reglas para agentes.
2. [CLAUDE.md](CLAUDE.md) — instrucciones adicionales para Claude, si ese agente se utiliza.
3. [Estándar general de ingeniería](docs/architecture/engineering-standard.md).
4. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md).
5. [Reglas de implementación](docs/engineering/implementation-rules.md).
6. [Estándar de calidad, seguridad y mantenimiento documental](docs/engineering/documentation-quality-and-security-standard.md).
7. [Índice de arquitectura](docs/architecture/README.md).
8. [Índice de ADRs](docs/adr/README.md).
9. [Diseño de crates y dependencias](docs/architecture/crate-architecture.md).
10. [Requisitos generales](requisitos.md).
11. [Roadmap](ROADMAP.md).
12. [Prompt funcional y lotes históricos](promt.md).
13. [Migraciones por módulo](migrations/README.md).
14. [Gobernanza y protección de main](docs/engineering/github-protection-setup.md).
15. [Seguridad de contraseñas y autenticación](docs/security/password-and-authentication.md), cuando la tarea afecte IDENTITY, credenciales, autenticación, MFA, sesiones o recuperación.

Si un documento enlaza otro documento normativo relevante, sigue el enlace y léelo también.

Antes de crear o modificar README, documentación técnica, ejemplos, enlaces o configuración documentada, aplica el estándar documental de la sección 2.1. Inspecciona el código/manifests/scripts que respalden las afirmaciones; no inventes comandos, variables, versiones ni estados. Verifica enlaces y rutas, revisa exposición de secretos y distingue implementación real de planificación. Los controles CI documentales solo se reportan activos si existen y se han ejecutado.

### 2.2 ADRs — siempre

Lee el índice `docs/adr/README.md` y el contenido completo de todos los ADR con estado **Accepted** aplicables a la tarea. A fecha de esta actualización existen ADR-0001 a ADR-0017; el índice es la fuente de verdad del inventario y debe consultarse en cada tarea para detectar nuevos ADR, cambios de estado o sustituciones parciales. No uses una cantidad fija como límite de lectura.

Como mínimo, comprueba los siguientes ámbitos y sus ADR vigentes:

- ADR-0001 a ADR-0006: ownership PostgreSQL y migraciones, contratos HTTP/gRPC, Outbox/Inbox y jobs, W3C Trace Context, contratos Protobuf y capacidad transversal AI.
- ADR-0007 y ADR-0008: cuatro procesos independientes, comunicación y distribución de módulos.
- ADR-0009: límites de crates, contratos públicos y dependencias.
- ADR-0010: pooling PostgreSQL y presupuesto de conexiones, incluidos pools separados de lectura/escritura definidos por su actualización vigente.
- ADR-0011: protección de contraseñas y controles de autenticación.
- ADR-0012: UUIDv7 global y PostgreSQL HA con réplicas de lectura.
- ADR-0013: consistencia distribuida, Outbox/Inbox y Sagas.
- ADR-0014: baja de tenants y conservación de datos de clientes.
- ADR-0015: observabilidad integral.
- ADR-0016: Redis Cluster, TLS y caché distribuida.
- ADR-0017: NATS Core y JetStream en clúster de alta disponibilidad.

Comprueba el estado actual de cada ADR en su archivo y en el índice. Un ADR Accepted es vinculante. Si un ADR posterior complementa o sustituye parcialmente a uno anterior, aplica únicamente el alcance explícito de esa sustitución; no descartes el resto del ADR anterior. Los ADR Proposed requieren aprobación explícita y no se tratan como decisiones aceptadas. Para autenticación, credenciales, MFA, sesiones o recuperación, revisa también [la especificación técnica de seguridad](docs/security/password-and-authentication.md). La aceptación documental no demuestra que la implementación, infraestructura, configuración o migraciones existan.

### 2.3 Requisitos y documentación específica de la tarea

Después de la lectura general:

- Localiza en `requisitos.md` el módulo, capacidad, flujo y criterios funcionales exactos que se van a implementar.
- Lee la matriz de dominios y responsabilidades. No deduzcas ownership por el nombre de una pantalla, actor o flujo.
- Lee la sección correspondiente de `ROADMAP.md`, incluidas sus dependencias, entregables y validaciones.
- Lee el lote funcional correspondiente en `promt.md`. Este archivo ordena lotes de trabajo; no reasigna módulos.
- Lee los README de los directorios de backend, módulo, crates o infraestructura que vayas a tocar.
- Inspecciona las implementaciones y pruebas actuales de los módulos consumidores y proveedores de contratos.
- Revisa los contratos OpenAPI, Protobuf y eventos relacionados antes de cambiarlos.

No basta con leer un fragmento aislado si el requisito depende de reglas o definiciones de otra sección. Sigue las referencias internas necesarias.

## 3. Jerarquía documental y resolución de contradicciones

Aplica esta precedencia:

1. Decisiones explícitas aprobadas por el propietario del producto y ADRs Accepted, dentro de su ámbito.
2. [Estándar general](docs/architecture/engineering-standard.md): base obligatoria.
3. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md): puede especializar o endurecer el estándar, nunca debilitarlo.
4. [Reglas de implementación](docs/engineering/implementation-rules.md): operacionalizan los documentos superiores.
5. [requisitos.md](requisitos.md): fuente de verdad funcional, de ownership y límites de capacidades.
6. [ROADMAP.md](ROADMAP.md): fases, dependencias y entregables; no reasigna ownership.
7. [promt.md](promt.md): orden de lotes funcionales; no redefine requisitos ni arquitectura.
8. README y documentación local: explican el área y deben mantenerse alineados con las fuentes superiores.

Si encuentras contradicciones:

- No elijas arbitrariamente el documento que parezca más conveniente.
- No cambies silenciosamente una decisión aceptada.
- Determina el alcance exacto de la contradicción y documenta los archivos implicados.
- Detén únicamente la parte bloqueada y presenta una explicación concreta.
- Si requiere cambiar arquitectura o una decisión aceptada, prepara una propuesta ADR en estado Proposed y espera aprobación explícita. Nunca marques el ADR como Accepted por cuenta propia.
- No conviertas una discrepancia documental en permiso para cambiar código, datos o ownership.

## 4. Arquitectura innegociable

### 4.1 Cuatro procesos independientes

Restaurant OS tiene exactamente cuatro procesos/binarios de aplicación independientes:

1. **Admin Platform Backend:** propietario únicamente de `PLATFORM`.
2. **Admin BFF:** composición y exposición HTTP/OpenAPI para interfaces administrativas; no posee dominios ni persistencia de negocio.
3. **Public BFF:** composición y exposición HTTP/OpenAPI para interfaces públicas y operativas; no posee dominios ni persistencia de negocio.
4. **Public Backend:** propietario de todos los demás módulos de negocio canónicos.

Los BFF son procesos separados, no bibliotecas integradas dentro de los backends. No existe un BFF único compartido ni un único backend que aloje los cuatro procesos.

### 4.2 Ownership y rutas físicas

- `PLATFORM` vive exclusivamente en `backend/admin-platform-backend/modules/platform/`.
- Todos los demás módulos canónicos viven en `backend/public-backend/modules/<modulo>/`.
- Los BFF pueden contener componentes internos de transporte, autenticación de borde, presentación y composición, pero no módulos propietarios de negocio ni tablas de negocio.
- Una operación iniciada desde una interfaz administrativa no cambia el propietario del dato. Si el dato pertenece a un módulo de Public Backend, la operación debe llegar al contrato de ese módulo.
- `IDENTITY` tiene un único propietario en Public Backend. PLATFORM consume sus contratos cuando los necesita; no duplica usuarios, membresías, autenticación ni tablas autoritativas.

Módulos canónicos de Public Backend:

`IDENTITY`, `ORGANIZATION`, `CATALOG`, `SALES`, `PAYMENTS`, `CASH`, `KITCHEN`, `INVENTORY`, `PROCUREMENT`, `PRODUCTION`, `BILLING`, `FINANCE`, `WORKFORCE`, `CUSTOMERS`, `INTEGRATIONS`, `AUTOMATION`, `ANALYTICS`, `AUDIT` y `REPORTING`.

### 4.3 Responsabilidades que no se pueden fusionar

- **CATALOG:** productos, variantes y agrupaciones comerciales genéricas.
- **KITCHEN:** estaciones operativas, comandas, KDS y preparación gastronómica.
- **PRODUCTION:** recetas versionadas, fórmulas/BOM, rendimientos y órdenes/lotes de producción.
- **INVENTORY:** existencias, bodegas, lotes físicos, movimientos y transferencias.
- **PROCUREMENT:** proveedores, cotizaciones, compras y recepciones.
- **SALES:** pedidos, cuentas y ciclo comercial.
- **PAYMENTS:** cobros, autorizaciones, capturas, reembolsos y liquidaciones.
- **CASH:** cajas, turnos, arqueos y movimientos de efectivo.
- **BILLING:** facturación fiscal, documentos electrónicos y numeración.
- **FINANCE:** tesorería, cuentas por cobrar/pagar y contabilidad.
- **ORGANIZATION:** estructura empresarial, empresas legales, grupos, marcas y sucursales.
- **IDENTITY:** identidad, usuarios, membresías, autenticación y autorización.
- **CUSTOMERS:** CRM, fidelización, consentimiento y segmentación.
- **WORKFORCE:** empleados, turnos, asistencia y compensaciones.
- **INTEGRATIONS:** conectores, API, webhooks, credenciales e integraciones.
- **AUTOMATION:** flujos, disparadores, condiciones y acciones.
- **ANALYTICS:** KPI, tendencias y modelos semánticos.
- **AUDIT:** auditoría transversal e historial de acciones.
- **REPORTING:** plantillas, generación, exportación y distribución de informes.
- **PLATFORM:** ciclo de vida SaaS, tenants, planes, suscripciones, límites y capacidades de administración de plataforma.

No traslades menús gastronómicos, cursos, modificadores culinarios ni reglas de servicio a CATALOG por conveniencia. No confundas comandas de KITCHEN con órdenes de producción de PRODUCTION. No inventes un dominio adicional ni dupliques ownership.

AI es una capacidad transversal sin módulo ni schema propietario aprobado actualmente. No crees un módulo AI ni tablas propias sin un ADR nuevo Accepted.

### 4.4 Comunicación

Entre módulos que comparten proceso:

- Consultas y comandos síncronos mediante contratos públicos y puertos/traits locales.
- `crates/adapters/local` existe desde el día uno.
- Los adaptadores local y gRPC implementan los mismos puertos públicos.
- Eventos para hechos ocurridos; los eventos durables usan Outbox/Inbox e idempotencia.
- Nunca importar implementaciones internas de otro módulo ni consultar sus tablas.

Entre procesos:

- gRPC + Protobuf versionado para solicitudes/respuestas síncronas.
- NATS Core para señales y mensajes efímeros sin necesidad de persistencia durable.
- NATS JetStream para eventos/mensajes durables con confirmación, reintentos o recuperación.

`FOR UPDATE SKIP LOCKED` es un mecanismo PostgreSQL para reclamar filas de Outbox/trabajo entre workers; no es un protocolo de comunicación.

### 4.5 Crates y contratos

Según ADR-0009:

- Un único Cargo workspace en la raíz y un único Cargo.lock compartido; los cuatro binarios siguen siendo procesos independientes.
- Cada uno de los 20 módulos tiene dos crates desde el inicio: implementación privada y crate público `<modulo>-contracts`, aunque el contrato inicial sea pequeño.
- Cada módulo mantiene su estructura `domain/`, `application/`, `adapters/`, `infrastructure/`, y `contracts/` independiente.
- Los consumidores dependen de contratos públicos, nunca de implementaciones ajenas.
- `crates/shared` solo contiene utilidades técnicas neutrales. No alojar DTO, entidades, enums, reglas, repositorios ni modelos de negocio.
- `crates/adapters/local`, `crates/adapters/grpc` y `crates/adapters/messaging` mantienen responsabilidades separadas.
- Fuente única de Protobuf: `contracts/protobuf/<backend>/<modulo>/v1/`.
- Los esquemas de eventos tienen ownership y versionado claros por módulo.
- OpenAPI es fuente de verdad HTTP; Protobuf es fuente de verdad gRPC.
- El código generado no se edita manualmente.
- No inventes el grafo de dependencias funcional entre módulos. Justifica cada dependencia por un caso de uso y un contrato requerido.

## 5. Reglas obligatorias de datos, SQL y migraciones

### 5.1 Prohibiciones por defecto

**No modificar, crear, renombrar, mover ni eliminar archivos `.sql` o migraciones sin autorización expresa del propietario del producto. No ejecutar migraciones, SQL DDL/DML destructivo ni comandos que alteren una base de datos sin autorización expresa.**

Esta prohibición incluye, entre otros:

- `migrations/*.sql` históricos.
- Cualquier `*.sql` nuevo o existente.
- Directorios `backend/*/modules/*/migrations/`.
- Scripts que apliquen, reviertan o alteren migraciones.
- Comandos SQLx que ejecuten migraciones.
- Cambios de schema, roles, permisos, políticas RLS, tablas, índices, constraints o datos.

La tarea de leer o analizar SQL no concede permiso para modificarlo ni ejecutarlo. Si la implementación parece requerir un cambio SQL, explica qué cambio sería necesario, por qué y qué archivos afectaría; deja el cambio pendiente hasta recibir autorización.

### 5.2 Ownership PostgreSQL

- PostgreSQL compartido inicialmente, con schema por módulo.
- Cada módulo tiene schema, rol dedicado, permisos limitados a su schema, directorio de migraciones e historial SQLx exclusivos.
- No hay tabla de historial SQLx compartida entre módulos.
- No crear FKs, joins, vistas ni consultas directas entre schemas de módulos diferentes.
- Un módulo no lee ni escribe tablas de otro módulo.
- Cada módulo conserva su propia secuencia de versiones SQLx.
- Separar rol de migración y rol runtime; runtime no debe tener DDL ni BYPASSRLS.
- Mantener aislamiento multi-tenant y contexto de tenant según requisitos y reglas vigentes.

### 5.3 Migraciones nuevas y archivos históricos

La ruta canónica para nuevas migraciones es:

`backend/<backend>/modules/<modulo>/migrations/`

Cada módulo configura su propio `sqlx.toml` y tabla de historial schema-qualified, por ejemplo `identity._sqlx_migrations`. No compartir `_sqlx_migrations`.

La carpeta raíz `migrations/` contiene archivos históricos. Se conservan como están; no son la ubicación canónica de nuevas migraciones. Antes de una tarea de persistencia:

1. Lee [migrations/README.md](migrations/README.md).
2. Identifica el módulo propietario.
3. Inspecciona el SQL histórico relacionado con ese módulo.
4. Inspecciona migraciones actuales del módulo y configuración SQLx, si existen.
5. Comprueba que no se dupliquen tablas ni responsabilidades.
6. Reporta cualquier discrepancia de schema o historial sin corregirla por iniciativa propia.

Inventario histórico actualmente documentado:

| Archivo | Propietario |
|---|---|
| `migrations/modulo_0_admin_plataforma_postgresql.sql` | PLATFORM |
| `migrations/modulo_1_organization_postgresql.sql` | ORGANIZATION |
| `migrations/modulo_2_identity_usuarios_seguridad_postgresql.sql` | IDENTITY |
| `migrations/modulo_3_catalog_postgresql.sql` | CATALOG |
| `migrations/modulo_4_sales_postgresql.sql` | SALES |
| `migrations/modulo_5_kitchen_postgresql.sql` | KITCHEN |
| `migrations/modulo_6_inventory_postgresql.sql` | INVENTORY |
| `migrations/modulo_7_procurement_postgresql.sql` y `migrations/modulo_9_procurement_operaciones_postgresql.sql` | PROCUREMENT |
| `migrations/modulo_8_production_postgresql.sql` | PRODUCTION |
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

Los prefijos `modulo_N` son referencias históricas, no IDs técnicos permanentes ni orden obligatorio de crates. Confirma el inventario real en el repositorio y en `migrations/README.md`; no asumas que la tabla anterior sustituye esa inspección.

## 6. Reglas de los directorios rules/

Inspecciona el contenido de `rules/` cuando la tarea se relacione con su tema. Actualmente los archivos de ese directorio están marcados como `superseded` y son referencias históricas, no normas activas:

- `rules/documentation.md`
- `rules/observabilidad.md`
- `rules/outbox.md`
- `rules/performance-testing.md`
- `rules/postgres.md`
- `rules/repository-governance.md`
- `rules/testing.md`

No apliques su contenido normativo antiguo ni restaures reglas obsoletas. Lee cada aviso y sigue el enlace a la fuente vigente, principalmente:

- Estándar general: `docs/architecture/engineering-standard.md`.
- Arquitectura: `docs/architecture/restaurant-os-architecture.md`.
- Reglas operativas: `docs/engineering/implementation-rules.md`.
- Gobernanza GitHub: `docs/engineering/github-protection-setup.md`.

Si aparece un archivo nuevo en `rules/`, comprueba su estado y referencias antes de tratarlo como vigente.

## 7. Fases y subfases de trabajo

### 7.1 Fases oficiales del producto

La fuente de verdad de fases, dependencias y entregables es [ROADMAP.md](ROADMAP.md). El roadmap contiene dos vistas relacionadas pero distintas: fases de evolución del producto (Fase 0 a Fase 10) y plan maestro de desarrollo (Fase 0 a Fase 5). No las mezcles, no las renumeres ni inventes una secuencia sustituta. Para cada tarea, identifica la vista y la fase concreta que corresponden y lee su sección completa.

Fases de producto:

- **Fase 0 — Fundaciones:** arquitectura, estructura, herramientas, seguridad, persistencia base, contratos, observabilidad y preparación técnica.
- **Fase 1 — Plataforma e identidad:** PLATFORM, tenants, suscripciones/capacidades SaaS e identidad/seguridad según ownership aprobado.
- **Fase 2 — Catálogo y ventas básicas:** CATALOG y SALES, con contratos y dependencias explícitas.
- **Fase 3 — Operación de mesas y cocina:** capacidades de servicio, KITCHEN y sus integraciones con SALES.
- **Fase 4 — Inventario, recetas y producción:** INVENTORY y PRODUCTION, conservando la separación de responsabilidades.
- **Fase 5 — Compras y proveedores:** PROCUREMENT y sus integraciones con INVENTORY/FINANCE cuando proceda.
- **Fase 6 — Personal y clientes:** WORKFORCE y CUSTOMERS.
- **Fase 7 — Contabilidad, facturación y finanzas:** BILLING, FINANCE, PAYMENTS y CASH según alcance y ownership.
- **Fase 8 — Analytics e inteligencia:** ANALYTICS, REPORTING y AUDIT según dependencias.
- **Fase 9 — Automatización e integraciones:** AUTOMATION e INTEGRATIONS.
- **Fase 10 — Escala, resiliencia y portal cliente:** escalabilidad, resiliencia, operación y superficies de cliente previstas en el roadmap.

Estas líneas son un índice resumido, no reemplazan los objetivos, dependencias, entregables ni criterios detallados del roadmap. Lee la sección oficial completa antes de ejecutar.

El plan maestro de desarrollo del mismo ROADMAP también organiza trabajo en:
- Fase 0 — Arquitectura y fundamentos.
- Fase 1 — POS y operación.
- Fase 2 — Administración empresarial.
- Fase 3 — SaaS comercial.
- Fase 4 — Analítica y automatización.
- Fase 5 — IA y expansión.

No sustituyas una vista por la otra. Si hay ambigüedad sobre la fase aplicable, explica la relación y usa las dependencias y entregables escritos en ROADMAP.

### 7.2 Subfases obligatorias para cada tarea

Descompón cada implementación en las siguientes subfases. No avances a una subfase bloqueada por una decisión pendiente.

**Subfase A — Descubrimiento y trazabilidad**
- Definir objetivo, alcance y resultado observable.
- Vincular cada comportamiento a requisito(s) concretos.
- Identificar módulo propietario, backend, consumidores y dependencias.
- Inspeccionar código, contratos, SQL, pruebas y documentación relacionada.
- Registrar supuestos y riesgos; no convertir supuestos en decisiones.

**Subfase B — Diseño técnico acotado**
- Definir casos de uso, entradas/salidas y reglas de dominio.
- Determinar puertos/contratos necesarios y dirección de dependencias.
- Determinar eventos, idempotencia, permisos, tenant y trazabilidad.
- Identificar cambios de API, Protobuf, eventos o persistencia.
- Comprobar que el diseño no duplica ownership ni accede a tablas ajenas.

**Subfase C — Plan de implementación**
- Enumerar archivos que se crearán o modificarán.
- Separar código, contratos, pruebas y documentación.
- Identificar tareas bloqueadas por SQL, migraciones, secretos, infraestructura o decisiones humanas.
- Establecer criterios verificables de aceptación.
- No ampliar el alcance sin autorización.

**Subfase D — Implementación**
- Implementar en el módulo y backend propietarios.
- Mantener capas y dependencias de ADR-0009.
- Mantener validación y autorización en backend; el frontend no es frontera de seguridad.
- Manejar errores, concurrencia, timeouts, reintentos e idempotencia cuando aplique.
- No dejar lógica de negocio en BFF, transporte o crates compartidos.
- No introducir dependencias funcionales circulares.

**Subfase E — Pruebas y validación**
- Pruebas unitarias de dominio y aplicación.
- Pruebas de contrato y adaptadores.
- Pruebas de integración con dependencias reales cuando la semántica lo requiera.
- Casos negativos, permisos, aislamiento tenant, duplicados, concurrencia y recuperación según alcance.
- Ejecutar formato, lint, compilación y tests disponibles.
- Verificar generación de contratos y ausencia de cambios manuales en código generado.
- No afirmar resultados de comandos no ejecutados.

**Subfase F — Documentación y trazabilidad**
- Actualizar README del área, contratos, diagramas, requisitos técnicos o guías afectadas.
- Mantener enlaces y referencias correctos.
- Si cambia una decisión, preparar ADR Proposed y detener su aceptación hasta aprobación.
- No duplicar reglas normativas en documentos históricos `rules/`.

**Subfase G — Revisión y entrega**
- Revisar el diff completo, no solo los archivos principales.
- Confirmar que no hubo cambios accidentales a SQL, migraciones, lockfiles, secretos o áreas ajenas.
- Comprobar que la rama parte de la base correcta y que el PR describe alcance, pruebas, riesgos y pendientes.
- Entregar resumen verificable y estado de cada validación.

### 7.3 Criterio de cierre por fase

Una fase o subfase solo puede declararse terminada cuando sus entregables y criterios de aceptación documentados estén cumplidos y exista evidencia. Si falta una dependencia, una aprobación, una migración autorizada o una validación, marcarla como **BLOQUEADA** o **PENDIENTE**, no como completada.

## 8. Reglas transversales de implementación

### 8.1 Seguridad y multi-tenancy

- El tenant debe formar parte del contexto de las operaciones empresariales.
- Verifica autorización en backend y en el módulo dueño.
- No confíes en IDs, roles, tenant o sucursal enviados por el cliente sin validación.
- No permitas acceso cruzado entre tenants, empresas legales, marcas o sucursales.
- Aplica mínimo privilegio, secretos fuera del repositorio y no registres credenciales ni datos sensibles innecesarios.
- RLS, roles y permisos deben seguir las reglas vigentes de PostgreSQL.

### 8.2 Stateless, Outbox/Inbox y trabajos

- No guardes estado durable de negocio únicamente en memoria del proceso.
- Persiste el evento Outbox en la misma transacción que el cambio de negocio.
- Publica fuera de esa transacción.
- Diseña entrega at-least-once y consumidores idempotentes; no afirmes exactly-once.
- Deduplica por consumidor y event_id; confirma Inbox y efectos persistentes en transacción local.
- ACK después del commit.
- Jobs multi-réplica requieren advisory lock, lease recuperable o elección de líder.
- Incluye reintentos, checkpoints y recuperación ante caída cuando aplique.

### 8.3 Observabilidad

- Usa OpenTelemetry y W3C Trace Context conforme a las reglas vigentes.
- Propaga `traceparent` por HTTP, metadata gRPC y envelope de eventos cuando corresponda.
- Mantén separados trace_id, span_id, request_id, correlation_id, causation_id y event_id.
- No uses IDs de alta cardinalidad como etiquetas métricas.
- No registres secretos ni información personal innecesaria.

### 8.4 Pruebas y calidad

- Usa PostgreSQL real para validar RLS, roles, permisos, transacciones, locks y migraciones cuando la tarea lo requiera y exista autorización para ejecutarlas.
- Usa broker real de prueba cuando se valide la semántica del transporte.
- Prueba duplicados, redelivery, concurrencia, fallos, leases vencidos y recuperación cuando aplique.
- No inventes comandos de CI o scripts: inspecciona manifests y workflows primero.
- Reporta cada validación como **APROBADO**, **FALLIDO**, **BLOQUEADO**, **NO EJECUTADO** o **NO APLICA**, con comando, alcance y evidencia.

## 9. Git, ramas y Pull Requests

- No trabajes directamente en `main`; crea una rama específica para la tarea desde el estado actualizado de la rama base.
- Usa un nombre de rama descriptivo y commits pequeños con mensajes claros.
- Mantén el PR limitado al alcance solicitado.
- Documenta en el PR: propósito, requisitos cubiertos, decisiones aplicadas, archivos relevantes, pruebas ejecutadas, riesgos y pendientes.
- Los cambios de arquitectura y documentación normativa se integran mediante PR.
- No afirmes que CODEOWNERS exige revisión si no verificaste Rulesets/branch protection.
- **No fusiones un PR sin autorización expresa del propietario del producto.**
- No despliegues, publiques releases ni ejecutes acciones irreversibles sin autorización explícita.
- Si no tienes permisos o herramientas para una acción, dilo claramente; no simules haberla realizado.

## 10. Límites de autorización

Sin autorización expresa, el agente NO puede:

1. Modificar, crear, mover, renombrar o eliminar archivos `.sql` ni migraciones.
2. Ejecutar migraciones ni SQL que altere datos o estructura.
3. Cambiar ownership, límites entre módulos o topología de procesos.
4. Aceptar ADRs o declarar aprobada una decisión del producto.
5. Fusionar PRs.
6. Desplegar, publicar releases, modificar infraestructura productiva o ejecutar acciones irreversibles.
7. Cambiar secretos, permisos externos o configuración de seguridad fuera del alcance autorizado.
8. Eliminar responsabilidades, requisitos, documentación o pruebas para hacer pasar una implementación.

Si una de estas acciones es necesaria, prepara el análisis y solicita autorización concreta antes de ejecutarla. No paralices trabajo independiente que sí esté autorizado y no dependa de esa acción.

## 11. Formato de respuesta obligatorio del agente

Al terminar cada tarea, responde en español con estas secciones:

1. **Objetivo:** qué se implementó.
2. **Fase y subfase:** referencia exacta del ROADMAP.
3. **Requisitos cubiertos:** IDs, títulos o secciones de requisitos.
4. **Ownership:** backend y módulo propietario.
5. **Archivos modificados:** lista y propósito.
6. **Contratos y datos:** cambios en HTTP/gRPC/eventos/persistencia; indicar expresamente si no hubo cambios SQL.
7. **Pruebas y validaciones:** comando, alcance y estado APROBADO/FALLIDO/BLOQUEADO/NO EJECUTADO/NO APLICA.
8. **Seguridad y riesgos:** tenant, permisos, idempotencia y riesgos relevantes.
9. **Pendientes/bloqueos:** autorizaciones o decisiones necesarias.
10. **Git/PR:** rama, commits y URL del PR; indicar claramente si no se creó o si sigue sin fusionar.

No digas “implementado” si solo se documentó. No digas “validado” si no ejecutaste la validación. No digas “migrado” si solo escribiste un archivo SQL. No presentes infraestructura objetivo como infraestructura activa.

---

## 12. Plantilla de tarea que acompaña este prompt

Después de entregar este documento, el propietario del producto proporcionará una tarea concreta. Interprétala como el alcance de trabajo, no como autorización implícita para acciones irreversibles.

**Tarea solicitada:**
[Describir aquí la funcionalidad o corrección específica.]

**Fase/subfase conocida (si aplica):**
[Referencia de ROADMAP o dejar que el agente la identifique.]

**Restricciones adicionales:**
[Indicar límites específicos de esta tarea.]

Si algún dato esencial no puede determinarse a partir de los documentos y del repositorio, formula únicamente la pregunta imprescindible. No vuelvas a preguntar decisiones ya aceptadas o requisitos que estén documentados.

---

**Regla final:** implementa lo solicitado, en el módulo correcto, siguiendo las fuentes normativas vigentes. Conserva todas las responsabilidades y decisiones aceptadas. Ante una necesidad de cambio arquitectónico o de datos no autorizado, detente en ese límite, explica la razón y espera aprobación humana.
