# Registro de revisión de escenarios de amenazas (tabletop)

**Fase:** 0.3 — Modelo de amenazas y requisitos de seguridad  
**Estado:** walkthrough documental completado; TT-01 a TT-08 revisados y aprobados por el propietario del producto  
**Versión:** 1.0  
**Fecha:** 2026-11-25  
**Alcance:** ejercicio de escritorio basado en arquitectura y ADR. No es una prueba de penetración, simulación sobre infraestructura, auditoría independiente ni evidencia de controles desplegados.  
**Participantes previstos:** propietario del producto / único mantenedor. No se presupone un equipo de respuesta todavía existente.

## 1. Objetivo y método

Recorrer escenarios plausibles para comprobar que el modelo identifica activos, fronteras, decisiones iniciales, responsables, evidencia y riesgos residuales. Para cada escenario se documentan detección, contención, preservación de evidencia, recuperación y condiciones de reanudación.

Este documento no afirma que los controles estén implementados. Un paso que dependa de infraestructura, alertas, credenciales o runbooks aún no existentes se marca como pendiente y se conserva en el registro de riesgos.

## 2. Escenarios

### TT-01 — Dispositivo POS perdido o robado durante operación offline

- **Amenazas:** S-06, D-08, E-08, DOM-07.
- **Supuesto:** el dispositivo conserva datos y operaciones pendientes; la conectividad no está disponible.
- **Detección esperada:** reporte del usuario/administrador; último heartbeat y estado de enrolamiento cuando vuelva a conectarse.
- **Contención:** revocar identidad del dispositivo desde un canal autorizado; bloquear nuevas sincronizaciones; no confiar en que la revocación llegue inmediatamente a un dispositivo desconectado.
- **Evidencia:** identificador del dispositivo, actor que reporta, última conexión, operaciones pendientes y resultado de revocación; sin copiar secretos.
- **Recuperación:** reasignar dispositivo sustituto; reconciliar operaciones pendientes mediante idempotencia y reglas explícitas; evaluar exposición de datos locales.
- **Brecha/riesgo:** la revocación remota no borra por sí sola datos en dispositivo desconectado; requiere cifrado local y minimización.
- **Referencia:** RR-008.

### TT-02 — Cola offline manipulada, duplicada o reordenada

- **Amenazas:** T-06, R-04, DS-06, DOM-06.
- **Supuesto:** una operación local se edita, duplica o reenvía varias veces.
- **Detección esperada:** verificación de integridad/secuencia, clave idempotente repetida, conflicto de estado o gap detectado por servidor.
- **Contención:** poner el lote en cuarentena/rechazarlo; no confirmar efectos financieros ni de inventario sin validación del servidor.
- **Evidencia:** ID de operación, dispositivo, secuencia, resultado de deduplicación y correlación.
- **Recuperación:** redrive controlado tras corregir la causa; conciliación con estado autoritativo del módulo propietario.
- **Brecha/riesgo:** requiere contrato de sync, persistencia Inbox y pruebas de conflicto en 0.10/0.6.
- **Referencia:** RR-008.

### TT-03 — Acceso cruzado entre tenants por API o caché

- **Amenazas:** D-01, D-02, T-07, DOM-07.
- **Supuesto:** usuario o dispositivo envía ID válido perteneciente a otro tenant; una entrada cacheada se reutiliza con contexto distinto.
- **Detección esperada:** pruebas negativas de tenant/sucursal; logs redactados con código de denegación y correlación.
- **Contención:** denegar en módulo propietario; invalidar o aislar caché; no depender del BFF ni de UUID opaco.
- **Evidencia:** actor, tenant autenticado, recurso objetivo y resultado de autorización sin revelar dato ajeno.
- **Recuperación:** revisar alcance de datos expuestos, invalidar claves y credenciales afectadas, preservar auditoría.
- **Brecha/riesgo:** RLS, autorización y namespace cache requieren implementación y pruebas en 0.4/0.6/0.7.
- **Referencia:** RR-002, RR-011.

### TT-04 — Secreto expuesto o workflow comprometido

- **Amenazas:** D-05, T-05, E-05.
- **Supuesto:** un token aparece en commit, log, artefacto o ejecución CI.
- **Detección esperada:** Gitleaks/alerta del proveedor o reporte humano; identificar tipo/alcance sin reproducir el valor.
- **Contención:** detener publicación; revocar/rotar el secreto por canal seguro; revisar permisos y ejecuciones; no asumir que borrar el commit revoca el secreto.
- **Evidencia:** ubicación, tipo, alcance, hora, rotación/revocación y builds afectados; nunca el valor secreto.
- **Recuperación:** reconstruir artefactos confiables, revisar dependencias/workflows y cerrar exposición.
- **Brecha/riesgo:** Gitleaks está en CI; gestor externo, SBOM, procedencia y pipeline de despliegue aún no se acreditan.
- **Referencia:** RR-004, RR-013.

### TT-05 — Manipulación de callback de proveedor de pagos

- **Amenazas:** S-04, D-06, DOM-03.
- **Supuesto:** llega callback falso, repetido, expirado o con importe/moneda diferentes.
- **Detección esperada:** verificación de firma, ventana temporal, identificador del evento, idempotencia y conciliación contra proveedor.
- **Contención:** no marcar pago confirmado; poner evento en cuarentena y alertar si hay anomalía.
- **Evidencia:** referencia PSP, firma verificada/no verificada, importe/moneda esperados y resultado; sin PAN ni secreto.
- **Recuperación:** consulta autenticada al PSP y conciliación controlada; reverso solo por flujo autorizado.
- **Brecha/riesgo:** integración y controles aún no implementados.
- **Referencia:** RR-012, RR-014.

### TT-06 — Ransomware, borrado o corrupción de backups

- **Amenazas:** T-08, D-10, DS-07.
- **Supuesto:** credencial privilegiada comprometida borra datos y copias o una restauración contiene datos corruptos.
- **Detección esperada:** alerta de borrado, verificación de integridad y prueba de restauración.
- **Contención:** aislar credencial comprometida; preservar copia inmutable/aislada; impedir que identidad runtime administre backups.
- **Evidencia:** inventario de copias, manifest de integridad, auditoría de acceso, RPO/RTO real medido.
- **Recuperación:** restaurar en entorno aislado, verificar consistencia, aplicar reconciliación legal/retención y reabrir servicio según runbook.
- **Brecha/riesgo:** no hay evidencia de backups desplegados ni restauraciones ejecutadas.
- **Referencia:** RR-009.

### TT-07 — Prompt injection o herramienta de IA con permisos excesivos

- **Amenazas:** D-11, E-09.
- **Supuesto:** contenido externo induce a una herramienta a revelar contexto o ejecutar acción no autorizada.
- **Detección esperada:** registro de invocación, herramienta, alcance y política aplicada; redacción de contenido sensible.
- **Contención:** detener herramienta/proveedor, revocar credencial y bloquear acciones externas de alto impacto.
- **Evidencia:** caso sanitizado, identidad de herramienta, permiso solicitado y decisión; no almacenar secretos ni datos innecesarios.
- **Recuperación:** revisar datos enviados, rotar credenciales, evaluar notificación y reanudar solo con allowlist y pruebas.
- **Brecha/riesgo:** no hay proveedor ni integración IA aprobada; controles son requisitos previos.
- **Referencia:** RR-010.

### TT-08 — Abuso de API y saturación de sincronización

- **Amenazas:** DS-01, DS-04, DS-06, DS-02.
- **Supuesto:** bot, tenant o dispositivo envía solicitudes/lotes masivos y consultas costosas.
- **Detección esperada:** métricas de tasa, tamaño, cola, latencia, conexiones y cuotas por actor/tenant/dispositivo.
- **Contención:** rate limit, backpressure, límites de concurrencia, circuit breaker y degradación segura; no omitir autorización.
- **Evidencia:** métricas agregadas y códigos de limitación, sin datos sensibles como labels.
- **Recuperación:** reducir carga, drenar colas controladamente y verificar que no haya operaciones duplicadas/perdidas.
- **Brecha/riesgo:** límites y protección perimetral aún no están implementados.
- **Referencia:** RR-006, RR-008, RR-015.

## 3. Guion de walkthrough y resultado

Para cada escenario, el revisor debe responder y registrar:

1. ¿Qué activo y frontera se afectan?
2. ¿Qué señal permite detectar el evento y existe realmente?
3. ¿Quién tiene autoridad para contenerlo?
4. ¿Qué credencial/permiso debe revocarse y por qué canal?
5. ¿Qué evidencia se preserva y qué dato debe redactarse?
6. ¿Cómo se recupera y cómo se valida integridad/idempotencia?
7. ¿Qué condición bloquea la reanudación?
8. ¿Qué riesgo residual y tarea del plan se actualizan?

**Resultado actual:** TT-01, TT-02, TT-03, TT-04, TT-05, TT-06, TT-07 y TT-08 cuentan con decisiones operativas revisadas y aprobadas por el propietario. Los ocho walkthroughs están completos. No se declara tabletop completo ni prueba técnica superada.

### Registro de ejecución

#### TT-01 — Dispositivo POS perdido o robado

- **Estado del walkthrough:** revisado y decisión aprobada por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** marcar el dispositivo como perdido/robado; revocar su identidad y credenciales desde el servidor; bloquear nuevas sincronizaciones; registrar el incidente y preservar auditoría; exigir autorización para enrolar un dispositivo sustituto; rechazar la aceptación automática de operaciones pendientes.
- **Limitación aceptada:** la revocación remota no alcanza inmediatamente a un dispositivo desconectado. Se requieren cifrado local y protección/minimización de credenciales y datos.
- **Resultado:** respuesta operativa aprobada para el escenario. Los controles siguen siendo requisitos de diseño hasta que se implementen y prueben en las fases correspondientes.
- **Acciones relacionadas:** TA-02 permanece pendiente de implementación; TA-07 permanece pendiente para pruebas negativas en CI.

#### TT-02 — Cola offline manipulada, duplicada o reordenada

- **Estado del walkthrough:** revisado y siete medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** cada operación debe tener un identificador único e idempotente; mantener integridad y secuencia verificables; validar cada operación en el servidor antes de aceptarla; impedir que duplicados generen ventas o movimientos repetidos; poner conflictos en cuarentena para conciliación; no confirmar efectos financieros únicamente por el reporte del dispositivo; y dejar trazabilidad auditable de cada sincronización.
- **Limitación aceptada:** estas medidas definen requisitos de diseño. No se afirma que la cola local sea inviolable ni que la integridad, secuencia, validación, cuarentena o auditoría estén implementadas o probadas.
- **Resultado:** respuesta operativa aprobada para el escenario. El contrato de sincronización, la persistencia Inbox, la deduplicación y las pruebas de conflicto deben implementarse y verificarse en las fases correspondientes.
- **Acciones relacionadas:** TA-03 permanece pendiente de implementación y pruebas; TA-07 permanece pendiente para incorporar pruebas negativas a CI.

#### TT-03 — Acceso cruzado entre tenants por API o caché

- **Estado del walkthrough:** revisado y ocho medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** cada módulo propietario valida autorización para tenant, sucursal y recurso; el tenant confiable se obtiene de identidad/contexto verificado en servidor y nunca de un valor libre enviado por cliente; aplicar RLS en PostgreSQL donde corresponda con contexto de sesión seguro; aislar claves y resultados Redis por tenant y ámbito de autorización; denegar por defecto cuando falte contexto o permiso; mantener pruebas negativas de aislamiento para API, búsquedas, exportaciones, caché, procesos y sincronización; auditar actor, tenant autenticado, recurso, módulo y decisión; y tratar UUID/identificadores opacos como localizadores, nunca como autorización.
- **Casos aprobados para validar:** cambio de ID para consultar factura ajena; consulta sin filtro de tenant; reutilización de caché entre tenants; acceso fuera del ámbito de sucursal; operación de sync con tenant manipulado; y trabajo en segundo plano con contexto heredado incorrectamente.
- **Limitación aceptada:** estas medidas son requisitos de diseño. No se afirma que RLS, autorización, aislamiento de Redis, auditoría o pruebas negativas estén implementados ni probados.
- **Resultado:** respuesta operativa aprobada para el escenario. Los controles deben implementarse y verificarse en las fases de identidad/autorización, PostgreSQL, Redis y pruebas.
- **Acciones relacionadas:** TA-05 y TA-07 permanecen pendientes de implementación y pruebas.

#### TT-05 — Manipulación de callback de proveedor de pagos

- **Estado del walkthrough:** revisado y ocho medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** verificar criptográficamente la firma del callback mediante el mecanismo oficial del PSP y gestionar la rotación de claves; validar el origen sin depender únicamente de la IP; procesar cada evento y operación de forma idempotente; comparar importe, moneda, referencia, comercio y transacción contra la operación pendiente del servidor; aplicar una máquina de estados con transiciones permitidas; consultar la API autenticada del PSP cuando el protocolo lo permita antes de confirmar efectos financieros; persistir eventos de forma durable con deduplicación, reintentos controlados, trazabilidad y cuarentena de eventos inválidos o contradictorios; y responder a anomalías preservando evidencia, alertando, revisando transacciones relacionadas y conciliando con el PSP.
- **Casos aprobados para validar:** callback con firma falsa o ausente; callback legítimo repetido; importe o moneda diferentes; referencia de pago perteneciente a otro tenant; evento recibido después de una cancelación; eventos fuera de orden; fallo del sistema después de recibir la confirmación del PSP; y referencia inexistente o manipulada.
- **Limitación aceptada:** una firma válida acredita autenticidad e integridad según el mecanismo del proveedor, pero no demuestra por sí sola que orden, tenant, importe y estado sean correctos. La integración debe respetar el protocolo específico del PSP. No se afirma que estos controles estén implementados ni probados.
- **Resultado:** respuesta operativa aprobada para el escenario. La integración, la persistencia durable, la idempotencia, la máquina de estados y la conciliación deben implementarse y verificarse en las fases correspondientes.
- **Acciones relacionadas:** TA-07 permanece pendiente para incorporar pruebas negativas a CI; la implementación de la integración y sus controles se planificará en la fase funcional correspondiente.

#### TT-04 — Secreto expuesto o workflow comprometido

- **Estado del walkthrough:** revisado y ocho medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** detectar secretos mediante escaneo automático en commits y CI y bloquear el flujo ante hallazgos; tratar toda credencial expuesta como comprometida, revocarla y rotarla por canal seguro; aplicar mínimo privilegio, alcance limitado y duración controlada; separar credenciales de producción de pruebas, forks y ejecuciones no confiables; proteger workflows, fijar acciones externas a referencias verificables y no ejecutar código no confiable con permisos elevados; auditar cambios, exposición y ejecuciones; reconstruir artefactos desde código confiable y verificar integridad antes de reanudar despliegues; y evitar imprimir secretos en logs, excepciones, respuestas API o errores.
- **Casos aprobados para validar:** clave privada subida a GitHub; workflow que imprime una variable secreta; acción o dependencia externa comprometida que roba un token; pull request no confiable que obtiene permisos excesivos; y modificación del pipeline para publicar una versión maliciosa.
- **Limitación aceptada:** Gitleaks y otros escáneres no garantizan detectar todos los secretos ni impiden su uso antes de la detección. Eliminar un secreto del historial no sustituye su revocación. No se afirma que los controles de producción estén desplegados o probados.
- **Resultado:** respuesta operativa aprobada para el escenario. La gestión de secretos, permisos, aislamiento de workflows, procedencia y validación de artefactos debe implementarse y verificarse en las fases correspondientes.
- **Acciones relacionadas:** TA-04 y TA-07 permanecen pendientes de implementación y pruebas.

#### TT-06 — Ransomware, borrado o corrupción de backups

- **Estado del walkthrough:** revisado y ocho medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** separar privilegios para impedir que las credenciales runtime de la aplicación administren o eliminen backups; mantener copias aisladas e inmutables durante periodos definidos y protegidas con credenciales separadas de producción; conservar copias independientes y, cuando corresponda, en otra ubicación o cuenta; alertar ante borrados, modificaciones, fallos de backup, cambios de retención y accesos privilegiados anómalos; verificar integridad mediante manifiestos, checksums u otros mecanismos apropiados; restaurar primero en un entorno aislado y comprobar integridad, consistencia de PostgreSQL y dependencias; definir RPO/RTO y medirlos mediante ejercicios periódicos de restauración; y reanudar producción solo después de contener el compromiso, rotar credenciales, validar datos, revisar transacciones y sincronizaciones pendientes y autorizar la reapertura.
- **Casos aprobados para validar:** cifrado de PostgreSQL con eliminación de backups accesibles; backups disponibles pero modificados o corruptos; restauración con inconsistencias entre módulos; divergencia entre PostgreSQL, Redis, colas y eventos; última copia íntegra más antigua que el RPO esperado; y compromiso de las credenciales de backup.
- **Limitación aceptada:** las medidas son requisitos de diseño y respuesta. No se afirma que existan backups inmutables o aislados, alertas, manifiestos, RPO/RTO medidos ni restauraciones ejecutadas. Una copia existente no se considera válida hasta verificarla y restaurarla.
- **Resultado:** respuesta operativa aprobada para el escenario. La arquitectura de backup, la protección de credenciales, las pruebas de restauración y los procedimientos de reconciliación deben implementarse y verificarse en las fases correspondientes.
- **Acciones relacionadas:** TA-04 permanece pendiente de implementación y pruebas; TA-07 permanece pendiente para incorporar pruebas negativas y validaciones automatizadas a CI.

#### TT-07 — Prompt injection o herramienta de IA con permisos excesivos

- **Estado del walkthrough:** revisado y diez medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** la IA no es autoridad para sustituir reglas de negocio ni autorización backend; cada herramienta opera con mínimo privilegio y sin acceso general a bases de datos, Redis, infraestructura o secretos; el backend propietario autoriza cada operación usando identidad, tenant, sucursal y permisos verificados; separar herramientas de lectura y escritura y exigir autorización adicional para acciones sensibles; requerir confirmación explícita de una persona autorizada para operaciones críticas, financieras, irreversibles o que afecten datos de clientes; tratar contenido externo como datos no confiables y nunca como instrucciones con autoridad; limitar herramientas y destinos mediante allowlists y validar estrictamente argumentos; minimizar y redactar datos sensibles y nunca incluir secretos o datos de otros tenants en el contexto del modelo; auditar solicitudes, herramientas, autorizaciones y resultados, con capacidad de suspensión y revocación; y probar prompt injection directo/indirecto, acceso cross-tenant, extracción de secretos, abuso de herramientas, escalamiento de privilegios y acciones sin confirmación.
- **Casos aprobados para validar:** instrucciones maliciosas en descripciones de productos; documentos que intentan obtener datos de otro restaurante; modificación de precios o eliminación de productos sin autorización; envío de información a URL externa; instrucciones para ignorar políticas; usuario con permiso de consulta que intenta ejecutar operaciones administrativas; herramienta externa comprometida que devuelve instrucciones; y operación financiera intentada sin confirmación humana.
- **Limitación aceptada:** no hay proveedor ni integración IA aprobada. Las decisiones son requisitos previos y no evidencia de controles implementados o probados. Toda futura integración debe pasar evaluación de seguridad y pruebas antes de habilitarse.
- **Resultado:** respuesta operativa aprobada para el escenario. La política de IA, el catálogo y permisos de herramientas, las confirmaciones, la minimización de contexto y las pruebas deben definirse e implementarse antes de integrar IA.
- **Acciones relacionadas:** TA-06 permanece pendiente hasta definir política de proveedores IA; TA-07 permanece pendiente para incorporar pruebas negativas y validaciones automatizadas a CI.

#### TT-08 — Abuso de API y saturación de sincronización

- **Estado del walkthrough:** revisado y diez medidas aprobadas por el propietario.
- **Fecha de revisión:** 2026-11-25.
- **Decisiones aprobadas:** aplicar rate limiting por usuario, tenant, dispositivo, IP y endpoint según el riesgo; establecer cuotas de consumo por tenant; limitar tamaño de payloads, elementos por lote, profundidad de estructuras y parámetros de consulta; proteger PostgreSQL con pools y límites de conexiones, timeouts, consultas optimizadas y concurrencia controlada; proteger Redis con límites de conexiones, memoria y operaciones costosas, y controlar el tamaño de claves; aplicar backpressure para ralentizar o rechazar temporalmente operaciones no críticas sin perder las ya aceptadas de forma durable; usar circuit breakers y degradación controlada para aislar dependencias lentas o caídas y preservar funciones esenciales del POS; limitar lotes y concurrencia de sincronización, aplicar idempotencia y reintentos con backoff y jitter; monitorear latencia, errores, conexiones, consumo, profundidad de colas, rechazos y cuotas por tenant sin exponer datos sensibles en etiquetas; y ejecutar pruebas de carga, estrés, ráfagas, agotamiento de recursos, aislamiento entre tenants y recuperación.
- **Casos aprobados para validar:** tenant con miles de solicitudes por segundo; dispositivo que envía lote enorme; consulta pesada que agota conexiones PostgreSQL; operaciones costosas en Redis; dependencia externa que deja de responder; tormenta de reintentos de sincronización; evasión de límites mediante múltiples IP; cola de eventos a capacidad máxima; consumo desproporcionado de recursos por un tenant; y recuperación tras saturación con operaciones pendientes o duplicadas.
- **Limitación aceptada:** rate limiting por IP no es suficiente para un SaaS multiempresa; Redis no debe ser un punto único de fallo para límites críticos; el rechazo de solicitudes no debe perder operaciones ya aceptadas; las operaciones financieras conservan idempotencia y trazabilidad; y la degradación nunca omite autorización ni controles de seguridad. Las medidas son requisitos de diseño, no evidencia de infraestructura protegida o pruebas ejecutadas.
- **Resultado:** respuesta operativa aprobada para el escenario. Los límites, cuotas, backpressure, aislamiento de recursos, resiliencia de sincronización, observabilidad y pruebas deben implementarse y verificarse en las fases correspondientes.
- **Acciones relacionadas:** TA-07 permanece pendiente para incorporar pruebas negativas y validaciones automatizadas del catálogo de amenazas a CI por etapa. Las pruebas de carga y resiliencia se planificarán en las fases de infraestructura y operación correspondientes.

## 4. Registro de acciones del ejercicio

| ID | Acción pendiente | Responsable | Fase | Estado |
|---|---|---|---|---|
| TA-01 | Ejecutar walkthrough de los ocho escenarios y registrar decisiones/fechas | Propietario del producto | 0.3 | Completado (8/8) |
| TA-02 | Implementar enrolamiento, revocación y protección local de POS | Propietario del producto | 0.4 / 0.10 | Pendiente |
| TA-03 | Diseñar y probar sync idempotente, integridad, conflictos y reconciliación | Propietario del producto | 0.10 | Pendiente |
| TA-04 | Implementar gestión de secretos, aislamiento de backups y restauración | Propietario del producto | 0.6 / 0.7 | Pendiente |
| TA-05 | Implementar controles de identidad, autorización y auditoría | Propietario del producto | 0.4 / 0.8 | Pendiente |
| TA-06 | Definir política de proveedores IA antes de integrar herramientas | Propietario del producto | Antes de integración IA | Pendiente |
| TA-07 | Incorporar pruebas negativas del catálogo de amenazas a CI por etapa | Propietario del producto | 0.4–0.10 y fases funcionales | Pendiente |

## 5. Criterio de cierre de esta evidencia

El ejercicio de escritorio queda completado cuando los ocho escenarios tienen activo, amenazas, detección, contención, evidencia, recuperación, brechas y riesgos vinculados, y el propietario ha revisado y aprobado las decisiones. Las acciones pendientes y los riesgos residuales permanecen registrados, con responsable, tratamiento y fase de cierre; no es necesario implementar aquí los controles técnicos asignados a otras subfases. Este registro no acredita pruebas técnicas, despliegues ni eficacia operativa de controles.
