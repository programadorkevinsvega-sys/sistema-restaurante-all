# Catálogo de eventos auditables por módulo

**Estado:** diseño aprobado — subfase 0.8
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.8
**Autoridad:** ADR-0026
**Documentos relacionados:**

- [Estrategia de observabilidad](./observability-design.md)
- [Matriz de alertas](./alert-matrix.md)

---

## 1. Propósito y reglas

Este catálogo define qué eventos deben auditarse, qué módulo los registra y qué
evidencia mínima deben contener.

**Reglas de ownership:**

- Cada módulo registra las acciones de su propio dominio.
- No existe una tabla de auditoría global compartida; cada módulo tiene la suya.
- El módulo AUDIT puede actuar como agregador de proyecciones de solo lectura,
  pero la fuente autoritativa sigue siendo cada módulo propietario.
- Los BFF registran señales técnicas de borde; no son la fuente de auditoría de negocio.

**Evidencia mínima por evento:**

| Campo | Descripción |
|---|---|
| `timestamp` | UTC ISO 8601 |
| `event_type` | Nombre estable del evento |
| `result` | `success` / `failure` / `partial` |
| `actor_id` | Usuario o identidad de servicio que ejecutó la acción |
| `actor_type` | `user` / `service` / `platform_operator` |
| `tenant_id` | Tenant afectado (cuando aplique) |
| `module` | Módulo propietario del evento |
| `resource_type` | Tipo de recurso afectado |
| `resource_id` | ID del recurso (UUID); sin incluir datos sensibles del recurso |
| `request_id` | Correlación con la solicitud que originó el evento |
| `trace_id` | Correlación de trazas W3C |
| `ip_hash` | Hash de IP origen; no la IP en claro |
| `justification` | Motivo cuando sea una acción excepcional |

**Nunca incluir en evidencia de auditoría:** contraseñas, tokens, hashes de credenciales,
datos de tarjeta, payloads completos ni secretos de proveedores.

---

## 2. PLATFORM

| Evento | Trigger | Criticidad |
|---|---|---|
| `tenant.created` | Creación de nuevo tenant | Alta |
| `tenant.suspended` | Suspensión de tenant | Alta |
| `tenant.activated` | Reactivación de tenant | Alta |
| `tenant.deleted` | Inicio de baja de tenant | Crítica |
| `plan.changed` | Cambio de plan o límites de tenant | Alta |
| `platform_operator.exceptional_access` | Acceso excepcional a datos operativos | Crítica |
| `platform_operator.login` | Login de operador de plataforma | Alta |
| `subscription.created` | Alta de suscripción | Media |
| `subscription.cancelled` | Cancelación de suscripción | Alta |

---

## 3. IDENTITY

| Evento | Trigger | Criticidad |
|---|---|---|
| `user.login_success` | Login exitoso | Media |
| `user.login_failed` | Intento de login fallido | Alta |
| `user.login_blocked` | Login bloqueado por intentos excesivos | Alta |
| `user.logout` | Cierre de sesión | Baja |
| `user.password_changed` | Cambio de contraseña | Alta |
| `user.password_reset_requested` | Solicitud de recuperación de contraseña | Alta |
| `user.password_reset_completed` | Recuperación completada | Alta |
| `user.mfa_enabled` | Activación de MFA | Alta |
| `user.mfa_disabled` | Desactivación de MFA | Alta |
| `user.mfa_challenge_failed` | Fallo en verificación MFA | Alta |
| `user.session_revoked` | Revocación de sesión (por admin o incidente) | Alta |
| `user.created` | Creación de usuario | Media |
| `user.role_assigned` | Asignación de rol | Alta |
| `user.role_revoked` | Revocación de rol | Alta |
| `user.deleted` | Eliminación de usuario | Alta |

---

## 4. ORGANIZATION

| Evento | Trigger | Criticidad |
|---|---|---|
| `branch.created` | Creación de sucursal | Media |
| `branch.modified` | Cambio de configuración de sucursal | Media |
| `branch.deactivated` | Desactivación de sucursal | Alta |
| `company.created` | Creación de empresa legal | Media |
| `brand.created` | Creación de marca | Media |
| `fiscal_config.changed` | Cambio de configuración fiscal | Alta |

---

## 5. CATALOG

| Evento | Trigger | Criticidad |
|---|---|---|
| `product.price_changed` | Cambio de precio de producto | Alta |
| `product.published` | Publicación de producto | Media |
| `product.unpublished` | Despublicación de producto | Media |
| `product.deleted` | Eliminación de producto | Alta |

---

## 6. SALES

| Evento | Trigger | Criticidad |
|---|---|---|
| `order.cancelled` | Cancelación de pedido | Alta |
| `order.discount_applied` | Aplicación de descuento manual | Alta |
| `order.voided` | Anulación de pedido | Alta |

---

## 7. PAYMENTS

| Evento | Trigger | Criticidad |
|---|---|---|
| `payment.captured` | Captura exitosa de pago | Alta |
| `payment.refunded` | Emisión de reembolso | Crítica |
| `payment.voided` | Anulación de pago confirmado | Crítica |
| `payment.failed` | Fallo de pago | Alta |
| `payment.dispute_opened` | Apertura de disputa por cliente | Alta |

---

## 8. CASH

| Evento | Trigger | Criticidad |
|---|---|---|
| `shift.opened` | Apertura de turno de caja | Media |
| `shift.closed` | Cierre de turno de caja | Media |
| `cash.egress_registered` | Registro de egreso de caja | Alta |
| `cash.adjustment` | Ajuste de caja con justificación | Alta |

---

## 9. INVENTORY

| Evento | Trigger | Criticidad |
|---|---|---|
| `inventory.adjustment` | Ajuste de inventario con justificación | Alta |
| `inventory.transfer` | Transferencia entre bodegas | Media |
| `inventory.write_off` | Registro de merma o pérdida | Alta |

---

## 10. BILLING

| Evento | Trigger | Criticidad |
|---|---|---|
| `invoice.issued` | Emisión de documento fiscal | Alta |
| `invoice.voided` | Anulación de documento fiscal | Crítica |
| `invoice.corrected` | Emisión de nota de crédito/débito | Crítica |

---

## 11. FINANCE

| Evento | Trigger | Criticidad |
|---|---|---|
| `period.closed` | Cierre de período contable | Alta |
| `account.adjusted` | Ajuste manual de cuenta | Crítica |
| `report.exported` | Exportación masiva de datos financieros | Alta |

---

## 12. INTEGRATIONS

| Evento | Trigger | Criticidad |
|---|---|---|
| `api_key.created` | Creación de API key | Alta |
| `api_key.revoked` | Revocación de API key | Alta |
| `webhook.invalid_signature` | Callback con firma inválida | Alta |
| `webhook.replay_detected` | Reintento de callback previamente procesado | Alta |
| `integration.credentials_changed` | Cambio de credenciales de integración | Alta |

---

## 13. ANALYTICS y REPORTING

| Evento | Trigger | Criticidad |
|---|---|---|
| `export.massive_data` | Exportación masiva de datos | Alta |
| `report.accessed` | Acceso a reporte sensible | Media |

---

## 14. Eventos de seguridad transversales (registrados por el módulo que los detecta)

| Evento | Módulo propietario | Criticidad |
|---|---|---|
| `access.denied_bola` | Módulo que detecta el intento | Crítica |
| `access.cross_tenant_attempt` | Módulo que detecta el intento | Crítica |
| `access.privilege_escalation_attempt` | IDENTITY | Crítica |
| `rate_limit.exceeded` | BFF (señal técnica) | Alta |
| `secret.rotation_completed` | Infraestructura / ops | Alta |
| `secret.suspected_exposure` | Infraestructura / ops | Crítica |

---

## 15. Estado de implementación

Catálogo aprobado. No existen tablas de auditoría, eventos emitidos ni código implementado.
La implementación comienza módulo a módulo a partir de la subfase 1.1 (PLATFORM) y 1.3 (IDENTITY).
