# Estándar de Sagas y consistencia distribuida

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Coordinar procesos de negocio durables que involucran varios propietarios de datos sin transacciones distribuidas globales.

## Principios

- Cada propietario confirma sus propios cambios en transacciones locales.
- No se debe asumir atomicidad ACID entre servicios o módulos independientes.
- Los estados intermedios y fallos parciales son parte explícita del diseño.
- Una compensación es una nueva operación de negocio, no un rollback mágico.

## Cuándo usar Saga

Usar Saga cuando el proceso cruza límites de propiedad, tiene varios pasos durables, puede fallar parcialmente, necesita reintentos, compensaciones o seguimiento de estado. No usar Saga para una operación local simple que cabe en una transacción del propietario.

## Orquestación y coreografía

- Orquestación cuando existe secuencia, decisiones, plazos, compensaciones o estado global del proceso.
- Coreografía cuando las reacciones son independientes y no necesitan un coordinador con resultado global.
- Evitar coreografías opacas, ciclos de eventos y cadenas sin propietario claro.

## Requisitos

- Cada Saga tiene propietario, identificador, versión, estado, pasos, deadlines y política de recuperación.
- El estado durable pertenece a un propietario definido; no se crea un coordinador central genérico sin necesidad.
- Cada paso y compensación es idempotente.
- Timeout no demuestra que el efecto remoto no ocurrió; se debe consultar o reconciliar antes de repetir o compensar.
- Se definen errores transitorios, permanentes, reintentos, backoff, jitter, expiración y cuarentena.
- Las operaciones irreversibles requieren intervención, reconciliación o estrategia específica.
- El usuario u operador puede conocer el estado del proceso sin confundirlo con el estado de cada agregado participante.
- Las métricas no deben usar identificadores únicos de proceso como labels de alta cardinalidad.

## Verificación

Pruebas de fallo en cada transición, duplicados, timeout ambiguo, compensación fallida, proceso detenido, replay y reconciliación.
