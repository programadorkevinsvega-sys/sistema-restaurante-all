# Estándar Transactional Outbox

**Versión:** 0.1.0 | **Estado:** Draft  
**Aplicabilidad:** cuando un cambio persistente debe producir un mensaje durable sin perder la relación entre ambos efectos.

## Objetivo

Evitar el dual-write inconsistente entre una base de datos y un broker.

## Requisitos

- El cambio de negocio y la intención de publicar deben confirmarse en la misma transacción local.
- La fila Outbox debe identificar evento, tipo, versión de esquema, productor, agregado, secuencia/versionado causal cuando aplique, fecha, correlación y contexto de trazabilidad.
- El dispatcher debe reclamar trabajo mediante mecanismo seguro ante concurrencia, leases o locking equivalente.
- La publicación debe ser reintentable y asumir entrega al menos una vez.
- El evento no debe marcarse como publicado antes de recibir la confirmación requerida del broker.
- Los leases deben expirar y permitir recuperación tras caída del worker.
- El despacho debe limitar concurrencia, tamaño de lote, antigüedad y recursos.
- Los mensajes inválidos o permanentemente fallidos deben ir a cuarentena/DLQ con diagnóstico y política de redrive.
- El payload debe evitar secretos y datos personales innecesarios.
- La retención y purga de Outbox deben preservar auditoría y recuperación requeridas.

## Orden y causalidad

No se debe asumir orden global. Si el consumidor necesita orden por agregado, incluir secuencia/versionado y definir detección de duplicados, huecos y eventos atrasados.

## Operación

Medir backlog, edad del evento más antiguo, tasa de error, reintentos, expiración de leases y latencia de publicación. Definir alertas y procedimiento de recuperación.

## Verificación

Pruebas de caída entre commit y publish, publish y ack, duplicación, timeout ambiguo, concurrencia de dispatchers, broker no disponible y recuperación de backlog.
