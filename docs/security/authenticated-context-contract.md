# Contrato de contexto autenticado

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 2.0
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0004, ADR-0007, ADR-0008, ADR-0021, ADR-0023
**Documentos relacionados:**

- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Sesiones, revocación y autenticación reforzada](./session-revocation-and-step-up-authentication.md)

---

## 1. Propósito y límites

Define los contextos autenticados de usuario tenant, operador de plataforma y servicio, y las
reglas de emisión, firma, propagación y validación entre los cuatro procesos.

Este contrato es un diseño. No genera código Rust, archivos Protobuf, middleware, claves KMS,
certificados ni infraestructura. Las estructuras SQL históricas existentes son referencia del
modelo de datos de cada módulo; este documento no las reemplaza ni autoriza modificarlas.

## 2. Autoridades de identidad y emisión

| Actor | Autoridad propietaria y emisora | Proceso propietario | Consumidor inicial |
|---|---|---|---|
| Usuario de tenant | IDENTITY | Public Backend | Public BFF |
| Operador interno SaaS | PLATFORM | Admin Platform Backend | Admin BFF |
| Proceso/worker | Identidad de workload autorizada | Proceso propietario de la carga | Proceso receptor |

- IDENTITY es la única autoridad de usuarios, credenciales, sesiones y roles de tenant.
- PLATFORM es la autoridad de operadores internos y sus privilegios SaaS.
- Admin Platform Backend no crea ni valida credenciales de usuarios de tenant por cuenta propia.
- Public Backend no crea ni valida identidades de operadores de plataforma por cuenta propia.
- Public BFF autentica usuarios de tenant mediante IDENTITY; Admin BFF autentica operadores
  mediante PLATFORM. Los BFF consumen aserciones de la autoridad correspondiente: no inventan,
  amplían ni firman privilegios.
- La autoridad emisora firma el contexto solo después de autenticar al actor y comprobar el
  estado de sesión, revocación, membresía y privilegios aplicables.

Un contexto de operador PLATFORM que solicite una operación sobre datos de negocio no obtiene
acceso por el mero hecho de estar firmado. El módulo propietario en Public Backend verifica
además que exista una concesión excepcional, temporal, justificada, acotada y auditable.

## 3. Tipos de contexto

### 3.1 Contexto de usuario de tenant

| Campo | Tipo | Obligatorio | Semántica |
|---|---|---|---|
| `actor_type` | enum | Sí | `human_tenant` |
| `actor_id` | UUIDv7 | Sí | Identificador del usuario propietario de IDENTITY |
| `tenant_id` | UUIDv7 | Sí | Tenant activo validado por IDENTITY |
| `session_id` | UUIDv7 | Sí | Sesión vigente en IDENTITY |
| `auth_level` | enum | Sí | `normal`, `mfa_verified`, `reauth_verified` |
| `roles` | string[] | Sí | Roles vigentes asignados por IDENTITY |
| `scope` | objeto/lista tipada | Sí | Ámbitos vigentes: grupo, empresa, marca, sucursal y recurso |
| `issued_at` | timestamp UTC | Sí | Emisión |
| `not_before` | timestamp UTC | Sí | Inicio de validez |
| `expires_at` | timestamp UTC | Sí | Fin de validez; corta duración |
| `issuer` | identificador | Sí | Autoridad IDENTITY |
| `audience` | identificador | Sí | Proceso/servicio destinatario autorizado |
| `kid` | string | Sí | Identificador de clave pública de verificación |
| `jti` | identificador único | Sí | Identificador de aserción para detección de replay cuando aplique |

### 3.2 Contexto de operador de plataforma

Usa la misma envoltura criptográfica, pero con `actor_type = human_platform`,
`actor_id` y `session_id` propiedad de PLATFORM, `issuer = PLATFORM`, roles y ámbitos
emitidos exclusivamente por PLATFORM, y `audience` limitado al proceso receptor concreto.
`tenant_id` estará ausente para operaciones globales de plataforma; para acceso excepcional
debe identificar el tenant exacto y la concesión que lo autoriza.

Los roles `platform_*` nunca se aceptan como roles de tenant ni son asignables desde IDENTITY.

### 3.3 Contexto de servicio

| Campo | Tipo | Obligatorio | Semántica |
|---|---|---|---|
| `actor_type` | enum | Sí | `service` |
| `service_id` | string | Sí | Identidad de workload/proceso/worker |
| `service_env` | enum/string | Sí | Entorno aislado |
| `permitted_operations` | string[] | Sí | Métodos/operaciones explícitamente autorizados |
| `tenant_id` | UUIDv7 | Condicional | Solo si la tarea está acotada a un tenant y su procedencia fue validada |
| `issuer`, `audience`, `issued_at`, `not_before`, `expires_at`, `kid`, `jti` | según envoltura | Sí | Procedencia, destino y vigencia |

Para un contexto de servicio, `issuer` identifica al proceso/worker propietario de esa
identidad. La firma usa una clave KMS asignada a ese workload y entorno; IAM permite invocar
solo la clave y operación correspondientes. IDENTITY y PLATFORM no emiten permisos de servicio
en nombre de workloads ajenos.

La identidad de servicio no equivale a permiso universal. El certificado mTLS identifica el
workload que conecta; la aserción firmada identifica el actor y el alcance autorizado. Ambos
deben corresponder a identidades permitidas para la comunicación.

### 3.4 Metadatos de correlación y datos prohibidos

| Campo | Formato | Uso |
|---|---|---|
| `trace_id` | W3C Trace Context | Correlación distribuida; nunca autoridad |
| `request_id` | UUIDv7 | Identificador único de solicitud |
| `saga_id` | UUIDv7, opcional | Saga en curso cuando aplique |
| `idempotency_key` | UUIDv7 o formato contractual, opcional | Idempotencia de operaciones con efecto |

Estos metadatos se propagan o regeneran según el contrato de trazabilidad/idempotencia. No
pueden alterar el actor, tenant, roles, ámbitos, emisor, audiencia ni vigencia de la aserción.

### 3.5 Datos prohibidos

`trace_id`, `request_id`, `saga_id` e `idempotency_key` son metadatos operativos, no
credenciales ni sustitutos de autorización. No se aceptan como autoridad tenant, user, roles
o permisos suministrados en el payload del cliente.

Nunca se incluyen contraseñas, hashes/salts, access/refresh tokens en claro, secretos MFA,
códigos de recuperación, datos completos de pago, datos personales sensibles innecesarios,
secretos de infraestructura ni claves privadas.

## 4. Firma, claves y transporte

1. Las aserciones que crucen fronteras de proceso se firman por su autoridad emisora.
2. mTLS es obligatorio para comunicación proceso-a-proceso. Se valida cadena, vigencia,
   identidad del certificado y correspondencia con el workload esperado.
3. Firma de contexto y mTLS son controles complementarios; ninguno sustituye al otro.
4. AWS KMS mantiene las claves privadas de firma. Se separan por autoridad emisora, entorno
   y propósito; nunca se exportan claves privadas a los procesos.
5. Los receptores obtienen las claves públicas confiables y verifican localmente la firma.
   No se invoca KMS Verify en cada solicitud.
6. Cada clave pública se identifica mediante `kid`. Los receptores mantienen un conjunto
   versionado de claves confiables y rechazan claves desconocidas o retiradas.
7. La rotación asimétrica es controlada: publicar nueva clave, distribuir la clave pública,
   aceptar temporalmente clave anterior y nueva, cambiar el emisor y retirar la anterior
   después de expirar las aserciones válidas y el margen de reloj/revocación.
8. Secrets Manager almacena secretos operativos que deban existir; no sustituye KMS.
   IAM concede a cada workload permisos mínimos y temporales para invocar solo las operaciones
   KMS que necesita.
9. La gestión concreta de certificados mTLS se define en 0.7.
10. Algoritmo, serialización canónica, tamaño máximo, formato de firma y distribución de
    claves se fijarán en contratos técnicos antes de implementar.

## 5. Reglas de propagación

### 5.1 Cliente → BFF → autoridad emisora → backend

- Public BFF autentica usuarios de tenant mediante IDENTITY.
- Admin BFF autentica operadores internos mediante PLATFORM.
- La autoridad emite la aserción después de validar actor, sesión, revocación, roles y ámbitos.
- El BFF la transmite al backend destinatario por mTLS sin modificar claims, ámbito, emisor,
  audiencia ni expiración.
- El BFF no transforma un contexto tenant en plataforma ni viceversa.

### 5.2 Backend → backend

El backend llamante presenta su identidad mTLS y propaga la aserción original sin cambiarla.
Puede añadir metadatos de correlación, pero nunca ampliar roles, tenant, audiencia, privilegios
ni vigencia. Si el destinatario requiere otra audiencia, la autoridad emisora produce una
aserción nueva; el llamante no re-firma.

### 5.3 Dentro del mismo backend

Los módulos pasan el contexto validado como parámetro explícito mediante contratos públicos.
El módulo propietario del recurso realiza la autorización final. No se usa estado global ni
thread-local implícito.

### 5.4 Workers y consumidores

Los eventos Outbox/JetStream no transportan una sesión humana como credencial activa. El worker
se autentica con su identidad de servicio, valida la procedencia del mensaje y reconstruye un
contexto de ejecución limitado. El tenant del mensaje es dato no confiable hasta contrastarlo
con la tarea autorizada y el recurso del módulo propietario. El worker no hereda roles humanos
ni privilegios ilimitados.

## 6. Validación obligatoria en cada receptor

1. Firma válida y `kid` confiable.
2. `issuer` permitido para el tipo de actor y la operación.
3. `audience` exacta para el receptor.
4. `issued_at`, `not_before` y `expires_at` válidos, con tolerancia de reloj acotada.
5. `jti` y controles anti-replay para operaciones que no admiten repetición.
6. Identidad mTLS del proceso llamante y autorización del método.
7. Tipo de actor y campos coherentes; no mezclar actor humano con servicio.
8. Vigencia de sesión, revocación y versión de roles/membresías según criticidad; una firma válida no revive una sesión revocada.
9. Cuando la operación lo exige, evidencia de autenticación reforzada vigente, vinculada al actor, sesión, tenant/ámbito, audiencia y operación; esa evidencia no concede permisos.
10. Tenant y ámbitos coherentes con el recurso concreto.
11. Autorización final en el módulo propietario, incluida cualquier concesión excepcional.

Un contexto inválido, expirado, con emisor/audiencia incorrectos, firma inválida o identidad
mTLS no autorizada se rechaza sin ejecutar efectos ni revelar detalles internos. Un fallo de
verificación o distribución de claves nunca se convierte en aceptación permisiva. La comprobación
de sesión/revocación y la evidencia de step-up siguen el diseño específico de
[Sesiones, revocación y autenticación reforzada](./session-revocation-and-step-up-authentication.md);
no se infieren de la firma ni del campo `auth_level` por sí solos.

## 7. Formato de transporte

El contexto se transporta mediante contrato tipado y versionado de Protobuf/metadatos gRPC,
conforme a ADR-0004 y ADR-0005. No se usa `Any`, JSON opaco ni un campo de negocio controlado
por el cliente como contenedor de autoridad.

## 8. Estado de implementación

Diseño aprobado. No existen todavía structs Rust, contratos Protobuf generados, middleware,
emisión/verificación de aserciones firmadas, claves KMS, distribución de claves, certificados
mTLS ni pruebas automatizadas de estos controles. La presencia de tablas y DDL históricos de
identidad y seguridad en `migrations/` no demuestra que las migraciones estén aplicadas ni que
los flujos de autenticación estén implementados. La implementación se planifica en las fases
del plan maestro después de completar los fundamentos correspondientes.
