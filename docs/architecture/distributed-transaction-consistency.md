# Estrategia técnica de consistencia distribuida y Sagas

**Estado:** especificación técnica aprobada y vigente, vinculada a [ADR-0013 Accepted](../adr/0013-distributed-transactions-and-saga-consistency.md).  
**Ámbito:** flujos de negocio que coordinan varios módulos dentro o entre los cuatro procesos.  
**Decisiones relacionadas:** ADR-0001, ADR-0003, ADR-0004, ADR-0007, ADR-0008 y ADR-0009.

## 1. Propósito y límites

Este documento describe cómo coordinar procesos de negocio de varios pasos sin romper el ownership de los módulos. No crea un módulo central de workflow ni reasigna responsabilidades.

Cada módulo conserva su schema, rol, transacciones, migraciones e historial SQLx independientes. No se permiten escrituras, joins, FKs ni consultas directas entre schemas propietarios distintos. Los BFF no coordinan reglas de negocio ni almacenan el estado autoritativo de las Sagas.

ADR-0013 está Accepted y esta especificación desarrolla sus decisiones. Su aprobación documental no significa que las Sagas, tablas, workers o flujos estén implementados.

## 2. Modelo de consistencia

### 2.1 Transacción local

Una transacción PostgreSQL protege invariantes y cambios que pertenecen al mismo módulo. El módulo escribe sus cambios de negocio y los mensajes Outbox correspondientes en una única transacción local. El dispatcher publica después del commit.

No se mantiene una transacción abierta mientras se llama a otro proceso, se espera una respuesta de NATS o se invoca un proveedor externo.

### 2.2 Consistencia entre módulos

Un proceso multi-módulo consiste en pasos locales. Entre pasos puede existir un estado parcial y observable. El objetivo no es simular atomicidad global, sino alcanzar un resultado definido mediante confirmaciones, reintentos, compensaciones o reconciliación.

La API debe diferenciar solicitud recibida, proceso aceptado y pendiente, proceso en ejecución, resultado terminal satisfactorio y resultado fallido o que requiere intervención. No devolver éxito final solo porque el primer módulo aceptó iniciar el flujo.

## 3. Selección del patrón

### 3.1 Llamada directa

Usar contrato/puerto local para un comando o consulta síncrona dentro del mismo proceso cuando el resultado sea necesario en la misma operación y no exista necesidad de recuperación durable independiente.

Usar gRPC + Protobuf entre procesos para una solicitud/respuesta que deba resolverse dentro del ciclo síncrono. Aplicar timeouts, límites de concurrencia y propagación de contexto. Un timeout deja el resultado potencialmente incierto; no prueba que el servidor no haya confirmado el efecto.

### 3.2 Saga orquestada

Usar Saga orquestada cuando el proceso coordine varios pasos con orden o decisiones, necesite esperar resultados de otros módulos, requiera timeout/reintentos/compensaciones, deba sobrevivir reinicios o necesite un resultado global explícito.

El coordinador vive en el módulo propietario del proceso de negocio y persiste su estado en su propio schema. Emite comandos mediante contratos; cada participante valida y ejecuta su propio efecto.

### 3.3 Coreografía

Usar coreografía cuando un evento de hecho ocurrido deba provocar una reacción independiente y desacoplada, sin coordinador que mantenga una conclusión multi-paso. Evitar cadenas de eventos circulares o implícitas que oculten quién es responsable del resultado.

No usar coreografía para ocultar una Saga que requiere decisiones centrales, compensaciones o estado global consultable.

## 4. Flujo de referencia

1. El módulo propietario recibe la solicitud y valida sus invariantes.
2. En una transacción local crea/actualiza el agregado y el estado durable del proceso, registra la intención/comando en Outbox y confirma.
3. El dispatcher publica el comando durable en JetStream.
4. El participante consume el comando, registra Inbox/deduplicación y aplica su efecto local más el evento de resultado en Outbox dentro de una transacción local.
5. El dispatcher del participante publica el resultado durable.
6. El coordinador consume el resultado, deduplica, actualiza su estado y decide el siguiente paso en su propia transacción local.
7. El proceso continúa hasta completar, fallar, compensar o requerir intervención.

Cada límite de commit, publicación, ACK, timeout y reinicio debe tolerar repetición. La confirmación de publicación del broker no significa que el participante haya completado el efecto de negocio.

## 5. Comandos y eventos

Un comando contiene identidad de operación, acción solicitada, objetivo, contexto de tenant/actor cuando corresponda, versión de contrato y datos mínimos. Un evento describe un hecho confirmado, no una intención.

Los nombres, payloads y versiones pertenecen al módulo propietario del contrato. El envelope de transporte no duplica el modelo de dominio. Los contratos evolucionan mediante versiones compatibles.

Para mensajes durables:

- escribir Outbox junto al cambio local que origina el mensaje;
- publicar fuera de la transacción de negocio;
- confirmar publicación durable antes de marcar la fila como publicada;
- procesar con Inbox/deduplicación;
- confirmar el mensaje de transporte después del commit local;
- permitir redelivery y reintentos.

NATS Core se reserva para señales efímeras sin requisito de recuperación durable. JetStream se usa para comandos y eventos que deban persistir, recuperarse o confirmarse de forma durable.

## 6. Idempotencia y resultados inciertos

La clave idempotente identifica una intención de negocio concreta y tiene alcance documentado, por ejemplo tenant, módulo propietario y operación. No reutilizar la misma clave para intenciones distintas.

Cada participante conserva evidencia suficiente para responder a una repetición sin duplicar el efecto. La escritura de Inbox/deduplicación y el efecto de negocio comparten transacción local cuando ambos residen en PostgreSQL.

Si ocurre un timeout después de enviar un comando:

1. no asumir que el participante no ejecutó la operación;
2. consultar estado por command_id/operation_id o esperar resultado durable;
3. repetir solo con la misma identidad idempotente si la operación admite repetición;
4. compensar únicamente después de determinar el resultado del paso.

Para sistemas externos, utilizar claves idempotentes del proveedor cuando estén disponibles. Si no existen, definir consulta/reconciliación y tratamiento explícito de incertidumbre.

## 7. Compensaciones

Una compensación es un nuevo comando de negocio que revierte o neutraliza un efecto según reglas del módulo propietario. No borra el historial ni revierte mágicamente una transacción confirmada.

Ejemplos conceptuales:

- liberar una reserva que todavía puede liberarse;
- solicitar un reembolso por un cobro ya capturado;
- cancelar una preparación antes de que alcance un estado irreversible.

Los ejemplos no definen políticas comerciales de SALES, PAYMENTS, INVENTORY o KITCHEN. Cada módulo decide qué efectos son compensables, qué estados permiten compensar y qué restricciones aplican.

La compensación referencia el paso original, es idempotente y produce su propio resultado auditable. Si el efecto no puede compensarse, el proceso requiere acción alternativa, reconciliación o intervención. Nunca declarar compensación exitosa sin confirmación del módulo propietario.

## 8. Reintentos, cuarentena y recuperación

- Clasificar errores transitorios, permanentes y de resultado desconocido.
- Aplicar backoff exponencial con jitter y límites configurables; evitar reintentos infinitos o tormentas.
- Respetar deadlines de negocio y timeouts técnicos por separado.
- No interpretar expiración de lease o pérdida de conexión como prueba de que el efecto no ocurrió.
- Enviar mensajes agotados/no procesables a cuarentena o DLQ conforme a la política del stream, preservando metadatos para diagnóstico y reanudación.
- Reanudar solo después de verificar idempotencia y estado del paso.
- La recuperación manual invoca comandos autorizados del módulo propietario y genera auditoría.

Los valores de intentos, delays, retención y política DLQ se definirán por flujo y entorno; no se fijan como constantes globales.

## 9. Orden y concurrencia

No hay orden global garantizado entre módulos. Cuando el orden por agregado sea relevante:

- incluir una versión o secuencia monotónica del agregado bajo autoridad del módulo productor;
- validar la secuencia recibida;
- detectar duplicados, eventos atrasados y huecos;
- posponer o reconciliar mensajes fuera de orden según el contrato;
- usar control optimista/pesimista local según las invariantes del módulo.

No derivar orden de negocio de UUIDv7, timestamp de creación, trace_id, correlation_id ni del orden de llegada del broker.

## 10. Estado consultable

El módulo coordinador conserva el estado durable y publica una referencia de proceso mediante su contrato. Los estados y transiciones exactos pertenecen al dominio. Se recomienda distinguir pendiente, en ejecución, completado, fallido, compensando, compensado y requiere intervención, según aplique.

El BFF puede agregar y presentar el estado, pero no lo inventa ni lo persiste como autoridad. Las proyecciones para consultas rápidas pertenecen al módulo consumidor y deben gestionar su eventual consistencia cuando importe.

## 11. Observabilidad

Mantener separados saga_id (o ID del proceso), operation_id/command_id, event_id, correlation_id, causation_id, trace_id y span_id.

Propagar W3C Trace Context en HTTP, gRPC, envelopes, Outbox, Inbox y workers. Registrar transiciones y decisiones relevantes con referencias al tenant y actor autorizado, sin incluir secretos o datos sensibles. Métricas recomendadas: procesos activos, antigüedad, duración, pasos fallidos, reintentos, compensaciones y procesos que requieren intervención. No etiquetar métricas con IDs únicos de proceso.

## 12. Ejemplo de ownership

En un proceso de pedido:

- SALES puede coordinar el ciclo comercial si es propietario del proceso.
- PAYMENTS conserva cobros, autorizaciones, capturas y reembolsos.
- INVENTORY conserva existencias, reservas y movimientos.
- KITCHEN conserva comandas, estaciones y preparación.

El coordinador registra el avance y solicita acciones por contratos. No accede a las tablas de participantes ni decide sus invariantes internas. El orden exacto de pasos y compensaciones se especifica en el caso de uso.

## 13. Pruebas requeridas antes de implementar

Cada flujo debe probar:

- duplicación de comandos y eventos;
- redelivery después del commit y antes del ACK;
- caída antes/después del commit local y antes/después de publicar Outbox;
- timeout con resultado exitoso pero respuesta perdida;
- reintentos concurrentes del mismo paso;
- eventos atrasados, fuera de orden y con huecos de versión;
- expiración de leases y recuperación por otra réplica;
- compensación repetida, fallida e imposible;
- proveedor externo con idempotencia y sin ella;
- intervención manual y reanudación;
- aislamiento de tenant y autorización en cada comando;
- compatibilidad de contratos durante despliegues graduales.

## 14. Restricciones de implementación

La aceptación de ADR-0013 no autorizará por sí sola cambios SQL, migraciones ni implementación de flujos específicos. Cada caso de uso requiere diseño funcional y técnico, contratos del módulo propietario, modelo de estados, compensaciones, política de reintentos, pruebas y autorización conforme a la gobernanza del repositorio.

No se crea un schema compartido, tabla global de Sagas, crate de negocio transversal ni servicio central de orquestación por este documento.

## 15. Referencias

- [ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos](../adr/0013-distributed-transactions-and-saga-consistency.md)
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](../adr/0003-stateless-outbox-inbox-and-jobs.md)
- [ADR-0007: Topología de cuatro backends independientes y comunicación](../adr/0007-four-independent-backends-and-communication.md)
- [ADR-0008: Distribución de módulos entre los cuatro procesos](../adr/0008-module-ownership-across-four-processes.md)
- [ADR-0009: Límites de crates y dirección de dependencias](../adr/0009-crate-boundaries-and-dependencies.md)

## 16. Estado

**Especificación técnica aprobada conforme a ADR-0013 Accepted; implementación pendiente.** No se han creado tablas, crates, contratos ejecutables, workers ni código. No se han modificado archivos SQL o migraciones ni se han ejecutado operaciones de base de datos.
