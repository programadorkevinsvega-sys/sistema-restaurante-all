# Estándar de arquitectura: monolito modular preparado para microservicios

Reglas base para cualquier backend, sistema o app nueva. Los ejemplos usan Rust + PostgreSQL + Protobuf/gRPC, pero los principios aplican a cualquier stack. Las palabras **DEBE** / **NO DEBE** son obligatorias; **DEBERÍA** es recomendación fuerte.

---

## 1. Principios

1. **Cada backend se organiza como un monolito modular dentro de su propio proceso/binario, preparado para separarse.** Los módulos de un mismo backend comparten proceso y respetan sus fronteras. Restaurant OS define cuatro procesos independientes: Admin Platform Backend, Admin BFF, Public BFF y Public Backend. Esta separación entre backends no convierte automáticamente cada módulo interno en microservicio. Cada módulo puede extraerse mañana cambiando adaptadores, no sus reglas de negocio.
2. **Cada módulo es dueño de su lógica, sus datos y su contrato.** Nadie más toca sus internos ni sus tablas.
3. **Las fronteras se imponen con herramientas, no con convenciones.** Compilador primero, CI después, revisión humana al final.
4. **Cada interacción entre módulos es una de dos cosas:** consulta/comando (síncrona) o evento (hecho ya ocurrido). Nunca una tercera vía (acceso directo a tablas, imports de internos).
5. **Nada de estado local relevante.** La app DEBE poder correr en N réplicas desde el día uno.
6. **Adoptar infraestructura conforme a decisiones arquitectónicas aprobadas y necesidades reales.** Las interfaces deben permitir sustituir adaptadores sin cambiar reglas de negocio.
7. **Todo requisito se demuestra con evidencia**, no con afirmaciones.

---

## 2. Estructura de módulos

### 2.1 Layout recomendado

```
contracts/
└── protobuf/
    └── <backend>/<modulo>/v1/*.proto      # contratos versionados

backend/
└── <backend>/
    └── modules/
        └── <modulo>/
            ├── Cargo.toml                 # crate privado de implementación
            ├── sqlx.toml                  # configuración SQLx exclusiva del módulo
            ├── src/
            │   ├── lib.rs
            │   ├── domain/
            │   ├── application/
            │   ├── adapters/
            │   └── infrastructure/
            ├── contracts/
            │   ├── Cargo.toml             # crate público <modulo>-contracts
            │   └── src/lib.rs
            └── migrations/                # migraciones e historial SQLx propios
```

**Aplicación en este repositorio:** cada módulo se implementa físicamente una sola vez en `backend/<backend-propietario>/modules/<modulo>/`. PLATFORM pertenece a Admin Platform Backend; todos los demás módulos de negocio canónicos pertenecen a Public Backend, conforme a ADR-0008 y la matriz de `requisitos.md`. Admin BFF y Public BFF son procesos independientes de composición y exposición HTTP/OpenAPI, sin propiedad de dominios ni persistencia de negocio. `crates/` contiene únicamente bibliotecas técnicas neutrales, contratos versionados y adaptadores; no aloja módulos propietarios de negocio. La ruta `backend/<backend>/modules/<modulo>/migrations/` es también la ubicación canónica de las migraciones nuevas del módulo, conforme al ADR-0001. La carpeta raíz `migrations/` se conserva como ubicación histórica.


### 2.2 Carpetas del repositorio

La estructura completa y la responsabilidad de cada carpeta están definidas en [requisitos.md](../../requisitos.md). Las reglas no negociables son:

- `apps/` contiene los cuatro paquetes binarios independientes. El repositorio usa un único Cargo workspace en la raíz y un único `Cargo.lock` compartido; cada paquete produce y despliega su propio proceso/binario.
- `backend/<backend>/modules/` contiene exclusivamente módulos cuyo propietario es ese backend.
- `contracts/protobuf/` es la única ubicación fuente de Protobuf versionado; `crates/contracts/events/` aloja esquemas de eventos versionados; `crates/shared/` aloja utilidades técnicas neutrales; `crates/adapters/` aloja adaptadores local, gRPC y mensajería.
- `packages/` contiene paquetes reutilizables de frontend, nunca lógica autoritativa de dominio.
- `infrastructure/` contiene configuración de Docker, despliegue, PostgreSQL, NATS, Redis y observabilidad; no es propietaria de migraciones.
- `docs/`, `rules/` y `migrations/` conservan sus responsabilidades documentales y el legado histórico respectivamente.
- Ningún módulo se duplica entre backends ni se mueve a `crates/shared/` por conveniencia.

### 2.3 Reglas

- Cada uno de los 20 módulos DEBE tener desde el inicio un crate de implementación y un crate público `*-contracts` bajo su directorio propietario, aunque el contrato comience con pocas operaciones.
- Un módulo SOLO puede depender de: (a) `*-contracts` de otros módulos, (b) bibliotecas técnicas neutrales aprobadas (logging, config, tiempo, errores base), (c) sus propias capas.
- NO DEBE importar `domain`, `application`, `adapters`, `infrastructure`, repositorios, servicios internos ni modelos de otro módulo, ni directa ni transitivamente.
- Los tipos internos (`struct`, entidades, errores de BD) NO DEBEN aparecer en la API pública.
- Visibilidad por defecto: privado. Solo se publica explícitamente lo que está en `contracts`.
- La composición (ensamblar módulos en el binario) vive en un único lugar (`composition`/`main`), nunca dentro de los módulos.

**Concreción de crates:** la estructura detallada de crates de implementación, crates públicos de contratos, crates de transporte y composición por proceso está definida en [Diseño de crates y dependencias](./crate-architecture.md) y aceptada mediante ADR-0009. Sus decisiones específicas de layout complementan este estándar y rigen la implementación.

**Debe fallar:**
```rust
// Un módulo consumidor importando la implementación interna de otro módulo
use provider_module::internal::OperationService;
```

**Permitido:**
```rust
// Un módulo consumidor usando únicamente el contrato público del módulo propietario
use provider_module_contracts::{OperationPort, OperationRequest, OperationResponse};
```

---

## 3. Contratos entre módulos

Cada módulo DEBE tener, desde el inicio:

1. **Una interfaz pública** (trait/interface) por capacidad: `AuthenticationPort`, etc.
2. **DTO propios** de request/response/evento. Nunca entidades de dominio ni modelos de BD.
3. **Un contrato Protobuf versionado equivalente** (`v1`, `v2`...), aunque hoy la implementación sea una llamada en proceso.
4. **Una implementación en proceso** para módulos que comparten el mismo backend y un adaptador de transporte (gRPC/Tonic) en las fronteras entre procesos. En Restaurant OS, los cuatro backends son procesos independientes; las llamadas síncronas entre ellos usan gRPC conforme a sus contratos.

Reglas de evolución:
- Cambios compatibles (campos opcionales nuevos) → misma versión.
- Cambios incompatibles → nueva versión (`v2`) con convivencia; el CI DEBE detectar rupturas (`buf breaking`).
- Los contratos gRPC en las fronteras entre backends y BFF son obligatorios desde el inicio.
- Los adaptadores local y gRPC implementan los mismos puertos públicos: el local se usa entre módulos del mismo proceso; gRPC, entre procesos. `crates/adapters/local` forma parte de la arquitectura desde el día uno y puede sustituirse por gRPC al extraer un módulo.
- Todo contrato DEBE propagar contexto explícito: `trace_id`, tenant, usuario/actor, idempotency key. Prohibido el estado global implícito.

---

## 4. Comunicación entre módulos

### 4.1 Cuándo usar cada estilo

| Necesidad | Mecanismo |
|---|---|
| Pedir algo y necesitar la respuesta ahora (validar stock, consultar precio, autenticar) | **Comando/consulta síncrona** vía puerto/trait público y DTO; `crates/adapters/local` implementa la invocación entre módulos que comparten proceso y `crates/adapters/grpc` implementa el mismo puerto en fronteras entre procesos |
| Notificar que algo ya ocurrió (`PedidoCreado`, `PagoConfirmado`) | **Evento durable** mediante Outbox/Inbox y NATS JetStream cuando corresponda |
| Invalidar cachés / señales efímeras sin garantía | Broadcast ligero mediante NATS Core |

### 4.2 Reglas

- NO usar solo gRPC: crea acoplamiento temporal y fallos en cascada al separar.
- NO usar solo eventos: todo se vuelve eventualmente consistente y lo que necesita respuesta inmediata se vuelve incómodo.
- Los eventos expresan **hechos en pasado**, con ID único, versión de esquema, timestamp y contexto (`trace_id`, tenant).
- Los consumidores DEBEN ser **idempotentes** (la entrega es "al menos una vez").
- Si se necesita orden, es **por entidad/agregado**, no global (particionar por clave).
- Evitar cadenas largas de llamadas síncronas entre módulos; si aparecen, replantear fronteras.

---

## 5. Réplicas y escalado horizontal

La app DEBE ser stateless desde el día uno. Con más de una réplica:

- **Bus de eventos en memoria NO es válido** para eventos que importan: un evento publicado en una réplica solo lo ven los suscriptores de esa réplica.
- **Eventos durables = Outbox transaccional:** el evento se escribe en la misma transacción que el cambio de datos. Nunca publicar "después" de confirmar.
- **Despacho del outbox**, una de dos opciones:
  - *Mientras no esté disponible el broker durable:* polling del Outbox con `FOR UPDATE SKIP LOCKED` (+ `LISTEN/NOTIFY` para despertar). Este mecanismo reclama filas de trabajo; no sustituye los contratos de comunicación entre módulos.
  - *Con NATS JetStream:* el dispatcher publica al stream tras la confirmación durable correspondiente; los consumidores usan **queue/consumer groups** para distribuir el procesamiento por grupo.
  - *Para señales efímeras:* NATS Core, sin tratarlo como almacenamiento durable.
- **Inbox/idempotencia** en consumidores: tabla de eventos procesados o claves idempotentes.
- **Jobs periódicos/cron:** con advisory lock de PostgreSQL o elección de líder; nunca "una vez por réplica".
- **Cachés locales:** evitarlas, usar TTL cortos o invalidación por broadcast.
- **Sesiones y estado de usuario:** en BD/almacén compartido, nunca en memoria del proceso.
- Health/readiness probes, apagado ordenado (graceful shutdown) y migraciones compatibles hacia atrás (rolling deploys).

**Decisión de mensajería de Restaurant OS:** NATS Core se utiliza para señales efímeras y NATS JetStream para mensajería durable cuando corresponda. `FOR UPDATE SKIP LOCKED` sigue siendo el mecanismo de reclamación de filas Outbox mientras el dispatcher durable no publique al broker. Esta decisión arquitectónica no constituye evidencia de que NATS esté instalado o desplegado.

---

## 6. Ownership de datos

1. Cada **schema/tabla pertenece a un solo módulo/backend/bounded context**, registrado en `data-ownership.yaml`.
2. Sin joins, vistas, funciones ni FKs entre schemas de módulos distintos.
3. **Prohibida cualquier operación SQL sobre datos ajenos:** `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `JOIN`, vistas, funciones; incluso una lectura simple sin join.
   ```sql
   -- Suscripciones NO debe consultar tablas de políticas comerciales
   SELECT * FROM platform.commercial_offer_versions;   -- ❌ debe fallar
   ```
4. **La defensa real son los roles de PostgreSQL:** un rol por módulo, con `GRANT` solo sobre su schema. Workers, jobs y pruebas de integración DEBEN usar esos mismos roles; prohibido usar credenciales que se salten el ownership.
5. Las migraciones viven **dentro del módulo propietario**.
6. Si un módulo necesita datos de otro: usa su contrato (consulta) o mantiene **su propia copia derivada** alimentada por eventos.
7. Excepciones solo para infraestructura que no transfiera ownership, explícitas y documentadas en el inventario.

---

## 7. Controles de arquitectura en CI (obligatorios)

Todos son bloqueantes. Sin tolerancia a incumplimientos existentes y sin que una compilación sustituya una prueba de integración o de staging.

| # | Control | Verifica | Falla si |
|---|---|---|---|
| 1 | **Fronteras de dependencias** | `cargo metadata --locked --format-version 1`: grafo real de paquetes + análisis de imports; mapa de pertenencia (backend, módulo, contratos, librerías neutrales) | hay dependencia o import (directo o transitivo) hacia internos de otro módulo |
| 2 | **Ownership SQL** | inventario schema/tabla → backend → contexto; migraciones, consultas SQLx, archivos SQL, vistas, funciones, grants y roles | cualquier operación sobre datos ajenos, migración fuera de su módulo, o credenciales que evadan el ownership |
| 3 | **Contratos** | existe trait público por módulo; DTO propios; Protobuf versionado equivalente; sin rupturas (`buf lint`/`buf breaking`) | falta interfaz, DTO expone internos, falta `.proto` o hay ruptura |
| 4 | **Superficies HTTP** | inventario de endpoints/superficies (`http-surfaces.yaml`) contra lo implementado | endpoint no declarado o declarado sin implementar |
| 5 | **Outbox/Inbox** | todo evento durable pasa por outbox transaccional; consumidores con inbox/idempotencia; inventario `durable-events.yaml` | evento publicado fuera de transacción o consumidor no idempotente |
| 6 | **Topología de despliegue** | `deployment-inventory.yaml` vs manifiestos reales | desviación entre lo declarado y lo desplegable |
| 7 | **Inventario de runtime** | procesos/servicios reales vs `runtime-inventory.yaml` | proceso no declarado o declarado inexistente |
| 8 | **E2E de staging** | gate de **aceptación de release**, separado de las pruebas de integración por PR; corre sobre el entorno real | recorrido incompleto, dependencia sustituida por mock, recuperación no demostrada, o SHA desplegado ≠ SHA validado |
| 9 | **Trazabilidad** | `REQ → CASE → módulo → contrato/evento/endpoint → prueba → job CI → evidencia → resultado → SHA` | requisito sin cobertura, prueba inexistente, evidencia ausente, SHA incorrecto o verificación de menor alcance que la exigida |

### 7.1 Archivos de control

```
architecture/
├── architecture-inventory.yaml
├── module-ownership.yaml
├── data-ownership.yaml
├── contracts.yaml
├── http-surfaces.yaml
├── durable-events.yaml
├── deployment-inventory.yaml
├── runtime-inventory.yaml
└── requirement-traceability.yaml

scripts/ci/architecture/        # o, mejor, un único `cargo xtask architecture`
├── check-cargo-boundaries
├── check-sql-ownership
├── check-contracts
├── check-http-surfaces
├── check-outbox-inbox
├── check-deployment-topology
├── check-runtime-inventory
├── check-staging-e2e
├── check-requirement-traceability
└── report

.github/workflows/architecture-compliance.yml
```

Reglas:
- Un **inventario central** como fuente única de verdad; nada de listas duplicadas en scripts.
- Preferir **un validador único** (p. ej. `cargo xtask`) que lea los YAML una vez, a muchos scripts bash.
- El **SHA y el resultado** de la trazabilidad los inyecta el CI, nunca se editan a mano.
- Los resultados se conservan como evidencia: ID de requisito, SHA, resultado por job.

### 7.2 Adopción por fases (si el código ya existe)

1. Fronteras de dependencias, ownership SQL y contratos (controles 1–3).
2. Outbox/inbox, superficies HTTP (4–5).
3. Topología y runtime (6–7).
4. Staging E2E y trazabilidad (8–9).

Un control puede activarse por fases, pero una vez activado es bloqueante y sin excepciones silenciosas.

---

## 8. Cuándo separar un módulo como microservicio

Separar SOLO si hay una razón medible:

- Escalado independiente (carga o recursos muy distintos al resto).
- Ciclo de despliegue o equipo independiente.
- Aislamiento de fallos o de seguridad/cumplimiento.
- Tecnología distinta justificada.

Checklist previo a separar:

- [ ] Todas las interacciones usan el contrato (trait + DTO + Protobuf), sin atajos.
- [ ] El módulo es dueño exclusivo de su schema, sin joins/FKs externos.
- [ ] Eventos con outbox/inbox e idempotentes.
- [ ] Contexto (`trace_id`, tenant, actor) viaja explícito.
- [ ] Existe adaptador gRPC (tonic) implementando el mismo trait.
- [ ] Observabilidad lista: trazas distribuidas, métricas, logs correlacionados.
- [ ] Timeouts, reintentos con backoff, circuit breaker y límites definidos para llamadas remotas.
- [ ] Plan de migración de datos y de rollback.

---

## 9. Anti-patrones (prohibidos)

- Importar el crate/paquete de implementación de otro módulo.
- Leer o escribir tablas de otro módulo ("solo un SELECT rápido").
- Exponer entidades de dominio o modelos de BD como DTO.
- Bus de eventos solo en memoria con más de una réplica.
- Publicar eventos fuera de la transacción del cambio de datos.
- Handlers de eventos no idempotentes.
- Jobs programados sin lock/líder en múltiples réplicas.
- Estado global o caché local no invalidable.
- Contratos sin versión o sin `.proto` equivalente.
- Tests de integración o E2E que sustituyen dependencias reales por mocks y se presentan como validación real.
- Considerar una compilación exitosa como prueba de integración.
- Reglas duplicadas en scripts sin inventario central.
- Aceptar incumplimientos "temporales" sin excepción documentada.

---

## 10. Definición de terminado (por cambio)

Un cambio está terminado solo si:

- [ ] Respeta las fronteras (control 1) y el ownership de datos (control 2).
- [ ] Sus contratos Rust y Protobuf están actualizados y versionados (control 3).
- [ ] Los eventos nuevos usan outbox y sus consumidores son idempotentes (control 5).
- [ ] Los inventarios YAML reflejan el cambio.
- [ ] Hay pruebas automatizadas enlazadas al requisito (`REQ → CASE → prueba`).
- [ ] El CI produce evidencia asociada al SHA.
- [ ] Si afecta el comportamiento desplegado: el E2E de staging pasó sobre el mismo SHA que se libera.

---

## 11. Resumen en una pantalla

1. Monolito modular, un crate por módulo + crate `contracts`.
2. Consultas/comandos → contrato/trait + DTO + Protobuf versionado; puertos locales entre módulos del mismo backend y gRPC entre los cuatro procesos independientes de Restaurant OS.
3. Hechos → eventos con outbox/inbox, idempotentes.
4. Stateless desde el día uno; bus en memoria solo en instancia única.
5. Cada schema tiene un dueño; roles de PostgreSQL lo imponen.
6. Nueve controles de CI bloqueantes, con inventarios YAML centrales y evidencia por SHA.
7. NATS Core/JetStream según el tipo de mensajería definido; la extracción de módulos a microservicios requiere una razón medible.