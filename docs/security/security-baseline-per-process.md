# Baseline de seguridad por proceso

**Estado:** vigente
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.3
**Fuente:** [Modelo de amenazas](./threat-model.md); ADR-0020 a ADR-0027.

---

## Propósito

Este documento define los controles mínimos que cada proceso debe satisfacer antes de exponer
cualquier superficie productiva. Un proceso no pasa a producción sin haber satisfecho su baseline.

El estado de cada control es **Diseñado** hasta que exista código, configuración y prueba verificada.
No se declara un control activo por el hecho de que exista un ADR o una especificación.

---

## Controles transversales (aplican a los cuatro procesos)

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Identidad de servicio propia; sin credenciales compartidas entre procesos | ADR-0023 | Diseñado | |
| TLS en todas las comunicaciones entre procesos y hacia datos | ADR-0023 | Diseñado | |
| Secretos en gestor externo; sin secretos en código, variables de entorno en texto plano ni imágenes | ADR-0023 | Diseñado | Gitleaks activo en CI detecta exposición en repo |
| Logs sin contraseñas, tokens, datos de pago ni payload personal | ADR-0015, ADR-0026 | Diseñado | |
| Health/readiness probes y graceful shutdown implementados | ADR-0003 | Diseñado | |
| Contenedor no privilegiado; filesystem de solo lectura donde sea posible; capacidades mínimas | ADR-0023 | Diseñado | |
| Propagación de W3C Trace Context en todos los contratos | ADR-0004 | Diseñado | |
| Auditoría de operaciones sensibles con actor, timestamp y contexto de tenant | ADR-0026 | Diseñado | |
| Pruebas de seguridad (autorización, aislamiento, entradas maliciosas) antes de exponer superficie | ADR-0020 | Diseñado | |

---

## Admin Platform Backend

**Responsabilidad:** ciclo de vida SaaS; módulo PLATFORM; tenants, planes y suscripciones.

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Separación total de identidad respecto a módulos de negocio de Public Backend | ADR-0008, ADR-0021 | Diseñado | |
| Operaciones de administración de tenant requieren rol de operador de plataforma; no accesibles por administradores de tenant | ADR-0021 | Diseñado | |
| Schema `platform` con rol PostgreSQL dedicado; sin acceso a schemas de otros módulos | ADR-0001 | Diseñado | |
| Superficie gRPC expuesta únicamente a Admin BFF; sin exposición directa pública | ADR-0007 | Diseñado | |
| Cambios de plan, límites y estado de tenant registrados en AUDIT | ADR-0026 | Diseñado | |
| Rate limiting en operaciones de creación/modificación de tenants | ADR-0025 | Diseñado | |

---

## Admin BFF

**Responsabilidad:** composición y exposición HTTP/OpenAPI para interfaces administrativas.
No posee dominios ni persistencia de negocio.

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Sin consultas directas a PostgreSQL de negocio; toda operación pasa por contrato del módulo propietario | ADR-0007, ADR-0008 | Diseñado | |
| Autenticación verificada en cada request; sin estado de sesión local en el proceso | ADR-0022 | Diseñado | |
| Autorización delegada al módulo propietario; el BFF no toma decisiones de acceso a datos | ADR-0021 | Diseñado | |
| CSP, HSTS, X-Frame-Options, X-Content-Type-Options y Referrer-Policy configurados | ADR-0022 | Diseñado | |
| Cookies con HttpOnly, Secure y SameSite=Strict o Lax según el flujo | ADR-0022 | Diseñado | |
| Rate limiting por IP y por token autenticado | ADR-0025 | Diseñado | |
| Rechazo de campos desconocidos en escrituras HTTP; DTO específicos por operación | ADR-0019 | Diseñado | |
| Timeouts de llamada hacia backends; sin espera indefinida | ADR-0020 | Diseñado | |
| Validación de tamaño de payload antes de procesar | ADR-0019, ADR-0027 | Diseñado | |

---

## Public BFF

**Responsabilidad:** composición y exposición HTTP/OpenAPI para interfaces públicas y operativas.
No posee dominios ni persistencia de negocio.

Hereda todos los controles de Admin BFF más los siguientes, por tener mayor superficie de exposición:

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Protección adicional contra scraping y bots en endpoints de catálogo y búsqueda | ADR-0025 | Diseñado | |
| Rate limiting más estricto en operaciones de creación de cuenta y login | ADR-0025 | Diseñado | |
| Validación de origen de callbacks de proveedores externos (PSP, integraciones) | ADR-0020 | Diseñado | |
| Sin exposición de IDs internos en respuestas públicas cuando no sean necesarios | ADR-0019 | Diseñado | |

---

## Public Backend

**Responsabilidad:** todos los módulos de negocio canónicos excepto PLATFORM.

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Aislamiento multi-tenant mediante RLS en PostgreSQL; rol por módulo; sin acceso cruzado entre schemas | ADR-0001, ADR-0021 | Diseñado | |
| RBAC + ABAC evaluado en el módulo propietario del recurso; sin delegación al BFF | ADR-0021 | Diseñado | |
| Contexto de tenant y actor validado en cada operación; nunca tomado del payload del cliente | ADR-0021 | Diseñado | |
| Workers y consumidores de Outbox/Inbox validan contexto antes de ejecutar | ADR-0021 | Diseñado | |
| Idempotencia en consumidores; rechazo de mensajes duplicados mediante Inbox | ADR-0003, ADR-0013 | Diseñado | |
| Consultas parametrizadas obligatorias (SQLx compile-time); sin interpolación | ADR-0019 | Diseñado | |
| Pool de conexiones por módulo con límites configurados; routing lectura/escritura | ADR-0010 | Diseñado | |
| Sagas con compensación definida para flujos multi-módulo; sin XA ni transacciones PostgreSQL compartidas | ADR-0013 | Diseñado | |
| Registros de AUDIT para operaciones financieras, cambios de configuración y acceso excepcional | ADR-0026 | Diseñado | |
| UUIDv7 para todos los identificadores de entidades principales | ADR-0012 | Diseñado | |

---

## Workers y consumidores de mensajería

**Responsabilidad:** Outbox, Inbox, Sagas, jobs periódicos y consumidores de JetStream.

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Identidad de worker separada del proceso principal; permisos mínimos sobre NATS y PostgreSQL | ADR-0023 | Diseñado | |
| Validación de mensaje antes de procesar: schema, versión, tenant y firma cuando aplique | ADR-0019 | Diseñado | |
| Idempotencia verificada antes de ejecutar efecto; tabla Inbox o clave idempotente | ADR-0003 | Diseñado | |
| Backpressure implementado; límite de mensajes en vuelo; timeout por mensaje | ADR-0017 | Diseñado | |
| Jobs periódicos con advisory lock en PostgreSQL; sin ejecución múltiple simultánea | ADR-0003 | Diseñado | |
| Fallos seguros: una dependencia caída no concede permisos ni produce efectos duplicados | ADR-0020 | Diseñado | |

---

## Clientes POS, dispositivos y operación offline

El cliente POS y el dispositivo son una superficie distinta de los cuatro procesos backend. Este baseline aplica a la aplicación POS, almacenamiento local y canal de sincronización; no convierte el cliente en propietario de datos ni en autoridad de autorización.

| Control | ADR | Estado | Notas |
|---|---|---|---|
| Enrolamiento explícito y una identidad revocable por dispositivo | ADR-0021, ADR-0022, ADR-0023 | Diseñado | No reutilizar una credencial global compartida entre terminales |
| Tenant, sucursal, permisos y estado del dispositivo se resuelven/validan en servidor | ADR-0021 | Diseñado | Nunca confiar en tenant/rol enviados libremente por el cliente |
| Datos locales minimizados y clasificados; no almacenar secretos ni PAN | ADR-0018, ADR-0022 | Diseñado | Definir datos permitidos offline por caso de uso |
| Almacenamiento local cifrado con claves protegidas por el sistema operativo/keystore | ADR-0022, ADR-0023 | Diseñado | No hardcodear claves ni usar una clave global embebida en la app |
| Bloqueo de pantalla, sesión local limitada, expiración y revocación del dispositivo | ADR-0022 | Diseñado | Definir comportamiento cuando el dispositivo vuelve a conectarse |
| Cola offline con IDs idempotentes, secuencia, integridad y límites de tamaño/edad | ADR-0003, ADR-0013, ADR-0019 | Diseñado | El servidor valida, deduplica y registra gaps/replay |
| Sincronización con reintentos/backoff, backpressure y límites por dispositivo/tenant | ADR-0017, ADR-0025 | Diseñado | No permitir que un terminal monopolice workers o conexiones |
| Conflictos de ventas, precios, impuestos, inventario y pagos tienen política explícita | ADR-0013, ADR-0019 | Diseñado | No resolver silenciosamente conflictos financieros |
| Revocación y reasignación bloquean sincronizaciones futuras y quedan auditadas | ADR-0021, ADR-0026 | Diseñado | Considerar dispositivo perdido/robado y credenciales comprometidas |
| Actualizaciones de cliente verificadas y soporte de versiones mínimas cuando sea viable | ADR-0024 | Diseñado | No asumir que una app cliente antigua sigue siendo confiable |

## Datos, caché, backups, objetos e IA

| Superficie | Control mínimo | ADR | Estado |
|---|---|---|---|
| Redis | Claves con tenant/alcance/versiones; ACL/TLS; no es autoridad de autorización ni fuente de verdad | ADR-0016, ADR-0021, ADR-0023 | Diseñado |
| NATS | Identidades por proceso, ACL por cuenta/subject, TLS, límites, ACK, retención y recuperación | ADR-0017, ADR-0023 | Diseñado |
| Backups/WAL/PITR | Cifrado, acceso separado, aislamiento/inmutabilidad cuando aplique, integridad y restauración probada | ADR-0010, ADR-0023, ADR-0026 | Diseñado |
| Object storage | Privado por defecto, autorización en descarga, URLs firmadas acotadas, cuarentena/validación y retención | ADR-0027 | Diseñado |
| IA/proveedores | Minimización, clasificación, contrato/retención revisados, aislamiento de contexto y herramientas de mínimo privilegio | ADR-0018, ADR-0020, ADR-0023, ADR-0026 | Diseñado |
| CI/CD | Permisos mínimos por job, acciones verificadas, separación PR/build/deploy, artefactos trazables | ADR-0024 | Parcial: workflow documental con `contents: read` y Gitleaks; no equivale a pipeline productivo |

## Notas de actualización

Este baseline se actualiza cuando:

- Una subfase completa la implementación y verificación de uno o más controles.
- Un ADR nuevo añade controles adicionales.
- Una prueba de seguridad revela un gap no considerado.

El estado pasa de **Diseñado** a **Implementado** cuando existe código y configuración real.
Pasa a **Verificado** cuando existe evidencia de prueba automatizada o revisión técnica registrada.
