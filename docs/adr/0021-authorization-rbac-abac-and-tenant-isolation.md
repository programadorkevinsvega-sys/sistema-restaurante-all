# ADR-0021: Autorización, RBAC/ABAC y aislamiento multi-tenant

- Estado: **Proposed**
- Fecha: 2026-11-25
- Ámbito: autorización de usuarios y servicios sobre operaciones y recursos de plataforma y negocio.
- Complementa: ADR-0007, ADR-0008, ADR-0009, ADR-0011, ADR-0014, ADR-0015, ADR-0016 y ADR-0020.
- Aprobación: pendiente de aprobación explícita.

## Contexto

Autenticación identifica al actor; autorización decide qué puede hacer. Un usuario legítimo puede intentar acceder a recursos ajenos, operar fuera de su sucursal, elevar privilegios o reutilizar permisos revocados. Conocer un UUID o URL no concede acceso. Los controles deben cubrir HTTP, gRPC, workers, exportaciones, descargas, WebSockets e integraciones.

## Decisión propuesta

### 1. Autorizar en el backend propietario

Toda lectura, creación, modificación, eliminación, exportación, descarga y acción de negocio se autoriza en servidor. El módulo propietario del recurso aplica la decisión final porque conoce su dominio, relaciones, estado e invariantes. El BFF puede verificar sesión y transmitir contexto validado, pero no sustituye esa autorización. Ningún módulo consulta tablas ajenas para resolver permisos.

### 2. Modelo combinado RBAC y ABAC

Adoptar RBAC para asignar conjuntos administrables de permisos a roles y ABAC para evaluar atributos/contexto: actor, tenant, organización, empresa legal, marca, sucursal, recurso, propietario, relación, estado, importe, canal, dispositivo, autenticación reforzada y contexto de riesgo.

No se impone un catálogo universal de roles ni una matriz compartida. Cada módulo define los permisos de sus operaciones y recursos. Las asignaciones y membresías permanecen bajo el ownership de los módulos responsables.

### 3. Contexto confiable

- Identidad y tenant se derivan de sesión, credencial o identidad de servicio autenticada y validada.
- tenant_id, user_id, role, permissions, owner_id o equivalentes enviados por el cliente nunca son autoridad.
- Si el cliente selecciona un tenant/ámbito, el servidor verifica membresía y permiso vigente.
- El contexto se transmite por contratos internos con procedencia e integridad.
- Actor humano e identidad del servicio se conservan como identidades distintas.
- Workers revalidan contexto y autorización al ejecutar; no heredan permisos ilimitados.
- trace_id, correlation_id, saga_id y demás identificadores no son credenciales.

### 4. BOLA/IDOR y pertenencia

Antes de operar un recurso, comprobar permiso para la acción, pertenencia al tenant/ámbito, relación actor-recurso, estado permitido y ausencia de revocación. Aplicar también a subrecursos, adjuntos, documentos, exportaciones, búsquedas y referencias indirectas. No basta validar solo el objeto principal.

Las respuestas no deben facilitar enumeración de recursos; la evidencia interna sí debe distinguir denegaciones y causas sin filtrar datos al cliente.

### 5. Separación plataforma/tenant

- Privilegios de administración SaaS pertenecen a PLATFORM.
- Administradores de tenant no obtienen privilegios de otros tenants ni de plataforma.
- Administradores de plataforma no reciben acceso irrestricto automático a datos operativos.
- Soporte excepcional es temporal, justificado, limitado, auditable y revocable; puede requerir segunda aprobación.
- Operaciones administrativas sobre dominios de negocio se ejecutan por contratos de sus módulos propietarios en Public Backend.
- No duplicar usuarios, membresías ni tablas de identidad entre procesos.

### 6. Acciones de alto impacto

Según riesgo, exigir MFA reciente, reautenticación, doble aprobación, motivo, límite de importe o ventana temporal. Aplicable a gestión de administradores, credenciales, exportaciones masivas, cambios fiscales y operaciones financieras sensibles. Umbrales y roles concretos se definen por dominio.

### 7. Revocación y caché

Cambios de rol, membresía, permisos y estado deben propagarse dentro de un plazo definido y probado. Sesiones/tokens no retienen privilegios revocados indefinidamente. Toda caché de autorización tendrá alcance, versión, expiración e invalidación. Fallos de Redis o caché nunca convierten denegación en permiso. Para operaciones críticas se consulta fuente autoritativa o versión vigente. Redis respeta ADR-0016 y no es fuente de autorización.

### 8. Identidades de servicio

Cada proceso, worker e integración tendrá identidad separada por entorno/función. Autenticación de servicio no equivale a permiso universal: se autorizan métodos gRPC, operaciones, subjects NATS y recursos concretos. Prohibidas credenciales administrativas compartidas para uso rutinario.

### 9. Pruebas obligatorias

Probar acceso cruzado entre usuarios, tenants y sucursales; escalada vertical; privilegios plataforma/tenant; permisos revocados con sesiones/cachés existentes; adjuntos, búsquedas, exportaciones y rutas alternativas; workers con contexto falso/ausente/vencido; concurrencia entre revocación y operación; denegación ante fallos de autorización.

## Alternativas consideradas

RBAC puro se rechaza como único modelo por no expresar contexto/propiedad. ABAC puro se rechaza como único modelo por dificultar la administración de roles recurrentes. Autorización solo en BFF y UUID como control de acceso se rechazan. No se crea tabla global compartida de permisos.

## Consecuencias

Reduce BOLA/IDOR, escaladas y filtraciones. Añade verificaciones, modelado de permisos y cuidado con cachés; requiere consistencia y pruebas entre módulos.

## Límites

No selecciona motor comercial/biblioteca, no define todos los roles ni umbrales, y no crea tablas, schemas, claims ejecutables, endpoints ni cambios SQL.

## Plan futuro

Inventariar acciones/recursos; definir contratos de contexto; modelar roles y atributos por dominio; verificar cada caso de uso propietario; diseñar revocación/versiones; añadir pruebas multi-tenant; instrumentar denegaciones y accesos excepcionales.

## Estado de implementación

Proposed. No implementa RBAC/ABAC, middleware, políticas, permisos, tablas, pruebas ni infraestructura.
