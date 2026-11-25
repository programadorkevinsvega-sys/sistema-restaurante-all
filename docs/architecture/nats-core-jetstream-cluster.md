# Estrategia técnica de NATS Core y JetStream en clúster

**Estado:** especificación técnica aprobada y vigente conforme a ADR-0017 Accepted.  
**Ámbito:** mensajería entre los cuatro procesos, módulos y workers autorizados.  
**Decisiones relacionadas:** ADR-0003, ADR-0004, ADR-0007, ADR-0008, ADR-0013, ADR-0015 y ADR-0017.

## 1. Objetivo y garantías

| Mecanismo | Uso | Garantía y límite |
|---|---|---|
| NATS Core | Señales efímeras y request/reply tolerante a desconexión | Suscriptores activos; sin persistencia ni replay |
| NATS JetStream | Eventos y trabajo durable | Persistencia, ACK y redelivery; at-least-once |
| PostgreSQL Outbox | Intención durable junto al cambio local | Atomicidad en la transacción del módulo |
| PostgreSQL Inbox | Deduplicación y efecto local | Evita repetir efectos confirmados ante redelivery |

No se promete exactly-once extremo a extremo. El ACK de publicación confirma aceptación durable según la configuración del stream; no confirma que un consumidor haya aplicado el efecto de negocio.

## 2. Topología de referencia

La topología mínima de producción consta de tres nodos NATS con JetStream habilitado, quorum y colocación entre dominios de fallo independientes. Los clientes conocen múltiples endpoints. Cada nodo tiene identidad, configuración y almacenamiento persistente local.

- NATS-1: Core + JetStream + almacenamiento local, dominio de fallo A.
- NATS-2: Core + JetStream + almacenamiento local, dominio de fallo B.
- NATS-3: Core + JetStream + almacenamiento local, dominio de fallo C.
- Los procesos se conectan mediante TLS a endpoints del clúster, no a una instancia fija.
- Los streams críticos se configuran con R=3 y se verifica la ubicación efectiva de las réplicas.

### 2.1 Clúster y quorum

- Tres nodos son la base mínima para tolerar la pérdida de uno y conservar mayoría.
- El crecimiento a cinco nodos requiere métricas y pruebas que justifiquen capacidad adicional. No se adopta un número par como objetivo de quorum.
- No confundir quorum del clúster/metadatos con el número de réplicas de cada stream.
- Habilitar JetStream en todos los nodos no replica automáticamente todos los streams.
- Ante pérdida de quorum no se fuerza escritura ni se desactiva consistencia.
- Agregar, evacuar o sustituir nodos requiere verificar réplicas, catch-up y quorum antes de retirar miembros.

### 2.2 Clústeres múltiples y recuperación geográfica

Gateways conectan clústeres separados, pero no los convierten en un único quorum. La replicación de un stream dentro de un clúster no se extiende automáticamente a otro.

La recuperación geográfica podrá usar un clúster independiente con mirrors/sources o backup/restauración soportados. Se documentarán dirección, retraso aceptable, promoción, prevención de split-brain, RPO/RTO y reconciliación. No permitir dos destinos activos para el mismo flujo durable sin ownership e idempotencia explícitos.

## 3. NATS Core

Usos permitidos: señales efímeras reconstruibles o cuya pérdida sea tolerable, notificaciones transitorias, request/reply con deadline y fan-out temporal.

- No asumir persistencia, replay, ACK durable ni entrega a suscriptores desconectados.
- El publicador no interpreta el envío como confirmación de procesamiento.
- Timeout no prueba que el receptor no ejecutó la operación.
- No transportar la única copia de una orden, evento de negocio o trabajo recuperable.
- Reconstruir señales perdidas desde la fuente autoritativa o usar JetStream si la pérdida no es tolerable.
- Slow consumers, desconexiones y reconexiones deben generar métricas y backpressure.

## 4. JetStream: streams y replicación

Cada stream tendrá ficha documentada: módulo productor, responsable, cuenta, subjects, finalidad, clasificación, versión, almacenamiento, réplicas/colocación, retención/límites, consumidores, ventana de replay, backup/restore, RPO/RTO y runbook.

La política estándar para streams críticos de producción es R=3 en tres dominios de fallo independientes. Toda excepción debe justificar la menor redundancia y su recuperación. No configurar R=1 accidentalmente para streams críticos.

### 4.1 Retención

- **Limits-based:** eventos con ventana de replay definida por límites de edad/tamaño/cantidad.
- **WorkQueue:** solo para flujos con semántica de cola exclusiva y ciclo de vida compatible.
- **Interest-based:** solo cuando el ciclo de vida dependa de consumidores durables interesados.

La retención se elige por semántica de negocio y recuperación. No reemplaza historial, auditoría ni obligaciones legales del módulo.

### 4.2 Consumidores durables

- Usar consumidores durables para procesamiento recuperable.
- ACK explícito después del commit local de Inbox y efecto, o después de persistir durablemente un mensaje pendiente de secuencia.
- Configurar ACK wait, redelivery, máximo de entregas y máximo de ACK pendientes según latencia medida.
- Limitar concurrencia y mensajes en vuelo a la capacidad real del consumidor.
- Resolver duplicados y desorden según event_sequence, cursor e Inbox; no confiar exclusivamente en el orden de llegada.
- Errores permanentes, contratos inválidos o agotamiento de reintentos pasan a cuarentena/DLQ de aplicación con evidencia y redrive auditado.

## 5. Integración Outbox/Inbox

1. El productor confirma cambio de negocio y Outbox en una transacción local PostgreSQL.
2. El dispatcher publica al subject autorizado de JetStream.
3. Solo tras ACK durable válido marca Outbox como publicado.
4. Resultado incierto: republicar la misma identidad, no crear otro evento lógico.
5. El consumidor valida contrato, versión, identidad y secuencia.
6. En transacción local registra Inbox y aplica efecto, o persiste durablemente el mensaje pendiente de secuencia.
7. Solo después del commit envía ACK.
8. Si se pierde el ACK, JetStream puede redeliver; Inbox evita repetir el efecto.

Outbox, Inbox e historial SQLx siguen independientes por módulo. No existe schema ni tabla compartida para centralizar mensajería.

## 6. Subjects, cuentas e identidad

Subjects jerárquicos, con productor y tipo de evento identificables, y versión cuando la compatibilidad lo requiera. La convención se mantendrá en un catálogo versionado. Ejemplo conceptual: dominio.modulo.recurso.evento.vN.

No usar datos personales, identificadores de tenant ni valores libres como segmentos. El envelope transporta el contexto necesario.

- Separar entornos y límites de confianza mediante cuentas NATS.
- Identidades de procesos y workers sin credenciales globales compartidas.
- Permisos publish/subscribe explícitos por subject y rol.
- Imports/exports entre cuentas explícitos, limitados y auditables.
- Cuenta de sistema y operaciones administrativas protegidas.
- Límites de conexiones, suscripciones, bytes y recursos por cuenta.

La cuenta NATS no reemplaza autorización de negocio, aislamiento de tenant ni controles de acceso de los módulos.

## 7. TLS y protección de datos

TLS protege por separado conexiones cliente-servidor, rutas internas, gateways, leaf nodes y endpoints administrativos/monitorización cuando atraviesen red. Validar certificados y rotarlos controladamente. TLS 1.2 mínimo y TLS 1.3 preferido cuando sea compatible.

Credenciales en gestor de secretos o mecanismo seguro equivalente, nunca en Git o imágenes. Definir expiración, rotación, revocación y respuesta ante compromiso.

Cifrado en reposo JetStream según clasificación y modelo de amenazas. La clave queda fuera de archivos de configuración, con permisos mínimos y backup/recuperación. Cifrado de volumen/disco como capa complementaria.

Minimizar payloads. No incluir secretos, tokens, credenciales ni datos sensibles completos. Retención y backups sujetos a clasificación, control de acceso y política de eliminación.

## 8. Almacenamiento, backups y disaster recovery

- Disco persistente local de baja latencia e IOPS dimensionadas por nodo; no compartir directorios.
- Supervisar capacidad, latencia, errores, crecimiento y espacio reservado.
- Snapshots/backups mediante mecanismos soportados, con verificación de consistencia y restaurabilidad.
- Copias fuera del clúster y, ante desastre, fuera del dominio/región de fallo principal.
- Pruebas de restauración completa/parcial, metadatos, identidad y reanudación de consumidores.
- RPO/RTO por clase de flujo. R=3 no protege contra borrado lógico propagado, corrupción común, pérdida regional o error administrativo.
- Replay conserva event_id, event_sequence, aggregate_version, causalidad y versión.
- No eliminar backups sin verificar retención, restauraciones y obligaciones legales.

## 9. Capacidad, backpressure y degradación

Dimensionar conexiones, reconexiones, subjects, suscripciones, fan-out, publicaciones/consumo por segundo, payload, almacenamiento, retención, CPU, memoria, red, IOPS, ACK pendientes, redelivery y lag.

Límites finitos a buffers, publicaciones pendientes, mensajes en vuelo, consumidores y reintentos. Backoff+jitter y recuperación gradual. La indisponibilidad del broker no borra Outbox ni bloquea indefinidamente transacciones de negocio.

Core puede degradarse perdiendo señales efímeras; la aplicación debe reconstruirlas o declarar degradación. JetStream sin quorum no confirma escrituras que no alcancen garantías configuradas. Prohibido degradar silenciosamente a Core para reemplazar publicación durable.

## 10. Observabilidad y alertas

Conforme a ADR-0015:

| Área | Señales mínimas |
|---|---|
| Core | conexiones, reconexiones, rutas, mensajes/bytes, errores, slow consumers |
| Cluster | nodos, quorum, líderes y cambios de topología |
| JetStream | réplicas, catch-up, streams/consumers, almacenamiento, publish ACK latency |
| Consumidores | pending, ACK pending, redelivery, lag, edad del mensaje más antiguo |
| Recursos | CPU, memoria, disco, IOPS, red y file descriptors |
| Seguridad | fallos authn/authz, cambios administrativos, certificados |
| Integración | Outbox backlog/edad, Inbox, DLQ, huecos y progreso |

Métricas sin event_id, tenant_id, aggregate_id, trace ID ni subjects dinámicos como labels. Logs sin payloads completos ni credenciales. Endpoints privados y autenticados. Cada alerta tendrá severidad, propietario, runbook y criterio de resolución.

## 11. Pruebas de aceptación antes de producción

1. Pérdida de un nodo sin perder quorum ni disponibilidad de streams R=3.
2. Pérdida de dominio de fallo y verificación de colocación.
3. Pérdida de quorum: no confirmar escrituras durables sin garantía requerida.
4. Reconexión, actualización rolling y reemplazo de nodo sin split-brain.
5. Detectar streams críticos accidentalmente R=1.
6. Publicación con respuesta perdida y republicación con misma identidad.
7. Caída de consumidor antes/después del commit y antes del ACK.
8. Redelivery, duplicados, desorden y huecos con recuperación idempotente.
9. Slow consumer, disco saturado, límite de almacenamiento y backpressure.
10. Aislamiento de cuentas y permisos por subject.
11. TLS y validación de certificados en clientes y rutas.
12. Rotación/revocación de credenciales y certificados.
13. Backup/restauración, integridad y reanudación probados.
14. Recuperación del clúster según RPO/RTO.
15. Monitorización sin permisos administrativos ni exposición pública.
16. Carga sostenida y picos sin buffers ilimitados ni tormentas de reintentos.
17. Caída de observabilidad sin interrumpir mensajería de negocio.

## 12. Parámetros operativos por cerrar con evidencia

| Parámetro | Criterio |
|---|---|
| Número final de nodos y dominios | Topología física, capacidad, quorum y presupuesto |
| Réplicas por stream | Criticidad, RPO, costo y tolerancia |
| Disco/IOPS | Throughput, retención, tamaño y crecimiento |
| Retención/límites | Replay, recuperación, auditoría y obligaciones |
| Max payload | Contratos, red, memoria y persistencia |
| ACK wait, max deliver, max ack pending | Duración y concurrencia del procesamiento |
| Timeouts y backoff | Latencia y SLO de dependencias |
| Límites de conexiones/suscripciones | Presupuesto por proceso/cuenta |
| RPO/RTO y backups | Criticidad y pruebas de restauración |
| Umbrales de lag | Producción/consumo y capacidad de drenaje |

Cada ficha tendrá propietario, entorno, evidencia, runbook y revisión. Son parámetros operativos, no decisiones arquitectónicas pendientes.

## 13. Referencias y jerarquía

- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](../adr/0003-stateless-outbox-inbox-and-jobs.md).
- [ADR-0004: W3C Trace Context](../adr/0004-w3c-trace-context.md).
- [ADR-0007: Cuatro backends independientes y comunicación](../adr/0007-four-independent-backends-and-communication.md).
- [ADR-0013: Consistencia distribuida y Sagas](../adr/0013-distributed-transactions-and-saga-consistency.md).
- [ADR-0015: Observabilidad integral](../adr/0015-integrated-observability-platform.md).
- [Operación de Transactional Outbox e Inbox](./transactional-outbox-inbox-operations.md).
- [Estrategia técnica de observabilidad integral](./observability-strategy.md).
- [Documentación oficial NATS: clustering y replicación](https://docs.nats.io/learn/clustering/).
- [Documentación oficial NATS: JetStream](https://docs.nats.io/concepts/jetstream).
- [Documentación oficial NATS: seguridad y TLS](https://docs.nats.io/learn/security/).

Si esta especificación contradice un ADR aceptado, prevalece el ADR. Una modificación requiere un nuevo ADR aceptado.

## 14. Estado de implementación

**Especificación documental aprobada y vigente; implementación pendiente.** No crea clústeres, nodos, streams, consumers, cuentas, subjects, credenciales, certificados, backups, dashboards, alertas, contenedores, manifests, crates ni dependencias. No modifica código, SQL, migraciones, schemas, roles PostgreSQL ni datos.
