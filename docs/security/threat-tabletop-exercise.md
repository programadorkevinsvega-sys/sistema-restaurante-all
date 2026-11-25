# Registro de revisión de escenarios de amenazas (tabletop)

**Fase:** 0.3 — Modelo de amenazas y requisitos de seguridad  
**Estado:** walkthrough documental en curso; TT-01 y TT-02 revisados y aprobados  
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

**Resultado actual:** TT-01 y TT-02 cuentan con decisiones operativas revisadas y aprobadas por el propietario. Los otros seis escenarios siguen pendientes de walkthrough. No se declara tabletop completo ni prueba técnica superada.

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

## 4. Registro de acciones del ejercicio

| ID | Acción pendiente | Responsable | Fase | Estado |
|---|---|---|---|---|
| TA-01 | Ejecutar walkthrough de los ocho escenarios y registrar decisiones/fechas | Propietario del producto | 0.3 | En curso (2/8) |
| TA-02 | Implementar enrolamiento, revocación y protección local de POS | Propietario del producto | 0.4 / 0.10 | Pendiente |
| TA-03 | Diseñar y probar sync idempotente, integridad, conflictos y reconciliación | Propietario del producto | 0.10 | Pendiente |
| TA-04 | Implementar gestión de secretos, aislamiento de backups y restauración | Propietario del producto | 0.6 / 0.7 | Pendiente |
| TA-05 | Implementar controles de identidad, autorización y auditoría | Propietario del producto | 0.4 / 0.8 | Pendiente |
| TA-06 | Definir política de proveedores IA antes de integrar herramientas | Propietario del producto | Antes de integración IA | Pendiente |
| TA-07 | Incorporar pruebas negativas del catálogo de amenazas a CI por etapa | Propietario del producto | 0.4–0.10 y fases funcionales | Pendiente |

## 5. Criterio de cierre de esta evidencia

El registro queda completo como preparación documental cuando los escenarios tienen activo, amenazas, detección, contención, evidencia, recuperación, brecha y riesgo vinculado. La subfase no se declara cerrada hasta que el propietario complete el walkthrough y acepte las acciones/residuales. Las pruebas técnicas se ejecutan en las subfases que implementan cada control.
