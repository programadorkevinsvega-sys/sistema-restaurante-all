# Matriz rol / atributo / acción / ámbito

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0021
**Documentos relacionados:**
- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)

---

## 1. Propósito y límites

Esta matriz define los roles del sistema, sus atributos de contexto ABAC relevantes y las
acciones que controlan en cada ámbito. Es un diseño de referencia; no crea tablas,
seeds, código ni migrations.

Cada módulo define los permisos de sus propias operaciones y recursos. Esta matriz recoge
los roles transversales y las reglas generales; los permisos específicos de cada dominio
se añaden en la subfase de implementación del módulo correspondiente.

Los roles no son un catálogo cerrado. Se extienden por dominio según necesidad funcional.

---

## 2. Roles del sistema

### 2.1 Roles de plataforma (propietario: PLATFORM)

| Rol | Ámbito | Descripción |
|---|---|---|
| `platform_operator` | Plataforma global | Administra tenants, planes y suscripciones. Acceso excepcional temporal a datos de tenant con justificación y auditoría. |
| `platform_support` | Plataforma global | Acceso de soporte de solo lectura; acotado por tenant y ventana temporal. |
| `platform_billing` | Plataforma global | Gestiona facturación SaaS y planes. Sin acceso a datos operativos de tenant. |

### 2.2 Roles de tenant (propietario: IDENTITY)

| Rol | Ámbito | Descripción |
|---|---|---|
| `tenant_admin` | Tenant completo | Configura empresas, sucursales, usuarios y permisos dentro de su tenant. Sin privilegios de plataforma. |
| `tenant_auditor` | Tenant completo | Solo lectura sobre registros de auditoría y reportes. Sin modificación de datos operativos. |
| `brand_manager` | Marca | Configura catálogo, menús y precios de su marca. |
| `branch_manager` | Sucursal | Gestiona operación de su sucursal: personal, turnos, caja e inventario. |
| `cashier` | Caja / Terminal | Abre turno, procesa ventas, cobra y cierra caja. Sin acceso a configuración. |
| `waiter` | Sucursal | Toma pedidos, asigna mesas y gestiona comandas de su área. |
| `kitchen_staff` | Estación de cocina | Ve y actualiza estado de comandas de su estación. Sin acceso a ventas ni pagos. |
| `inventory_manager` | Sucursal | Gestiona inventario, bodegas y transferencias. Sin acceso a configuración de precios. |
| `procurement_officer` | Empresa legal | Gestiona proveedores, compras y recepciones. |
| `accountant` | Empresa legal | Accede a módulos financieros y contables. Sin modificar operaciones de venta. |
| `hr_manager` | Empresa legal | Gestiona empleados, turnos y compensaciones. |
| `analyst` | Tenant / Marca / Sucursal | Acceso de solo lectura a dashboards y reportes de su ámbito. |
| `integration_manager` | Tenant | Configura credenciales de integración y webhooks. |

### 2.3 Roles de servicio (propietario: infraestructura)

| Rol | Ámbito | Descripción |
|---|---|---|
| `outbox_worker` | Backend / tenant | Despacha eventos del Outbox. Acotado a su propio schema. |
| `inbox_consumer` | Backend / tenant | Procesa mensajes del Inbox. Acotado a su propio schema. |
| `scheduler` | Backend global | Ejecuta jobs periódicos con advisory lock. |

---

## 3. Atributos ABAC relevantes

Los atributos de contexto que modifican la decisión de autorización más allá del rol:

| Atributo | Fuente | Uso |
|---|---|---|
| `tenant_id` | Sesión validada | Aísla todos los recursos; nunca del payload del cliente |
| `empresa_legal_id` | Recurso / sesión | Acota reportes financieros y fiscales |
| `marca_id` | Recurso / sesión | Acota configuración de catálogo y menús |
| `sucursal_id` | Recurso / sesión | Acota operación del día, caja e inventario |
| `area_id` | Recurso / sesión | Acota comandas y mesas |
| `resource_owner_id` | Recurso en BD | Verifica relación actor-recurso para BOLA |
| `resource_state` | Recurso en BD | Algunos estados no admiten ciertas acciones (ej. pedido cancelado) |
| `auth_level` | Sesión | Acciones de alto impacto requieren `mfa_verified` |
| `amount` | Parámetro de operación | Umbral para segunda aprobación en pagos |
| `channel` | Sesión | POS físico vs web vs API externa |

---

## 4. Matriz acción / rol / atributos requeridos

### 4.1 Gestión de tenant (PLATFORM)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Crear tenant | `platform_operator` | — | Registrado en AUDIT |
| Suspender / activar tenant | `platform_operator` | — | Registrado en AUDIT |
| Ver configuración de tenant | `platform_operator`, `platform_support` | — | Support: solo lectura |
| Acceso excepcional a datos operativos | `platform_operator` | Ventana temporal + justificación | Requiere `mfa_verified`; auditado |

### 4.2 Configuración de organización (ORGANIZATION)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Crear empresa legal | `tenant_admin` | `tenant_id` | |
| Crear sucursal | `tenant_admin`, `branch_manager` (propia) | `tenant_id`, `empresa_legal_id` | |
| Modificar configuración de sucursal | `tenant_admin`, `branch_manager` | `sucursal_id` del actor = sucursal del recurso | |
| Ver estructura completa del tenant | `tenant_admin`, `tenant_auditor` | `tenant_id` | |

### 4.3 Gestión de usuarios (IDENTITY)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Crear usuario en tenant | `tenant_admin` | `tenant_id` | No puede asignar roles superiores al propio |
| Asignar rol a usuario | `tenant_admin` | `tenant_id`; rol ≤ privilegio del actor | |
| Revocar sesión de otro usuario | `tenant_admin` | `tenant_id` | Registrado en AUDIT |
| Cambiar propia contraseña | Cualquier usuario autenticado | `user_id` del contexto | |
| Resetear contraseña de otro | `tenant_admin` | `tenant_id` | Requiere `mfa_verified` |
| Configurar MFA | Propio usuario | `user_id` del contexto | |
| Habilitar MFA obligatorio para rol | `tenant_admin` | `tenant_id` | |

### 4.4 Catálogo y precios (CATALOG)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Crear / modificar producto | `tenant_admin`, `brand_manager` | `tenant_id`, `marca_id` | |
| Modificar precio | `tenant_admin`, `brand_manager` | `tenant_id`, `marca_id` | Registrado en AUDIT |
| Ver catálogo | Todos los roles de tenant | `tenant_id` | Lectura sin restricción por rol |
| Publicar / despublicar producto | `tenant_admin`, `brand_manager` | `tenant_id`, `marca_id` | |

### 4.5 Ventas y pedidos (SALES)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Crear pedido | `cashier`, `waiter` | `tenant_id`, `sucursal_id` | |
| Ver pedido propio | `cashier`, `waiter` | `tenant_id`, `sucursal_id`, `resource_owner_id` | |
| Ver todos los pedidos de sucursal | `branch_manager`, `tenant_admin` | `tenant_id`, `sucursal_id` | |
| Cancelar pedido | `cashier` (propio), `branch_manager`, `tenant_admin` | `tenant_id`, `sucursal_id`, `resource_state` ≠ pagado | |
| Aplicar descuento manual | `branch_manager`, `tenant_admin` | `tenant_id`, `sucursal_id` | Registrado en AUDIT |

### 4.6 Pagos (PAYMENTS)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Procesar cobro | `cashier` | `tenant_id`, `sucursal_id` | |
| Ver transacción | `cashier` (propia), `branch_manager`, `accountant`, `tenant_admin` | `tenant_id`, `sucursal_id` | |
| Emitir reembolso | `branch_manager`, `tenant_admin` | `tenant_id`, `sucursal_id` | Requiere `mfa_verified`; registrado en AUDIT |
| Anular pago confirmado | `tenant_admin` | `tenant_id` | Requiere `mfa_verified` + segunda aprobación; registrado en AUDIT |

### 4.7 Caja (CASH)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Abrir turno de caja | `cashier` | `tenant_id`, `sucursal_id` | |
| Cerrar turno de caja | `cashier` (propio), `branch_manager` | `tenant_id`, `sucursal_id` | |
| Ver arqueo | `cashier` (propio), `branch_manager`, `accountant` | `tenant_id`, `sucursal_id` | |
| Registrar egreso de caja | `cashier`, `branch_manager` | `tenant_id`, `sucursal_id` | Registrado en AUDIT |

### 4.8 Inventario (INVENTORY)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Ver existencias | `inventory_manager`, `branch_manager`, `tenant_admin` | `tenant_id`, `sucursal_id` | |
| Registrar ajuste | `inventory_manager`, `branch_manager` | `tenant_id`, `sucursal_id` | Requiere justificación; registrado en AUDIT |
| Conteo físico | `inventory_manager` | `tenant_id`, `sucursal_id` | |
| Transferencia entre bodegas | `inventory_manager` | `tenant_id`, `sucursal_id` del origen y destino | |

### 4.9 Reportes y analítica (ANALYTICS / REPORTING)

| Acción | Roles permitidos | Atributos ABAC | Notas |
|---|---|---|---|
| Ver dashboard de sucursal | `branch_manager`, `cashier`, `tenant_admin` | `tenant_id`, `sucursal_id` | |
| Ver dashboard de marca | `brand_manager`, `tenant_admin` | `tenant_id`, `marca_id` | |
| Ver reportes consolidados del tenant | `tenant_admin`, `tenant_auditor`, `analyst` | `tenant_id` | |
| Exportar datos masivos | `tenant_admin` | `tenant_id` | Requiere `mfa_verified`; registrado en AUDIT; rate limiting |

---

## 5. Reglas de asignación de roles

- Un `tenant_admin` no puede asignarse a sí mismo ni a otros usuarios un rol de nivel superior al suyo.
- Los roles de plataforma (`platform_*`) solo los asigna un `platform_operator`; nunca un `tenant_admin`.
- Los roles de servicio no son asignables a usuarios humanos.
- Un usuario puede tener múltiples roles acumulativos dentro del mismo tenant.
- Los roles son contextuales al ámbito (sucursal, marca): un `cashier` de una sucursal no opera en otra.

---

## 6. Estado de implementación

Diseño aprobado. No existen tablas, seeds, migraciones, código de evaluación de roles ni
middleware. La implementación comienza en subfase 1.4 — Autorización RBAC/ABAC y contexto confiable,
apoyada en los módulos IDENTITY y ORGANIZATION completados en 1.2 y 1.3.
