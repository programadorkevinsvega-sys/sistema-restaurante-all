# Modelo de identidad y autorización

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0008, ADR-0011, ADR-0020, ADR-0021, ADR-0023
**Documentos relacionados:**

- [Contrato de contexto autenticado](./authenticated-context-contract.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Seguridad de contraseñas y autenticación](./password-and-authentication.md)
- [Acceso privilegiado y soporte excepcional](./privileged-access-and-exceptional-support.md)
- [Sesiones, revocación y autenticación reforzada](./session-revocation-and-step-up-authentication.md)

---

## 1. Propósito

Este documento define la estructura de identidades, el modelo de autorización y las reglas de
propagación de contexto que se aplicarán en todos los procesos de Restaurant OS. Es un diseño;
no implementa código, tablas, tokens ni middleware.

---

## 2. Tipos de identidad

### 2.1 Identidad de usuario

Representa a un usuario de tenant autenticado. Los operadores internos SaaS son una categoría humana separada cuya autoridad es PLATFORM.

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
Public BFF consume la aserción emitida por IDENTITY y la propaga sin alterar claims ni privilegios. Admin BFF no autentica operadores de plataforma contra IDENTITY.

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

- Propietario exclusivo: módulo PLATFORM en Admin Platform Backend.
- Admin BFF consume la autoridad de PLATFORM; no autentica estos operadores contra IDENTITY.
- No comparte tablas, credenciales, sesiones ni tokens con usuarios de tenant.
- La aserción de contexto de operador la emite PLATFORM con su propio issuer y clave KMS.
- El acceso excepcional a datos operativos de tenant es temporal, justificado, limitado, auditable y revocable; una aserción firmada de PLATFORM no concede acceso por sí sola.
- Public Backend solo acepta esa aserción para una operación de negocio cuando el módulo propietario valida la concesión excepcional; no existe acceso global automático.
- El ciclo de vida, alcance, aprobación, expiración, revocación y auditoría de esas concesiones se especifica en [Acceso privilegiado y soporte excepcional](./privileged-access-and-exceptional-support.md).

---

## 3. Modelo de autorización RBAC + ABAC

### 3.1 Principios

- **Autorización en el módulo propietario:** el módulo dueño del recurso aplica la decisión final.
  Public BFF verifica la sesión tenant con IDENTITY y Admin BFF verifica la sesión de operador con PLATFORM. Ambos propagan una aserción firmada sin alterar claims; no toman decisiones de acceso a datos.
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
- Estado autoritativo de sesión en PostgreSQL bajo la autoridad propietaria: IDENTITY para usuarios tenant y PLATFORM para operadores SaaS; nunca en memoria local de una réplica.
- IDENTITY revoca la familia de refresh tokens cuando detecta reutilización; la estrategia de PLATFORM debe respetar su modelo SQL existente y no asumir campos de familia que no estén definidos.
- La vigencia de una sesión, la validez de una aserción firmada y una evidencia de autenticación reforzada se comprueban por separado.

### Revocación

- Cambio de contraseña, recuperación o detección de compromiso invalida sesiones activas.
- Cambios de rol o membresía se propagan dentro de un plazo definido y probado.
- Las cachés de autorización tienen alcance, versión y TTL explícitos.
- Un fallo de Redis nunca convierte una denegación en permiso; para operaciones críticas
  se consulta la fuente autoritativa.

### Propagación entre procesos

El contexto autenticado se propaga en cada llamada gRPC como parte del contrato del mensaje.
Nunca se transmite en NATS Core ni en eventos JetStream como credencial activa.
La especificación de emisores, audiencia, firma, mTLS, claves y propagación está en
[Contrato de contexto autenticado](./authenticated-context-contract.md) y ADR-0023. El ciclo
de vida, la revocación, la invalidación de aserciones y la autenticación reforzada se detallan
en [Sesiones, revocación y autenticación reforzada](./session-revocation-and-step-up-authentication.md).

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

Diseño aprobado. El repositorio contiene migraciones SQL históricas con estructuras de datos de PLATFORM e IDENTITY, incluidas tablas relacionadas con credenciales, sesiones, roles y políticas RLS en determinadas tablas. Esos archivos son el diseño SQL existente de los módulos; no prueban que las migraciones estén aplicadas, que los roles runtime/migrator estén provisionados ni que los flujos funcionales existan.

Aún no existen flujos ejecutables completos de autenticación/autorización, emisión/verificación de aserciones firmadas, middleware, contratos gRPC generados ni pruebas automatizadas. No se deben recrear tablas ni diseñar un modelo paralelo ignorando los SQL históricos. Su traslado a las rutas canónicas y las correcciones de compatibilidad se realizarán posteriormente mediante tareas autorizadas, sin reescribir migraciones históricas.
