# Estándar de arquitectura: monolito modular preparado para microservicios

Reglas base para cualquier backend, sistema o app nueva. Los ejemplos usan Rust, PostgreSQL y Protobuf/gRPC, pero los principios aplican a cualquier stack. **DEBE/NO DEBE** son obligatorios; **DEBERÍA** es recomendación fuerte.

## 1. Principios

1. Empezar como monolito modular, diseñado para separarse: un solo binario inicialmente; cada módulo puede convertirse en servicio cambiando un adaptador, no su lógica.
2. Cada módulo es dueño de su lógica, datos y contrato.
3. Las fronteras se imponen con herramientas: compilador, CI y revisión humana.
4. Toda interacción entre módulos es consulta/comando síncrono o evento (hecho ocurrido). No hay acceso directo a tablas ni imports de internos.
5. La aplicación DEBE ser stateless y poder correr en N réplicas desde el día uno.
6. No adoptar infraestructura antes de necesitarla, pero diseñar interfaces como si ya existiera.
7. Todo requisito se demuestra con evidencia.

## 2. Estructura y límites

- Cada módulo DEBE ser un paquete/crate propio, con contrato público separado cuando el stack lo permita.
- Un módulo solo depende de contratos públicos de otros módulos, bibliotecas técnicas neutrales aprobadas y sus propias capas.
- NO DEBE importar dominio, aplicación, adaptadores, infraestructura, repositorios, servicios internos ni modelos de otro módulo, directa o transitivamente.
- Entidades de dominio, modelos de persistencia y errores internos NO DEBEN aparecer en APIs públicas.
- Visibilidad privada por defecto. La composición e inyección de dependencias vive en un único punto de ensamblaje.

## 3. Contratos

Cada módulo define desde el inicio: interfaz pública por capacidad; DTO propios de request/response/evento; contrato Protobuf versionado equivalente; implementación local y adaptador de transporte cuando se separe.

Los cambios compatibles pueden conservar versión; los incompatibles requieren nueva versión y convivencia. CI DEBE detectar rupturas. Los contratos gRPC entre backends y BFF son obligatorios desde el inicio. Los contratos propagan contexto explícito de trazabilidad, tenant, actor y clave de idempotencia cuando corresponda.

## 4. Comunicación

| Necesidad | Mecanismo |
|---|---|
| Respuesta inmediata | Puerto/trait local; gRPC cuando corresponda separar procesos |
| Hecho ya ocurrido | Evento durable versionado |
| Señal efímera sin garantía | Broadcast ligero, solo si el riesgo lo permite |

No usar solo gRPC ni solo eventos. Los eventos expresan hechos pasados, con identidad estable, versión, timestamp y contexto. Los consumidores DEBEN ser idempotentes; la entrega durable es at-least-once. El orden, si se requiere, es por agregado. Evitar cadenas largas de llamadas síncronas.

## 5. Réplicas y escalado

La app DEBE ser stateless desde el día uno.

- Un bus de eventos en memoria NO sirve para eventos durables con varias réplicas.
- Outbox persiste el evento en la misma transacción que el cambio de negocio.
- Sin broker, el dispatcher usa polling con FOR UPDATE SKIP LOCKED; con broker, confirmación durable y grupos de consumidores.
- Consumidores con Inbox y/o claves idempotentes.
- Jobs periódicos con advisory lock de PostgreSQL o elección de líder; nunca una ejecución no coordinada por réplica.
- Sesiones y estado relevante en almacenamiento compartido, no en memoria local.
- Health/readiness, apagado ordenado, límites de concurrencia y migraciones compatibles hacia atrás.
- Cachés locales evitadas o con TTL e invalidación explícitos.

NATS/JetStream u otro broker se adopta ante una razón medible, no por moda.

## 6. Ownership de datos

1. Cada schema y tabla pertenece a un módulo y se registra en el inventario de propiedad.
2. No se permiten joins, vistas, funciones ni FKs entre schemas de módulos distintos.
3. Un módulo no consulta ni modifica tablas de otro módulo.
4. PostgreSQL impone ownership: un rol por módulo, con privilegios limitados a su schema. Workers, jobs y pruebas usan identidades que respetan la misma frontera.
5. Las migraciones pertenecen al módulo propietario.
6. Para datos ajenos se usa el contrato o una proyección propia alimentada por eventos.
7. Excepciones deben documentarse y aprobarse.

## 7. Controles de arquitectura en CI

Se adoptan por fases según existan código y tooling. Una vez activados son bloqueantes; no hay excepciones silenciosas. Compilar no sustituye integración ni E2E.

| Control | Verifica | Falla si |
|---|---|---|
| Fronteras | Grafo real de paquetes e imports | Dependencia a internos ajenos |
| Ownership SQL | Schemas, tablas, migraciones, consultas, grants y roles | Acceso o migración fuera del ownership |
| Contratos | Interfaces, DTO, Protobuf/OpenAPI y compatibilidad | Contrato ausente o ruptura |
| HTTP | Inventario de endpoints vs implementación | Endpoint no declarado o declaración inexistente |
| Outbox/Inbox | Eventos durables y consumidores idempotentes | Publicación no atómica o consumidor no idempotente |
| Topología | Inventario vs manifiestos | Desviación desplegable |
| Runtime | Inventario vs procesos reales | Proceso declarado inexistente o no declarado |
| E2E staging | Release sobre entorno real y mismo SHA | Recorrido incompleto o SHA distinto |
| Trazabilidad | REQ → CASE → módulo → contrato/evento/endpoint → prueba → CI → evidencia → SHA | Cobertura o evidencia ausente |

Mantener inventarios centrales como fuente única. CI inyecta SHA/resultados; conservar evidencia. Activar primero fronteras/ownership/contratos, luego Outbox/Inbox/HTTP, topología/runtime y finalmente staging/trazabilidad.

## 8. Separación en microservicios

Separar solo por razón medible: escalado independiente, ciclo de despliegue/equipo, aislamiento de fallos/seguridad o tecnología justificada. Antes de separar: contratos públicos, ownership exclusivo, Outbox/Inbox/idempotencia, contexto explícito, adaptador gRPC, observabilidad, timeouts/reintentos/límites y plan de migración/rollback.

## 9. Anti-patrones

Imports de implementaciones ajenas; SQL sobre tablas ajenas; entidades/modelos BD expuestos; bus en memoria para eventos durables multi-réplica; publicar fuera de transacción; consumidores no idempotentes; jobs sin lock/líder; estado global o caché no invalidable; contratos sin versión; mocks presentados como integración real; compilación presentada como integración; excepciones temporales sin ADR.

## 10. Definición de terminado

- [ ] Respeta fronteras y ownership.
- [ ] Contratos Rust/Protobuf/OpenAPI versionados.
- [ ] Eventos con Outbox y consumidores idempotentes.
- [ ] Inventarios actualizados.
- [ ] Pruebas enlazadas a requisitos.
- [ ] CI produce evidencia asociada al SHA cuando el control esté activado.
- [ ] E2E staging sobre el mismo SHA si afecta comportamiento desplegado.

## 11. Resumen

Monolito modular; contratos públicos; Outbox + Inbox + idempotencia; stateless; schema por módulo con roles PostgreSQL; evidencia automatizada; brokers y microservicios solo por razones medibles.
