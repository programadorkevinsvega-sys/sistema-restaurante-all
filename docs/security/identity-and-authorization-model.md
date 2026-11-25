# Modelo de identidad y autorización

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0008, ADR-0011, ADR-0020, ADR-0021
**Documentos relacionados:**

- [Contrato de contexto autenticado](./authenticated-context-contract.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Seguridad de contraseñas y autenticación](./password-and-authentication.md)

---

## 1. Propósito

Este documento define la estructura de identidades, el modelo de autorización y las reglas de
propagación de contexto que se aplicarán en todos los procesos de Restaurant OS. Es un diseño;
no implementa código, tablas, tokens ni middleware.

---

## 2. Tipos de identidad

### 2.1 Identidad de usuario

Representa a un ser humano autenticado que interactúa con el sistema a través de un BFF.

| Atributo | Descripción |
|---|---|
| `user_id` | UUIDv7; propietario: IDENTITY |
| `tenant_id` | UUIDv7 del tenant al que pertenece la sesión activa |
| `email` | Identificador de login; no es una clave de negocio |
| `roles` | Conjunto de roles asignados en el ámbito de la sesión |
| `permissions` | Conjunto derivado de roles + atributos ABAC evaluados |
| `auth_level` | Normal / MFA\_verified / Reauth\_required |
| `session_id` | UUIDv7 de la sesión activa |
| `issued_at` | Timestamp de emisión del access token |
| `expires_at` | Timestamp de expiración del access token |

**Propietario exclusivo:** módulo IDENTITY en Public Backend.
Los BFF no calculan ni almacenan estos atributos; los reciben del contrato de IDENTITY como
contexto validado y los propagan a los backends.

### 2.2 Identidad de servicio

Representa a un proceso, worker o integración que actúa sin intervención humana directa.

| Atributo | Descripción |
|---|---|
| `service_id` | Identificador del proceso/worker; ej. `public-backend`, `outbox-worker` |
| `service_env` | Entorno: `production`, `staging`, `development` |
| `permitted_operations` | Conjunto explícito de métodos gRPC, subjects NATS y operaciones autorizadas |
| `tenant_scope` | `all` para operadores de plataforma; `tenant_id` específico para workers acotados |

Cada proceso y worker tiene identidad propia por entorno. No se comparten credenciales entre
procesos ni entornos. La identidad de servicio no equivale a permiso universal.

### 2.3 Identidad de operador de plataforma

Identidad de los empleados internos que administran la plataforma SaaS.

- Propietario: módulo PLATFORM en Admin Platform Backend.
- No comparte tablas, sesiones ni tokens con usuarios de tenant.
- El acceso excepcional a datos operativos de un tenant es temporal, justificado, auditado y revocable.
- Se separa técnicamente de las identidades de IDENTITY para módulos de negocio.

---

## 3. Modelo de autorización RBAC + ABAC

### 3.1 Principios

- **Autorización en el módulo propietario:** el módulo dueño del recurso aplica la decisión final.
  Los BFF verifican sesión y propagan contexto; no toman decisiones de acceso a datos.
- **RBAC** asigna conjuntos de permisos a roles administrables.
- **ABAC** evalúa atributos de contexto para afinar la decisión: tenant, sucursal, recurso,
  relación actor-recurso, estado, importe, canal y nivel de autenticación.
- **Denegar por defecto:** toda acción no permitida explícitamente está denegada.
- **IDs de cliente nunca son autoridad:** `tenant_id`, `user_id`, `role` enviados en el payload
  del cliente se ignoran para decisiones de autorización; se usan solo los del contexto
  autenticado validado por el servidor.

### 3.2 Jerarquía de ámbito

```text
Plataforma
  └── Tenant
        └── Grupo empresarial
              └── Empresa legal
                    └── Marca
                          └── Sucursal
                                └── Área / Estación / Caja
```

Un permiso concedido en un nivel no se hereda automáticamente en niveles inferiores a menos
que la política del módulo lo defina explícitamente. Un administrador de tenant no obtiene
acceso a datos de otro tenant ni a privilegios de plataforma.

### 3.3 Evaluación de una solicitud

```text
1. ¿El actor tiene sesión/token válido y no revocado?           → Denegar si no
2. ¿El token pertenece al tenant solicitado?                    → Denegar si no
3. ¿El actor tiene el permiso para esta acción sobre este tipo? → Denegar si no
4. ¿El recurso concreto pertenece al tenant/ámbito del actor?   → Denegar si no (BOLA check)
5. ¿El estado del recurso permite esta acción?                  → Denegar si no
6. ¿Se requiere nivel de autenticación elevado (MFA/reauth)?    → Denegar si no satisfecho
7. Ejecutar la operación
```

Todos los pasos se ejecutan en el módulo propietario del recurso, no en el BFF.

### 3.4 Acciones de alto impacto

Requieren controles adicionales según el dominio:

- Reautenticación o verificación MFA reciente.
- Segunda aprobación para operaciones financieras por encima de umbrales (definidos por dominio).
- Motivo registrado en AUDIT.
- Ventana temporal limitada para el permiso elevado.

Aplica a: cambio de credenciales, gestión de administradores, exportaciones masivas, anulación de
pagos confirmados, cambios fiscales y acceso excepcional de soporte.

---

## 4. Separación plataforma / tenant

| Dimensión | PLATFORM (Admin Platform Backend) | Módulos de negocio (Public Backend) |
|---|---|---|
| Propietario de identidades | Operadores de plataforma | IDENTITY — usuarios de tenant |
| Base de datos | Schema `platform` propio | Schemas propios por módulo |
| Acceso entre ellos | Vía contratos gRPC | Vía contratos gRPC |
| Administrador de tenant | No obtiene privilegios de plataforma | Administra su propio tenant |
| Operador de plataforma | No obtiene acceso irrestricto a datos operativos | Acceso excepcional temporal y auditado |

No se duplican tablas de usuarios, sesiones ni permisos entre procesos.

---

## 5. Sesiones, revocación y propagación

### Sesiones

- Access tokens de corta duración (duración definida por política de tenant en IDENTITY).
- Refresh tokens con rotación; almacenados solo como hash.
- Detección de reutilización de refresh token: revocación de toda la familia de sesión.
- Expiración absoluta y por inactividad según política del tenant.
- Estado autoritativo de sesión en PostgreSQL (IDENTITY), no en memoria de réplica.

### Revocación

- Cambio de contraseña, recuperación o detección de compromiso invalida sesiones activas.
- Cambios de rol o membresía se propagan dentro de un plazo definido y probado.
- Las cachés de autorización tienen alcance, versión y TTL explícitos.
- Un fallo de Redis nunca convierte una denegación en permiso; para operaciones críticas
  se consulta la fuente autoritativa.

### Propagación entre procesos

El contexto autenticado se propaga en cada llamada gRPC como parte del contrato del mensaje.
Nunca se transmite en NATS Core ni en eventos JetStream como credencial activa.
La especificación exacta de campos y formato está en
[Contrato de contexto autenticado](./authenticated-context-contract.md).

---

## 6. Workers y consumidores

- Cada worker valida el contexto de tenant y actor antes de ejecutar cualquier operación.
- Un worker sin contexto válido rechaza el mensaje y registra el evento.
- Los workers tienen identidad de servicio propia; no heredan permisos del proceso principal.
- La autorización de un worker sobre una operación de negocio usa los mismos módulos
  propietarios que un usuario humano; no existe un bypass por ser interno.
- La idempotencia se verifica antes de ejecutar el efecto, no después.

---

## 7. Estado de implementación

Diseño aprobado. No existen en este momento:

- Crates de IDENTITY ni código de autenticación.
- Tokens, sesiones ni middleware.
- Tablas, roles PostgreSQL ni RLS implementados.
- Contratos gRPC de autenticación generados.

La implementación comienza en la subfase 1.3 — IDENTITY: usuarios, autenticación y sesiones,
previa satisfacción de las dependencias 0.4, 0.5 y 0.6.
