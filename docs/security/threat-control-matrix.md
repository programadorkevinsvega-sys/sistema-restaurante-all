# Matriz amenaza / control / fase / evidencia

**Estado:** vigente
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.3
**Fuente de amenazas:** [Modelo de amenazas](./threat-model.md)
**Riesgos residuales:** [Registro de riesgos residuales](./residual-risk-register.md)

---

## Lectura de la tabla

- **ID amenaza:** referencia al ID en `threat-model.md`.
- **Control:** descripción del control técnico u organizativo.
- **Tipo:** Preventivo / Detectivo / Correctivo.
- **Fase de implementación:** subfase del plan maestro donde se implementa.
- **ADR de referencia:** decisión arquitectónica que sustenta el control.
- **Estado:** Diseñado / En implementación / Implementado / Verificado.
- **Evidencia:** enlace o descripción de la evidencia cuando el estado sea Implementado o Verificado.
- **Prueba/criterio:** caso negativo o positivo reproducible que demuestra el comportamiento esperado; la existencia del criterio no significa que la prueba esté implementada o ejecutada.

Un control en estado Diseñado significa que existe la decisión pero no el código, configuración ni prueba.

---

## Suplantación

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| S-01 | Tokens de sesión de corta duración; rotación de refresh token; revocación inmediata en logout | Preventivo | 0.4 | ADR-0011, ADR-0022 | Diseñado | — |
| S-01 | Detección de reutilización de token revocado; alerta y bloqueo automático | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| S-02 | Identidad de servicio por proceso; mTLS entre procesos; sin credenciales compartidas | Preventivo | 0.7 | ADR-0023 | Diseñado | — |
| S-03 | Argon2id para contraseñas; límite de intentos; bloqueo progresivo; MFA disponible | Preventivo | 0.4 | ADR-0011 | Diseñado | — |
| S-04 | Verificación de firma de callback (HMAC/JWT según proveedor); rechazo de callbacks sin firma válida | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| S-05 | Identidad de worker con permisos mínimos; validación de origen de mensaje; rechazo sin contexto válido | Preventivo | 0.4 | ADR-0021 | Diseñado | — |

## Manipulación

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| T-01 | Consultas parametrizadas obligatorias (SQLx compile-time); sin interpolación de SQL | Preventivo | 0.6 | ADR-0019 | Diseñado | — |
| T-02 | Validación y recálculo de precios/descuentos en backend propietario; BFF no modifica reglas de negocio | Preventivo | 0.5 | ADR-0019, ADR-0020 | Diseñado | — |
| T-03 | Outbox/Inbox con idempotencia; ACK explícito; rechazo de mensajes sin ID único o firma | Preventivo | 0.6 | ADR-0003, ADR-0013 | Diseñado | — |
| T-04 | Validación de tipo MIME, extensión, tamaño y contenido en uploads; antivirus/sandbox cuando aplique | Preventivo | 0.7 | ADR-0027 | Diseñado | — |
| T-05 | Acciones fijadas a SHA en CI; lockfile comprometido = bloqueo de pipeline; firma de artefactos | Preventivo | 0.2 | ADR-0024 | Diseñado | — |

## Repudio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| R-01 | Registro de actor, timestamp, operación y contexto en AUDIT para toda operación financiera | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| R-02 | Registro de cambios de configuración de tenant con actor y diff en AUDIT | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| R-03 | Acceso excepcional de soporte requiere autorización, registro y notificación al tenant | Detectivo/Correctivo | 0.8 | ADR-0026 | Diseñado | — |

## Divulgación de información

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| D-01 | Aislamiento multi-tenant en PostgreSQL mediante RLS y rol por módulo; validación de tenant en cada operación de módulo propietario | Preventivo | 0.6 | ADR-0021 | Diseñado | — |
| D-01 | Pruebas de cruce de tenant en cada endpoint y operación | Detectivo | 0.4 | ADR-0021 | Diseñado | — |
| D-02 | RBAC + ABAC evaluado en módulo propietario; sin autorización delegada al BFF | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| D-03 | Logs sin contraseñas, tokens, datos de pago ni payload personal; redacción automática | Preventivo | 0.8 | ADR-0015, ADR-0026 | Diseñado | — |
| D-04 | Rate limiting por actor y tenant en exportaciones y reportes; paginación obligatoria; alerta por volumen anómalo | Preventivo/Detectivo | 0.5 | ADR-0025 | Diseñado | — |
| D-05 | Escaneo Gitleaks en el workflow documental para detectar secretos versionados | Detectivo | 0.2 | ADR-0024 | Implementado | `.github/workflows/documentation-security.yml`; ejecuciones exitosas PR #33, #45 y #46 y merge de #46 |
| D-05 | Gestor externo, identidades separadas, rotación, revocación y protección de secretos operativos | Preventivo/Correctivo | 0.7 | ADR-0023, ADR-0024 | Diseñado | No existe evidencia de gestor externo configurado; RR-004 |
| D-06 | Tokens PSP en lugar de datos de tarjeta; sin almacenamiento de PAN; flujo PCI delegado a proveedor | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| D-07 | Validación y lista de destinos permitidos para URLs controladas por usuario; sin fetch de URLs arbitrarias | Preventivo | 0.5 | ADR-0019, ADR-0025 | Diseñado | — |

## Denegación de servicio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| DS-01 | Rate limiting por IP y por token en BFF; WAF con reglas de abuso y DDoS | Preventivo | 0.7 | ADR-0025 | Diseñado | — |
| DS-02 | Pool de conexiones por módulo con límites configurados; circuit breaker ante PostgreSQL degradado | Preventivo | 0.6 | ADR-0010 | Diseñado | — |
| DS-03 | Límite de tamaño de payload y archivos validado antes de procesamiento; rechazo temprano | Preventivo | 0.5 | ADR-0027 | Diseñado | — |
| DS-04 | Throttling por actor y tenant en endpoints costosos; timeouts de consulta; presupuesto de recursos | Preventivo | 0.5 | ADR-0025 | Diseñado | — |
| DS-05 | Backpressure en consumidores NATS; límite de mensajes en vuelo; alerta por profundidad de cola | Preventivo/Detectivo | 0.6 | ADR-0017 | Diseñado | — |

## Elevación de privilegios

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| E-01 | RBAC evaluado en módulo propietario; roles mínimos por defecto; sin herencia implícita | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-02 | Separación de identidad entre operador de plataforma y administrador de tenant; PLATFORM no comparte sesión con módulos de negocio | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-03 | DTO específicos por operación; rechazo de campos desconocidos en escrituras HTTP; sin mass assignment | Preventivo | 0.5 | ADR-0019 | Diseñado | — |
| E-04 | Workers validan contexto de tenant y actor antes de ejecutar operación; rechazo sin contexto válido | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-05 | Permisos mínimos del workflow documental; el job declara `contents: read` y no requiere permisos de escritura | Preventivo | 0.2 | ADR-0024 | Implementado | `.github/workflows/documentation-security.yml`; configuración del workflow revisada |
| E-05 | Environments de producción, identidad de despliegue temporal y gates de publicación | Preventivo | Fase de despliegue / 10.5 / F.6 | ADR-0024 | Diseñado | No existe workflow de despliegue productivo que permita verificar estos controles; no se afirma que estén configurados |
| E-06 | CSP estricta; cookies HttpOnly y Secure; tokens no accesibles desde JS cuando sea posible | Preventivo | 0.4 | ADR-0022 | Diseñado | — |
| E-07 | SameSite en cookies; CSRF token o verificación de origen en operaciones de estado | Preventivo | 0.4 | ADR-0022 | Diseñado | — |

## Controles para nuevas superficies y amenazas adicionales

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| S-06 | Enrolamiento autenticado por administrador, identidad única por dispositivo, credenciales revocables y verificación de estado antes de sincronizar | Preventivo | 0.10; 0.4; 0.7 | ADR-0021, ADR-0022, ADR-0023 | Diseñado | — |
| T-06 | Cola local cifrada y protegida contra manipulación; secuencia/identificador idempotente; el servidor valida y reconcilia sin confiar en el estado local | Preventivo/Detectivo | 0.10 | ADR-0003, ADR-0013, ADR-0019, ADR-0022 | Diseñado | — |
| T-07 | Claves de caché incluyen tenant, alcance, recurso y versión de autorización; caché nunca es autoridad de autorización; invalidación/versionado probado | Preventivo | 0.6; 0.7 | ADR-0016, ADR-0021 | Diseñado | — |
| T-08 | Backups cifrados, acceso separado, integridad verificable, copias aisladas/inmutables cuando aplique y restauración probada | Preventivo/Correctivo | 0.6; 0.7; 10.7 | ADR-0010, ADR-0017, ADR-0023, ADR-0026 | Diseñado | — |
| R-04 | Secuencia local y servidor, actor/dispositivo, correlación, resultado de sincronización y registro de gaps/conflictos sin alterar auditoría histórica | Detectivo | 0.8; 0.10 | ADR-0015, ADR-0026 | Diseñado | — |
| D-08 | Minimización de datos locales, cifrado con claves protegidas por el SO/keystore, bloqueo de dispositivo, expiración y revocación; no almacenar secretos duraderos | Preventivo | 0.10; 0.7 | ADR-0022, ADR-0023 | Diseñado | — |
| D-09 | Almacenamiento privado por defecto, autorización en cada descarga, URLs firmadas de alcance/tiempo mínimo y prohibición de listar objetos públicamente | Preventivo | 0.9; fases de archivos | ADR-0027 | Diseñado | — |
| D-10 | Cifrado de backups/exportaciones, credenciales separadas, mínimo privilegio, copias aisladas y auditoría de lectura/descarga | Preventivo/Detectivo | 0.6; 0.7; 10.7 | ADR-0023, ADR-0026, ADR-0027 | Diseñado | — |
| D-11 | Minimización/redacción antes de enviar datos a IA; proveedor y finalidad aprobados; contrato/retención revisados; prohibir secretos y datos no autorizados | Preventivo | Fases de integración IA; 0.3 como requisito | ADR-0018, ADR-0020, ADR-0023 | Diseñado | — |
| DS-06 | Cuotas por dispositivo/tenant, tamaño y frecuencia de lotes, backpressure, límites de concurrencia y rechazo idempotente de replay | Preventivo/Detectivo | 0.5; 0.7; 0.10 | ADR-0025, ADR-0017, ADR-0019 | Diseñado | — |
| DS-07 | Backups aislados e íntegros, objetivos RPO/RTO por clase de dato, runbooks y restauraciones periódicas con reconciliación posterior | Correctivo | 0.6; 0.7; 0.8; 10.7 | ADR-0023, ADR-0026 | Diseñado | — |
| E-08 | Solo rol autorizado puede enrolar, revocar o reasignar dispositivos; auditoría de cada cambio | Preventivo/Detectivo | 0.4; 0.8; 0.10 | ADR-0021, ADR-0026 | Diseñado | — |
| E-09 | Herramientas de IA con allowlist y permisos mínimos, sandbox, separación de datos, confirmación humana para acciones sensibles y registro | Preventivo/Detectivo | Fases de integración IA; antes de habilitar herramientas | ADR-0020, ADR-0023, ADR-0026 | Diseñado | — |

## Amenazas de dominio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| DOM-01 | Cambios de precio requieren rol autorizado; registro en AUDIT con actor y valor anterior/nuevo | Preventivo/Detectivo | 0.4 / 0.8 | ADR-0021 | Diseñado | — |
| DOM-02 | Ajustes de inventario requieren justificación y actor; alerta por ajustes fuera de rango | Preventivo/Detectivo | 0.4 / 0.8 | ADR-0021 | Diseñado | — |
| DOM-03 | Anulación de pagos confirmados requiere rol específico, flujo de aprobación y registro | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| DOM-04 | Aislamiento de sucursal verificado en cada operación; sin acceso cruzado por ID enviado por cliente | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| DOM-05 | Recetas versionadas con historial inmutable; modificación requiere nueva versión | Preventivo | Fase 3 | ADR-0001 | Diseñado | — |
| DOM-06 | Clave idempotente por operación/dispositivo, secuencia verificable y reconciliación transaccional; conflictos de precio, impuestos, stock y pago no se resuelven silenciosamente | Preventivo/Correctivo | 0.10; 0.6; fases funcionales de ventas/caja/inventario | ADR-0003, ADR-0013, ADR-0019, ADR-0020 | Diseñado | — |
| DOM-07 | El servidor resuelve tenant/sucursal desde identidad y enrolamiento vigente del dispositivo; rechaza contexto enviado que no coincida | Preventivo | 0.4; 0.10 | ADR-0021, ADR-0022 | Diseñado | — |


---

## Catálogo de pruebas y criterios de aceptación

Los siguientes criterios completan la dimensión de prueba de la matriz. Son especificaciones de prueba, no resultados ejecutados. Cada caso debe convertirse en prueba automatizada o evidencia de revisión en la subfase de implementación asignada.

| Amenazas | Prueba / criterio de aceptación |
|---|---|
| S-01, S-03, E-06, E-07 | Token expirado, revocado, reutilizado y solicitud CSRF/XSS simulada: acceso rechazado; no se filtran credenciales ni se ejecuta acción no autorizada. |
| S-02, S-05, T-03, DS-05 | Certificado/identidad de servicio inválido, subject NATS no autorizado, mensaje duplicado o replay: conexión/publicación/efecto rechazado o deduplicado; ACK solo tras persistencia según contrato. |
| S-04 | Callback con firma ausente, incorrecta, expirada o repetida: rechazo; callback válido procesado idempotentemente. |
| S-06, E-08 | Dispositivo no enrolado, revocado, reasignado o con credencial inválida: sincronización y administración rechazadas; cada acción administrativa queda auditada. |
| T-01, T-02, E-03 | Payload de inyección, precio/descuento manipulado y campos internos/tenant/rol desconocidos: consulta segura, recálculo en backend y rechazo de mass assignment. |
| T-04, DS-03, D-09 | Archivo con MIME falso, contenido no permitido, traversal, tamaño excesivo y URL no autorizada: cuarentena/rechazo; descarga sin autorización denegada. |
| T-05, D-05, E-05 | Secreto de prueba detectado bloquea CI; workflow no obtiene permisos no declarados; no se expone secreto productivo a PR. La protección de despliegue se valida cuando exista workflow/environment real. |
| T-06, R-04 | Modificar, borrar, reordenar o repetir una operación local: integridad/secuencia detectada; servidor deduplica y deja evidencia de conflicto/gap sin aplicar dos veces el efecto. |
| T-07 | Solicitar recurso cacheado con tenant, usuario o permiso distinto: no se devuelve dato ajeno; cambio de permisos/versiones invalida o evita reutilización de entrada obsoleta. |
| T-08, D-10, DS-07 | Alterar copia/snapshot o usar credencial runtime para borrar/leer backup: operación denegada o integridad detectada; restauración de prueba cumple RPO/RTO aprobado y reconciliación. |
| R-01, R-02, R-03 | Operación financiera, cambio de tenant y acceso excepcional: actor, motivo, tiempo y resultado trazables; actor no autorizado no puede modificar auditoría. |
| D-01, D-02, E-01, E-02, E-04, DOM-04, DOM-07 | IDs válidos de otro tenant/sucursal y contexto de dispositivo inconsistente: denegación sin filtrar existencia; worker y sincronización usan contexto autenticado del servidor. |
| D-03 | Inyectar tokens, contraseñas, datos personales y PAN de prueba en errores/logs: valores sensibles ausentes o redactados en logs, trazas y respuestas. |
| D-04, DS-01, DS-04, DS-06 | Scraping, exportación masiva, ráfaga y lotes de sync excesivos: cuotas/rate limit/backpressure aplicados sin agotar recursos ni omitir autorización. |
| D-06, DOM-03 | Intentar almacenar PAN o alterar/anular pago confirmado: datos de tarjeta no persisten; cambio de estado requiere flujo autorizado, idempotente y auditado. |
| D-07 | URL hacia loopback, RFC1918, metadata cloud, DNS rebinding, redirección o puerto no permitido: fetch bloqueado tras validar destino efectivo. |
| D-08 | Extraer almacenamiento local de dispositivo perdido o revocado: datos minimizados/cifrados; credencial revocada no permite sincronizar. |
| D-11, E-09 | Prompt injection o salida de IA que solicita datos/acciones fuera de alcance: herramienta deniega, no revela secretos/tenant ajeno y exige confirmación para acciones sensibles. |
| DS-02 | Saturar pool/degradar PostgreSQL: límites y timeouts contienen la presión; no hay crecimiento ilimitado ni fail-open. |
| DOM-01, DOM-02, DOM-05 | Cambios no autorizados de precio, inventario o receta: rechazados o versionados con justificación, actor y auditoría. |

**Regla de evidencia:** el estado Implementado requiere código/configuración real; Verificado requiere ejecución reproducible con resultado y commit/build identificable. Un test escrito pero no ejecutado no permite marcar Verificado.
