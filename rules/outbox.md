> **Estado: superseded.** Este documento se conserva como referencia histórica. La fuente normativa vigente es [Reglas vigentes de Outbox, Inbox e idempotencia](../docs/engineering/implementation-rules.md#4-stateless-outboxinbox-e-idempotencia). No añadir reglas nuevas aquí ni resolver contradicciones desde este archivo; actualizar la fuente vigente y registrar ADR cuando corresponda.\n\n# Reglas de eventos Outbox e Inbox

## Alcance

Estas reglas aplican a eventos de dominio que deban publicarse de forma
duradera y a consumidores que procesen mensajes con efectos persistentes.
Complementan los [requisitos de eventos](../requisitos.md) y el
[roadmap](../ROADMAP.md); no implican que el broker, los workers ni el flujo
completo estén implementados.

Restaurant OS inicia como monolito modular con PostgreSQL compartido. La
selección del broker sigue abierta; estas reglas definen garantías
independientes del transporte y no requieren una topología de microservicios.

## Propiedad y atomicidad

- Publicar eventos que representen hechos de dominio ya confirmados, no
  comandos ni estados que todavía puedan revertirse.
- Registrar un evento Outbox solo cuando un consumidor necesite recibir ese
  hecho de forma durable; no emitir eventos por cada cambio interno.
- Por defecto, el módulo propietario de los datos persiste sus eventos Outbox
  y controla su ciclo de vida.
- Insertar el cambio de negocio y su evento Outbox en la misma transacción
  PostgreSQL local del módulo. Si la transacción falla, ninguno debe quedar
  confirmado.
- No llamar al broker dentro de la transacción de negocio ni compartir
  transacciones SQLx entre módulos.
- Un puerto o adapter de mensajería puede abstraer la publicación, pero no
  sustituye la persistencia atómica del Outbox. Un Outbox compartido requiere
  una decisión arquitectónica documentada que respete la propiedad de datos y
  la atomicidad local.

Las migraciones existentes no siguen todavía una única convención de
persistencia: algunas definen Outbox por módulo y otras describen una capa de
mensajería compartida o futura. Reconciliar esa diferencia antes de implementar
los productores y workers; la presencia de una tabla o un puerto no demuestra
que exista entrega durable.

## Contrato del evento

- Versionar el tipo y el esquema del evento. Los consumidores deben validar la
  versión y no reinterpretar silenciosamente versiones desconocidas.
- El contrato debe incluir un identificador estable del evento, tipo, versión,
  tenant, sucursal cuando corresponda, agregado de origen y fecha del hecho.
  Incluir contexto de correlación y causalidad cuando esté disponible.
- Mantener estable la identidad del evento durante todos los reintentos.
- Incluir solo los datos que el consumidor necesita. No incluir secretos,
  credenciales, datos de pago ni información personal innecesaria.
- Validar que el tenant y la sucursal del evento correspondan a los recursos
  afectados. El contenido del mensaje no concede autorización; cada consumidor
  establece su contexto autorizado y aplica RLS según las reglas de
  [PostgreSQL](./postgres.md).
- No asumir orden global. Si un flujo requiere orden por agregado, definir una
  secuencia o versión del agregado y hacer explícito cómo se detectan huecos o
  eventos atrasados.

Las migraciones pueden tener estructuras distintas según el dominio. Esta
regla define garantías semánticas, no exige copiar un DDL, nombre de tabla o
formato de payload idéntico en todos los módulos.

## Publicación desde Outbox

- Reclamar eventos pendientes con concurrencia acotada y un lease recuperable.
  Confirmar el reclamo en una transacción breve y liberar la conexión antes de
  esperar al broker.
- Publicar fuera de la transacción PostgreSQL. Marcar el evento como publicado
  solo después de recibir la confirmación de publicación durable que ofrezca el
  broker seleccionado.
- Proteger las actualizaciones de estado con el lease o token de reclamo
  vigente, para que un worker con un lease vencido no sobrescriba el estado de
  otro worker.
- Tratar la entrega como *at-least-once*. Si el broker acepta el mensaje y el
  worker falla antes de guardar el resultado, el evento puede publicarse de
  nuevo.
- Reintentar fallos transitorios con backoff acotado y jitter. Registrar el
  resultado y pasar los fallos permanentes o agotados a un estado durable de
  cuarentena o DLQ; no descartarlos silenciosamente.
- Limitar concurrencia, tamaño de lote, tiempo de espera y uso de conexiones.
  Aplicar backpressure si el broker o la base de datos no pueden sostener el
  ritmo de publicación.

No prometer entrega *exactly-once* extremo a extremo. La elección entre
RabbitMQ, NATS JetStream u otro broker y sus confirmaciones específicas sigue
siendo una decisión del proyecto; documentarla antes de fijar configuración
dependiente del transporte.

## Procesamiento con Inbox

- Deduplicar por consumidor y `event_id`, incluyendo el tenant en la clave
  cuando el modelo de persistencia lo requiera.
- Confirmar en una sola transacción local la deduplicación o registro Inbox y
  los efectos persistentes del consumidor.
- Confirmar el mensaje al broker solo después del commit local. Si el mensaje
  se entrega de nuevo, reconocerlo sin repetir efectos ya confirmados.
- Distinguir fallos transitorios de errores permanentes de contrato o negocio.
  Reintentar solo los primeros; poner los segundos en cuarentena con suficiente
  información diagnóstica y sin exponer datos sensibles.
- Para efectos en servicios externos, usar claves idempotentes, otro Outbox o
  un flujo de compensación/reconciliación. Una transacción local no hace
  atómica una llamada externa.
- Autorizar y auditar los replays. No alterar silenciosamente un evento para
  hacerlo pasar por válido.

## Retención y operación

- Definir retención y limpieza según el horizonte de reintentos, recuperación,
  replay y obligaciones legales del dominio.
- No eliminar eventos pendientes, mensajes en procesamiento ni registros
  necesarios para deduplicar antes de que expire el horizonte de reentrega.
- Observar cantidad y antigüedad de eventos pendientes, latencia y errores de
  publicación, reintentos, cuarentena/DLQ, retraso del consumidor y duplicados.
- Correlacionar logs y trazas con los identificadores de evento y de
  correlación cuando estén disponibles. No usarlos como etiquetas de métricas
  de alta cardinalidad, conforme a
  [observabilidad](./observabilidad.md).
- Documentar quién puede inspeccionar, replayar o purgar registros y cómo
  verificar la integridad tras la recuperación.

## Pruebas y aceptación

Probar, según el flujo implementado:

- rollback de la escritura de negocio y del Outbox en conjunto;
- caída después del commit local y antes de publicar;
- caída después de la confirmación del broker y antes de marcar publicado;
- workers concurrentes, leases vencidos y recuperación de reclamos;
- entrega duplicada y caída del consumidor antes y después de su commit;
- mensajes inválidos, versiones desconocidas, errores transitorios y
  cuarentena;
- aislamiento de tenant y sucursal, límites de concurrencia y recuperación tras
  indisponibilidad del broker o PostgreSQL.

Usar PostgreSQL y el broker seleccionado en pruebas de integración cuando se
valide su semántica real; mocks aislados no prueban confirmaciones,
redelivery ni durabilidad del transporte. Seguir las reglas de
[testing](./testing.md) e informar los bloqueos y el alcance realmente probado.
