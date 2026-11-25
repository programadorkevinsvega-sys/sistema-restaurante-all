# ADR-0017: NATS Core y JetStream en clúster de alta disponibilidad

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto y aceptado: 2026-11-24
- Aprobación: propietario del producto.

## Contexto

ADR-0007 establece NATS Core para señales y mensajes efímeros, y NATS JetStream para eventos/mensajes que requieren persistencia, confirmación durable, reintentos o recuperación. ADR-0003 y ADR-0013 establecen Outbox/Inbox, entrega at-least-once e idempotencia. La plataforma debe soportar fallos, crecimiento, aislamiento y operación segura. Un clúster Core no convierte los mensajes efímeros en durables; JetStream requiere configuración explícita de réplicas por stream.

## Decisión

### 1. Topología de clúster

1. NATS será la plataforma de mensajería para los usos definidos en ADR-0007; no se incorpora otro broker para los mismos flujos.
2. Producción utilizará un clúster NATS distribuido, con Core y JetStream habilitados en los nodos de la plataforma.
3. La base de alta disponibilidad será de **tres nodos como mínimo**, número impar para mantener quorum ante la pérdida de uno. El crecimiento a cinco nodos u otra topología requiere justificación de capacidad y validación operativa.
4. Los nodos se distribuirán entre dominios de fallo independientes (zonas, racks y hosts), con anti-afinidad. Tres procesos en el mismo host no constituyen alta disponibilidad.
5. Cada nodo tendrá identidad y almacenamiento persistente propios. No se compartirá el directorio JetStream entre nodos ni se usará filesystem compartido como sustituto de la replicación nativa.
6. Los clientes utilizarán múltiples endpoints y tolerarán desconexiones, reconexión con backoff+jitter, drenado y failover. Ningún proceso dependerá de un único nodo.
7. Gateways/super-clusters conectan clústeres independientes; no amplían automáticamente el quorum ni replican un stream entre clústeres.

### 2. Responsabilidades y garantías

**NATS Core** queda reservado para señales efímeras, notificaciones transitorias y request/reply cuya pérdida durante desconexiones sea tolerable o reconstruible desde una fuente autoritativa.

- Entrega a suscriptores activos, sin persistencia ni replay.
- La reconexión no recupera mensajes publicados mientras un suscriptor estaba desconectado.
- Requests con deadline, timeout explícito, límites de concurrencia y backpressure.
- Prohibido para eventos confirmados, trabajo recuperable o procesos que requieran replay.

**NATS JetStream** queda reservado para eventos y mensajes durables mediante streams persistentes y consumidores durables.

- Streams de negocio de producción con almacenamiento en disco.
- Política predeterminada para streams críticos: replicación **R=3**, distribuida entre tres dominios de fallo independientes cuando la infraestructura lo permita.
- Menos réplicas solo para datos expresamente no críticos, con pérdida aceptable documentada; nunca por omisión accidental.
- La publicación se considera durable solo después del ACK de JetStream según la política efectiva del stream.
- Consumidores con ACK explícito, límites de entrega y de mensajes pendientes, ventanas de ACK y redelivery dimensionados.
- Entrega **at-least-once**. Duplicados y redelivery son esperados; la idempotencia es obligatoria.
- Deduplicación/doble confirmación del broker no equivalen a exactly-once extremo a extremo ni sustituyen Outbox/Inbox.

### 3. Ownership y aislamiento

1. El módulo productor conserva propiedad del evento, contrato versionado, Outbox y política de publicación.
2. El módulo consumidor conserva Inbox/deduplicación, cursor/secuencia cuando aplique y efecto local.
3. No existe Outbox, Inbox, historial SQLx ni schema compartido por utilizar un broker común.
4. Los subjects serán jerárquicos, versionados y gobernados por módulo productor y tipo de mensaje. Se prohíben subjects genéricos sin propietario y comodines amplios como autorización por defecto.
5. Contratos/envelopes mantienen ADR-0003, ADR-0004 y ADR-0013: identidad, versión, productor, agregado/secuencia cuando aplique, causalidad y W3C Trace Context. UUIDv7/timestamps no sustituyen el orden del agregado.
6. Los BFF no son propietarios de eventos ni de estado durable. Los módulos conservan ownership conforme a ADR-0008.
7. Imports/exports entre cuentas NATS serán explícitos, mínimos y auditables.

### 4. Seguridad

- TLS obligatorio para clientes y enlaces internos del clúster; proteger también gateways, leaf nodes y endpoints administrativos si se incorporan.
- Validación de certificados; TLS 1.2 mínimo y TLS 1.3 preferido cuando sea compatible.
- Identidades/credenciales NATS gestionadas de forma segura (NKeys/JWT u otro mecanismo soportado), sin credenciales estáticas compartidas entre procesos.
- Mínimo privilegio por cuenta y subject: publicar/suscribirse solo a los subjects requeridos. Identidades separadas para procesos, consumidores y operación.
- Aislamiento por cuentas y límites de recursos; cuenta de sistema y endpoints administrativos/monitorización no expuestos públicamente.
- Secretos fuera del repositorio, imágenes y logs; rotación y revocación controladas.
- Cifrado en reposo de JetStream según clasificación y modelo de amenazas. Claves fuera de archivos de configuración, con control de acceso, rotación y recuperación probada.
- Mensajes minimizados: no almacenar secretos, credenciales, tokens, payloads completos de pago ni datos personales innecesarios.

### 5. Persistencia y recuperación

1. Cada stream tendrá propietario, subjects, finalidad, clasificación, retención, réplicas, límites y runbook documentados.
2. Retención explícita según semántica: limits-based para historial/replay acotado; work-queue solo para trabajo de consumo exclusivo; interest-based solo cuando corresponda. No hay política universal.
3. Retención debe cubrir ventanas de consumo/replay/recuperación; no sustituye historial de negocio ni retención legal.
4. R=3 protege ante fallos de nodos del clúster, pero **no sustituye backups ni protege por sí sola ante pérdida del clúster, borrado lógico, corrupción o desastre regional**.
5. Backups/snapshots consistentes fuera del clúster y pruebas de restauración. Recuperación geográfica mediante mirror/source o clúster independiente, con RPO/RTO documentados.
6. La pérdida de quorum puede detener escrituras durables. No forzar líderes ni reducir quorum para aparentar disponibilidad sacrificando consistencia.
7. Replay y redrive conservan identidad, versión, secuencia y causalidad originales; consumidores idempotentes.

### 6. Resiliencia, escalabilidad y observabilidad

- Dimensionar throughput, picos, tamaño de mensajes, fan-out, conexiones, consumidores, almacenamiento, IOPS, red y retención.
- Backpressure end-to-end: límites finitos de buffers, publicaciones pendientes, mensajes en vuelo, ACK pendientes, concurrencia y lotes Outbox. Prohibidos buffers ilimitados y reintentos sincronizados.
- Timeouts, backoff exponencial+jitter y clasificación de errores; no reintentar indefinidamente errores permanentes.
- Mensajes no procesables a cuarentena/DLQ de aplicación, con evidencia y redrive auditado; nunca descartar silenciosamente.
- Despliegues rolling verificando quorum, réplicas, consumidores y almacenamiento.
- Agregar nodos no aumenta automáticamente réplicas de streams ni distribuye uniformemente su carga.
- Conforme a ADR-0015, medir nodos/rutas/conexiones, slow consumers, quorum, líderes, réplicas/catch-up, streams/consumers, ACK latency, lag, redelivery, almacenamiento, disco/IOPS, CPU/memoria, seguridad y backlog Outbox/Inbox/DLQ.
- Endpoints de monitorización privados y protegidos. No usar payloads, credenciales ni IDs de alta cardinalidad como labels.

### 7. Parámetros operativos

Cantidad final de nodos, dominios de fallo, réplicas por stream, capacidad/IOPS, tamaño máximo, retención, límites de conexiones/consumidores/ACK, deadlines, backoff, RPO/RTO y umbrales de lag se dimensionan por entorno y flujo con pruebas. Son parámetros de operación, no decisiones arquitectónicas pendientes.

## Consecuencias

- Core y JetStream tienen garantías y usos distintos.
- La plataforma elimina el nodo único como punto de fallo y establece quorum/replicación para mensajería durable crítica.
- Core no recupera mensajes efímeros; los flujos que no toleran pérdida usan JetStream.
- JetStream puede redeliver; consumidores idempotentes confirman después del commit local.
- Se requieren almacenamiento, backups, observabilidad y runbooks.
- Se preservan ownership de módulos, Outbox/Inbox independientes y separación de los cuatro procesos.
- Esta decisión no significa que NATS, nodos, streams, cuentas, certificados o backups estén desplegados.

## Alternativas consideradas

- Un único servidor NATS en producción: rechazado por ser punto único de fallo.
- NATS Core para todos los mensajes: rechazado porque no persiste ni reproduce mensajes.
- Una sola réplica para eventos críticos: rechazada por no tolerar pérdida del nodo.
- Asumir que JetStream replica automáticamente todos los streams: rechazado; cada stream configura y verifica réplicas.
- Usar gateways como sustituto de replicación: rechazado; conectan clústeres, no extienden el quorum de un stream.
- Exactly-once global del broker: rechazado; el sistema mantiene at-least-once + Outbox/Inbox + idempotencia.
- JetStream como base de datos de negocio: rechazado; PostgreSQL y el módulo propietario conservan la fuente autoritativa.

## Relación con ADR anteriores

ADR-0003 y ADR-0013 mantienen Outbox/Inbox, idempotencia, Sagas y recuperación. ADR-0004 mantiene W3C Trace Context. ADR-0007 mantiene gRPC para solicitudes síncronas, Core para señales efímeras y JetStream para mensajería durable. ADR-0008 conserva ownership. ADR-0015 define observabilidad. ADR-0017 concreta topología, disponibilidad, seguridad y operación sin cambiar responsabilidades aprobadas.

## Estado de implementación

Decisión arquitectónica aceptada. Este ADR no instala NATS, crea nodos/clústeres, habilita JetStream, configura streams/consumers/accounts, crea certificados/credenciales/backups ni modifica código, dependencias, SQL, migraciones, schemas o datos. La implementación requiere una fase posterior.
