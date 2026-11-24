# Operación de Transactional Outbox e Inbox

**Estado:** especificación técnica vigente vinculada a ADR-0003, ADR-0013 y ADR-0015.  
**Ámbito:** publicación y consumo de comandos/eventos durables por los módulos propietarios de Restaurant OS.  
**Decisiones relacionadas:** ADR-0001, ADR-0003, ADR-0004, ADR-0007, ADR-0008, ADR-0009, ADR-0010, ADR-0013 y ADR-0015.  
**Parámetros pendientes:** dimensionamiento, umbrales, retenciones y valores concretos por módulo, flujo y entorno.

## 1. Propósito

Esta especificación desarrolla las reglas operativas para persistir, publicar, consumir, ordenar, recuperar y supervisar mensajes durables mediante Transactional Outbox e Inbox.

El objetivo es que una caída, timeout, redelivery, despliegue o saturación no provoque pérdida silenciosa de hechos de negocio ni efectos duplicados no controlados. La garantía es entrega **at-least-once** con consumidores idempotentes; no se promete exactly-once extremo a extremo.

Este documento concreta las decisiones ya aceptadas. No crea un nuevo patrón de consistencia, no modifica ownership y no autoriza implementación.

## 2. Reglas invariantes y ownership

1. El módulo propietario persiste el cambio de negocio y la intención durable de publicar en la misma transacción local.
2. La transacción incluye el cambio de negocio, la asignación de secuencia cuando aplique y todos los registros Outbox que representan hechos derivados de ese cambio.
3. La publicación al broker ocurre después del commit; nunca se mantiene una transacción PostgreSQL abierta esperando una respuesta de NATS/JetStream.
4. Cada módulo administra sus propios registros, dispatchers, consumidores, Inbox, políticas de reintento y recuperación dentro de su ownership. No existe una Outbox, Inbox ni tabla de historial compartida entre módulos.
5. Cada módulo conserva schema, rol, migraciones e historial SQLx independientes. No se permiten escrituras, joins, FKs ni consultas directas entre schemas propietarios.
6. Los BFF no leen ni escriben Outbox/Inbox ni acceden directamente a PostgreSQL de negocio.
7. El transporte durable es NATS JetStream conforme a ADR-0007. NATS Core queda reservado para señales efímeras que no requieren recuperación durable.
8. Los comandos expresan acciones solicitadas; los eventos describen hechos ya confirmados. No publicar una intención como si el hecho ya hubiera ocurrido.
9. Los consumidores registran deduplicación y aplican el efecto local en una misma transacción cuando ambos son persistibles en PostgreSQL. El ACK del mensaje ocurre después del commit local.
10. La indisponibilidad temporal del broker no revierte un cambio de negocio ya confirmado: el mensaje permanece durable en Outbox hasta su publicación o intervención controlada.

## 3. Contrato operativo del mensaje

Cada mensaje durable debe disponer de un envelope versionado, definido por el contrato del módulo propietario. Debe incluir, cuando aplique:

- `event_id`: identidad estable y única del evento.
- `event_type` y `schema_version`: tipo y versión del contrato.
- `producer_module`: módulo propietario que produjo el mensaje.
- `aggregate_type` y `aggregate_id`: agregado al que pertenece.
- `event_sequence`: secuencia monotónica del evento dentro del agregado cuando el orden sea relevante.
- `aggregate_version`: versión del agregado que originó el evento, si el dominio la utiliza.
- `occurred_at`: instante informativo de ocurrencia; no es mecanismo de orden.
- `tenant_id` y contexto de actor: solo cuando el contrato y la autorización lo requieran.
- `correlation_id`, `causation_id`, `command_id` y `saga_id`: cuando correspondan, manteniendo sus significados diferenciados.
- Contexto W3C Trace Context para propagación de trazas, conforme a ADR-0004.

El envelope no debe duplicar el modelo de dominio ni incluir secretos, credenciales, tokens, datos completos de pago o información personal que el consumidor no necesite. Los payloads y metadatos se minimizan y clasifican.

Los identificadores técnicos UUID del sistema siguen ADR-0012. UUIDv7 y timestamps no sustituyen la secuencia de eventos ni demuestran causalidad.

## 4. Transactional Outbox

### 4.1 Escritura atómica

En una única transacción local del módulo productor:

1. Validar autorización e invariantes del dominio.
2. Aplicar el cambio de negocio.
3. Asignar la secuencia del evento bajo la concurrencia/serialización necesaria para ese agregado, si aplica.
4. Insertar los mensajes Outbox correspondientes con identidad estable y contrato versionado.
5. Confirmar la transacción.

Si la transacción revierte, no debe quedar ni el cambio ni la intención de publicación. Si confirma, ambos quedan persistidos. No insertar Outbox en una segunda transacción posterior al cambio.

Si una operación produce varios eventos, el módulo define el orden determinista entre ellos y les asigna secuencias no ambiguas dentro del agregado. La asignación de secuencia y el cambio que la origina deben compartir la transacción.

### 4.2 Ciclo de vida del registro

El ciclo operativo debe distinguir al menos los conceptos siguientes, aunque sus nombres físicos sean decisión de implementación:

- pendiente de publicación;
- reclamado/en proceso por un dispatcher;
- publicado con confirmación durable del broker;
- diferido para reintento;
- en cuarentena o sujeto a intervención.

Un registro no se considera publicado por el mero hecho de haber iniciado una llamada al broker. El dispatcher solo lo marca como publicado después de obtener y validar la confirmación durable correspondiente.

Si el resultado de publicación es incierto (por ejemplo, timeout después de enviar), no asumir que el broker no recibió el mensaje. La recuperación debe tolerar volver a publicar con la misma identidad estable; los consumidores deduplican.

### 4.3 Dispatchers concurrentes y leases

- El trabajo se reclama mediante un mecanismo durable y recuperable, compatible con ADR-0003: leases/claim con expiración y, cuando corresponda, `FOR UPDATE SKIP LOCKED`.
- La reclamación se realiza en lotes acotados; no se cargan todos los pendientes en memoria.
- Un lease expirado permite recuperar trabajo tras caída, pero no demuestra que la publicación anterior no haya ocurrido.
- La actualización a publicado debe estar protegida por identidad del mensaje y por el lease/claim vigente, para que un worker antiguo no sobrescriba el estado de otro intento.
- La concurrencia de publicación es limitada por módulo y workload.
- Cuando el orden por agregado sea obligatorio, los dispatchers no deben adelantar una secuencia posterior mientras exista una anterior sin resolver para ese mismo agregado, salvo política explícita de aislamiento/reordenamiento del contrato.
- No se requiere serializar agregados distintos: la concurrencia puede avanzar entre agregados independientes.
- Un dispatcher no mantiene abierta una transacción de base de datos durante una llamada de red al broker.

### 4.4 Confirmación y fallos

La confirmación debe corresponder a la persistencia durable aceptada por JetStream y a la configuración efectiva del stream. Un ACK de publicación no significa que un consumidor haya procesado el evento.

Ante un fallo:

- error transitorio: diferir y reintentar conforme a política;
- error permanente de contrato/configuración: detener el ciclo de reintento automático y escalar;
- resultado desconocido: reconciliar o republicar con la misma identidad idempotente, sin crear un evento lógico nuevo;
- caída del dispatcher: recuperar el lease y continuar desde el estado durable.

No borrar silenciosamente un mensaje por alcanzar un límite de intentos. El agotamiento conduce a cuarentena/DLQ o intervención documentada.

## 5. Inbox, deduplicación y ACK

### 5.1 Procesamiento atómico

Para un consumidor con efecto persistente local:

1. Recibir el mensaje durable.
2. Validar contrato, identidad, autorización/contexto y secuencia.
3. En una transacción local del módulo consumidor, registrar la recepción/deduplicación Inbox y aplicar el efecto de negocio o persistirlo como pendiente durable de orden.
4. Confirmar la transacción.
5. Solo entonces enviar el ACK al broker.

Si la transacción falla, no confirmar el mensaje al broker; la redelivery es esperada. Si el commit se completa pero se pierde el ACK, el mensaje puede llegar otra vez y debe reconocerse sin repetir el efecto.

### 5.2 Claves de deduplicación e integridad

- La deduplicación primaria se realiza por consumidor y `event_id`, con alcance y retención compatibles con la ventana real de redelivery/replay.
- Para eventos ordenados, aplicar también una restricción lógica por agregado y secuencia: un mismo par agregado/secuencia no puede representar dos eventos diferentes para el mismo contrato/flujo.
- Si llega el mismo `event_id` con contenido/identidad incompatible, o dos `event_id` distintos reclaman la misma secuencia, no elegir uno silenciosamente: aislar y generar una incidencia de integridad.
- Una repetición ya aplicada debe producir una respuesta idempotente y permitir confirmar el transporte sin repetir el efecto.
- La Inbox no se elimina antes de que expire la ventana aprobada de redelivery, replay y recuperación, considerando auditoría y requisitos legales.

### 5.3 Mensajes no procesables

Errores de esquema, versión incompatible, datos inválidos o violaciones de invariantes no deben reintentarse indefinidamente. Se clasifican, se conservan para inspección segura y se enrutan a cuarentena/DLQ o intervención conforme a la política del flujo.

Un consumidor no debe confirmar un mensaje que todavía no ha procesado ni persistido de forma durable. La excepción operativa es persistir primero el mensaje como pendiente de secuencia en su almacenamiento local durable; en ese caso el ACK confirma esa custodia durable, no la aplicación del efecto de negocio.

## 6. Secuencia por agregado y recuperación de huecos

### 6.1 Alcance del orden

No existe orden global entre módulos, streams, procesos o agregados. Solo se exige orden donde el contrato de dominio lo requiera, normalmente dentro de un agregado del módulo productor.

- `event_sequence` identifica el orden de los eventos de ese agregado.
- `aggregate_version` identifica una versión del agregado cuando el dominio la utiliza.
- Una versión puede producir cero, uno o varios eventos; por tanto, versión y secuencia no son intercambiables.
- El productor es la única autoridad para asignar la secuencia.
- Los consumidores no derivan orden de UUIDv7, timestamps, llegada al broker, `trace_id` ni `correlation_id`.

La secuencia debe asignarse de forma atómica bajo el control de concurrencia del agregado. Dos transacciones concurrentes no pueden confirmar eventos con la misma secuencia ni publicar una secuencia posterior como si la anterior no existiera.

### 6.2 Reglas del consumidor

Para cada agregado y flujo ordenado, el consumidor mantiene un cursor/posición durable de la última secuencia aplicada y aplica estas reglas:

- **Siguiente secuencia esperada:** procesar el efecto y avanzar el cursor en la misma transacción local.
- **Secuencia ya aplicada:** tratar como duplicado/obsoleta después de verificar identidad; no repetir el efecto.
- **Secuencia mayor que la esperada:** existe un hueco. No aplicar el efecto posterior si depende del anterior.
- **Secuencia menor que la esperada pero no reconocida como duplicado:** investigar conflicto, replay antiguo o corrupción; no descartarla sin validar.
- **Misma secuencia con otro evento:** incidencia de integridad; aislar y requerir intervención.

La entrega del broker puede duplicarse o llegar fuera de orden. La corrección del consumidor no depende de que JetStream por sí solo garantice el orden de negocio.

### 6.3 Tratamiento durable de huecos

Al detectar un hueco:

1. Registrar la secuencia esperada, la recibida, el agregado y el contexto de correlación.
2. Conservar durablemente el evento posterior recibido, junto con su envelope original, en el mecanismo local de Inbox/pendientes del consumidor; o dejarlo sin ACK si todavía no existe custodia durable y la política de redelivery es segura.
3. Si se confirma el mensaje al broker, hacerlo únicamente después de confirmar esa custodia durable local.
4. Solicitar/consultar al módulo productor autoritativo la existencia y estado de la secuencia faltante mediante el contrato permitido. Nunca consultar directamente su schema.
5. Reintentar la recuperación de forma limitada y observable.
6. Cuando llegue o se recupere la secuencia faltante, aplicar los eventos contiguos en orden, avanzando cursor y efectos dentro de transacciones locales.
7. Verificar que no quedan huecos pendientes y registrar el resultado de la reconciliación.

No fabricar un evento faltante ni modificar su payload para forzar continuidad. Si el productor confirma que no existe, la secuencia fue anulada formalmente o ya no puede recuperarse, el módulo propietario debe emitir una resolución explícita y auditable según el contrato; el consumidor no puede saltar el hueco por decisión local.

### 6.4 Recuperación y republicación

La recuperación puede utilizar una republicación del evento original desde la fuente durable del productor, conservando `event_id`, secuencia, tipo y payload originales. Si se necesita una representación corregida, debe definirse como una nueva versión/operación explícita con causalidad trazable; no sobrescribir el evento histórico como si nunca hubiera existido.

Las solicitudes de replay son operaciones controladas, autenticadas, auditadas y limitadas en tasa. No deben permitir leer o publicar datos de otro tenant sin autorización. Las proyecciones locales se reconstruyen/reconcilian desde mensajes autoritativos, sin apropiarse de la fuente de verdad.

## 7. Reintentos y clasificación de errores

La política debe clasificar, al menos:

- **Transitorio:** indisponibilidad temporal de red, broker o dependencia; saturación recuperable.
- **Permanente/no procesable:** contrato incompatible, payload inválido, autorización denegada o violación no recuperable.
- **Resultado desconocido:** timeout o desconexión después de que el efecto/publicación pudo haberse confirmado.
- **Conflicto de secuencia/integridad:** hueco, secuencia duplicada con identidad distinta o causalidad inconsistente.

Reglas:

- Los reintentos son limitados, con backoff exponencial y jitter.
- El máximo de intentos, delays, ventana total y clasificación de errores se configuran por módulo/flujo/entorno según criticidad y SLO; no hay un número universal.
- Respetar deadlines de negocio sin asumir que su expiración deshace un efecto.
- Antes de repetir un resultado desconocido, consultar/reconciliar o repetir con la misma identidad idempotente.
- Evitar reintentos simultáneos y tormentas; aplicar límites de concurrencia y circuit breaking/admisión cuando corresponda.
- Al agotar la política, mover a cuarentena/DLQ o estado de intervención sin borrar la evidencia.
- Registrar cada intento y su resultado sin incluir payloads sensibles en logs.

## 8. Dead Letter Queue (DLQ) y cuarentena

### 8.1 Propósito y clasificación

DLQ/cuarentena aísla mensajes que no pueden progresar automáticamente, sin perder evidencia ni bloquear indefinidamente el flujo normal. No es un mecanismo de descarte ni un archivo histórico ilimitado.

Cada mensaje en DLQ debe conservar o referenciar de forma segura:

- envelope y payload original exactos, o una referencia durable e íntegra a ellos;
- `event_id`, tipo/versión, productor, agregado y secuencia;
- consumidor y stream/consumer de origen;
- primera y última fecha de fallo, número de intentos y último resultado;
- clasificación y causa normalizada del fallo;
- `correlation_id`, `causation_id`, `saga_id` y contexto de traza cuando existan;
- referencia al runbook/incidencia y a las intervenciones efectuadas.

Los datos deben cifrarse y protegerse con mínimo privilegio. Los registros operativos no deben duplicar datos personales sensibles innecesarios. Cuando el payload original deba preservarse para replay, se almacena en un repositorio durable con acceso auditado y retención aprobada; no se expone en dashboards o logs.

### 8.2 Retención

No se establece una retención universal en días. Antes de producción, cada stream/DLQ debe definir y aprobar:

- clase de mensaje y criticidad;
- retención mínima necesaria para investigación, recuperación y obligaciones legales;
- límites de almacenamiento y política de capacidad;
- responsable de aprobar eliminación;
- procedimiento de exportación/archivo si se requiere conservación;
- tratamiento de datos personales, secretos y solicitudes legales aplicables;
- comportamiento al alcanzar límites, sin eliminación silenciosa.

La retención de DLQ es distinta de la retención de streams de negocio, Outbox/Inbox, auditoría y registros legales. Expirar un mensaje de DLQ no autoriza borrar un hecho de negocio ni su evidencia legal en el módulo propietario.

### 8.3 Inspección

La inspección debe:

1. Identificar productor, consumidor, contrato, agregado y secuencia.
2. Revisar causa, intentos, timestamps y trazas correlacionadas.
3. Determinar si el fallo es transitorio, permanente, incompatibilidad de versión, dato inválido, autorización, secuencia o integridad.
4. Comprobar si el efecto ya ocurrió pese a timeout/ACK perdido.
5. Evaluar impacto en Saga, proyecciones y pasos posteriores.
6. Definir si procede corregir configuración/handler, desplegar compatibilidad, reconciliar, compensar o escalar.

El acceso de inspección será de solo lectura por defecto. Ver o exportar payloads requiere permiso explícito y auditoría.

### 8.4 Reprocesamiento seguro

Antes de redrive/replay:

- corregir y validar la causa;
- verificar el estado del efecto en el módulo propietario;
- confirmar compatibilidad del consumidor con la versión original;
- comprobar deduplicación e idempotencia;
- comprobar que la secuencia anterior ya fue recuperada o que existe una resolución autorizada;
- aprobar la acción según severidad y ownership.

El reprocesamiento conserva `event_id`, secuencia y causalidad originales. Se limita la tasa y el volumen, y se monitoriza el resultado. No editar manualmente mensajes, borrar DLQ masivamente ni reenviar indiscriminadamente. Si el contenido debe cambiar, emitir una nueva operación/evento explícito que referencie al original, con autorización del módulo productor.

Cada inspección, exportación, redrive, descarte autorizado y resolución debe registrar actor/sistema, motivo, hora, alcance, resultado y referencia de aprobación. Una acción manual no puede escribir directamente en tablas de otro módulo.

## 9. Backpressure y límites operativos

### 9.1 Principio

Todas las colas, buffers, lotes, workers, conexiones y mensajes en vuelo deben tener límites. No se permite crecimiento ilimitado en memoria, conexiones o trabajo pendiente.

La carga debe regularse de extremo a extremo: admisión del consumidor, concurrencia del worker, pool SQLx del módulo, publicación a JetStream y capacidad de almacenamiento del stream.

### 9.2 Límites por definir

Cada módulo/flujo/entorno debe dimensionar y documentar, como mínimo:

- tamaño máximo de lote Outbox;
- concurrencia de dispatchers y consumidores;
- mensajes en vuelo y máximo de ACK pendientes;
- tamaño máximo de payload y límites del contrato;
- capacidad de buffers y colas locales;
- lease, timeout de adquisición y duración máxima de operación;
- límites de reintentos y ventana de retry;
- frecuencia de polling/adquisición;
- capacidad de almacenamiento y retención de streams/DLQ;
- presupuesto de CPU, memoria y conexiones PostgreSQL;
- reserva de capacidad para solicitudes de negocio y tareas operativas críticas.

Los valores se obtendrán de pruebas de carga, throughput esperado, latencia objetivo, tamaño de payload, capacidad del broker/DB, número máximo de réplicas y SLO. No copiar parámetros ilustrativos ni imponer un valor global a todos los módulos.

### 9.3 Protección de PostgreSQL y SQLx

- Outbox/Inbox usan el pool runtime del módulo propietario, conforme a ADR-0010; no se crea automáticamente un pool por worker.
- La concurrencia de background work se limita para no consumir todas las conexiones ni impedir solicitudes normales.
- Se reserva margen de conexiones para operaciones normales, recuperación y administración según el presupuesto global.
- Las transacciones son breves; nunca mantenerlas abiertas mientras se espera a JetStream, un proveedor o un backoff.
- Las reclamaciones usan lotes acotados y leases recuperables; los índices y el diseño físico se decidirán en la futura implementación sin modificar SQL en esta especificación.
- Ante espera de pool, locks o consultas lentas, reducir admisión y concurrencia antes de acumular tareas ilimitadas.
- Los errores de saturación se hacen visibles y controlados; no se ocultan mediante reintentos inmediatos.

### 9.4 Protección de JetStream y consumidores

- Limitar mensajes en vuelo, concurrencia y lotes por consumidor.
- Ajustar ACK wait, redelivery y límites del consumidor con base en la duración observada y los SLO; no fijar valores universales aquí.
- Pausar o reducir el pull/admisión cuando el consumidor o la base de datos estén saturados.
- Evitar que un consumidor lento provoque crecimiento ilimitado de buffers locales.
- Supervisar límites de almacenamiento, retención, replicación y capacidad del stream.
- La presión de un consumidor no debe inducir un bucle de reintentos agresivo ni bloquear agregados no relacionados.
- Para flujos ordenados, el aislamiento por agregado debe evitar que un hueco bloquee innecesariamente el procesamiento de otros agregados.

### 9.5 Modo degradado y recuperación

Cuando una dependencia no esté disponible:

- conservar en Outbox los mensajes aún no publicados;
- limitar la admisión de trabajo nuevo si el backlog amenaza la capacidad o los SLO;
- mantener health/readiness coherentes con la capacidad real de procesar trabajo;
- aplicar graceful shutdown y liberar/revocar leases de forma segura;
- reanudar gradualmente después de recuperar la dependencia, evitando una ráfaga de backlog;
- no descartar eventos de negocio para recuperar capacidad;
- escalar la intervención si la retención/capacidad disponible está próxima a agotarse.

El sistema debe poder priorizar operaciones críticas mediante políticas explícitas, sin alterar arbitrariamente la secuencia de un agregado.

## 10. Observabilidad y alertas

La instrumentación sigue ADR-0015 y usa OpenTelemetry, Prometheus, Alertmanager, Grafana, Loki y Tempo. Los indicadores se exponen con etiquetas de cardinalidad acotada (proceso, módulo, flujo normalizado, stream/consumer controlado, entorno y resultado). No usar `event_id`, `aggregate_id`, `tenant_id`, `user_id`, `saga_id`, `trace_id` ni otros IDs únicos como labels métricas.

### 10.1 Métricas mínimas

#### Outbox

- cantidad de mensajes pendientes y reclamados;
- edad del mensaje pendiente más antiguo;
- tasa de inserción/publicación;
- latencia commit-a-confirmación;
- errores, timeouts, expiración de leases y republicaciones;
- lotes, concurrencia y tiempo de ciclo del dispatcher.

#### Inbox y consumidores

- mensajes recibidos, procesados, duplicados y fallidos;
- tiempo desde publicación/ocurrencia hasta procesamiento;
- ACK, redelivery, pending ACK y consumer lag;
- secuencias fuera de orden, huecos activos y antigüedad del hueco más antiguo;
- mensajes diferidos y tiempo de espera de secuencia;
- latencia de transacción local y espera de pool SQLx.

#### DLQ

- entradas por causa normalizada;
- tamaño/almacenamiento utilizado;
- antigüedad del mensaje más antiguo;
- tasa de crecimiento, redrive, éxito/fallo de replay;
- mensajes próximos a vencer según política aprobada.

#### Capacidad y backpressure

- concurrencia activa y límites;
- mensajes en vuelo;
- tamaño de lotes y buffers;
- saturación/espera de pools SQLx;
- CPU, memoria, disco y almacenamiento de JetStream;
- pausas/reducción de admisión y tiempo en modo degradado;
- progreso de workers y leases expirados.

### 10.2 Alertas obligatorias

Las alertas deben cubrir, al menos:

- Outbox pendiente o mensaje más antiguo por encima del objetivo del flujo;
- publicación detenida, errores persistentes o leases que expiran repetidamente;
- crecimiento sostenido del backlog o del consumer lag;
- consumidores sin progreso, redelivery anormal o ACK pendientes excesivos;
- hueco de secuencia que supera su ventana de recuperación;
- DLQ con nuevas entradas, crecimiento o mensajes próximos a vencer;
- almacenamiento de JetStream/DLQ acercándose al límite operativo;
- saturación de pool SQLx, adquisición lenta, timeouts o presión de locks;
- workers saturados, reinicios repetidos o leases abandonados;
- backpressure sostenido que comprometa SLO o capacidad de recuperación.

Los umbrales y ventanas se definen por SLO, carga medida, criticidad y capacidad del entorno. Toda alerta tiene severidad, propietario, canal de notificación, condición de resolución y runbook. Evitar alertas por cada mensaje individual; agrupar por módulo/flujo/causa.

## 11. Procedimientos de intervención

Toda intervención manual se ejecuta mediante herramientas/operaciones autorizadas del módulo propietario, nunca mediante edición directa de tablas de otro módulo ni manipulación informal del broker.

### 11.1 Outbox detenido o backlog creciente

1. Identificar módulo, flujo, edad del mensaje más antiguo y tasa de crecimiento.
2. Revisar salud del proceso, dispatcher, PostgreSQL/pool SQLx, red y JetStream.
3. Distinguir indisponibilidad, saturación, error de credenciales/configuración, payload inválido o lease atascado.
4. Verificar si publicaciones con resultado incierto pudieron llegar al broker.
5. Recuperar leases vencidos conforme al mecanismo seguro y reanudar con concurrencia limitada.
6. Aumentar capacidad solo dentro del presupuesto global y después de medir la dependencia limitante.
7. Verificar reducción del backlog y ausencia de duplicación de efectos.

### 11.2 Hueco de secuencia

1. Identificar agregado, secuencia esperada y primera secuencia posterior recibida.
2. Confirmar que no es un retraso de entrega, duplicado o conflicto de identidad.
3. Consultar al módulo productor por su contrato, sin leer sus tablas.
4. Solicitar replay del evento original o resolución formal del productor.
5. Aplicar en orden y verificar cursor, efectos y ausencia de huecos restantes.
6. Si no puede resolverse, detener solo el alcance afectado, abrir incidencia y escalar al propietario del dominio.

### 11.3 DLQ

1. Abrir una incidencia con referencia al mensaje y causa.
2. Inspeccionar metadatos y payload solo con autorización.
3. Verificar efecto previo, secuencia, Saga y compatibilidad de contrato.
4. Corregir la causa y ejecutar pruebas de validación.
5. Aprobar y ejecutar redrive limitado, conservando identidad y auditoría.
6. Confirmar resultado y cerrar la incidencia o escalar si persiste.

### 11.4 Saturación/backpressure

1. Identificar el recurso limitante (pool PostgreSQL, locks, CPU/memoria, JetStream, consumidor o proveedor).
2. Reducir admisión/concurrencia del workload no crítico y mantener reservas para operaciones esenciales.
3. No aumentar workers/conexiones a ciegas ni sobrepasar el presupuesto de ADR-0010.
4. Comprobar que buffers y mensajes en vuelo permanecen dentro de límites.
5. Recuperar gradualmente la admisión cuando la dependencia se estabilice.
6. Vigilar backlog, latencia, redelivery y SLO hasta normalización.

### 11.5 Acciones prohibidas

- Borrar Outbox, Inbox, DLQ o mensajes pendientes para hacer desaparecer alertas.
- Marcar un mensaje como publicado sin confirmación durable.
- Confirmar al broker antes de persistir el efecto o la custodia durable del mensaje.
- Saltar secuencias sin resolución explícita del productor.
- Cambiar `event_id`, secuencia o payload original durante replay.
- Reintentar/compensar un resultado incierto sin reconciliación.
- Ejecutar SQL manual contra schemas de otros módulos.
- Reprocesar DLQ masivamente sin límites, autorización e idempotencia.
- Exponer payloads, secretos o datos personales en logs, métricas o tickets.

## 12. Retención, limpieza y auditoría de Outbox/Inbox

La limpieza de registros no es automática por antigüedad sin evaluar sus obligaciones.

Antes de eliminar registros publicados/procesados se deben definir:

- ventana máxima de redelivery y replay del transporte;
- ventana de recuperación y reconciliación;
- necesidades de auditoría y soporte;
- referencias desde Sagas, historial de módulo y procesos legales;
- requisitos de conservación y protección de datos;
- mecanismo de archivo/verificación cuando corresponda.

Outbox/Inbox operativos no sustituyen el historial de negocio ni el registro de auditoría propio de cada módulo. La eliminación de una copia operativa no elimina el hecho de negocio que deba conservarse. La política debe evitar tanto borrar evidencia necesaria como acumular indefinidamente datos operativos.

## 13. Pruebas de aceptación antes de implementar

La futura implementación debe demostrar, por módulo y flujo aplicable:

1. Caída antes del commit: ni cambio de negocio ni Outbox quedan confirmados.
2. Caída después del commit y antes de publicar: Outbox permite publicar tras recuperación.
3. Publicación exitosa con respuesta perdida: republicación no duplica el efecto.
4. Caída después de publicar y antes de marcar Outbox: recuperación segura.
5. Caída después del commit del consumidor y antes del ACK: Inbox evita repetir el efecto.
6. Dos dispatchers/consumidores concurrentes: leases y deduplicación evitan corrupción.
7. Eventos duplicados, atrasados, fuera de orden y con huecos: comportamiento determinista.
8. Conflicto de dos eventos con la misma secuencia: aislamiento y alerta de integridad.
9. Recuperación/replay de hueco conserva identidad, secuencia y causalidad.
10. Error permanente y agotamiento de reintentos: cuarentena/DLQ con evidencia.
11. Inspección, aprobación, redrive y retención de DLQ son auditables.
12. Backpressure limita memoria, mensajes en vuelo, workers y conexiones sin perder mensajes durables.
13. Indisponibilidad de PostgreSQL o JetStream no provoca tormentas de reintentos ni ACK prematuros.
14. Un módulo no accede a tablas, credenciales ni schemas de otro módulo.
15. Métricas/alertas identifican backlog, antigüedad, lag, huecos, DLQ y saturación sin cardinalidad descontrolada ni datos sensibles.
16. Graceful shutdown y expiración de leases permiten recuperación por otra réplica.
17. Despliegues graduales toleran versiones de contratos compatibles.

## 14. Parámetros que deben cerrarse antes de producción

No se fijan números universales en esta especificación. Cada módulo/flujo/entorno debe aprobar una ficha operativa que contenga:

| Parámetro | Criterio para definirlo |
|---|---|
| Máximo de intentos y ventana total | Clasificación de error, SLO, criticidad y tiempo de recuperación |
| Backoff, jitter y timeout | Latencia de dependencia, duración de operación y deadline |
| Lote y concurrencia | Throughput, tamaño de payload, CPU y capacidad PostgreSQL/JetStream |
| Lease y frecuencia de reclamación | Duración real del trabajo, recuperación y concurrencia de réplicas |
| Mensajes en vuelo / ACK wait | Tiempo de procesamiento y capacidad del consumidor |
| Retención Outbox/Inbox/DLQ/stream | Replay, auditoría, recuperación, obligaciones legales y almacenamiento |
| Umbrales de backlog/antigüedad/lag | SLO, tasa de producción/consumo y capacidad de drenaje |
| Límites de payload/buffers | Contratos, memoria y capacidad de red/almacenamiento |
| Reserva de conexiones | Presupuesto global PostgreSQL de ADR-0010 y máximo de réplicas |
| Severidad y escalamiento | Impacto de negocio, alcance y tiempo tolerable de degradación |

La ficha debe incluir propietario, fecha de revisión, entorno, evidencia de pruebas de carga, runbook y aprobación operativa. Un valor definido para un módulo no se convierte automáticamente en estándar universal.

## 15. Referencias y jerarquía

- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](../adr/0003-stateless-outbox-inbox-and-jobs.md): reglas base de atomicidad, SKIP LOCKED, leases, Inbox, at-least-once, idempotencia y backpressure.
- [ADR-0010: PostgreSQL Connection Pooling y gestión de recursos](../adr/0010-postgresql-connection-pooling-and-resource-management.md): pools por módulo, presupuesto global y límites de workers.
- [ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos](../adr/0013-distributed-transactions-and-saga-consistency.md): ownership, Sagas, transporte durable, secuencia/versiones, recuperación e intervención.
- [ADR-0015: Observabilidad integral](../adr/0015-integrated-observability-platform.md): instrumentación, métricas, logs, trazas y alertas.
- [Estrategia técnica de consistencia distribuida y Sagas](./distributed-transaction-consistency.md): coordinación de procesos multi-módulo.
- [Estrategia técnica de observabilidad integral](./observability-strategy.md): plataforma de telemetría.

Si esta especificación pareciera contradecir un ADR aceptado, prevalece el ADR. Una modificación de una decisión aceptada requiere el proceso de gobernanza y un ADR aprobado; esta especificación no puede debilitarlas.

## 16. Estado de implementación

**Especificación documental creada; implementación pendiente.** Este documento no crea tablas, schemas, roles, migraciones, índices, crates, dependencias, contratos ejecutables, workers, dispatchers, consumidores, streams, DLQs, dashboards, alertas ni infraestructura. No modifica archivos `.sql` ni migraciones y no ejecuta operaciones de base de datos.

Los parámetros operativos y fichas por módulo/flujo deben completarse con evidencia de capacidad y pruebas antes del despliegue a producción.
