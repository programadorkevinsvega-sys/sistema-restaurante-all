# Matriz de operaciones permitidas offline — subfase 0.10

**Estado:** diseño aprobado — subfase 0.10
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.10
**Autoridad:** ADR-0021, ADR-0019
**Documentos relacionados:**

- [Especificación offline-first](./offline-first-spec.md)
- [Máquina de estados de sincronización](./offline-sync-state-machine.md)
- [Política de conflictos](./offline-conflict-policy.md)

---

## 1. Convenciones

| Valor | Significado |
|---|---|
| ✅ Permitida | Operación completamente disponible offline |
| ⚠️ Limitada | Disponible con restricciones explícitas |
| ❌ Bloqueada | No disponible sin conexión; requiere conectividad |

La columna **Razón si bloqueada** explica por qué la operación no puede operar sin conexión.

---

## 2. Ventas y pedidos (SALES)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Crear pedido nuevo | ✅ Permitida | Usando catálogo local descargado; `order_id` generado en dispositivo |
| Agregar línea a pedido | ✅ Permitida | Solo productos del catálogo local |
| Modificar cantidad en pedido | ✅ Permitida | — |
| Aplicar descuento autorizado | ⚠️ Limitada | Solo descuentos preconfigurados descargados al turno; no descuentos manuales de alto valor |
| Cancelar línea de pedido | ✅ Permitida | Antes de cobrar |
| Cancelar pedido completo | ✅ Permitida | Antes de cobrar |
| Ver historial de pedidos propios del turno | ✅ Permitida | Solo pedidos del dispositivo en el turno actual |
| Ver historial de pedidos de otros cajeros | ❌ Bloqueada | Requiere consultar el servidor; no se sincroniza localmente |
| Devolución / anulación de pedido previo | ❌ Bloqueada | Requiere verificar estado en servidor; riesgo de duplicar reembolso |

---

## 3. Cobros y pagos (PAYMENTS / CASH)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Cobro en efectivo | ✅ Permitida | Registrado localmente; sincronizado al reconectar |
| Cobro con otro método pre-autorizado (vale, crédito interno) | ⚠️ Limitada | Solo métodos configurados explícitamente como disponibles offline |
| Cobro con tarjeta débito/crédito | ❌ Bloqueada | Requiere autorización del PSP en tiempo real |
| Cobro con QR o billetera digital | ❌ Bloqueada | Requiere confirmación del proveedor en tiempo real |
| Cobro por importe superior al umbral offline | ❌ Bloqueada | Umbral configurable por sucursal; por encima requiere conexión |
| Registrar propina en efectivo | ✅ Permitida | — |
| Dividir cuenta | ✅ Permitida | Usando métodos disponibles offline |
| Emisión de recibo impreso | ✅ Permitida | Recibo sin folio fiscal mientras no haya numeración asignada |
| Emisión de documento fiscal (factura, boleta) | ⚠️ Limitada | Solo si hay folios del rango offline asignado disponibles |
| Emisión de documento fiscal sin folio asignado | ❌ Bloqueada | No se puede emitir documento fiscal sin numeración vigente asignada |
| Reembolso o devolución de pago | ❌ Bloqueada | Requiere verificar el cobro original en el servidor |

---

## 4. Caja y turno (CASH)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Ver saldo de caja del turno actual | ✅ Permitida | Calculado con movimientos locales del turno |
| Registrar egreso de caja (fondo de cambio, retiro autorizado) | ⚠️ Limitada | Montos pequeños preconfigurados; egresos grandes requieren conexión |
| Cierre de turno | ⚠️ Limitada | Se puede iniciar el cierre local; la conciliación final requiere conexión |
| Apertura de turno nuevo | ❌ Bloqueada | Requiere validación con el servidor y descarga de datos frescos |
| Arqueo enviado al servidor | ❌ Bloqueada | Se guarda localmente; se envía al reconectar |

---

## 5. Catálogo (CATALOG)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Consultar productos disponibles | ✅ Permitida | Usando catálogo local descargado al turno |
| Buscar producto por nombre o código | ✅ Permitida | Búsqueda local |
| Ver precio de producto | ✅ Permitida | Precio descargado al turno; puede estar desactualizado |
| Crear o modificar producto | ❌ Bloqueada | Cambios de catálogo requieren conexión; son operaciones del back-office |
| Cambiar precio | ❌ Bloqueada | Idem |

---

## 6. Cocina / Kitchen Display (KITCHEN)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Enviar comanda a cocina (impresión local) | ✅ Permitida | Si hay impresora local configurada |
| Enviar comanda a KDS en red local | ⚠️ Limitada | Solo si el KDS está en la red local del restaurante y no requiere Internet |
| Ver estado de preparación desde servidor | ❌ Bloqueada | Requiere conexión al backend |
| Marcar ítem como preparado en KDS | ❌ Bloqueada | Requiere conexión |

---

## 7. Autenticación y sesión (IDENTITY)

| Operación | Estado offline | Restricciones / Razón si bloqueada |
|---|---|---|
| Operar con sesión activa descargada | ✅ Permitida | El token de sesión fue descargado y validado antes de perder conexión |
| Iniciar sesión nueva | ❌ Bloqueada | Requiere validación con el servidor de IDENTITY |
| Cambiar de cajero en el mismo turno | ⚠️ Limitada | Solo si las credenciales del segundo cajero están en caché local del turno |
| Cambiar de tenant | ❌ Bloqueada | Requiere descarga de datos del nuevo tenant |
| Token de sesión expirado durante offline | ❌ Bloqueada | Al reconectar, debe reautenticarse antes de continuar |

---

## 8. Criterios de aceptación de la puerta de avance

Antes de considerar la implementación offline lista para producción:

- [ ] Las operaciones bloqueadas efectivamente se bloquean: el POS no permite ejecutarlas sin conexión.
- [ ] Ningún reintento duplica una venta, cobro o movimiento de inventario.
- [ ] El dispositivo no emite documentos fiscales sin numeración vigente asignada.
- [ ] Al cambiar de tenant, los datos del tenant anterior son eliminados completamente.
- [ ] Una sesión revocada en el servidor se detecta al reconectar y cierra la sesión local.
- [ ] La cola de operaciones se sincroniza en el orden correcto al reconectar.
- [ ] Un conflicto de inventario no produce una venta duplicada en el servidor.
- [ ] Los logs de sincronización no contienen payloads de ventas, datos de pago ni datos personales.

---

## 9. Estado de implementación

Diseño aprobado. No existe código del POS, lógica de bloqueo de operaciones offline
ni interfaz implementada. La implementación y verificación de esta matriz son
criterio de aceptación de las subfases 2.5 y 2.6.
