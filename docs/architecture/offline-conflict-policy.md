# Política de conflictos offline — subfase 0.10

**Estado:** diseño aprobado — subfase 0.10
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.10
**Autoridad:** ADR-0013
**Documentos relacionados:**

- [Especificación offline-first](./offline-first-spec.md)
- [Máquina de estados de sincronización](./offline-sync-state-machine.md)
- [Matriz de operaciones permitidas offline](./offline-operations-matrix.md)

---

## 1. Qué es un conflicto

Un conflicto ocurre cuando una operación creada offline no puede aplicarse en el servidor
porque el estado del recurso en el servidor ya no es compatible con el estado que tenía
el dispositivo cuando creó la operación.

Ejemplos:

- El cajero vendió el último producto en stock offline, pero otro cajero (online) lo vendió primero.
- Se aplicó un precio desactualizado porque el precio cambió mientras el dispositivo estaba offline.
- Se usó un folio fiscal que ya fue asignado a otra operación por el servidor.

---

## 2. Tipos de conflicto

| Tipo | Descripción | Frecuencia esperada |
|---|---|---|
| `inventory_conflict` | La cantidad disponible en el servidor es menor a la operada offline | Baja (si los límites offline están bien configurados) |
| `price_conflict` | El precio aplicado offline difiere del vigente en el servidor al sincronizar | Baja (catálogo se descarga al abrir turno) |
| `folio_conflict` | El folio fiscal fue asignado a otra operación antes de sincronizar | Muy baja (folios asignados por rango exclusivo) |
| `state_conflict` | El recurso está en un estado que no admite la operación (ej. pedido ya cancelado) | Muy baja |
| `duplicate_conflict` | La operación ya fue procesada (caso cubierto por idempotencia; no es conflicto real) | No aplica si la idempotencia funciona |

---

## 3. Reglas de resolución por tipo

### 3.1 Conflicto de inventario (`inventory_conflict`)

| Situación | Resolución |
|---|---|
| La diferencia es de 1 unidad y el margen de error es aceptable | **Aceptar automáticamente** si la sucursal tiene política de tolerancia configurada |
| La diferencia supera el margen o no hay política de tolerancia | **Escalar a revisión humana** del gerente de sucursal |
| El producto ya no existe en el catálogo del servidor | **Rechazar** la línea; el pedido se marca parcial; notificar al cajero |

**El servidor es la autoridad de inventario.** No se acepta automáticamente una venta que el servidor rechaza por stock insuficiente sin autorización explícita del gerente.

### 3.2 Conflicto de precio (`price_conflict`)

| Situación | Resolución |
|---|---|
| Diferencia menor al umbral configurado (ej. ± 1%) | **Aceptar con precio del servidor** y registrar discrepancia en AUDIT |
| Diferencia mayor al umbral | **Escalar a revisión humana**; el cajero ve la diferencia y aprueba o cancela |
| El producto ya no tiene precio activo en el servidor | **Rechazar**; requiere intervención del gerente |

El precio final aplicado siempre queda registrado con su fuente (offline o corregido por servidor).

### 3.3 Conflicto de folio fiscal (`folio_conflict`)

Regla: **este conflicto no debe ocurrir si el diseño es correcto.**

Los folios offline son rangos exclusivos asignados al dispositivo por el servidor al abrir el turno. Un folio asignado a un dispositivo no puede ser asignado a otro dispositivo simultáneamente.

Si ocurre:

1. Es un bug en la gestión de rangos; escalar a desarrollo.
2. No emitir el documento fiscal; el pedido se marca como pendiente de numeración.
3. Requerir conexión para asignar un nuevo folio.

### 3.4 Conflicto de estado (`state_conflict`)

| Situación | Resolución |
|---|---|
| El recurso fue modificado online mientras estaba offline | **Revisar cada campo**: si no hay colisión real, aceptar; si hay colisión, escalar |
| El recurso fue eliminado o cancelado en el servidor | **Rechazar** la operación offline; notificar al operador |

---

## 4. Reglas generales de resolución

| Regla | Descripción |
|---|---|
| El servidor siempre gana en última instancia | No existe resolución que fuerce al servidor a aceptar datos inconsistentes |
| No hay resolución automática para conflictos financieros | Pagos, cobros, devoluciones y movimientos de caja siempre requieren revisión humana si hay conflicto |
| La operación conflictiva no se elimina | Se mantiene en la cola con estado `conflict` y todos sus datos para auditoría |
| La resolución es trazable | Toda resolución (automática o humana) queda registrada en AUDIT con actor, timestamp y decisión |
| El operador puede descartar una operación conflictiva | Con autorización del gerente; la operación queda marcada `discarded` en la cola local y en AUDIT |
| Descartar no borra el dato local | La operación permanece en la cola con estado `discarded`; solo se limpia en el siguiente ciclo de retención |

---

## 5. Interfaz de resolución para el operador

Cuando hay conflictos en la cola, el POS muestra al gerente:

1. Lista de operaciones en estado `conflict` con descripción del conflicto.
2. Para cada operación: qué datos tenía el dispositivo vs. qué dice el servidor.
3. Opciones: **Aceptar con datos del servidor** / **Escalar a soporte** / **Descartar operación**.
4. Para conflictos financieros: solo **Escalar a soporte** o **Descartar con justificación**.

El gerente no puede forzar datos inconsistentes al servidor; solo puede aceptar la corrección del servidor o descartar la operación.

---

## 6. Estado de implementación

Política aprobada. No existe código de resolución de conflictos ni interfaz de revisión
implementada. La implementación comienza en la subfase 2.6 (offline-first del POS).
