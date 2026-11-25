# Contrato de contexto autenticado

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0004, ADR-0007, ADR-0021
**Documentos relacionados:**
- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)

---

## 1. Propósito

Define los campos, semántica y reglas de propagación del contexto autenticado que acompaña
toda solicitud entre fronteras de proceso y entre módulos dentro del mismo proceso.

Este documento es un diseño. No genera código Protobuf, structs Rust ni middleware.

---

## 2. Campos del contexto autenticado

### 2.1 Contexto de usuario humano

Transmitido en llamadas originadas por una sesión de usuario.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `trace_id` | string (W3C traceparent) | Sí | Propagación de trazas W3C Trace Context |
| `request_id` | UUIDv7 string | Sí | Identificador único de la solicitud; para idempotencia y correlación |
| `tenant_id` | UUIDv7 string | Sí | Tenant autenticado; establecido por el servidor, nunca del cliente |
| `user_id` | UUIDv7 string | Sí | Usuario autenticado |
| `session_id` | UUIDv7 string | Sí | Sesión activa; verificable en IDENTITY |
| `auth_level` | enum | Sí | `normal` / `mfa_verified` / `reauth_required` |
| `roles` | string[] | Sí | Roles activos en la sesión; derivados de IDENTITY |
| `issued_at` | int64 (unix ms) | Sí | Emisión del access token |
| `expires_at` | int64 (unix ms) | Sí | Expiración del access token |
| `ip_hash` | string | No | Hash de la IP del cliente; para auditoría; nunca la IP en claro |
| `user_agent_hash` | string | No | Hash del User-Agent; para auditoría |

### 2.2 Contexto de identidad de servicio

Transmitido en llamadas proceso-a-proceso sin sesión de usuario activa.

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `trace_id` | string (W3C traceparent) | Sí | Propagación de trazas |
| `request_id` | UUIDv7 string | Sí | Identificador único de la solicitud |
| `service_id` | string | Sí | Identificador del proceso/worker llamante |
| `service_env` | string | Sí | Entorno: `production`, `staging`, `development` |
| `tenant_id` | UUIDv7 string | Condicional | Presente cuando la operación es acotada a un tenant |
| `saga_id` | UUIDv7 string | No | Identificador de la Saga en curso cuando aplique |
| `idempotency_key` | UUIDv7 string | No | Clave de idempotencia para operaciones con efecto |

### 2.3 Campos nunca presentes en el contexto

Los siguientes campos **nunca** forman parte del contexto transmitido entre procesos:

- Contraseñas, hashes de contraseña, salts.
- Tokens en claro (access token, refresh token).
- Secretos TOTP, códigos MFA o códigos de recuperación.
- Datos de tarjeta de pago.
- Payloads personales sensibles (documentos de identidad, datos médicos).
- Secretos de infraestructura.

---

## 3. Reglas de propagación

### 3.1 BFF → Backend

El BFF valida la sesión contra IDENTITY antes de cada solicitud. El contexto autenticado
se construye a partir de la respuesta de IDENTITY y se adjunta a la llamada gRPC hacia
el backend. El BFF nunca construye el contexto a partir del payload del cliente.

```
Cliente → [HTTPS] → BFF → [verifica sesión en IDENTITY] → [construye contexto] → [gRPC] → Backend
```

### 3.2 Backend → Backend (gRPC)

Cuando un backend llama a otro, propaga el contexto recibido sin modificarlo, añadiendo:
- El `service_id` del proceso llamante como campo adicional de trazabilidad.
- Un nuevo `request_id` para la solicitud derivada, enlazado al `trace_id` padre.

No se eleva el `auth_level` ni se añaden roles en la propagación.

### 3.3 Dentro del mismo backend (módulo a módulo)

Los módulos que comparten proceso se comunican mediante contratos públicos (puertos/traits).
El contexto se pasa como parámetro explícito en cada llamada; nunca como estado global ni
thread-local implícito.

```rust
// Correcto: contexto explícito como parámetro
fn create_order(ctx: &AuthenticatedContext, cmd: CreateOrderCommand) -> Result<OrderId, Error>;

// Prohibido: contexto como estado global o implícito
fn create_order(cmd: CreateOrderCommand) -> Result<OrderId, Error>; // sin contexto
```

### 3.4 Workers y consumidores

Los mensajes del Outbox/JetStream no transportan el contexto autenticado como credencial activa.
Los workers reconstruyen un contexto de servicio (`service_id` + `tenant_id` si aplica) a partir
del contenido del mensaje y de su propia identidad de servicio. No heredan la sesión del
usuario que originó el evento.

Si una operación de worker requiere autorización de negocio, la evalúa usando el contexto
de servicio contra el módulo propietario del recurso, igual que lo haría un usuario.

---

## 4. Validación del contexto en cada módulo

Antes de ejecutar cualquier operación, el módulo receptor verifica:

1. `trace_id` presente y con formato W3C válido.
2. `request_id` presente y con formato UUIDv7.
3. `tenant_id` presente y con formato UUIDv7 (cuando la operación es acotada a tenant).
4. `user_id` o `service_id` presente según el tipo de solicitud.
5. `expires_at` no vencido (para contextos de usuario).
6. `auth_level` suficiente para la operación solicitada.
7. El `tenant_id` del contexto coincide con el tenant del recurso solicitado.

Un contexto inválido o ausente resulta en rechazo inmediato con código de error apropiado
(`UNAUTHENTICATED` o `PERMISSION_DENIED` en gRPC) sin revelar detalles internos.

---

## 5. Formato de transporte

El contexto se transmite como metadatos gRPC (headers) o como campo dedicado en el mensaje
Protobuf, según el contrato del módulo. La decisión concreta de formato se toma al implementar
los contratos Protobuf en la subfase 1.3, respetando ADR-0004 (W3C Trace Context) y ADR-0005
(contratos Protobuf versionados).

No se usa un campo genérico de tipo `Any` ni se serializa el contexto como JSON dentro de
un campo string.

---

## 6. Estado de implementación

Diseño aprobado. No existen structs Rust, archivos `.proto`, middleware ni código de validación.
La implementación comienza en subfase 1.3.
