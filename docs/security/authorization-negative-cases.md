# Casos negativos de autorización

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0021
**Documentos relacionados:**

- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Modelo de amenazas](./threat-model.md) — amenazas D-01, D-02, E-01, E-02, E-03, E-04

---

## 1. Propósito

Define los escenarios negativos que deben rechazarse en toda operación protegida.
Cada caso especifica la condición de prueba, el resultado esperado y la fase de
verificación. Estos casos son el criterio mínimo de aceptación de seguridad para
cualquier endpoint, operación gRPC, worker o consumidor.

**Un módulo no pasa a integración sin haber ejecutado los casos de su categoría.**

---

## 2. Convenciones

- **Resultado esperado:** siempre es un rechazo con código de error. Nunca datos de otro tenant,
  datos del recurso solicitado sin permiso ni ejecución del efecto.
- **Código HTTP esperado:** 401 (no autenticado), 403 (autenticado pero sin permiso) o 404
  (recurso no encontrado cuando revelar su existencia sería información).
- **Código gRPC esperado:** `UNAUTHENTICATED` o `PERMISSION_DENIED`.
- **Sin filtración:** el mensaje de error no revela por qué exactamente se denegó (no distinguir
  "no existe" de "no tienes permiso" en la respuesta al cliente).

---

## 3. Casos de cruce de tenant (BOLA — D-01)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-T-01 | Usuario del tenant A solicita recurso que pertenece al tenant B usando un ID válido | `tenant_id` en contexto = A; `resource.tenant_id` = B | 403 / `PERMISSION_DENIED`; sin datos del recurso |
| NEG-T-02 | Usuario envía `tenant_id` del tenant B en el payload intentando saltarse el contexto | Contexto autenticado = tenant A; payload tiene `tenant_id` = B | El módulo usa el contexto, ignora el payload; resultado como NEG-T-01 |
| NEG-T-03 | Worker procesa mensaje con `tenant_id` que no coincide con el recurso de la operación | Mensaje.tenant_id ≠ recurso.tenant_id | Rechazo del mensaje; sin efecto; evento en AUDIT |
| NEG-T-04 | Usuario enumera IDs secuencialmente para acceder a recursos de otros tenants | IDs incrementales o UUIDs adivinados | 403 o 404 consistente; sin diferencia de timing que revele existencia |
| NEG-T-05 | Administrador de tenant A intenta listar usuarios del tenant B | Rol `tenant_admin` en tenant A | 403; sin datos del tenant B |

---

## 4. Casos de escalada vertical de privilegios (E-01, E-02)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-E-01 | Usuario con rol `cashier` intenta acceder a operación de `tenant_admin` | Token con roles = [`cashier`] | 403 / `PERMISSION_DENIED` |
| NEG-E-02 | Administrador de tenant intenta usar endpoint de operador de plataforma | Token con roles = [`tenant_admin`] | 403 / `PERMISSION_DENIED` |
| NEG-E-03 | `tenant_admin` intenta asignar a otro usuario un rol de plataforma | Rol `platform_operator` en payload | 403; rol no asignado |
| NEG-E-04 | Usuario intenta asignarse a sí mismo un rol superior al que posee | Rol `cashier` solicita elevarse a `branch_manager` | 403; sin cambio de roles |
| NEG-E-05 | Operador de plataforma intenta acceder a datos operativos sin justificación/ventana temporal | Sin registro de acceso excepcional activo | 403; sin datos operativos |

---

## 5. Casos de escalada horizontal (D-02)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-H-01 | Cajero de sucursal A intenta ver ventas de sucursal B del mismo tenant | `cashier` en sucursal A; recurso en sucursal B | 403 / `PERMISSION_DENIED` |
| NEG-H-02 | `branch_manager` de marca X intenta modificar catálogo de marca Y del mismo tenant | Rol acotado a marca X; recurso en marca Y | 403 |
| NEG-H-03 | Usuario intenta exportar datos de una sucursal a la que no pertenece | ABAC: `sucursal_id` del actor ≠ `sucursal_id` del recurso | 403 |
| NEG-H-04 | `waiter` accede al pedido de otro `waiter` del mismo turno | `resource_owner_id` ≠ `user_id` del contexto | 403 (o 404 si no se revela existencia) |

---

## 6. Casos de sesión inválida o revocada (S-01, S-03)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-S-01 | Solicitud sin token de autenticación | Header de Authorization ausente | 401 / `UNAUTHENTICATED` |
| NEG-S-02 | Token con firma inválida o manipulado | Token modificado | 401 |
| NEG-S-03 | Token expirado | `expires_at` < now | 401; sin datos |
| NEG-S-04 | Token revocado (sesión cerrada, contraseña cambiada) | `session_id` marcado como revocado en IDENTITY | 401 |
| NEG-S-05 | Refresh token reutilizado después de rotación | Token usado previamente | 401; familia de sesión revocada completa |
| NEG-S-06 | Acción de alto impacto sin `auth_level = mfa_verified` | Token normal, operación requiere MFA | 403 con indicación de MFA requerido |

---

## 7. Casos de mass assignment (E-03)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-M-01 | Payload HTTP incluye `tenant_id` intentando cambiar el tenant del recurso | Campo extra en JSON de escritura | Campo ignorado; operación usa `tenant_id` del contexto |
| NEG-M-02 | Payload incluye `user_id` intentando cambiar el propietario del recurso | Campo extra en JSON | Campo ignorado o error 400 si el DTO lo rechaza explícitamente |
| NEG-M-03 | Payload incluye `roles` o `permissions` en creación de pedido | Campo no esperado en DTO | Rechazado con 400 (campo desconocido) |
| NEG-M-04 | Payload incluye `price` calculado en un endpoint que lo calcula el servidor | Campo ignorado en precio de línea de pedido | Precio recalculado por el servidor; payload ignorado |
| NEG-M-05 | gRPC incluye campos de `AuthenticatedContext` en el mensaje de negocio | `tenant_id` en el body Protobuf del comando | Ignorado; solo se usa el contexto del header gRPC |

---

## 8. Casos de worker con contexto inválido (E-04)

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-W-01 | Mensaje de Outbox/JetStream sin `tenant_id` | Campo ausente | Rechazo; sin efecto; log de error con `message_id` |
| NEG-W-02 | `tenant_id` del mensaje no coincide con el recurso a modificar | Mismatch | Rechazo; sin efecto; registro en AUDIT |
| NEG-W-03 | Worker intenta procesar operación para la que no tiene permiso de servicio | `service_id` sin el permiso requerido | `PERMISSION_DENIED`; mensaje en dead-letter queue o NACK |
| NEG-W-04 | Mensaje duplicado procesado dos veces | `idempotency_key` ya registrado en Inbox | Segundo procesamiento silenciosamente ignorado; sin efecto duplicado |
| NEG-W-05 | Mensaje con `tenant_id` de un tenant dado de baja | `tenant.status = deleted` | Rechazo; sin efecto; log de evento |

---

## 9. Casos de acceso a subrecursos y adjuntos

| ID | Escenario | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-R-01 | URL de archivo en almacenamiento construida manualmente para acceder a archivo de otro tenant | URL directa sin token de acceso | 403 / acceso denegado; sin archivo |
| NEG-R-02 | Búsqueda con filtro que incluye `tenant_id` de otro tenant | Parámetro de búsqueda manipulado | Resultados acotados al tenant del contexto; sin resultados ajenos |
| NEG-R-03 | Exportación de reporte con rango de fechas que incluye datos de período previo al tenant | Fechas anteriores a la creación del tenant | Solo datos del período válido del tenant |
| NEG-R-04 | Acceso a reporte de otro módulo mediante referencia indirecta | ID de reporte de otro tenant en URL | 403 o 404 |

---

## 10. Protocolo de ejecución de casos negativos

Cada caso se ejecuta como prueba automatizada con:

1. Configuración del estado inicial (tenant, usuario, recurso).
2. Solicitud con la condición adversa.
3. Aserción del código de respuesta esperado.
4. Aserción de que el body no contiene datos del recurso protegido.
5. Verificación de que no hubo efecto secundario (sin escrituras, sin eventos publicados).
6. Verificación de que el intento quedó registrado cuando corresponde (AUDIT).

Los casos se ejecutan antes de que el módulo pase a integración o staging. El fallo de
cualquier caso bloquea el avance, independientemente del estado del resto de pruebas.

---

## 11. Estado de implementación

Diseño aprobado. Las pruebas no están escritas ni ejecutadas. Se implementan en paralelo
con la subfase de cada módulo correspondiente, comenzando por IDENTITY (1.3) y
Autorización RBAC/ABAC (1.4).
