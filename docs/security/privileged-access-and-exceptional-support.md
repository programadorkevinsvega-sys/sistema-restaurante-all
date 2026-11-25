# Acceso privilegiado y soporte excepcional sobre datos de tenant

**Estado:** propuesta de diseño para revisión — subfase 0.4  
**Versión:** 1.0  
**Fecha:** 2026-11-25  
**Autoridad:** ADR-0020, ADR-0021, ADR-0023  
**Propietario de la concesión:** PLATFORM — Admin Platform Backend  
**Propietario de la autorización del recurso:** módulo de negocio correspondiente — Public Backend

**Documentos relacionados:**
- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Contrato de contexto autenticado](./authenticated-context-contract.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Casos negativos de autorización](./authorization-negative-cases.md)
- [Diseño de aislamiento por módulo y proceso](./isolation-design.md)

---

## 1. Propósito y límites

Define el ciclo de vida y las condiciones de seguridad para que un operador de PLATFORM obtenga
acceso excepcional y temporal a datos operativos pertenecientes a un tenant.

Una aserción firmada de PLATFORM acredita la identidad y el contexto del operador; por sí sola
no concede acceso a recursos de negocio. La autorización final permanece en el módulo propietario
del recurso en Public Backend, conforme a ADR-0021.

Este documento es diseño. No crea endpoints, contratos Protobuf, tablas, migraciones, permisos,
middleware, claves, infraestructura ni controles operativos. No modifica ni reemplaza los SQL
históricos de PLATFORM, IDENTITY o los módulos de negocio.

## 2. Principios obligatorios

1. **Sin acceso implícito:** ningún rol de plataforma concede por sí solo acceso a datos operativos.
2. **Justificación y propósito:** cada solicitud declara un motivo concreto y una referencia de
   incidente, solicitud o caso de soporte cuando exista.
3. **Mínimo alcance:** la concesión se limita a un tenant, módulo, recursos y acciones explícitos.
4. **Tiempo limitado:** toda concesión tiene inicio y expiración; no existen concesiones permanentes.
5. **Separación de funciones:** quien solicita no puede aprobar su propia concesión.
6. **Autenticación reforzada:** el operador debe acreditar MFA reciente o reautenticación conforme
   a la política de acciones de alto impacto.
7. **Decisión del propietario:** el módulo dueño valida la concesión y vuelve a autorizar cada
   operación; no delega la decisión al BFF.
8. **Revocación:** la concesión puede revocarse antes de su expiración y deja de autorizar nuevas
   operaciones.
9. **Auditoría:** solicitud, aprobación, activación, uso, denegación, expiración y revocación dejan
   evidencia atribuible.
10. **Fallo cerrado:** si no se puede comprobar identidad, vigencia, alcance o estado de la concesión,
    la operación se deniega.
11. **Sin bypass de datos:** soporte no recibe credenciales PostgreSQL, acceso directo a schemas,
    acceso a backups ni acceso administrativo al proceso propietario.
12. **Sin privilegios heredados:** una concesión no se transmite a otro operador, worker, proceso
    o sesión.

## 3. Roles y límites

| Rol PLATFORM | Capacidades respecto a datos operativos |
|---|---|
| `platform_support` | Solo lectura, siempre mediante concesión excepcional específica. No puede escribir, exportar masivamente ni ejecutar acciones de negocio. |
| `platform_operator` | Puede solicitar acceso excepcional. La aprobación y el uso quedan sujetos a la concesión, a la política de riesgo y a la autorización del módulo propietario. |
| `platform_billing` | Sin acceso a datos operativos de tenant por sus funciones de facturación SaaS. |

Los roles anteriores son propiedad exclusiva de PLATFORM. No se asignan desde IDENTITY ni se
aceptan como roles de tenant.

La concesión no eleva el rol base del operador ni permite administrar el tenant como si fuera
su `tenant_admin`. Tampoco permite cambiar roles, membresías o permisos de usuarios de tenant
salvo que exista una operación de plataforma explícita, separada y autorizada por su propietario.

## 4. Solicitud y contenido de una concesión

Una solicitud debe identificar, como mínimo:

| Dato | Regla |
|---|---|
| `grant_id` | Identificador único de la concesión |
| `requester_actor_id` | Operador PLATFORM autenticado que solicita |
| `tenant_id` | Un único tenant objetivo; nunca wildcard ni "todos los tenants" |
| `target_module` | Módulo propietario del recurso |
| `resource_scope` | Recursos concretos o selector acotado y verificable |
| `allowed_actions` | Acciones explícitas; no usar permiso genérico `admin` o `all` |
| `purpose` | Motivo operativo específico y comprensible |
| `case_reference` | Ticket/incidente/caso de soporte cuando exista |
| `requested_at` | Fecha y hora de solicitud |
| `requested_from` / `requested_until` | Ventana solicitada, con expiración obligatoria |
| `risk_classification` | Clasificación de riesgo de las acciones solicitadas |
| `approval` | Identidad del aprobador, decisión, fecha y motivo |

El selector de recursos debe permitir al módulo propietario comprobar pertenencia al tenant y
evitar que una concesión inicialmente estrecha se convierta en acceso a recursos agregados no
previstos. Las exportaciones masivas y las búsquedas que cubren conjuntos dinámicos se consideran
acciones de alto impacto y requieren una política específica; no se habilitan por una concesión
de lectura ordinaria.

No se fija aquí una duración máxima numérica universal. La política de producto/seguridad debe
establecer máximos por clasificación antes de implementar. Hasta entonces, no se habilita el
flujo en producción.

## 5. Aprobación y activación

1. PLATFORM autentica al solicitante y verifica que su cuenta esté activa y que su sesión tenga
   el nivel de autenticación requerido.
2. PLATFORM valida que el solicitante puede pedir el tipo de acceso; solicitar no equivale a
   aprobar.
3. Una persona distinta del solicitante, con autoridad de aprobación en PLATFORM, revisa el
   tenant, módulo, recursos, acciones, motivo, referencia y duración.
4. La aprobación registra identidad, decisión, momento y justificación. Una solicitud denegada
   no produce una concesión activa.
5. Las acciones de escritura, exportación, acceso masivo o alto impacto requieren segunda
   aprobación independiente y MFA reciente. La clasificación de operaciones concretas debe
   mantenerse en la política del módulo propietario.
6. La concesión solo se activa después de aprobarse y cuando comienza su ventana autorizada.
7. Cualquier ampliación de tenant, recursos, acciones o duración requiere una nueva aprobación;
   no se modifica silenciosamente una concesión activa.

La política de aprobación no debe permitir autoaprobación ni aprobación por una identidad de
servicio. El proceso exacto de asignación de aprobadores y escalamiento operativo se concretará
antes de la implementación.

## 6. Estados y ciclo de vida

| Estado | Significado | Transición permitida |
|---|---|---|
| `requested` | Solicitud registrada, pendiente de revisión | `approved`, `rejected`, `cancelled` |
| `approved` | Aprobada, aún fuera de ventana o pendiente de activación | `active`, `expired`, `revoked` |
| `active` | Dentro de la ventana aprobada y utilizable dentro del alcance | `expired`, `revoked` |
| `rejected` | Solicitud denegada | Terminal |
| `cancelled` | Solicitante canceló antes de activarse | Terminal |
| `expired` | La ventana autorizada terminó | Terminal |
| `revoked` | Revocada antes de terminar la ventana | Terminal |

Una concesión no se reactiva ni se extiende después de expirar o revocarse. Se solicita una nueva
concesión con nueva justificación y aprobación.

## 7. Validación por el módulo propietario

En cada operación de negocio, el módulo propietario debe comprobar:

1. La aserción de PLATFORM tiene firma válida, emisor permitido, audiencia correcta y vigencia.
2. El actor es un operador PLATFORM activo y la identidad mTLS del llamante corresponde al
   workload autorizado.
3. Existe una concesión aprobada, activa y no revocada.
4. El `tenant_id` de la concesión coincide exactamente con el recurso.
5. El módulo, recurso y acción solicitados están dentro del alcance concedido.
6. El momento actual está dentro de la ventana de la concesión.
7. La clasificación de riesgo y el nivel MFA/reautenticación satisfacen la política de la acción.
8. El estado y las invariantes del recurso permiten la operación.
9. No existe una revocación o cambio de estado más reciente que invalide el permiso.

La comprobación no se delega al Admin BFF ni se resuelve consultando tablas de PLATFORM desde
el schema del módulo. Se utiliza un contrato explícito con PLATFORM o una evidencia verificable
y revocable definida por contrato. El mecanismo concreto debe garantizar una ventana máxima
de propagación de revocación; ese límite se definirá y probará antes de habilitar el acceso.
Si el módulo no puede establecer de forma confiable la vigencia/estado de la concesión, deniega.

El módulo propietario registra el uso efectivo y el resultado de autorización. La concesión no
sustituye las reglas normales de pertenencia, estado, integridad ni autorización del dominio.

## 8. Revocación y expiración

Una concesión puede revocarse por el operador autorizado, un aprobador o un proceso de seguridad
de PLATFORM ante cierre del caso, sospecha de abuso, compromiso de cuenta, cambio de alcance o
necesidad operativa.

La revocación debe:
- impedir nuevas operaciones tan pronto como se alcance el límite de propagación definido;
- invalidar cualquier caché o evidencia derivada dentro de ese mismo límite;
- conservar el registro histórico de la concesión y su uso;
- no borrar ni alterar operaciones válidamente completadas antes de la revocación;
- generar evidencia atribuible del actor, momento y motivo de revocación.

La expiración se aplica aunque el operador mantenga abierta su sesión o conserve una aserción
firmada aún vigente. La sesión PLATFORM y la concesión son controles independientes: ambos
deben seguir válidos.

## 9. Auditoría y privacidad

PLATFORM registra el ciclo de vida de la concesión: solicitud, aprobación/rechazo, activación,
cambio permitido, expiración y revocación. El módulo propietario registra cada intento de uso,
acción ejecutada o denegada, recurso/tenant objetivo, `grant_id`, actor, motivo categorizado,
correlación y resultado.

AUDIT conserva los eventos según su ownership y política de retención. Los registros:
- no contienen contraseñas, tokens, claves, secretos ni payloads completos de negocio;
- no deben almacenar más datos personales que los necesarios para atribución e investigación;
- distinguen el acceso de soporte del acceso ordinario de usuarios del tenant;
- permiten correlacionar solicitud, aprobación, concesión y operaciones realizadas;
- no pueden ser modificados por el operador que usa la concesión.

## 10. Emergencias y decisiones aún no cerradas

No se habilita un mecanismo break-glass que omita aprobación, alcance, expiración, validación del
módulo propietario o auditoría. Si el producto requiere un flujo de emergencia, deberá definirse
como un tipo de concesión separado, con justificación reforzada, expiración más estricta,
notificación y revisión posterior; requiere aprobación explícita antes de implementarse.

También deben decidirse antes de la implementación:
- duración máxima por clasificación de riesgo;
- catálogo de operaciones que requieren segunda aprobación;
- si determinados casos requieren notificación o consentimiento del tenant;
- SLA máximo de propagación de revocación y comportamiento durante indisponibilidad de PLATFORM;
- proceso operativo de asignación/escalamiento de aprobadores.

Estas decisiones no se resuelven mediante valores inventados en esta especificación.

## 11. Pruebas negativas obligatorias

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-SUP-01 | Operador intenta acceder sin concesión | Denegación; sin datos ni efecto |
| NEG-SUP-02 | Solicitante intenta aprobar su propia solicitud | Denegación; concesión no activa |
| NEG-SUP-03 | Concesión apunta al tenant A y recurso pertenece al tenant B | Denegación por módulo propietario |
| NEG-SUP-04 | Operación no incluida en `allowed_actions` | Denegación; sin efecto |
| NEG-SUP-05 | Recurso o módulo fuera del alcance aprobado | Denegación; sin datos |
| NEG-SUP-06 | Concesión expirada o aún no activa | Denegación |
| NEG-SUP-07 | Concesión revocada, aunque la sesión siga vigente | Denegación |
| NEG-SUP-08 | `platform_support` intenta escribir o exportar masivamente | Denegación |
| NEG-SUP-09 | Aserción PLATFORM válida sin concesión activa | Denegación |
| NEG-SUP-10 | PLATFORM no disponible o estado de concesión no verificable | Fallo cerrado; sin efecto |
| NEG-SUP-11 | Se amplía el alcance sin nueva aprobación | Denegación |
| NEG-SUP-12 | Worker intenta reutilizar la concesión de un operador | Denegación; identidades no intercambiables |
| NEG-SUP-13 | Acceso concedido queda en caché después de revocación más allá del límite aprobado | La prueba debe fallar; no se permite uso posterior al SLA de revocación |
| NEG-SUP-14 | El registro de auditoría no puede confirmarse para una acción que lo exige | Denegación o no ejecución de la acción, según contrato transaccional aprobado |

## 12. Estado de implementación

Propuesta documental para revisión. No existen aún flujo de solicitud/aprobación, contrato de
concesión, validación entre PLATFORM y módulos, mecanismo de revocación, eventos AUDIT ni pruebas
automatizadas. Los escenarios son criterios de diseño; no se han ejecutado.

La implementación queda bloqueada hasta resolver las decisiones del apartado 10, aprobar los
contratos entre procesos y preparar las pruebas de integración/seguridad. No se modifican SQL
históricos ni se crean tablas o migraciones en esta subfase.
