# Modelo de identidad y autorización

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 2.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0008, ADR-0011, ADR-0020, ADR-0021, ADR-0028
**Documentos relacionados:**
- [Contrato de contexto autenticado](./authenticated-context-contract.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Seguridad de contraseñas y autenticación](./password-and-authentication.md)

---

## 1. Propósito

Define la estructura de identidades, autorización y propagación de contexto en los cuatro
procesos. Es diseño, no implementación ejecutable. Los SQL históricos existentes son la
referencia del modelo de datos de los módulos; no se deben ignorar ni reemplazar por un modelo
paralelo.

## 2. Tipos de identidad

### 2.1 Identidad de usuario de tenant

Representa a un ser humano autenticado que opera dentro de un tenant.

| Atributo | Descripción |
|---|---|
| `user_id` | UUIDv7; propietario: IDENTITY |
| `tenant_id` | UUIDv7 del tenant activo validado por IDENTITY |
| `email` | Identificador de login; no es clave de negocio |
| `roles` | Roles vigentes asignados por IDENTITY |
| `permissions` | Permisos derivados de roles y evaluación ABAC del módulo |
| `auth_level` | Normal / MFA_verified / Reauth_required |
| `session_id` | UUIDv7 de sesión vigente en IDENTITY |
| `issued_at` / `expires_at` | Vigencia de la aserción |

**Propietario exclusivo:** módulo IDENTITY en Public Backend. Public BFF consume la aserción
emitida por IDENTITY y la propaga sin alterar claims ni privilegios. Admin BFF no autentica
operadores de plataforma contra IDENTITY.

### 2.2 Identidad de servicio

Representa a un proceso, worker o integración que actúa sin intervención humana directa.
Cada proceso y worker tiene identidad propia por entorno. No se comparten credenciales entre
procesos ni entornos. La identidad de servicio no equivale a permiso universal.

### 2.3 Identidad de operador de plataforma

Identidad de empleados internos que administran la plataforma SaaS.

- Propietario exclusivo: módulo PLATFORM en Admin Platform Backend.
- Admin BFF consume la autoridad de PLATFORM; no autentica estos operadores contra IDENTITY.
- No comparte tablas, credenciales, sesiones ni tokens con usuarios de tenant.
- La aserción de contexto de operador la emite PLATFORM con su propio issuer y clave KMS.
- El acceso excepcional a datos operativos de tenant es temporal, justificado, limitado,
  auditable y revocable.
- Public Backend solo acepta esa aserción para una operación de negocio cuando el módulo
  propietario valida la concesión excepcional; no existe acceso global automático.

## 3. Modelo de autorización RBAC + ABAC

### 3.1 Principios

- **Autorización en el módulo propietario:** Public BFF verifica sesión tenant con IDENTITY;
  Admin BFF verifica sesión de operador con PLATFORM. Ambos propagan una aserción firmada sin
  alterar claims; no deciden acceso a datos.
- **RBAC** asigna conjuntos de permisos a roles administrables.
- **ABAC** evalúa atributos de actor, tenant, organización, empresa, marca, sucursal, recurso,
  relación, estado, importe, canal, dispositivo y nivel de autenticación.
- **Denegar por defecto:** toda acción no permitida explícitamente está denegada.
- **IDs de cliente nunca son autoridad:** tenant, usuario, rol o permiso enviados por cliente
  se ignoran para autorización; solo vale el contexto autenticado validado.
- Firma válida no equivale a autorización: el módulo propietario toma la decisión final.

### 3.2 Jerarquía de ámbito

Plataforma → Tenant → Grupo empresarial → Empresa legal → Marca → Sucursal → Área/Estación/Caja.

Un permiso no se hereda automáticamente a niveles inferiores salvo que la política del módulo
lo establezca. Un administrador de tenant no obtiene acceso a otros tenants ni a plataforma.

### 3.3 Acciones de alto impacto

Pueden exigir MFA/reautenticación reciente, segunda aprobación, motivo registrado en AUDIT y
ventana temporal limitada. Aplica a credenciales, administradores, exportaciones masivas,
anulaciones de pagos, cambios fiscales y acceso excepcional de soporte.

## 4. Separación plataforma / tenant

| Dimensión | PLATFORM (Admin Platform Backend) | Módulos de negocio (Public Backend) |
|---|---|---|
| Propietario de identidades | Operadores SaaS | IDENTITY — usuarios tenant |
| Autoridad emisora | PLATFORM | IDENTITY |
| BFF consumidor | Admin BFF | Public BFF |
| Base de datos | Schema propio platform | Schemas propios por módulo |
| Acceso entre procesos | Contratos gRPC + mTLS + contexto firmado | Contratos gRPC + mTLS + contexto firmado |

No se duplican tablas de usuarios, sesiones ni permisos. Una operación administrativa sobre
un dominio de negocio se ejecuta en el módulo propietario de Public Backend; PLATFORM no
adquiere propiedad de esos datos.

## 5. Sesiones, revocación y propagación

- Access tokens de corta duración; refresh tokens rotatorios y almacenados solo como hash.
- Reutilización de refresh token revoca la familia de sesión.
- Cambio de contraseña, recuperación o compromiso invalida sesiones activas.
- Cambios de roles/membresía se propagan dentro de un plazo definido y probado.
- Las cachés tienen alcance, versión, TTL e invalidación explícitos; un fallo nunca concede
  permiso. Operaciones críticas consultan fuente autoritativa.
- El contexto se propaga en llamadas gRPC como aserción firmada. Nunca se transmite como
  credencial activa en NATS Core o JetStream.
- Emisor, audiencia, expiración, firma, mTLS y rotación se rigen por el contrato de contexto
  y ADR-0028.

## 6. Workers y consumidores

Cada worker tiene identidad de servicio propia, valida mensajes y contexto antes de operar,
y no hereda permisos humanos. No existe bypass por ser interno. El módulo propietario autoriza
la operación y la idempotencia se verifica antes de ejecutar el efecto.

## 7. Estado de diseño e implementación

El repositorio contiene SQL históricos de PLATFORM e IDENTITY con estructuras de datos de
identidad/seguridad, incluidas tablas de credenciales, sesiones, roles y DDL RLS en determinadas
tablas. Son la base de datos diseñada para los módulos y deben conservarse como referencia
durante su traslado a las rutas canónicas y las correcciones futuras.

La presencia de SQL en Git no demuestra que las migraciones estén aplicadas en una instancia,
que los roles runtime/migrator estén provisionados ni que los flujos sean operativos. Aún no
existen flujos ejecutables completos de autenticación/autorización, emisión/verificación de
aserciones, middleware, contratos gRPC generados ni pruebas automatizadas. No se deben
recrear tablas ni modificar ahora los SQL históricos. Su traslado y correcciones requerirán
tareas autorizadas posteriores, manteniendo trazabilidad.
