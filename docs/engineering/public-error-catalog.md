# Catálogo de errores públicos

**Estado:** diseño aprobado — subfase 0.5
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.5
**Autoridad:** ADR-0019
**Documentos relacionados:**

- [Validación de entradas y contratos de datos](../architecture/input-validation-and-data-contracts.md)
- [Plantilla de contrato de entrada](./input-contract-template.md)

---

## 1. Propósito y reglas

Los códigos de error son estables. No dependen de mensajes internos de bibliotecas, nombres
de tablas, constraints de PostgreSQL, stack traces ni detalles de implementación.

Un error público cumple estas reglas:

- **Código estable:** `dominio.tipo` en snake_case; no cambia entre versiones del módulo.
- **Mensaje seguro:** en español o el idioma configurado del tenant; no revela internos.
- **Sin filtración:** no incluye SQL, rutas, nombres de módulos internos, payloads completos
  ni datos de otros tenants.
- **Distinguible:** diferencia sintaxis inválida, dominio inválido, estado inválido y límite
  alcanzado; no colapsarlos en un único error genérico.
- **Localizable:** el `code` es la clave estable; el `message` puede variar por idioma.

### Estructura de respuesta de error

```json
{
  "code": "validation.required",
  "message": "El campo es obligatorio.",
  "field_errors": [
    { "field": "name", "code": "validation.required" },
    { "field": "price", "code": "validation.format" }
  ],
  "request_id": "01932e4a-7c3f-7000-9f5b-3d2e1a4b5c6d"
}
```

- `code`: código del error principal.
- `message`: descripción segura y localizable.
- `field_errors`: lista acotada; solo cuando el error es de validación de campos específicos.
- `request_id`: UUIDv7 de correlación; no sensible.

No se incluye `stack_trace`, `cause`, `sql`, `table`, `constraint` ni valor original del campo.

---

## 2. Catálogo de códigos

### 2.1 Validación estructural y sintáctica

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `validation.required` | 400 | INVALID_ARGUMENT | Campo obligatorio ausente o vacío |
| `validation.format` | 400 | INVALID_ARGUMENT | Formato no válido (UUID, email, fecha, decimal) |
| `validation.type` | 400 | INVALID_ARGUMENT | Tipo de dato incorrecto |
| `validation.length.min` | 400 | INVALID_ARGUMENT | Valor más corto que el mínimo permitido |
| `validation.length.max` | 400 | INVALID_ARGUMENT | Valor más largo que el máximo permitido |
| `validation.range.min` | 422 | INVALID_ARGUMENT | Número menor que el mínimo permitido |
| `validation.range.max` | 422 | INVALID_ARGUMENT | Número mayor que el máximo permitido |
| `validation.enum` | 400 | INVALID_ARGUMENT | Valor no pertenece al conjunto definido |
| `validation.unknown_field` | 400 | INVALID_ARGUMENT | Campo no reconocido en escritura |
| `validation.readonly_field` | 400 | INVALID_ARGUMENT | Campo de solo servidor enviado por cliente |
| `validation.cardinality.min` | 400 | INVALID_ARGUMENT | Colección con menos elementos del mínimo |
| `validation.cardinality.max` | 400 | INVALID_ARGUMENT | Colección supera el máximo de elementos |
| `validation.duplicate` | 422 | INVALID_ARGUMENT | Elemento duplicado en colección |
| `validation.null` | 400 | INVALID_ARGUMENT | Campo no nullable recibió null |
| `validation.precision` | 422 | INVALID_ARGUMENT | Decimal con más decimales de los permitidos |

### 2.2 Semántica y dominio

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `validation.semantic` | 422 | INVALID_ARGUMENT | Combinación de campos incoherente |
| `domain.rule_violation` | 422 | INVALID_ARGUMENT | Regla de negocio del módulo no cumplida |
| `domain.invalid_transition` | 409 | FAILED_PRECONDITION | Transición de estado no permitida desde el estado actual |
| `domain.dependency_missing` | 422 | FAILED_PRECONDITION | Recurso requerido para la operación no existe o no está activo |

### 2.3 Recursos

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `resource.not_found` | 404 | NOT_FOUND | Recurso no existe en el tenant del actor |
| `resource.conflict` | 409 | ALREADY_EXISTS | Recurso con la misma clave única ya existe |
| `resource.wrong_tenant` | 403 | PERMISSION_DENIED | Recurso existe pero pertenece a otro tenant |
| `resource.deleted` | 404 | NOT_FOUND | Recurso existe pero fue eliminado; usar 404 para no revelar existencia |
| `resource.locked` | 409 | FAILED_PRECONDITION | Recurso está siendo procesado por otra operación |

### 2.4 Autorización y autenticación

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `auth.unauthenticated` | 401 | UNAUTHENTICATED | Sin sesión válida o token ausente/expirado |
| `auth.token_expired` | 401 | UNAUTHENTICATED | Token expirado; solicitar refresh |
| `auth.session_revoked` | 401 | UNAUTHENTICATED | Sesión revocada; requiere nuevo login |
| `auth.mfa_required` | 403 | PERMISSION_DENIED | Operación requiere MFA verificado recientemente |
| `auth.reauth_required` | 403 | PERMISSION_DENIED | Operación requiere reautenticación |
| `auth.forbidden` | 403 | PERMISSION_DENIED | Actor autenticado sin permiso para esta operación |
| `auth.tenant_mismatch` | 403 | PERMISSION_DENIED | Tenant solicitado no coincide con el contexto |

### 2.5 Límites de recursos y abuso

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `limit.payload_too_large` | 413 | RESOURCE_EXHAUSTED | Body o archivo supera el límite permitido |
| `limit.rate_exceeded` | 429 | RESOURCE_EXHAUSTED | Límite de frecuencia de llamadas alcanzado |
| `limit.quota_exceeded` | 429 | RESOURCE_EXHAUSTED | Cuota del tenant o plan alcanzada |
| `limit.concurrency` | 429 | RESOURCE_EXHAUSTED | Demasiadas operaciones concurrentes del mismo actor |
| `limit.media_type` | 415 | INVALID_ARGUMENT | Content-Type no admitido por la operación |

### 2.6 Idempotencia

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `idempotency.conflict` | 409 | ALREADY_EXISTS | Idempotency key ya usada con payload diferente |
| `idempotency.processing` | 409 | ALREADY_EXISTS | Idempotency key en proceso; reintento demasiado rápido |

### 2.7 Archivo y almacenamiento

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `file.type_not_allowed` | 400 | INVALID_ARGUMENT | Tipo de archivo no permitido por la operación |
| `file.size_exceeded` | 413 | RESOURCE_EXHAUSTED | Archivo supera el tamaño máximo |
| `file.corrupted` | 400 | INVALID_ARGUMENT | Archivo no pudo ser leído o está corrupto |
| `file.rejected` | 400 | INVALID_ARGUMENT | Archivo rechazado por análisis de contenido |

### 2.8 Mensajería y workers

| Código | Uso | Descripción |
|---|---|---|
| `message.schema_invalid` | Log interno / DLQ | Mensaje no cumple el esquema del contrato |
| `message.version_unsupported` | Log interno / DLQ | Versión del evento no soportada por este consumidor |
| `message.context_missing` | Log interno / DLQ | `tenant_id` u otro campo de contexto obligatorio ausente |
| `message.duplicate` | Log interno | Mensaje ya procesado; ignorado por idempotencia |

Los códigos de mensajería son internos; no se exponen en APIs HTTP ni gRPC.

### 2.9 Errores internos

| Código | HTTP | gRPC | Descripción |
|---|---|---|---|
| `internal.error` | 500 | INTERNAL | Error inesperado; no revelar detalles al cliente |
| `internal.unavailable` | 503 | UNAVAILABLE | Servicio temporalmente no disponible |
| `internal.timeout` | 504 | DEADLINE_EXCEEDED | Operación excedió el tiempo límite |

Los errores internos se registran con `request_id` y contexto suficiente para diagnóstico,
pero la respuesta al cliente solo incluye el código y un mensaje genérico.

---

## 3. Reglas de uso

- Nunca exponer `internal.error` con detalles de la causa al cliente.
- Nunca usar `resource.not_found` cuando el recurso existe pero pertenece a otro tenant;
  usar `resource.wrong_tenant` (403) o también 404 si se decide no revelar existencia.
- No colapsar todos los errores de validación en `validation.required` o `internal.error`.
- Los códigos de mensajería no salen en respuestas de API.
- El `request_id` en la respuesta de error coincide con el `request_id` del contexto autenticado.

---

## 4. Estado de implementación

Catálogo aprobado. No existen tipos Rust, enums, middleware ni handlers implementados.
Se implementa módulo a módulo a partir de la subfase 1.3.
