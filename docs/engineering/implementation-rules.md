# Reglas de implementación y operación

**Estado:** vigente. Subordinadas al [Estándar general](../architecture/engineering-standard.md) y a la [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md).

Estas reglas operacionalizan arquitectura; no redefinen propiedad de dominios ni debilitan decisiones.

> **Propuesta pendiente:** el [Diseño de crates y dependencias](../architecture/crate-architecture.md), asociado a [ADR-0009](../adr/0009-crate-boundaries-and-dependencies.md), concreta la estructura prevista de paquetes y dependencias. ADR-0009 permanece Proposed; sus detalles no se consideran norma aceptada hasta aprobación explícita.

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
- La distribución concreta de dominios entre los cuatro backends debe
  respetar `requisitos.md`; no duplicar ni asignar módulos por inferencia.

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
- Antes de implementar, fijar SQLx/SQLx CLI y verificar compatibilidad contra Cargo.toml, Cargo.lock y sqlx.toml. En la raíz inspeccionada del repositorio no se encontró Cargo.toml ni Cargo.lock; no se puede afirmar una versión fijada ni compatibilidad comprobada contra una versión concreta.

### FKs y consultas

FKs, joins y consultas directas solo dentro del límite de propiedad del mismo módulo. No FKs, joins, vistas ni consultas directas entre schemas propietarios distintos. Referencias cross-module mediante IDs y contratos; proyecciones derivadas bajo propiedad del consumidor.

## 3. OpenAPI, Protobuf y generación

- OpenAPI es fuente HTTP y genera tipos/clientes HTTP para los frontends y los dos BFF independientes (Admin BFF y Public BFF).
- Protobuf es fuente gRPC y genera stubs/tipos para Rust en los cuatro procesos; se utiliza en las fronteras entre procesos.
- Mantener contratos fuente versionados; no duplicar tipos derivados manualmente.
- Fijar versiones de generadores y comandos reproducibles al incorporar tooling.
- CI genera desde cero y falla si git diff --exit-code detecta diferencias en artefactos versionados.
- CI valida lint y breaking changes; para Protobuf controles equivalentes a buf lint y buf breaking.
- No declarar el control activo hasta verificar workflow y herramientas ejecutadas.

## 4. Stateless, Outbox/Inbox e idempotencia

### Estado de proceso

No guardar sesiones, estado de usuario, colas durables ni estado de negocio solo en memoria local. Pools acotados y compartidos por proceso; concurrencia limitada por workload. Configurar readiness/liveness, graceful shutdown, timeouts y backpressure.

### Outbox

El evento se persiste en la misma transacción PostgreSQL que el cambio de negocio. No publicar al broker dentro de esa transacción. Sin dispatcher durable operativo, reclamar lotes con `FOR UPDATE SKIP LOCKED` y leases recuperables; publicar fuera de la transacción breve. Con NATS JetStream, marcar publicado tras confirmación durable. Entrega at-least-once; no exactly-once.

NATS Core se reserva para señales efímeras que no requieren persistencia durable. NATS JetStream se utiliza para eventos/mensajes que requieren persistencia, confirmación durable, reintentos o recuperación. `FOR UPDATE SKIP LOCKED` coordina el reclamo de filas de trabajo del Outbox entre workers; no es un protocolo de comunicación entre módulos.

### Inbox e idempotencia

Cada consumidor deduplica por consumidor y event_id (incluyendo tenant si el modelo lo requiere). Inbox/deduplicación y efectos persistentes se confirman en una transacción local. ACK al transporte después del commit. Efectos externos usan claves idempotentes, Outbox adicional o reconciliación/compensación. Handlers toleran redelivery, concurrencia, reintentos y reinicios.

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

## 8. Estado de herramientas

Estas reglas no demuestran que Cargo workspace, SQLx, OpenAPI generator, Buf, CI, OpenTelemetry, Collector, broker, Docker deployment o controles de arquitectura estén instalados. Verificar manifests, workflows y evidencia antes de marcarlos activos.
