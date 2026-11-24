# ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos

- Estado: **Accepted**
- Propuesto: 2026-11-24
- Aprobado: 2026-11-24
- Aprobación: decisión aprobada explícitamente por el propietario del producto.
- Complementa: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0007, ADR-0008 y ADR-0009.
- Ámbito: procesos de negocio que coordinan dos o más módulos, dentro o entre los cuatro procesos.

## Contexto

Restaurant OS distribuye responsabilidades entre módulos propietarios y cuatro procesos independientes. Cada módulo conserva su schema, rol, migraciones e historial SQLx. No existen tablas de negocio ni historiales compartidos entre módulos, ni se permiten FKs, joins o consultas directas entre schemas propietarios distintos.

Una operación puede requerir efectos coordinados en varios módulos. Por ejemplo, el ciclo de una venta puede involucrar SALES, PAYMENTS, INVENTORY y KITCHEN. Cada módulo debe conservar la autoridad sobre sus propios datos y confirmar sus cambios localmente. Una transacción PostgreSQL no debe tratar esos límites como una única unidad local.

ADR-0003 ya establece Outbox/Inbox, entrega at-least-once, idempotencia, efectos externos y compensación. ADR-0007 establece gRPC para solicitudes/respuestas entre procesos, NATS Core para señales efímeras y NATS JetStream para mensajes/eventos durables. Hace falta concretar cómo se coordinan procesos multi-paso, cómo se representa su progreso y cómo se recuperan fallos parciales.

## Decisión

### 1. Atomicidad local y consistencia entre módulos

1. Cada módulo confirma sus invariantes y cambios de negocio dentro de transacciones locales sobre su schema PostgreSQL.
2. No se utilizarán transacciones distribuidas XA/2PC ni transacciones PostgreSQL compartidas entre módulos para coordinar un caso de uso.
3. Ningún módulo escribirá directamente en tablas de otro módulo ni consultará schemas ajenos para completar una operación.
4. Una operación que abarque varios módulos se compondrá de pasos locales coordinados. Cada paso puede confirmar de manera independiente; por ello la consistencia entre módulos será eventual durante el proceso.
5. Los contratos distinguirán entre una operación aceptada/en curso y una operación completada. Una respuesta inicial no declarará éxito global mientras falten pasos obligatorios.

### 2. Sagas y propiedad de la coordinación

1. Los procesos de negocio durables que coordinan varios módulos, requieren estado durante el tiempo o deben recuperarse de fallos utilizarán el patrón Saga.
2. Cada Saga tendrá un módulo propietario responsable del proceso de negocio que la inicia y de su resultado global. Su estado durable vivirá bajo el schema y ownership de ese módulo. No se creará una base de datos, schema, tabla compartida ni módulo técnico central de Sagas.
3. El estado permitirá reanudar el proceso después de reinicios: identificador del proceso, referencia al agregado, etapa, resultados de pasos, intentos, plazos, correlación y estado de recuperación, según las necesidades del dominio.
4. Los participantes siguen siendo propietarios de sus efectos y estados locales. El coordinador no modifica directamente sus datos.
5. Se usará orquestación explícita cuando hagan falta orden, decisiones, plazos, compensaciones o seguimiento global. La coreografía por eventos se reserva para reacciones desacopladas que no requieran un coordinador ni una conclusión multi-paso.
6. No se creará un servicio orquestador universal ni un módulo de dominio adicional por defecto. La coordinación residirá dentro del módulo propietario del proceso. Si no existe un propietario claro, se requiere una decisión arquitectónica explícita antes de implementar.

### 3. Comandos, eventos y transporte

1. Un comando expresa una solicitud de realizar una acción; un evento expresa un hecho que ya ocurrió. No se publicarán comandos como si fueran eventos consumados.
2. Dentro del mismo backend/proceso, los comandos y consultas síncronos usarán contratos públicos y puertos locales conforme a ADR-0007 y ADR-0009.
3. Entre procesos, las solicitudes/respuestas que necesitan resultado inmediato usarán gRPC + Protobuf versionado.
4. Los pasos que deban sobrevivir desconexiones, reinicios, reintentos o ejecución diferida usarán mensajería durable mediante NATS JetStream. Las señales que no requieren recuperación durable podrán usar NATS Core.
5. La publicación de comandos durables, eventos y resultados derivados de un cambio local se coordinará con Outbox, persistiendo el mensaje en la misma transacción local que registra el cambio o la intención que debe publicarse.
6. Cada consumidor aplicará Inbox/deduplicación y confirmará el efecto local antes de confirmar el mensaje al transporte, conforme a ADR-0003.
7. No se usará una llamada gRPC larga como sustituto de una coordinación durable de varios pasos. Si el resultado no puede determinarse durante la solicitud, se devolverá un estado en curso y se consultará posteriormente al módulo propietario.

### 4. Idempotencia y resultados inciertos

1. Cada paso ejecutable tendrá una identidad estable de operación/comando y una clave de idempotencia con alcance definido.
2. La deduplicación cubrirá reentregas, reintentos del solicitante, concurrencia de workers y recuperación después de reinicios.
3. El módulo participante aplicará idempotencia junto con el efecto local en una transacción, siempre que el efecto sea persistible en su base de datos.
4. Para proveedores externos y efectos fuera de la transacción local se usarán claves idempotentes del proveedor cuando existan, registros de intento, consulta/reconciliación y compensación cuando corresponda.
5. Una respuesta perdida no implica que el paso haya fallado. Antes de repetir o compensar una operación de resultado incierto, el coordinador consultará o reconciliará el resultado con el participante o proveedor.

### 5. Fallos, reintentos, plazos y compensaciones

1. Los reintentos serán limitados y tendrán backoff, jitter y clasificación de errores configurables. Los errores permanentes no se reintentarán indefinidamente.
2. Un plazo vencido provocará la verificación del resultado del paso, no la suposición automática de que el efecto no ocurrió.
3. Una compensación es una nueva operación de negocio ejecutada por el módulo propietario del efecto; no es un rollback de una transacción ya confirmada.
4. Las compensaciones serán explícitas, idempotentes, auditables y vinculadas al paso original. No se asumirá que toda acción es reversible ni que compensar restaura exactamente el estado anterior.
5. Si un paso irreversible ya ocurrió, no puede compensarse o su resultado es incierto, la Saga quedará en un estado durable que requiera reconciliación o intervención. No se marcará falsamente como completada o compensada.
6. Los errores recuperables podrán reintentarse según política. Los mensajes agotados o no procesables se pondrán en cuarentena/DLQ según la configuración del stream, con procedimiento de inspección y reanudación segura.
7. La intervención manual invocará operaciones autorizadas del módulo propietario y dejará auditoría; no se resolverá editando tablas ajenas.

### 6. Estados y consulta del proceso

La máquina de estados exacta pertenece al dominio y al proceso propietario. El contrato y la persistencia distinguirán los conceptos que apliquen entre aceptado/pendiente, en ejecución, completado, fallido, compensando, compensado y requiere reconciliación/intervención.

Los nombres y transiciones concretos se definirán por caso de uso; no se impondrá una enumeración universal. El estado global no reemplaza el estado autoritativo de cada agregado participante.

Cuando una API acepte un flujo asíncrono, devolverá una referencia consultable al proceso y no confundirá aceptación con finalización. El módulo propietario expondrá el estado mediante su contrato; los BFF solo componen y presentan ese estado.

### 7. Orden, versiones y consistencia de lecturas

1. No se asumirá orden global entre mensajes, módulos o procesos.
2. Cuando el orden de eventos de un agregado sea relevante, el contrato incluirá una versión/secuencia del agregado o mecanismo equivalente definido por el módulo productor. El consumidor detectará duplicados y eventos fuera de orden o con huecos según la política del contrato.
3. Los consumidores mantendrán proyecciones locales solo bajo su propio ownership, alimentadas por eventos y reconstruibles/reconciliables.
4. Una proyección puede estar temporalmente atrasada. Las APIs y procesos que requieran una decisión autoritativa consultarán al módulo propietario o utilizarán una garantía explícita de versión/consistencia.
5. UUIDv7, timestamps de eventos, trace_id y correlation_id no sustituyen secuencias de agregado, causalidad ni control de concurrencia.

### 8. Observabilidad y auditoría

1. Cada proceso coordinado tendrá un identificador de proceso de negocio/Saga distinto de event_id, command_id, trace_id y correlation_id.
2. Propagar W3C Trace Context conforme a ADR-0004 y conservar correlación y causación entre comandos, eventos, Outbox, Inbox y workers.
3. Registrar transiciones, decisiones, reintentos, expiraciones, compensaciones y reconciliaciones con tenant, actor/sistema responsable y referencias necesarias, evitando secretos y datos sensibles en logs.
4. Las métricas distinguirán procesos activos, duración, fallos, compensaciones, mensajes pendientes, antigüedad y casos que requieren intervención. No se utilizarán identificadores de alta cardinalidad como etiquetas métricas.

### 9. Ejemplo sin reasignar ownership

En un flujo de pedido, SALES puede ser propietario del ciclo comercial y coordinar los pasos necesarios. PAYMENTS conserva la autoridad sobre autorizaciones, capturas y reembolsos; INVENTORY conserva la autoridad sobre existencias y reservas; KITCHEN conserva la autoridad sobre comandas y preparación. La Saga coordina contratos y resultados, pero no crea tablas compartidas ni mueve responsabilidades entre módulos.

El orden concreto, las reglas para reservar o descontar inventario, cuándo solicitar/capturar un pago, cuándo enviar una comanda y qué compensaciones son válidas se decidirán en el diseño del caso de uso. Este ADR no fija reglas comerciales específicas.

## Consecuencias

### Beneficios esperados

- Se preservan ownership exclusivo y transacciones locales.
- Los procesos de varios pasos pueden reanudarse después de fallos y reinicios.
- Los resultados parciales son explícitos y consultables.
- Las compensaciones son operaciones de negocio trazables, no intentos de rollback distribuido.
- La comunicación síncrona y durable se utiliza según la necesidad real.
- Los módulos evolucionan sin depender de tablas compartidas ni de una transacción global.

### Costos y riesgos

- Los procesos pueden permanecer temporalmente en estados intermedios.
- Cada Saga requiere estado, timeouts, reintentos, idempotencia, observabilidad y procedimientos operativos.
- Las compensaciones necesitan reglas del dominio y pueden no ser posibles para efectos irreversibles.
- Los consumidores deben tolerar duplicados y mensajes fuera de orden.
- Se requiere reconciliación para resultados inciertos de sistemas externos.

## Alternativas consideradas

- **Transacción distribuida XA/2PC entre módulos:** rechazada porque acopla disponibilidad y ciclo de vida de módulos, contradice el ownership aislado y no encaja con procesos independientes.
- **Una única base de datos o tablas compartidas para coordinar módulos:** rechazada porque rompe ownership, aislamiento de schemas y migraciones/historiales independientes.
- **Solo llamadas gRPC síncronas encadenadas:** rechazada como solución general para procesos durables; una desconexión o timeout deja resultados inciertos y no ofrece recuperación durable por sí sola.
- **Solo coreografía por eventos para todos los flujos:** rechazada como regla universal; los procesos con decisiones, plazos, compensaciones y estado global requieren coordinación explícita.
- **Un microservicio o módulo central universal de Sagas:** rechazado por defecto porque centralizaría estado de procesos que pertenecen a módulos propietarios. Podrá reconsiderarse mediante otro ADR basado en necesidades demostrables.

## Relación con ADR anteriores

- ADR-0001 conserva ownership de schema, rol, migraciones e historial SQLx por módulo.
- ADR-0003 conserva Outbox/Inbox, at-least-once, idempotencia, recuperación y coordinación de workers; ADR-0013 concreta su uso en procesos multi-módulo.
- ADR-0004 conserva W3C Trace Context y su propagación.
- ADR-0007 conserva los cuatro procesos, gRPC, NATS Core y JetStream, además de adaptadores locales entre módulos del mismo proceso.
- ADR-0008 conserva la distribución de módulos y sus responsabilidades.
- ADR-0009 conserva límites de crates y contratos públicos; las Sagas no autorizan dependencias a implementaciones ajenas.

## Estado de implementación

**Decisión aceptada; implementación pendiente.** No se han creado tablas, schemas, crates, contratos ejecutables, eventos, workers ni código de Saga. No se han modificado archivos SQL o migraciones ni se han ejecutado operaciones de base de datos.
