# Reglas de implementación y operación

**Estado:** vigente. Subordinadas al [Estándar general](../architecture/engineering-standard.md) y a la [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md).

Estas reglas operacionalizan arquitectura; no redefinen propiedad de dominios ni debilitan decisiones.

> **Decisión aceptada:** el [Diseño de crates y dependencias](../architecture/crate-architecture.md), establecido por [ADR-0009](../adr/0009-crate-boundaries-and-dependencies.md), define la estructura de paquetes y dependencias que debe seguir la implementación.

## 1. Módulos y contratos

### Ubicación y composición

- Los cuatro procesos tienen puntos de entrada independientes bajo
  `apps/<proceso>/src/`.
- PLATFORM vive exclusivamente bajo
  `backend/admin-platform-backend/modules/platform/`; los demás módulos
  propietarios de negocio viven bajo
  `backend/public-backend/modules/<modulo>/`, según ADR-0008.
- Admin BFF y Public BFF no poseen módulos de negocio ni persistencia propietaria.
- Cada módulo tiene un crate de implementación en su raíz (`Cargo.toml`, `sqlx.toml`, `src/{domain,application,adapters,infrastructure}/`) y un crate público obligatorio en `contracts/{Cargo.toml,src/lib.rs}`. Los 20 contratos existen desde el inicio, aunque algunos sean mínimos.
- `contracts/protobuf/<backend>/<modulo>/v1/` es la única fuente Protobuf;
  `crates/contracts/events/` contiene esquemas de eventos;
  `crates/shared/` se limita a utilidades técnicas neutrales;
  `crates/adapters/` contiene adaptadores local, gRPC y mensajería. El adaptador local existe desde el día uno y los adaptadores local y gRPC implementan los mismos puertos.
- `packages/` contiene paquetes reutilizables de frontend; nunca reemplaza
  validaciones, autorización o reglas del backend.
- `infrastructure/` contiene configuración de servicios e infraestructura,
  no migraciones ni lógica de dominio.
- La distribución concreta de dominios entre los cuatro backends está aprobada en ADR-0008 y debe respetar `requisitos.md`; no duplicar ni reasignar módulos por inferencia.

- Depender de contratos públicos; no importar implementaciones internas ajenas.
- DTO no exponen entidades ni modelos SQL.
- OpenAPI describe HTTP; Protobuf describe gRPC.
- Código generado no se edita manualmente. Fijar generadores y versiones al incorporar tooling.
- CI regenera y falla ante diferencias; valida lint y breaking changes.
- Protobuf existe desde el inicio aunque algunas llamadas internas sean locales.

## 2. PostgreSQL, roles y migraciones SQLx

Cada módulo tiene schema y rol PostgreSQL dedicado con privilegios limitados. Pruebas, workers y jobs respetan el ownership. Separar identidad de migración y runtime; runtime sin DDL ni BYPASSRLS.

SQLx usa por defecto `_sqlx_migrations`. Cada módulo debe configurar su propia tabla de historial schema-qualified dentro de su schema PostgreSQL. La tabla predeterminada sin calificar no debe compartirse entre módulos. Por ello:

- Cada módulo tiene directorio propio en `backend/<backend>/modules/<modulo>/migrations/` y tabla de historial SQLx exclusiva y schema-qualified, p. ej. `identity._sqlx_migrations` y `catalog._sqlx_migrations`.
- Está prohibido compartir una tabla `_sqlx_migrations` entre módulos. Cada historial mantiene su propia secuencia de versiones; no se requiere numeración global entre módulos.
- Configurar sqlx.toml por crate:

    [migrate]
    migrations-dir = "backend/<backend>/modules/identity/migrations"
    table-name = "identity._sqlx_migrations"

- sqlx::migrate!() y SQLx CLI pueden leer la configuración por crate. Un Migrator construido manualmente no hereda automáticamente sqlx.toml; configurar explícitamente su tabla.
- No ejecutar varios directorios bajo un historial compartido.
- El rol de migración solo modifica su schema y tabla de historial.
- Migraciones desde un proceso controlado de despliegue, una vez por versión; nunca desde cada réplica.
- Cambiar el nombre de un historial usado exige migrar registros y coordinar versiones desplegadas; no hacerlo directamente en producción.
- El repositorio usa un único Cargo workspace en la raíz, con cuatro paquetes binarios independientes y un único `Cargo.lock` compartido.
- Antes de implementar, fijar SQLx/SQLx CLI y verificar compatibilidad contra Cargo.toml, Cargo.lock y sqlx.toml. En la raíz inspeccionada del repositorio no se encontró Cargo.toml ni Cargo.lock; no se puede afirmar una versión fijada ni compatibilidad comprobada contra una versión concreta.

### FKs y consultas

FKs, joins y consultas directas solo dentro del límite de propiedad del mismo módulo. No FKs, joins, vistas ni consultas directas entre schemas propietarios distintos. Referencias cross-module mediante IDs y contratos; proyecciones derivadas bajo propiedad del consumidor.

## 2.1 Política aceptada de identificadores

La política global UUIDv7 y la versión objetivo PostgreSQL están aceptadas en [ADR-0012](../adr/0012-uuid-v7-global-identifiers-and-postgresql.md), con detalle en [Estrategia técnica de identificadores](../architecture/identifier-strategy.md). La aceptación define el estándar, pero no significa que generación, contratos, columnas, defaults, índices o datos estén modificados. La convergencia de identificadores existentes requiere un plan separado por módulo y autorización expresa. No modificar archivos SQL ni ejecutar migraciones sin autorización expresa.

## 2.2 Seguridad de credenciales y autenticación

IDENTITY en Public Backend es el único propietario de credenciales locales, hashing, verificación, MFA, sesiones y recuperación. Los BFF no calculan hashes ni consultan directamente las tablas de IDENTITY; Admin Platform Backend consume sus contratos cuando corresponda y no duplica credenciales.

La especificación técnica aprobada está en [Seguridad de contraseñas y autenticación](../security/password-and-authentication.md) y desarrolla [ADR-0011 Accepted](../adr/0011-password-hashing-and-authentication-security.md). Sus parámetros y controles son decisiones aprobadas; su presencia documental no demuestra que los flujos estén implementados.

La implementación futura deberá usar Argon2id con salt aleatorio único, PHC y límites de concurrencia/memoria; no almacenar contraseñas en claro ni usar hashes rápidos. Las credenciales nunca se registran en logs, trazas o eventos. Cualquier cambio en SQL o migraciones se tramita en una tarea separada y con autorización expresa. La presencia del diseño SQL de IDENTITY no demuestra que los flujos estén implementados.

## 3. OpenAPI, Protobuf y generación

- OpenAPI es fuente HTTP y genera tipos/clientes HTTP para los frontends y los dos BFF independientes (Admin BFF y Public BFF).
- Protobuf es fuente gRPC y genera stubs/tipos para Rust en los cuatro procesos; las fuentes viven únicamente en `contracts/protobuf/<backend>/<modulo>/v1/` y se utilizan en las fronteras entre procesos.
- Mantener contratos fuente versionados; no duplicar tipos derivados manualmente.
- Fijar versiones de generadores y comandos reproducibles al incorporar tooling.
- CI genera desde cero y falla si git diff --exit-code detecta diferencias en artefactos versionados.
- CI valida lint y breaking changes; para Protobuf controles equivalentes a buf lint y buf breaking.
- No declarar el control activo hasta verificar workflow y herramientas ejecutadas.

## 4. Stateless, Outbox/Inbox e idempotencia

### Estado de proceso

No guardar sesiones, estado de usuario, colas durables ni estado de negocio solo en memoria local. Los pools PostgreSQL deben ser acotados y reutilizables por identidad runtime de módulo; no se comparte un pool/rol global entre módulos. Dentro de cada instancia, las operaciones del módulo reutilizan su pool. La concurrencia se limita por workload. Configurar readiness/liveness, graceful shutdown, timeouts y backpressure. La estrategia detallada está establecida en [ADR-0010 Accepted](../adr/0010-postgresql-connection-pooling-and-resource-management.md). La decisión está aprobada; los pools y su configuración todavía no están implementados.

### Outbox

El evento se persiste en la misma transacción PostgreSQL que el cambio de negocio. No publicar al broker dentro de esa transacción. Sin dispatcher durable operativo, reclamar lotes con `FOR UPDATE SKIP LOCKED` y leases recuperables; publicar fuera de la transacción breve. Con NATS JetStream, marcar publicado tras confirmación durable. Entrega at-least-once; no exactly-once.

NATS Core se reserva para señales efímeras que no requieren persistencia durable. NATS JetStream se utiliza para eventos/mensajes que requieren persistencia, confirmación durable, reintentos o recuperación. `FOR UPDATE SKIP LOCKED` coordina el reclamo de filas de trabajo del Outbox entre workers; no es un protocolo de comunicación entre módulos.

### Inbox e idempotencia

Cada consumidor deduplica por consumidor y event_id (incluyendo tenant si el modelo lo requiere). Inbox/deduplicación y efectos persistentes se confirman en una transacción local. ACK al transporte después del commit. Efectos externos usan claves idempotentes, Outbox adicional o reconciliación/compensación. Handlers toleran redelivery, concurrencia, reintentos y reinicios.

### Consistencia distribuida y procesos multi-módulo

La coordinación de procesos de negocio durables entre varios módulos está aprobada en [ADR-0013 Accepted](../adr/0013-distributed-transactions-and-saga-consistency.md) y desarrollada en [Estrategia técnica de consistencia distribuida y Sagas](../architecture/distributed-transaction-consistency.md). El patrón Saga, su ownership y sus reglas de consistencia son decisiones vigentes; la implementación de cada flujo sigue sujeta a su diseño técnico y a la autorización aplicable.

### Jobs periódicos

Todo job que pueda correr en varias réplicas usa advisory lock PostgreSQL, lease exclusivo recuperable o elección de líder. Definir alcance/vencimiento y recuperación tras caída. Jobs con checkpoints, lotes y concurrencia acotados e idempotencia. Prohibido asumir que cron en cada réplica ejecuta una sola vez.

## 5. OpenTelemetry y W3C Trace Context

Propagar W3C Trace Context mediante traceparent y tracestate cuando aplique:

- HTTP: headers W3C.
- gRPC: metadata.
- Eventos: traceparent y tracestate opcional en envelope versionado.
- Outbox/Inbox/workers: conservar el contexto al persistir y continuar trabajo.

trace_id es el identificador incluido en traceparent; conservarlo al continuar el flujo. Mantener separados trace_id, span_id, request_id, correlation_id, causation_id y event_id. No usar IDs de alta cardinalidad como etiquetas métricas ni registrar secretos/datos personales innecesarios. La traza no concede autorización.

## 6. Pruebas y calidad

Inspeccionar código, contratos, migraciones y pruebas antes de modificar. Usar PostgreSQL real para RLS, roles, permisos, transacciones, locks y migraciones. Probar fallos Outbox/Inbox, duplicados, redelivery, leases vencidos y recuperación. Usar broker real de prueba cuando se valide semántica de transporte. Probar generación de contratos y que CI detecta diferencias. Reportar solo verificaciones ejecutadas: APROBADO, FALLIDO, BLOQUEADO, NO EJECUTADO o NO APLICA; indicar comando, alcance y evidencia.

## 7. Gobernanza

Los cambios arquitectónicos se revisan contra precedencia y ADRs. Cada ADR nace Proposed; pasa a Accepted solo con aprobación explícita del propietario del producto y fecha. CODEOWNERS identifica responsables; la revisión obligatoria de code owners requiere Ruleset o branch protection configurado expresamente. Integrar mediante PR a main. No afirmar enforcement efectivo hasta verificar branch protection/rulesets. Los pasos objetivo están en [Configuración de protección de main](./github-protection-setup.md). Cambios documentales ejecutan validaciones disponibles; no inventar comandos.

## 8. Documentación y README

Toda creación o modificación de documentación debe cumplir el [Estándar de calidad, seguridad y mantenimiento documental](./documentation-quality-and-security-standard.md). La documentación debe describir evidencia real, respetar ownership y ADR aceptados, evitar secretos y datos sensibles, verificar comandos/variables/enlaces y distinguir capacidades implementadas de planificadas. Los README resumen y enlazan fuentes normativas; no duplican ADR ni reglas. Los documentos de `rules/` marcados como `superseded` son históricos y no deben reactivarse. No declarar validaciones documentales, escáneres, workflows o checks como activos sin evidencia de ejecución. La automatización de CI documental se incorpora mediante un cambio autorizado y verificable.

## 9. Estado de herramientas

Estas reglas no demuestran que Cargo workspace, SQLx, OpenAPI generator, Buf, CI, OpenTelemetry, Collector, broker, Docker deployment o controles de arquitectura estén instalados. Verificar manifests, workflows y evidencia antes de marcarlos activos.
