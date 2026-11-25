# Plantilla de contrato de entrada por operación

**Estado:** diseño aprobado — subfase 0.5
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.5
**Autoridad:** ADR-0019, ADR-0002
**Documentos relacionados:**

- [Catálogo de reglas y formatos](./validation-rules-catalog.md)
- [Catálogo de errores públicos](./public-error-catalog.md)
- [Checklist de revisión de validación](./validation-review-checklist.md)

---

## 1. Propósito

Esta plantilla define la estructura mínima que debe documentar cada operación antes de
implementarse. Se completa una instancia por operación (endpoint HTTP o método gRPC).

No es un DTO de código. Es la especificación que luego se traduce a OpenAPI, Protobuf y
validadores del módulo propietario.

---

## 2. Plantilla

```markdown
## Contrato de entrada: <NombreOperacion>

**Módulo propietario:** <MODULO>
**Backend:** <admin-platform-backend | public-backend>
**Protocolo:** <HTTP POST /ruta | gRPC <Servicio>/<Metodo>>
**Versión:** v1
**Idempotente:** <sí / no / condicional>
**Idempotency key:** <campo | header | no aplica>

### Contexto requerido

| Campo de contexto | Obligatorio | Descripción |
|---|---|---|
| `tenant_id` | Sí | Del contexto autenticado; nunca del payload |
| `user_id` | Sí / No | Del contexto autenticado cuando aplique |
| `auth_level` | <normal / mfa_verified> | Nivel mínimo requerido |

### Campos de entrada

| Campo | Tipo | Obligatorio | Nullable | Reglas | Notas |
|---|---|---|---|---|---|
| `campo_1` | string | Sí | No | Min 1, Max 100 chars | Texto corto; sin normalización |
| `campo_2` | decimal string | Sí | No | Rango [0.01, 999999.99]; 2 decimales | Importe en COP |
| `campo_3` | UUIDv7 | No | Sí | Formato UUID válido | Referencia a recurso propio del tenant |
| `campo_4` | enum | Sí | No | `draft`, `active` | Estado inicial válido |

### Campos prohibidos en escritura

Los siguientes campos se rechazan si aparecen en el body (mass assignment):
`tenant_id`, `created_at`, `status_interno`, `aprobado_por`, ...

### Validaciones de dominio

1. `campo_3` si presente debe pertenecer al `tenant_id` del contexto.
2. La combinación `campo_x` + `campo_y` no puede superar el límite Z.
3. ...

### Validaciones de estado

- El recurso referenciado debe estar en estado `active` para permitir esta operación.
- Verificar dentro de transacción con bloqueo apropiado.

### Respuesta exitosa

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | UUIDv7 string | ID del recurso creado/modificado |
| `created_at` | ISO 8601 UTC | Timestamp de creación |

### Errores esperados

| Código | HTTP | gRPC | Condición |
|---|---|---|---|
| `validation.required` | 400 | INVALID_ARGUMENT | Campo obligatorio ausente |
| `validation.format` | 400 | INVALID_ARGUMENT | Formato inválido |
| `validation.range` | 422 | INVALID_ARGUMENT | Valor fuera de rango |
| `resource.not_found` | 404 | NOT_FOUND | Recurso referenciado no existe |
| `resource.wrong_tenant` | 403 | PERMISSION_DENIED | Recurso de otro tenant |
| `state.invalid_transition` | 409 | FAILED_PRECONDITION | Estado no permite esta operación |

### Pruebas negativas requeridas

- [ ] Campo obligatorio ausente → 400
- [ ] Tipo incorrecto → 400
- [ ] Valor fuera de rango → 422
- [ ] UUID válido de otro tenant → 403 o 404
- [ ] Campo prohibido en escritura → 400 o ignorado (según contrato)
- [ ] Concurrencia: dos requests simultáneos con mismo recurso → segundo falla correctamente
- [ ] Idempotency key reutilizada con mismo payload → respuesta idempotente
- [ ] Idempotency key reutilizada con payload distinto → según política de la operación
```

---

## 3. Ejemplo completado: Crear producto en CATALOG

```markdown
## Contrato de entrada: CrearProducto

**Módulo propietario:** CATALOG
**Backend:** public-backend
**Protocolo:** HTTP POST /v1/catalog/products
**Versión:** v1
**Idempotente:** sí
**Idempotency key:** header `Idempotency-Key` (UUIDv7)

### Contexto requerido

| Campo de contexto | Obligatorio | Descripción |
|---|---|---|
| `tenant_id` | Sí | Del contexto autenticado |
| `user_id` | Sí | Del contexto autenticado |
| `auth_level` | normal | No requiere MFA |

### Campos de entrada

| Campo | Tipo | Obligatorio | Nullable | Reglas | Notas |
|---|---|---|---|---|---|
| `name` | string | Sí | No | Min 1, Max 200 chars | Nombre comercial del producto |
| `sku` | string | No | Sí | Max 100 chars; alfanumérico + guiones | Código interno; único por tenant |
| `price` | decimal string | Sí | No | Rango [0.00, 9999999.99]; 2 decimales | Precio base en moneda del tenant |
| `category_id` | UUIDv7 | Sí | No | Formato UUID válido | Debe pertenecer al tenant |
| `is_active` | boolean | No | No | true/false; default true | Publicación del producto |

### Campos prohibidos en escritura

`tenant_id`, `created_at`, `updated_at`, `deleted_at`, `created_by`

### Validaciones de dominio

1. `category_id` debe pertenecer al `tenant_id` del contexto.
2. `sku` si presente debe ser único dentro del tenant.

### Validaciones de estado

No aplican en creación.

### Respuesta exitosa

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | UUIDv7 string | ID del producto creado |
| `created_at` | ISO 8601 UTC | Timestamp de creación |

### Errores esperados

| Código | HTTP | gRPC | Condición |
|---|---|---|---|
| `validation.required` | 400 | INVALID_ARGUMENT | `name`, `price` o `category_id` ausente |
| `validation.format` | 400 | INVALID_ARGUMENT | `price` no es decimal válido |
| `validation.range` | 422 | INVALID_ARGUMENT | `price` negativo o excede máximo |
| `resource.not_found` | 404 | NOT_FOUND | `category_id` no existe en el tenant |
| `resource.wrong_tenant` | 403 | PERMISSION_DENIED | `category_id` pertenece a otro tenant |
| `resource.conflict` | 409 | ALREADY_EXISTS | `sku` duplicado en el tenant |

### Pruebas negativas requeridas

- [ ] `name` ausente → 400
- [ ] `price` como número float JSON → 400
- [ ] `price` negativo → 422
- [ ] `category_id` de otro tenant → 403 o 404
- [ ] `sku` duplicado con concurrencia → 409
- [ ] Campo `tenant_id` en body → ignorado; usa contexto autenticado
- [ ] Campo `created_at` en body → 400 (campo desconocido rechazado)
```

---

## 4. Reglas de uso de la plantilla

- Se completa una instancia por operación antes de comenzar la implementación.
- Los límites numéricos se dimensionan; no se copian de otro contrato sin justificación.
- Los errores son estables; no dependen de mensajes de bibliotecas internas.
- La plantilla completada se revisa con el checklist de validación antes de implementar.

---

## 5. Estado de implementación

Plantilla aprobada. No existen contratos completados hasta la subfase 1.3.
Cada módulo completará una instancia por operación antes de implementarla.
