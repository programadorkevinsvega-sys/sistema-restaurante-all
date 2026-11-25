# Estándar de mensajería y contratos de eventos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Hacer explícitos el significado, ownership, compatibilidad, entrega y seguridad de mensajes entre componentes.

## Requisitos

- Cada evento tiene productor propietario, tipo estable y versión de esquema.
- Los nombres distinguen hechos ocurridos de comandos o intenciones.
- El contrato define campos obligatorios, semántica, unidades, timestamps, identidad, tenant cuando aplique y reglas de evolución.
- El consumidor valida autenticidad del productor, esquema y autorización.
- Se asume entrega al menos una vez salvo garantía formal demostrada por la tecnología y el flujo.
- No se promete exactly-once de extremo a extremo.
- Los mensajes no transportan secretos ni datos sensibles innecesarios.
- Los subjects, topics y queues tienen ACL, cuotas, retención y ownership.
- La política de orden se define por clave o agregado; no se asume orden global.
- Se documentan retención, replay, DLQ, redrive y compatibilidad.

## Core efímero y mensajería durable

La mensajería efímera sirve para señales cuyo perderse es aceptable o cuya fuente permite reconstrucción. La mensajería durable se utiliza para hechos o trabajos que requieren persistencia, confirmación, replay y recuperación. La selección debe responder a semántica, no solo a preferencia tecnológica.

## Verificación

Pruebas de compatibilidad de esquema, ACL, duplicación, replay, orden, expiración, backpressure y recuperación.
