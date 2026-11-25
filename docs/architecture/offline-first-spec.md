# Especificación offline-first del POS — subfase 0.10

**Estado:** diseño aprobado — subfase 0.10
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.10
**Autoridad:** ADR-0003, ADR-0011, ADR-0012, ADR-0013, ADR-0019, ADR-0021
**Documentos relacionados:**

- [Máquina de estados de sincronización](./offline-sync-state-machine.md)
- [Política de conflictos offline](./offline-conflict-policy.md)
- [Matriz de operaciones permitidas offline](./offline-operations-matrix.md)
- [Diseño Outbox/Inbox/Saga](./outbox-inbox-saga-design.md)
- [Estrategia UUIDv7](./uuid-strategy.md)

---

## 1. Propósito y alcance

El POS debe poder operar con conectividad degradada o ausente durante períodos acotados,
sin perder ventas, cobros ni integridad de datos. La operación offline no es el modo normal;
es un modo de degradación controlada con límites explícitos.

Este documento es un diseño; no implementa código, base de datos local ni APIs.

---

## 2. Principios del modo offline

1. **Offline como modo degradado, no como modo equivalente.** Algunas operaciones no están disponibles sin conexión.
2. **El servidor es la autoridad final.** Los datos locales son un subconjunto descargado; el servidor decide en caso de conflicto.
3. **Idempotencia en toda operación local.** Cada operación tiene un ID único generado en el dispositivo antes de ejecutarse.
4. **Sin duplicados.** Ningún reintento de sincronización puede duplicar una venta, cobro o movimiento de inventario.
5. **Protección del dato local.** Los datos en el dispositivo están cifrados y se limpian al cambiar de tenant/usuario.
6. **Límites explícitos.** El dispositivo no opera indefinidamente sin conexión; tiene umbrales tras los cuales bloquea operaciones críticas.

---

## 3. Identificadores generados en dispositivo

Los IDs de operaciones creadas offline siguen UUIDv7 generados en el dispositivo:

| Campo | Regla |
|---|---|
| Generación | UUIDv7 en el dispositivo antes de crear la operación local |
| Unicidad | El ID es globalmente único; el servidor no asigna un nuevo ID al sincronizar |
| Autoridad | El módulo servidor valida el ID al recibir la sincronización; lo rechaza si ya existe con otro tenant |
| Idempotencia | El servidor usa el `operation_id` del dispositivo como clave idempotente |
| Prohibido | Reutilizar IDs entre sincronizaciones; usar IDs secuenciales locales que colisionen |

---

## 4. Conjunto mínimo de datos locales

El dispositivo descarga y mantiene actualizado este conjunto antes de entrar en modo offline:

| Dato | Propietario | Frecuencia de actualización | Crítico para offline |
|---|---|---|---|
| Catálogo activo (productos, variantes, precios) | CATALOG | Al abrir turno / evento de invalidación | Sí |
| Excepciones de sucursal (precios locales, disponibilidad) | CATALOG / ORGANIZATION | Al abrir turno | Sí |
| Métodos de pago permitidos en la sucursal | ORGANIZATION / PAYMENTS | Al abrir turno | Sí |
| Configuración fiscal de la sucursal | ORGANIZATION / BILLING | Al abrir turno | Sí |
| Rangos de numeración asignados (folios offline) | BILLING | Al abrir turno; reponer cuando queden < N | Sí |
| Inventario conocido (cantidad aproximada) | INVENTORY | Periódica; no garantiza exactitud offline | No (solo referencial) |
| Configuración del turno activo | CASH | Al abrir turno | Sí |
| Sesión y permisos del cajero activo | IDENTITY | Al autenticarse | Sí |
| Configuración de impresoras y periféricos | ORGANIZATION | Al abrir turno | Sí |

**Reglas de descarga:**

- El dispositivo solo descarga datos de **su sucursal**; sin datos de otras sucursales del tenant.
- Los datos descargados tienen timestamp de versión para detectar cambios al reconectar.
- El catálogo offline nunca incluye datos de otros tenants.
- Si el dispositivo no puede descargar el conjunto mínimo al iniciar el turno, **no entra en modo offline**.

---

## 5. Persistencia local durable

| Componente | Requisito |
|---|---|
| Motor de BD local | Embedded (SQLite u equivalente); ACID por transacción local |
| Cifrado | Base de datos cifrada en reposo con clave derivada de credencial del operador |
| Ubicación | No en rutas ejecutables; sin respaldo automático a servicios de nube del SO |
| Integridad | Verificar integridad al arrancar; no operar si la BD local está corrupta |
| Capacidad | Dimensionar para N días de operación offline según política del negocio |

La clave de cifrado local no se almacena en texto plano ni en el código fuente.

---

## 6. Cola de operaciones offline

Toda operación creada mientras el dispositivo está sin conexión se escribe en la **cola de operaciones** antes de ejecutarse localmente.

| Campo | Descripción |
|---|---|
| `operation_id` | UUIDv7 generado en el dispositivo |
| `operation_type` | Tipo de operación (`create_order`, `add_payment`, `close_shift`, etc.) |
| `payload` | Datos mínimos necesarios para sincronizar |
| `created_at` | Timestamp local del dispositivo |
| `status` | `pending` / `syncing` / `synced` / `failed` / `conflict` |
| `sync_attempts` | Número de intentos de sincronización |
| `server_response` | Respuesta del servidor al sincronizar (éxito, error, conflicto) |
| `idempotency_key` | Igual a `operation_id`; enviado al servidor para idempotencia |

**Reglas de la cola:**

- Una operación solo se ejecuta localmente si primero queda persistida en la cola.
- El orden de la cola es el orden de ejecución en el servidor (preservar secuencia).
- Operaciones dependientes se envían en orden; no enviar la siguiente hasta que la anterior esté `synced`.
- La cola se limpia solo después de confirmación `synced` del servidor.

---

## 7. Reintentos y sincronización

| Escenario | Comportamiento |
|---|---|
| Fallo transitorio de red | Reintento con backoff exponencial + jitter |
| Error 4xx del servidor (rechazo permanente) | Estado `failed`; requiere revisión humana |
| Error de conflicto (409) | Estado `conflict`; aplicar política de conflictos |
| Conexión restaurada | Sincronizar cola en orden; item a item |
| Reinicio del dispositivo | Retomar cola pendiente desde el inicio |
| Operación ya procesada (idempotencia) | Servidor responde éxito; cliente marca `synced` |

Límite de reintentos: configurable por entorno (ej. 5 intentos antes de marcar `failed`).

---

## 8. Límites del modo offline

| Límite | Regla |
|---|---|
| Duración máxima offline | Configurable por sucursal; ej. 8 horas. Pasado el límite, bloquear operaciones críticas nuevas. |
| Folios fiscales offline | Solo se emiten si hay rangos asignados disponibles. Sin rango = sin documento fiscal. |
| Pagos con tarjeta | No permitidos offline (requieren autorización del PSP en línea). Solo efectivo y métodos pre-autorizados. |
| Pagos de alto importe | Umbral configurable; por encima del umbral, requiere confirmación online. |
| Devoluciones y anulaciones | No permitidas offline; requieren conexión para verificar el estado original en el servidor. |
| Cambios de precios o catálogo | No se aplican offline; el cajero opera con los datos descargados al abrir el turno. |
| Apertura de turno nuevo | Requiere conexión para validar con el servidor. |

---

## 9. Protección de datos locales

| Control | Regla |
|---|---|
| Cifrado en reposo | BD local cifrada; clave derivada de credencial del operador activo |
| Limpieza al cerrar sesión | Al cambiar de operador o tenant, limpiar datos sensibles de la sesión anterior |
| Limpieza al cambiar tenant | Eliminar completamente los datos locales del tenant anterior antes de descargar datos del nuevo |
| Sin datos en logs | Los logs de sincronización no incluyen payloads de ventas, datos de pago ni datos personales |
| Sesión expirada | Si el token de sesión expira offline, el operador debe reautenticarse al reconectar antes de continuar |
| Revocación remota | Al reconectar, el dispositivo verifica si la sesión fue revocada en el servidor; si fue revocada, cierra sesión local |
| Sin secretos en código | La clave de cifrado local no está hardcodeada; se deriva de credenciales del usuario |

---

## 10. Telemetría de sincronización

El dispositivo emite métricas de sincronización sin incluir datos sensibles:

| Métrica | Descripción |
|---|---|
| `pos_offline_duration_seconds` | Tiempo que el dispositivo lleva sin conexión |
| `pos_queue_pending_count` | Operaciones en cola pendientes de sincronizar |
| `pos_sync_success_total` | Operaciones sincronizadas exitosamente |
| `pos_sync_failed_total` | Operaciones con estado `failed` o `conflict` |
| `pos_sync_latency_seconds` | Latencia de sincronización al reconectar |

Los logs de sincronización incluyen `operation_id`, `operation_type`, resultado y timestamps. Nunca incluyen el payload de la operación, datos de pago ni datos personales del cliente.

---

## 11. Estado de implementación

Especificación aprobada. No existe código del POS, base de datos local, cola de operaciones
ni pipeline de sincronización implementados. La implementación comienza en la subfase 2.5
(POS web/PWA) y 2.6 (offline-first).
