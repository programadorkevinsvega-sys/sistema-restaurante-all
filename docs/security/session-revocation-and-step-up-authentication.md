# Sesiones, revocación y autenticación reforzada

**Estado:** propuesta de diseño para revisión — subfase 0.4  
**Versión:** 1.0  
**Fecha:** 2026-11-25  
**Autoridad:** ADR-0008, ADR-0011, ADR-0020, ADR-0021 y ADR-0022  
**Propietarios:** IDENTITY (sesiones de usuarios tenant) y PLATFORM (sesiones de operadores SaaS)

**Documentos relacionados:**

- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Contrato de contexto autenticado](./authenticated-context-contract.md)
- [Seguridad de contraseñas y autenticación](./password-and-authentication.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Acceso privilegiado y soporte excepcional](./privileged-access-and-exceptional-support.md)

---

## 1. Propósito y límites

Esta especificación desarrolla el ciclo de vida de sesiones, la revocación de credenciales/contextos y la autenticación reforzada (*step-up authentication*) para acciones sensibles.

Es un diseño documental. No implementa endpoints, middleware, cookies, contratos Protobuf, tablas, migraciones, claves, infraestructura ni pruebas ejecutables. No modifica archivos SQL históricos.

La identidad autenticada, la aserción firmada entre procesos, la autenticación reforzada y una concesión excepcional de soporte son controles distintos. Ninguno sustituye a los demás.

## 2. Autoridad y separación de sesiones

| Actor | Autoridad exclusiva de sesión | Persistencia diseñada existente |
|---|---|---|
| Usuario de tenant | IDENTITY en Public Backend | `identity.user_sessions` |
| Operador interno SaaS | PLATFORM en Admin Platform Backend | `platform.admin_sessions` |

Reglas:

1. IDENTITY administra sesiones, credenciales, membresías y autenticación de usuarios tenant.
2. PLATFORM administra las sesiones y credenciales propias de operadores SaaS. No crea una segunda identidad tenant.
3. Una sesión de IDENTITY nunca autentica a un operador PLATFORM; una sesión PLATFORM nunca autentica a un usuario tenant.
4. Cada autoridad emite aserciones firmadas con issuer y audience propios. Los BFF consumen y transportan la autoridad correspondiente; no mantienen una autoridad de sesión paralela.
5. Cada sesión pertenece a un actor y a una autoridad. No se comparte, transfiere ni convierte entre actores, tenants o procesos.
6. El cambio de tenant exige volver a comprobar membresía, estado y permisos en IDENTITY y emitir un contexto correspondiente al tenant seleccionado. No se altera el tenant de una aserción existente.
7. Las identidades de servicio y workers no utilizan ni heredan sesiones humanas.

### 2.1 Correspondencia con el SQL histórico

La inspección read-only confirma que el SQL existente ya contempla:

- `identity.user_sessions`: `tenant_id`, `user_id`, `refresh_token_hash`, `token_family_id`, `mfa_verified_at`, `created_at`, `last_seen_at`, `expires_at`, `revoked_at` y `revoke_reason`.
- `platform.admin_sessions`: `admin_id`, `refresh_token_hash`, `created_at`, `last_seen_at`, `expires_at` y `revoked_at`.

Estas estructuras son el diseño de datos existente y deben reutilizarse cuando llegue la implementación. La diferencia de campos entre ambos modelos debe respetarse; no se presume que PLATFORM tenga `token_family_id` ni se crea ahora un esquema paralelo. La inspección del archivo SQL no acredita que la migración esté aplicada o que los flujos funcionen.

## 3. Ciclo de vida de una sesión

Los estados siguientes son estados lógicos del diseño, no una instrucción para agregar una columna o un enum SQL:

| Estado | Significado | ¿Puede autenticar nuevas operaciones? |
|---|---|---|
| Activa | No revocada y dentro de límites de inactividad y expiración absoluta | Sí, sujeto a autorización |
| Revocada | Invalidada explícitamente por logout, seguridad o administración autorizada | No |
| Expirada | Superó el límite de inactividad o expiración absoluta | No |
| Comprometida | Marcada como comprometida por evidencia de seguridad | No |
| Terminada | Cerrada por política o ciclo de vida del actor | No |

Una sesión solo es válida si la autoridad propietaria confirma que no está revocada/terminada y que no superó sus límites temporales. La expiración del access token y la vigencia de la sesión son verificaciones separadas.

### 3.1 Emisión y tokens

- Los access tokens/aserciones son de corta duración, firmados, con issuer, audience, actor, session_id, issued_at, not_before, expires_at, kid y jti según el contrato.
- Los refresh tokens son aleatorios, de alta entropía y se almacenan solo como hash.
- Los tokens no aparecen en URLs, logs, trazas, eventos, mensajes de error ni almacenamiento web accesible a JavaScript.
- Los tokens de refresh solo se aceptan en el endpoint y autoridad que los emitió.
- El BFF no renueva ni inventa autoridad por cuenta propia: canaliza la operación con la autoridad propietaria y entrega al navegador únicamente el mecanismo de sesión web que se apruebe conforme a ADR-0022.

### 3.2 Rotación y detección de reutilización

1. Cada refresh válido se consume una sola vez y produce un refresh token nuevo; el anterior queda inutilizable.
2. El consumo del token anterior, la creación del sucesor y la actualización del estado de sesión/familia se realizan atómicamente mediante una operación condicional/transaccional en la autoridad propietaria (IDENTITY o PLATFORM). La operación debe comprobar que el token sigue vigente y no consumido dentro de la misma unidad atómica.
3. La autoridad propietaria garantiza que como máximo una solicitud concurrente puede consumir el token y producir un sucesor válido. Una segunda solicitud que presente el token ya consumido se trata como reutilización, no como una rotación paralela.
4. La serialización en cliente/BFF puede reducir carreras, pero es solo una optimización; no constituye el control de seguridad ni sustituye la exclusión atómica en IDENTITY/PLATFORM.
5. En IDENTITY, una reutilización confirmada provoca la revocación de la familia identificada por el `token_family_id` existente. PLATFORM debe definir una respuesta equivalente compatible con su modelo existente, sin presuponer un campo `token_family_id` ni crear ahora estructuras SQL.
6. La respuesta al cliente no revela si el token era inexistente, expirado, revocado o reutilizado. La causa categorizada se conserva en auditoría.
7. Cualquier tolerancia a reintentos de red debe diseñarse como excepción acotada, idempotente, ligada a la misma operación y resistente a replay; no se presume ni habilita por defecto.

La revocación de familia en IDENTITY se apoya en el `token_family_id` ya presente en su diseño SQL. Para PLATFORM, la detección y respuesta a reutilización deben resolverse usando las estructuras existentes y un mecanismo compatible, sin atribuirle campos que no existen ni modificar SQL en esta subfase.

### 3.3 Expiración por inactividad y absoluta

- IDENTITY aplica los valores de `session_idle_timeout_minutes` y `session_absolute_timeout_hours` de la política del tenant existente, con actualización autoritativa de actividad y sin extender la expiración absoluta por uso.
- Los límites por tenant no pueden superar los límites de seguridad globales que se aprueben para el producto.
- PLATFORM debe aplicar límites de inactividad y absolutos para operadores SaaS, pero sus valores y ubicación de configuración no se inventan ni se copian de la política tenant.
- Una sesión expirada no se reactiva mediante refresh; el actor debe autenticarse de nuevo.
- La hora del servidor es la autoridad para expiración. No se confía en relojes ni fechas suministrados por el cliente.

## 4. Revocación

### 4.1 Eventos que requieren revocación

La autoridad propietaria revoca una sesión o familia de sesiones, según el alcance del evento, ante:

- logout de la sesión actual;
- logout de todas las sesiones solicitado por el actor;
- cambio o recuperación de contraseña;
- compromiso confirmado o sospechado de credenciales/sesión;
- reutilización de refresh token;
- desactivación, bloqueo o terminación de la cuenta;
- cambio de credenciales MFA que requiera invalidar sesiones;
- revocación de un factor de autenticación cuando la política de riesgo lo exija;
- cambio de privilegios, roles o membresía que no deba conservarse en sesiones/contextos ya emitidos;
- decisión de seguridad o administrativa autorizada.

La política distingue revocación de una sesión concreta, de una familia de refresh tokens y de todas las sesiones del actor. La autoridad registra el alcance y el motivo categorizado.

### 4.2 Invalidación de access tokens y aserciones ya emitidas

Una firma válida y una fecha `expires_at` futura no bastan para conservar autoridad después de revocar la sesión o los privilegios.

- Los receptores deben comprobar vigencia de sesión y versión de permisos/roles conforme a la criticidad de la operación, usando un contrato verificable con la autoridad propietaria.
- La corta duración del access token limita la exposición, pero no sustituye la propagación de revocación.
- `jti` permite identificar una aserción y apoyar controles anti-replay; por sí solo no revoca una sesión ni todas sus aserciones.
- Las cachés de estado/autorización deben tener ámbito, versión, expiración e invalidación explícitos. Una entrada obsoleta no puede mantener un permiso más allá del SLA aprobado.
- Redis es caché, no fuente autoritativa. Su indisponibilidad nunca convierte una denegación en permiso.
- Las operaciones críticas fallan cerradas cuando no puede comprobarse la sesión, la revocación o la versión de privilegios requerida.
- Los eventos NATS pueden notificar invalidaciones, pero no son la única garantía de revocación; el receptor debe poder detectar estado obsoleto aun si se pierde una notificación.
- Las sesiones y sus credenciales no se propagan como credenciales activas en NATS Core ni JetStream.

### 4.3 Propagación entre procesos y BFF

1. IDENTITY y PLATFORM son las fuentes autoritativas separadas para sus respectivos actores.
2. La autoridad emite la aserción después de comprobar el estado actual de sesión, actor, membresía y privilegios.
3. Los BFF validan la sesión en su frontera según el contrato, mantienen las protecciones de cookie/CSRF de ADR-0022 y propagan la aserción sin ampliar claims.
4. El backend/módulo propietario valida la aserción, identidad mTLS, sesión/versión cuando corresponda y autorización final.
5. Cerrar sesión invalida la sesión en su autoridad, limpia la cookie/estado privado del navegador y hace que los nuevos requests sean rechazados incluso si el navegador conserva una copia antigua de la cookie.
6. Los BFF no usan una sesión local en memoria como fuente de verdad ni mantienen tokens de larga duración en localStorage/sessionStorage.
7. El mecanismo concreto de introspección, versión de sesión, invalidación y caché debe quedar definido en contratos versionados antes de implementar; no se introduce un servicio central con acceso a todos los schemas.

### 4.4 SLA y comportamiento ante fallos

El SLA máximo de propagación de revocación debe medirse de extremo a extremo: autoridad emisora, cachés, BFF, llamadas gRPC, backend receptor y workers. Debe cubrir revocación de sesión, familia, rol/membresía y concesión de soporte.

No se fija un número sin análisis de riesgo, latencia, topología y pruebas. Antes de producción se debe aprobar un límite cuantificado y demostrarlo bajo concurrencia, partición de red, caída de Redis, retraso/pérdida de eventos y reinicio de procesos.

Si la autoridad no está disponible:

- no se emiten ni renuevan sesiones;
- las operaciones críticas que requieren estado vigente se deniegan;
- ningún receptor extiende indefinidamente una decisión cacheada;
- las operaciones no críticas solo pueden usar una política de caché degradada si su máximo de antigüedad está explícitamente aprobado y probado.

## 5. Elevación de autenticación (*step-up*)

### 5.1 Diferencia entre autenticación y autorización

La elevación de autenticación demuestra que el actor completó recientemente un factor o reautenticación más fuerte. No agrega roles, permisos, tenant, sucursales, recursos ni privilegios.

- RBAC/ABAC sigue determinando si el actor puede ejecutar la acción.
- El módulo propietario sigue comprobando recurso, ámbito, estado e invariantes.
- La elevación no sustituye una segunda aprobación humana, una concesión de soporte ni una regla de doble control.
- Un actor sin permiso no obtiene permiso por completar MFA.

### 5.2 Cuándo exigirla

La matriz de acciones de cada módulo clasificará las operaciones que requieren:

- autenticación normal;
- MFA reciente;
- reautenticación reciente;
- MFA más segunda aprobación;
- concesión excepcional independiente.

La clasificación debe incluir, como mínimo, acciones de alto impacto ya señaladas en ADR-0011/0021: gestión de credenciales y administradores, cambios de roles/permisos, exportaciones masivas, cambios fiscales, anulaciones/reembolsos sensibles y acciones de soporte privilegiado. La lista final y umbrales pertenecen al módulo/operación y requieren revisión de riesgo.

### 5.3 Flujo de elevación

1. El módulo propietario de la operación determina autoritativamente si la acción exige MFA o reautenticación, conforme a su política de riesgo y a la matriz de autorización. El BFF puede iniciar la experiencia de usuario y transportar solicitudes/respuestas, pero no decide el requisito, no amplía claims ni concede privilegios.
2. La autoridad propietaria de la sesión (IDENTITY o PLATFORM) inicia un challenge asociado a la sesión actual y al actor autenticado.
3. El actor completa el factor permitido (por ejemplo, TOTP o WebAuthn) o reautenticación fuerte. No se aceptan códigos reutilizados, factores revocados ni respuestas fuera de ventana.
4. La autoridad verifica el factor, rota el identificador de sesión conforme a ADR-0022, invalida el identificador anterior y emite una nueva aserción de contexto vinculada al identificador nuevo. La evidencia step-up se vincula a ese mismo identificador nuevo.
5. El backend/módulo propietario valida la evidencia firmada y vuelve a evaluar RBAC/ABAC, tenant, recurso, acción, estado y cualquier aprobación adicional.
6. La evidencia solo sirve para el propósito, ámbito y ventana para los que fue emitida. No se convierte en una elevación permanente de la sesión.
7. Las solicitudes que presenten el identificador/contexto anterior después de completar el step-up se rechazan. Al terminar la ventana, cambiar de tenant/sesión o revocar el factor/sesión, se exige una nueva elevación cuando la política lo requiera.

### 5.4 Vinculación mínima de la evidencia

La evidencia de step-up será una aserción independiente, firmada por IDENTITY o PLATFORM según la autoridad de la sesión, y transportada sin alteración por el BFF. No se considera demostrada por el valor `auth_level` del contexto principal. El receptor valida su firma y los siguientes campos mínimos:

- `issuer` y `audience` exactos;
- `actor_id` y `actor_type`;
- `session_id` nuevo, posterior a la rotación;
- `tenant_id` y scope exactos cuando apliquen;
- nivel alcanzado (`mfa_verified` o `reauth_verified`) y método/factor utilizado;
- instante de autenticación (`auth_time`);
- operación/recurso o clase de acciones para la que se emitió;
- `issued_at`, `not_before` y `expires_at`;
- `jti` único y referencia al challenge consumido para anti-replay;
- referencia de correlación/auditoría.

El receptor comprueba que la evidencia pertenece al mismo actor, autoridad, sesión nueva, tenant/scope, audiencia y operación de la solicitud. La autoridad emisora debe garantizar que el challenge y su `jti` no se consuman más de una vez para operaciones no repetibles; el receptor aplica el control anti-replay correspondiente. La revocación/expiración de la sesión invalida la evidencia aunque su firma y vencimiento sigan siendo válidos. `auth_level` en el contexto principal es solo un indicador de nivel declarado para esa aserción; nunca sustituye la evidencia firmada ni la comprobación de sesión.

La evidencia no debe incluir secretos MFA, códigos, credenciales ni datos biométricos. El formato tipado y versionado de esta aserción independiente se definirá en el contrato Protobuf antes de implementar; este documento no modifica contratos generados.

### 5.5 Alcance, duración y replay

- La elevación se limita al actor, sesión nueva posterior a la rotación, tenant y clase de operación indicados.
- Al completar step-up se rota el identificador de sesión conforme a ADR-0022; el identificador anterior queda invalidado y no puede autenticar ni autorizar solicitudes posteriores.
- La nueva aserción de contexto y la evidencia step-up quedan vinculadas al nuevo `session_id`; cualquier evidencia asociada al identificador anterior se rechaza.
- No se reutiliza entre sesiones, navegadores, actores, tenants ni autoridades.
- La duración máxima se define por clase de riesgo y debe ser la mínima que permita completar la operación.
- Para operaciones no repetibles o de alto impacto, la evidencia/challenge se consume una sola vez o se vincula a una operación idempotente concreta.
- Repetir la misma solicitud idempotente no duplica efectos; cambiar recurso, acción o payload fuera del contrato invalida la evidencia.
- Si la sesión se revoca o expira, la elevación deja de ser válida aunque su propio vencimiento no haya llegado.

No se fijan minutos universales ni una ventana MFA única para todas las operaciones. Deben aprobarse por clasificación antes de habilitar cada operación.

## 6. Revocación de roles, membresía y privilegios

- Revocar o modificar una asignación de rol/membresía invalida la versión de autorización anterior.
- Las aserciones y cachés con una versión anterior dejan de autorizar nuevas operaciones dentro del SLA aprobado.
- Un cambio de privilegio no se interpreta como elevación de autenticación.
- Un cambio de tenant obliga a validar membresía y emitir contexto nuevo.
- Los workers revalidan la autorización al ejecutar el efecto, no solo al recibir el mensaje.
- El módulo propietario vuelve a validar la decisión en el momento de la operación; no confía en permisos calculados previamente por un BFF o worker.

## 7. Relación con acceso privilegiado de soporte

La concesión de soporte definida en [Acceso privilegiado y soporte excepcional](./privileged-access-and-exceptional-support.md) permanece separada:

- una sesión PLATFORM válida no equivale a una concesión;
- una elevación MFA no crea ni amplía una concesión;
- una concesión activa no mantiene utilizable una sesión revocada;
- revocar la sesión del operador impide nuevas operaciones aunque la concesión histórica siga en estado activo;
- revocar la concesión impide nuevas operaciones aunque la sesión PLATFORM siga válida;
- el módulo propietario comprueba ambas condiciones y registra el resultado.

El SLA de revocación de concesiones de soporte debe ser compatible con el SLA general de revocación, y no puede ser más permisivo.

## 8. Auditoría y privacidad

Registrar, según ownership, emisión, refresh, reutilización detectada, logout, revocación, expiración, invalidación de privilegios, challenge MFA, éxito/fracaso de step-up, operación denegada por falta de elevación y uso de evidencia elevada.

Los registros deben permitir correlacionar actor, session_id, tenant cuando aplique, autoridad, motivo categorizado, resultado, jti/challenge id y request/trace id. No deben incluir tokens, cookies, códigos MFA, secretos, hashes de refresh tokens ni payloads completos. El usuario no debe recibir detalles que faciliten enumeración o replay.

## 9. Casos negativos obligatorios

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-SES-01 | Refresh token revocado, expirado o ya consumido | Rechazo; no se emite nueva sesión |
| NEG-SES-02 | Reutilización de refresh token rotado | Revocar familia en IDENTITY; alertar/auditar |
| NEG-SES-03 | Dos refresh concurrentes con el mismo token desde clientes, pestañas, dispositivos o réplicas BFF distintas | Consumo atómico en IDENTITY/PLATFORM; como máximo un sucesor válido; la segunda presentación se trata según política de reutilización |
| NEG-SES-04 | Sesión revocada con access token aún no expirado | Nuevas operaciones rechazadas según comprobación de estado/versión |
| NEG-SES-05 | Sesión supera timeout de inactividad o absoluto | Rechazo; requiere autenticación nueva |
| NEG-SES-06 | Usuario cambia contraseña o recupera cuenta | Revocación del alcance de sesiones definido por política; tokens previos no reutilizables |
| NEG-SES-07 | Rol/membresía revocados con caché/aserción anterior | Denegación dentro del SLA aprobado |
| NEG-SES-08 | Redis o autoridad de sesión no disponible para operación crítica | Fallo cerrado; sin efecto |
| NEG-SES-09 | Cookie antigua tras logout o cambio de tenant | No autentica; sin acceso a datos privados |
| NEG-SES-10 | Sesión IDENTITY presentada como PLATFORM o viceversa | Rechazo por autoridad/issuer incorrectos |
| NEG-ELV-01 | Actor sin permiso intenta operar tras completar MFA | Denegación por RBAC/ABAC |
| NEG-ELV-02 | Evidencia elevada pertenece a otra sesión, actor o tenant | Rechazo |
| NEG-ELV-03 | Evidencia elevada expirada o emitida para otra audiencia | Rechazo |
| NEG-ELV-04 | Factor MFA revocado, inválido o challenge reutilizado | Rechazo; sin elevar nivel |
| NEG-ELV-05 | Evidencia de step-up se reutiliza para otra acción/recurso | Rechazo; anti-replay |
| NEG-ELV-06 | Sesión revocada después del step-up | Evidencia deja de ser válida |
| NEG-ELV-07 | Se intenta usar step-up como segunda aprobación o concesión de soporte | Rechazo; controles independientes |
| NEG-ELV-08 | BFF agrega claims o eleva el nivel de autenticación | Rechazo por integridad/autoridad |
| NEG-ELV-09 | Worker reutiliza evidencia humana elevada | Rechazo; identidad de servicio independiente |
| NEG-ELV-10 | No se puede comprobar vigencia o alcance de la evidencia | Fallo cerrado |
| NEG-ELV-11 | Tras completar step-up se presenta el identificador de sesión o contexto anterior | Rechazo; el identificador anterior quedó invalidado por la rotación |
| NEG-ELV-12 | Evidencia step-up con firma, issuer, audience, actor, sesión nueva, tenant/scope, operación, `auth_time` o `jti` no coincidentes | Rechazo y auditoría; no se infiere validez desde `auth_level` |

Estos casos complementan los casos `NEG-C-*` y `NEG-SUP-*` existentes. Son criterios de diseño; no están automatizados ni ejecutados.

## 10. Decisiones pendientes antes de implementación

No se inventan valores para cerrar estas decisiones:

1. SLA cuantificado de revocación de sesión, familia, roles/membresías y concesiones de soporte, con medición end-to-end.
2. Límites de inactividad y expiración absoluta de sesiones PLATFORM, y límites globales que acotan las políticas configurables de IDENTITY.
3. Clases de riesgo y catálogo exacto de operaciones que requieren MFA, reautenticación, segunda aprobación o concesión excepcional.
4. Ventana de frescura MFA/reautenticación y duración máxima de evidencia elevada por clase de riesgo.
5. Contrato de consumo atómico/condicional de refresh y política de reintento/reutilización específica para PLATFORM, compatible con su SQL existente.
6. Contrato tipado de la aserción independiente step-up, su anti-replay, vinculación a operación y validación por receptores.
7. Contrato técnico de consulta/versionado de sesión y autorización, invalidación de cachés y comportamiento degradado.
8. Modelo de cookie/estado web del BFF compatible con ADR-0022 y con la rotación del identificador de sesión.
9. Política de revocación por cambio de contraseña, recuperación, cambio de MFA, rol, membresía y desactivación, diferenciando sesión actual, familia y todas las sesiones.

Cada decisión deberá tener propietario, justificación de riesgo, valor verificable, prueba y runbook cuando corresponda.

## 11. Estado de implementación y puerta

Esta propuesta no implementa autenticación, sesiones, rotación, revocación, step-up, cookies, contratos, middleware, auditoría, cachés ni infraestructura. No modifica archivos SQL ni crea migraciones.

Antes de implementar deben aprobarse las decisiones del apartado 10, cerrar los contratos versionados y mapear los casos negativos a pruebas automatizadas. La implementación funcional de IDENTITY/PLATFORM y los controles web se ejecutará en sus fases correspondientes, respetando ownership y dependencias del plan maestro.

La puerta documental de 0.4 solo podrá cerrarse cuando el diseño sea aprobado y las pruebas negativas estén definidas. La puerta técnica posterior exige pruebas ejecutadas con evidencia; este documento no las acredita.
