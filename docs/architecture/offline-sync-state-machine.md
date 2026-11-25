# Máquina de estados de sincronización offline — subfase 0.10

**Estado:** diseño aprobado — subfase 0.10
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.10
**Autoridad:** ADR-0003, ADR-0013
**Documentos relacionados:**

- [Especificación offline-first](./offline-first-spec.md)
- [Política de conflictos](./offline-conflict-policy.md)
- [Matriz de operaciones permitidas offline](./offline-operations-matrix.md)

---

## 1. Estados del dispositivo POS

```text
                    ┌─────────────────┐
                    │   INITIALIZING  │ ← arranque del dispositivo
                    └────────┬────────┘
                             │ descarga datos mínimos exitosa
                             ▼
              ┌──────────────────────────┐
              │         ONLINE           │ ←──────────────────┐
              │  (conectado y operativo) │                    │
              └──────────┬───────────────┘                    │
                         │ pérdida de conexión                │
                         ▼                                    │
              ┌──────────────────────────┐                    │
              │         OFFLINE          │                    │
              │  (operación degradada)   │                    │
              └──────────┬───────────────┘                    │
                         │ conexión restaurada                │
                         ▼                                    │
              ┌──────────────────────────┐                    │
              │        SYNCING           │ ───────────────────┘
              │  (sincronizando cola)    │  sync completada (cola vacía)
              └──────────┬───────────────┘
                         │ sync fallida o conflictos sin resolver
                         ▼
              ┌──────────────────────────┐
              │      SYNC_ERROR          │
              │  (requiere intervención) │
              └──────────────────────────┘
```

---

## 2. Estados del dispositivo — descripción

| Estado | Descripción | Operaciones permitidas |
|---|---|---|
| `INITIALIZING` | El dispositivo está descargando el conjunto mínimo de datos | Ninguna |
| `ONLINE` | Conectado; cola vacía o sincronizando en segundo plano | Todas las autorizadas |
| `OFFLINE` | Sin conexión; operando con datos locales | Solo las de la matriz offline |
| `SYNCING` | Conexión restaurada; sincronizando cola | Todas las de `ONLINE`; nueva cola puede acumularse |
| `SYNC_ERROR` | Hay operaciones en `failed` o `conflict` sin resolver | Solo operaciones que no dependan de la cola bloqueada |

---

## 3. Transiciones del dispositivo

| Desde | Evento | Hacia | Acción |
|---|---|---|---|
| `INITIALIZING` | Descarga exitosa del conjunto mínimo | `ONLINE` | Habilitar operaciones |
| `INITIALIZING` | Fallo de descarga | `INITIALIZING` (reintento) o error bloqueante | Notificar al operador |
| `ONLINE` | Pérdida de conexión detectada | `OFFLINE` | Activar modo degradado; notificar al operador |
| `OFFLINE` | Conexión restaurada | `SYNCING` | Iniciar sincronización de cola en orden |
| `OFFLINE` | Límite de tiempo offline excedido | `OFFLINE` (bloqueado parcialmente) | Bloquear operaciones críticas nuevas |
| `SYNCING` | Cola vacía y sin conflictos | `ONLINE` | Volver a operación normal |
| `SYNCING` | Error irrecuperable o conflicto sin resolver | `SYNC_ERROR` | Notificar al operador; requerir intervención |
| `SYNC_ERROR` | Operador resuelve conflictos / ops fallidas | `SYNCING` | Reintentar sincronización |
| `SYNC_ERROR` | Conexión perdida durante resolución | `OFFLINE` | Mantener cola; continuar cuando reconecte |

---

## 4. Estados de una operación en la cola

```text
  PENDING → SYNCING → SYNCED
                ↓
             FAILED
                ↓
           CONFLICT
```

| Estado | Descripción |
|---|---|
| `pending` | Creada localmente; esperando sincronización |
| `syncing` | Enviada al servidor; esperando respuesta |
| `synced` | Confirmada por el servidor exitosamente |
| `failed` | Rechazada permanentemente por el servidor (4xx no de conflicto) |
| `conflict` | Detectado conflicto en el servidor (409); requiere resolución |

---

## 5. Flujo de sincronización de la cola

```text
1. Tomar la primera operación en estado `pending` de la cola (en orden)
2. Marcarla como `syncing`
3. Enviar al servidor con `idempotency_key = operation_id`
4. Esperar respuesta:
   ├── 2xx (éxito) → marcar `synced` → continuar con la siguiente
   ├── 4xx no-409 (error permanente) → marcar `failed` → detener cola dependiente
   ├── 409 (conflicto) → marcar `conflict` → aplicar política de conflictos
   └── 5xx / timeout → marcar `pending` nuevamente → backoff + reintento
5. Si la operación bloqueante es `failed` o `conflict` sin resolver:
   ├── Bloquear operaciones dependientes
   └── Notificar al operador para intervención
6. Una vez resuelta, retomar desde la siguiente operación
```

**Garantía de idempotencia:** si el servidor ya procesó la operación (respuesta 2xx con mismo `operation_id`), el cliente la marca `synced` sin crear un duplicado.

---

## 6. Recuperación tras reinicio del dispositivo

Al reiniciar:

1. Cargar cola de la BD local.
2. Reanudar desde la primera operación `pending` o `syncing`.
3. Las operaciones `syncing` al momento del reinicio se reenvían (el servidor usa idempotencia).
4. Si el token de sesión expiró durante el reinicio: reautenticar antes de sincronizar.
5. Si los datos locales están corruptos: no entrar en modo offline hasta restaurar desde el servidor.

---

## 7. Detección de conexión

| Señal | Acción |
|---|---|
| Fallo de request HTTP al servidor | Iniciar contador de intentos; tras N fallos consecutivos → `OFFLINE` |
| Respuesta exitosa del servidor | Si estaba `OFFLINE` → transicionar a `SYNCING` |
| Ping periódico (heartbeat) al servidor | Detectar reconexión en segundo plano |
| Tiempo máximo sin heartbeat exitoso | Confirmar estado `OFFLINE` |

El heartbeat no lleva datos de negocio; solo verifica conectividad con el backend del POS.

---

## 8. Estado de implementación

Diseño aprobado. No existe código de máquina de estados, base de datos local
ni cliente de sincronización implementado. La implementación comienza en la subfase 2.5.
