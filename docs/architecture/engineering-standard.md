# Estándar de arquitectura: monolito modular preparado para microservicios

Reglas base para cualquier backend, sistema o app nueva. Los ejemplos usan Rust + PostgreSQL + Protobuf/gRPC, pero los principios aplican a cualquier stack. Las palabras **DEBE** / **NO DEBE** son obligatorias; **DEBERÍA** es recomendación fuerte.

---

## 1. Principios

1. **Empezar como monolito modular, diseñado para separarse.** Un solo binario hoy; cada módulo puede convertirse en servicio mañana cambiando un adaptador, no su lógica.
2. **Cada módulo es dueño de su lógica, sus datos y su contrato.** Nadie más toca sus internos ni sus tablas.
3. **Las fronteras se imponen con herramientas, no con convenciones.** Compilador primero, CI después, revisión humana al final.
4. **Cada interacción entre módulos es una de dos cosas:** consulta/comando (síncrona) o evento (hecho ya ocurrido). Nunca una tercera vía (acceso directo a tablas, imports de internos).
5. **Nada de estado local relevante.** La app DEBE poder correr en N réplicas desde el día uno.
6. **No adoptar infraestructura antes de necesitarla**, pero sí diseñar las interfaces como si ya existiera.
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
            ├── contracts/                 # crate público: traits + DTO + eventos
            ├── domain/                    # entidades, reglas (privado)
            ├── application/
            │   ├── ports/                 # interfaces que el módulo expone/consume
            │   └── dto/                   # DTO propios (nunca entidades)
            ├── adapters/
            │   ├── inbound/               # HTTP, gRPC, handlers de eventos
            │   └── outbound/              # BD, clientes de otros módulos, bus
            └── infrastructure/
                └── composition/           # cableado e inyección de dependencias
```

### 2.2 Reglas

- Cada módulo DEBE ser un paquete/crate propio, con un crate `*-contracts` separado.
- Un módulo SOLO puede depender de: (a) `*-contracts` de otros módulos, (b) bibliotecas técnicas neutrales aprobadas (logging, config, tiempo, errores base), (c) sus propias capas.
- NO DEBE importar `domain`, `application`, `adapters`, `infrastructure`, repositorios, servicios internos ni modelos de otro módulo, ni directa ni transitivamente.
- Los tipos internos (`struct`, entidades, errores de BD) NO DEBEN aparecer en la API pública.
- Visibilidad por defecto: privado. Solo se publica explícitamente lo que está en `contracts`.
- La composición (ensamblar módulos en el binario) vive en un único lugar (`composition`/`main`), nunca dentro de los módulos.

**Debe fallar:**
```rust
// BUSINESS importando la implementación interna de CORE
use ensambria_core::identity_authentication::AuthenticationService;
```

**Permitido:**
```rust
// BUSINESS consumiendo el contrato público del owner
use core_identity_contracts::{AuthenticationPort, AuthenticateRequest, AuthenticateResponse};
```

---

## 3. Contratos entre módulos

Cada módulo DEBE tener, desde el inicio:

1. **Una interfaz pública** (trait/interface) por capacidad: `AuthenticationPort`, etc.
2. **DTO propios** de request/response/evento. Nunca entidades de dominio ni modelos de BD.
3. **Un contrato Protobuf versionado equivalente** (`v1`, `v2`...), aunque hoy la implementación sea una llamada en proceso.
4. **Una implementación en proceso** (en memoria) y, cuando se separe, un **adaptador de transporte** (gRPC/tonic) que implementa el mismo trait.

Reglas de evolución:
- Cambios compatibles (campos opcionales nuevos) → misma versión.
- Cambios incompatibles → nueva versión (`v2`) con convivencia; el CI DEBE detectar rupturas (`buf breaking`).
- Los contratos gRPC en las fronteras entre backends y BFF son obligatorios desde el inicio.
- Todo contrato DEBE propagar contexto explícito: `trace_id`, tenant, usuario/actor, idempotency key. Prohibido el estado global implícito.

---

## 4. Comunicación entre módulos

### 4.1 Cuándo usar cada estilo

| Necesidad | Mecanismo |
|---|---|
| Pedir algo y necesitar la respuesta ahora (validar stock, consultar precio, autenticar) | **Comando/consulta síncrona** vía trait (en proceso) → gRPC al separar |
| Notificar que algo ya ocurrió (`PedidoCreado`, `PagoConfirmado`) | **Evento durable** |
| Invalidar cachés / señales efímeras sin garantía | Broadcast ligero (p. ej. NATS core) |

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
  - *Sin broker:* polling con `FOR UPDATE SKIP LOCKED` (+ `LISTEN/NOTIFY` para despertar). Cada evento lo toma una sola réplica.
  - *Con broker (NATS/JetStream):* el dispatcher publica al stream; los consumidores usan **queue/consumer groups** para que cada evento lo procese una sola réplica por grupo.
- **Inbox/idempotencia** en consumidores: tabla de eventos procesados o claves idempotentes.
- **Jobs periódicos/cron:** con advisory lock de PostgreSQL o elección de líder; nunca "una vez por réplica".
- **Cachés locales:** evitarlas, usar TTL cortos o invalidación por broadcast.
- **Sesiones y estado de usuario:** en BD/almacén compartido, nunca en memoria del proceso.
- Health/readiness probes, apagado ordenado (graceful shutdown) y migraciones compatibles hacia atrás (rolling deploys).

**Cuándo adoptar NATS/JetStream:** cuando haya módulos en procesos separados, o varias réplicas con necesidad real de desacople, reintentos, replay o múltiples consumidores. Antes de eso, outbox + SKIP LOCKED es suficiente y no añade infraestructura.

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
2. Consultas/comandos → trait + DTO + Protobuf (en memoria hoy, gRPC mañana).
3. Hechos → eventos con outbox/inbox, idempotentes.
4. Stateless desde el día uno; bus en memoria solo en instancia única.
5. Cada schema tiene un dueño; roles de PostgreSQL lo imponen.
6. Nueve controles de CI bloqueantes, con inventarios YAML centrales y evidencia por SHA.
7. NATS/JetStream y microservicios solo cuando haya una razón medible.