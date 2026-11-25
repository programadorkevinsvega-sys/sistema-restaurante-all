# Estándar de trabajos en segundo plano y leases

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Ejecutar trabajos durables y concurrentes de forma recuperable, limitada y observable.

## Requisitos

- Cada job debe tener propietario, tipo, versión de payload, estado, intentos, timestamps y política de expiración.
- La reclamación debe ser atómica y segura con múltiples workers.
- Los leases deben tener expiración y renovación controlada; un worker pausado no debe conservar autoridad indefinidamente.
- La ejecución debe ser idempotente o disponer de mecanismo de deduplicación.
- Definir timeout, heartbeat cuando aplique, backoff, jitter, máximo de intentos y DLQ.
- Limitar concurrencia global y por clase de trabajo, tenant y proveedor externo.
- Aplicar backpressure cuando la cola supere límites de edad, tamaño o capacidad.
- Los trabajos largos deben usar checkpoints y ser reanudables.
- No mantener transacciones de base de datos abiertas durante llamadas externas largas.
- La cancelación debe ser cooperativa y definir qué ocurre con efectos ya confirmados.

## Coordinación

Locks, leases y advisory locks requieren TTL o renovación, fencing token cuando corresponda y tratamiento de split-brain. Un lock vencido no garantiza que el worker anterior haya dejado de ejecutar.

## Verificación

Pruebas de worker caído, lease vencido, doble reclamación, pausa larga, reintento, cancelación, sobrecarga y recuperación.
