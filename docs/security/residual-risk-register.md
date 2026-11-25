# Registro de riesgos residuales

**Estado:** vigente
**Versión:** 1.3
**Fecha:** 2026-11-25
**Fase:** 0.3/0.4
**Fuente:** [Modelo de amenazas](./threat-model.md) y [Matriz de control](./threat-control-matrix.md)

---

## Lectura del registro

Un riesgo residual es una amenaza para la que no existe aún un control implementado y verificado,
o cuyo control tiene limitaciones conocidas. Los SQL históricos del repositorio son la base de datos diseñada para cada módulo. La presencia de tablas, constraints o DDL RLS en esos archivos no demuestra que se hayan trasladado a las rutas canónicas, aplicado en una instancia ni probado. Cada entrada incluye:

- **ID:** referencia al ID de amenaza en `threat-model.md`.
- **Descripción:** qué riesgo permanece abierto.
- **Motivo:** por qué el control no está implementado todavía.
- **Tratamiento:** estrategia explícita para reducir, evitar o controlar el riesgo mientras permanezca abierto; no equivale a aceptación formal ni a cierre.
- **Controles compensatorios activos:** mitigaciones parciales ya en lugar.
- **Fase de cierre prevista:** subfase del plan maestro donde se cierra.
- **Propietario:** responsable de implementar el control y cerrar el riesgo.
- **Condición de revisión:** cuándo se revisa este registro aunque no haya llegado la fase.

La aceptación formal de un riesgo que no se cerrará en la fase prevista requiere aprobación
explícita del propietario del producto.

---

## Riesgos abiertos

### RR-001 — Autenticación y sesiones (S-01, S-03, E-06, E-07)

| Campo | Valor |
|---|---|
| ID amenazas | S-01, S-03, E-06, E-07 |
| Descripción | No existe implementación de autenticación, gestión de sesiones, rotación de tokens ni controles de navegador (CSP, cookies seguras). |
| Motivo | La subfase 0.4 está pendiente. No se construye código de autenticación antes de que el modelo de identidad y autorización esté aprobado. |
| Tratamiento | Mitigar: implementar autenticación, sesiones seguras, rotación y controles de navegador en 0.4; mantener las superficies no expuestas hasta verificarlo. |
| Controles compensatorios | El repositorio no tiene superficies públicas desplegadas. No hay endpoints expuestos en esta etapa. |
| Fase de cierre | 0.4 — Identidad, autorización y aislamiento |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Si se expone cualquier endpoint antes de completar 0.4 |

### RR-002 — Aislamiento multi-tenant y RBAC (D-01, D-02, E-01, E-02, E-04)

| Campo | Valor |
|---|---|
| ID amenazas | D-01, D-02, E-01, E-02, E-04 |
| Descripción | Existe DDL histórico RLS en determinados módulos/tablas, pero no se ha acreditado su aplicación ni cobertura completa; tampoco provisión de roles runtime/migrator ni lógica ejecutable RBAC/ABAC probada. |
| Motivo | Modelo y contrato en 0.4; distribución canónica de SQL, reconciliación de referencias cross-schema, roles y verificación de RLS en 0.6 y fases funcionales. |
| Tratamiento | Mitigar: inventariar DDL sin reescribir históricos ahora; trasladar/corregir SQL mediante cambios autorizados, provisionar roles y probar RLS/autorización antes de exponer datos. |
| Controles compensatorios | No hay base de datos en producción ni datos reales expuestos en esta etapa. |
| Fase de cierre | Diseño: 0.4. SQL/roles/RLS y pruebas: 0.6 y fases funcionales correspondientes. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de trasladar/corregir SQL, aplicar migraciones, provisionar roles o exponer datos; revisar cambios en tablas tenant-scoped |

### RR-003 — Validación de entradas en fronteras (T-01, T-02, E-03, D-07)

| Campo | Valor |
|---|---|
| ID amenazas | T-01, T-02, E-03, D-07 |
| Descripción | No existe política de validación implementada en ninguna frontera (BFF, backend, gRPC, workers). |
| Motivo | Depende de 0.5 (política transversal de validación de entradas). |
| Tratamiento | Mitigar: establecer validación centralizada y específica por frontera en 0.5, con pruebas negativas antes de habilitar endpoints y consumers. |
| Controles compensatorios | No hay endpoints expuestos ni datos de entrada procesados en esta etapa. |
| Fase de cierre | 0.5 |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de implementar cualquier endpoint o consumer |

### RR-004 — Secretos de infraestructura (D-05 parcial)

| Campo | Valor |
|---|---|
| ID amenazas | D-05 |
| Descripción | No existe gestor de secretos operativo configurado; la decisión de AWS administrado está aprobada, pero no desplegada. Los secretos de infraestructura (DSN, claves API, certificados) no tienen ciclo de rotación ni revocación automatizado. |
| Motivo | Depende de 0.7 (infraestructura, red, secretos y criptografía). Gitleaks en CI detecta exposición accidental en repositorio, pero no gestiona secretos operativos. |
| Tratamiento | Mitigar: AWS Secrets Manager, IAM y KMS según ADR-0023; desplegar y probar en 0.7. Gitleaks solo es un control complementario de repositorio. |
| Controles compensatorios | Gitleaks activo en CI (implementado y verificado en PR #33). Sin infraestructura productiva desplegada. |
| Fase de cierre | 0.7 |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Si se configura cualquier servicio de infraestructura antes de 0.7 |

### RR-005 — Auditoría y detección de incidentes (R-01, R-02, R-03, D-03)

| Campo | Valor |
|---|---|
| ID amenazas | R-01, R-02, R-03, D-03 |
| Descripción | No existe módulo AUDIT implementado ni plataforma de observabilidad configurada. No hay alertas, runbooks ni proceso de respuesta a incidentes operativo. |
| Motivo | Depende de 0.8 (observabilidad, auditoría y respuesta a incidentes). |
| Tratamiento | Mitigar: implementar auditoría, observabilidad, alertas y respuesta a incidentes en 0.8, con pruebas de detección y operación. |
| Controles compensatorios | Ninguno operativo en esta etapa. |
| Fase de cierre | 0.8 |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Si se exponen superficies productivas antes de completar 0.8 |

### RR-006 — DDoS y abuso de APIs (DS-01, DS-04)

| Campo | Valor |
|---|---|
| ID amenazas | DS-01, DS-04 |
| Descripción | No existe WAF, rate limiting ni protección DDoS configurada en ningún BFF. |
| Motivo | Depende de 0.7 (infraestructura y red) y de la existencia de BFF desplegados. |
| Tratamiento | Mitigar: diseñar y desplegar WAF, límites y protección DDoS en 0.7 y antes de exponer BFF en Fase 1; mantenerlos sin exposición pública hasta verificar. |
| Controles compensatorios | No hay BFF desplegado públicamente en esta etapa. |
| Fase de cierre | 0.7 y Fase 1 (despliegue inicial de BFF) |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de exponer cualquier BFF a tráfico externo |

### RR-007 — Revisión independiente no disponible en modelo solo-maintainer

| Campo | Valor |
|---|---|
| ID amenazas | E-05 (riesgo organizativo; no equivale a una vulnerabilidad técnica del workflow documental) |
| Descripción | El proyecto tiene un único mantenedor. No existe una segunda persona que pueda realizar revisión humana independiente; no se simula esa aprobación. |
| Motivo | Restricción organizativa conocida y aceptada para el estado actual del proyecto. |
| Tratamiento | Mitigar parcialmente mediante PR obligatorio, revisión propia estructurada, CI y Ruleset; no simular revisión independiente ni declarar eliminado el riesgo organizativo. Reevaluar al incorporar un segundo mantenedor. |
| Controles compensatorios | PR obligatorio; revisión propia estructurada; CI obligatorio; Ruleset activo; resolución de conversaciones; bloqueo de force-push/borrado; bypass vacío; evidencia del diff y checks. |
| Fase de cierre | Al incorporar un segundo colaborador autorizado con capacidad real de revisión. No bloquea por sí solo la operación actual mientras los controles compensatorios se mantengan. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Cada cambio sensible y cada modificación del Ruleset; además, inmediatamente al incorporar otro colaborador. |
| Estado | Riesgo organizativo conocido; controles compensatorios verificados en PR #46 y Ruleset `protect-main` (ID 28057956). |

---

### RR-008 — Dispositivos POS y operación offline

| Campo | Valor |
|---|---|
| ID amenazas | S-06, T-06, R-04, D-08, DS-06, E-08, DOM-06, DOM-07 |
| Descripción | No existe todavía implementación verificada de enrolamiento/revocación de dispositivos, protección del almacenamiento local, integridad de cola, sincronización idempotente ni reconciliación de conflictos offline. |
| Motivo | El diseño offline-first se implementará en 0.10 y las capacidades transversales de identidad, validación, infraestructura y auditoría dependen de 0.4, 0.5, 0.7 y 0.8. |
| Tratamiento | Mitigar: implementar enrolamiento/revocación, protección local, integridad, idempotencia y reconciliación offline en 0.4/0.5/0.7/0.8/0.10; no habilitar sincronización productiva antes de las pruebas. |
| Controles compensatorios | No declarar el dispositivo autoridad de tenant, permisos, precios ni estado final; limitar datos locales y no habilitar sincronización productiva antes de los controles. Son requisitos de diseño, no controles técnicos ya desplegados. |
| Fase de cierre | 0.4, 0.5, 0.7, 0.8 y 0.10; pruebas de flujo en las fases funcionales correspondientes. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de habilitar almacenamiento local con datos reales, enrolamiento o sincronización de ventas. |

### RR-009 — Backups, almacenamiento de objetos y recuperación

| Campo | Valor |
|---|---|
| ID amenazas | T-08, D-09, D-10, DS-07, T-04 (parcial) |
| Descripción | Cifrado, aislamiento, permisos, integridad y restauración de backups/objetos no están implementados ni probados en entornos reales. |
| Motivo | Depende del diseño de datos, infraestructura, almacenamiento y operación de recuperación. |
| Tratamiento | Mitigar: implementar cifrado, aislamiento, retención, integridad y restauración probada en las fases asignadas; no almacenar datos reales ni considerar réplicas como backups. |
| Controles compensatorios | No almacenar datos reales ni exponer buckets/objetos/backups públicamente; no considerar réplicas como backup. |
| Fase de cierre | 0.6, 0.7, 0.8, 0.9 y 10.7 según activo. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de almacenar archivos o datos persistentes reales y antes de cualquier despliegue productivo. |

### RR-010 — Uso de IA y herramientas externas

| Campo | Valor |
|---|---|
| ID amenazas | D-11, E-09, DS-04 (parcial) |
| Descripción | No existe todavía política técnica implementada para minimización de datos enviados a IA, aislamiento de contexto, permisos de herramientas, retención, prompt injection ni aprobación de acciones sensibles. |
| Motivo | Las integraciones de IA y sus proveedores se incorporarán solo cuando exista caso de uso, evaluación y contrato aprobados. |
| Tratamiento | Evitar temporalmente la exposición: no habilitar proveedores, modelos ni herramientas IA con datos o capacidad de acción hasta aprobar evaluación, contrato, minimización y controles técnicos. |
| Controles compensatorios | No enviar secretos, PAN, datos sensibles ni información de tenant a herramientas/modelos externos sin autorización, evaluación del proveedor y controles contractuales/técnicos. |
| Fase de cierre | Antes de cada integración IA; 0.3 define requisitos, y las fases de integración ejecutan controles. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de habilitar cualquier proveedor, agente o herramienta con acceso a datos o acciones. |

### RR-011 — Aislamiento e integridad de caché Redis

| Campo | Valor |
|---|---|
| ID amenazas | T-07 |
| Descripción | Las claves, namespaces, invalidación y pruebas de aislamiento de caché no están implementadas ni verificadas. |
| Motivo | Depende de Redis, ownership por módulo, autorización y estrategia de caché distribuida. |
| Tratamiento | Mitigar: definir namespaces por tenant/alcance, invalidación segura y pruebas de aislamiento al implementar Redis y autorización; no cachear datos sensibles hasta verificar. |
| Controles compensatorios | Redis no es fuente autoritativa ni mecanismo de autorización; no reutilizar entradas entre tenants/alcances. |
| Fase de cierre | 0.6 y 0.7; pruebas de aislamiento en las fases de implementación. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de cachear respuestas con datos de usuario, tenant o permisos. |

### RR-012 — Identidad de servicios y seguridad de mensajería

| Campo | Valor |
|---|---|
| ID amenazas | S-02, S-04, S-05, T-03, DS-05 |
| Descripción | Identidades de servicio, mTLS, ACL/subjects NATS, validación de callbacks y protección de replay no están implementados ni probados. |
| Motivo | Depende de identidad, infraestructura, mensajería y contratos de eventos. |
| Tratamiento | Mitigar: implementar identidad de servicios, mTLS, ACL de mensajería, validación de callbacks y protección contra replay antes de conectar procesos o aceptar eventos externos. |
| Controles compensatorios | No exponer endpoints administrativos ni subjects amplios; no procesar eventos externos sin validación e idempotencia. |
| Fase de cierre | 0.4, 0.6, 0.7 y fases de integración con proveedores. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de conectar procesos, publicar eventos o aceptar callbacks externos. |

### RR-013 — Cadena de suministro y despliegue

| Campo | Valor |
|---|---|
| ID amenazas | T-05, D-05 (parcial), E-05 (técnico) |
| Descripción | Gitleaks y el workflow documental están activos, pero no existe evidencia suficiente de SCA integral, SBOM, procedencia/firma de artefactos, runner de despliegue aislado ni environment productivo protegido. |
| Motivo | El workflow actual valida documentación y secretos; no es un pipeline de build/release/despliegue. |
| Tratamiento | Mitigar: ampliar el pipeline con SCA, SBOM, procedencia/firma de artefactos y despliegues protegidos antes de publicar o desplegar artefactos. |
| Controles compensatorios | PR obligatorio, CI documental con permisos `contents: read`, Gitleaks y bloqueo de merge ante fallos. |
| Fase de cierre | 0.2 para gobernanza; 0.7 y 10.5/F.6 para cadena de suministro y despliegue. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de generar/publicar imágenes, artefactos o desplegar a staging/producción. |

### RR-014 — Integridad y autorización de operaciones de pago

| Campo | Valor |
|---|---|
| ID amenazas | D-06, DOM-03 |
| Descripción | El flujo PSP, tokenización, autorización de reversos/anulaciones y pruebas de integridad financiera no están implementados ni certificados. |
| Motivo | Depende de las fases de pagos/caja y de la integración con proveedor seleccionado. |
| Tratamiento | Evitar temporalmente el procesamiento financiero real: no procesar pagos ni ejecutar reversos reales hasta implementar y probar integración PSP, tokenización, autorización e idempotencia. |
| Controles compensatorios | No almacenar PAN ni datos completos de tarjeta; no marcar pagos como confirmados por callback no verificado; no permitir anulación sin autorización. |
| Fase de cierre | Fase 2 y fases de caja/pagos; preparación de cumplimiento antes de producción. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de procesar pagos reales o almacenar tokens/datos financieros. |

### RR-015 — Disponibilidad de PostgreSQL y límites de recursos

| Campo | Valor |
|---|---|
| ID amenazas | DS-02 |
| Descripción | Los pools, circuit breakers, timeouts y límites reales aún no están implementados ni dimensionados. |
| Motivo | Depende de la implementación de PostgreSQL y de pruebas de carga/degradación. |
| Tratamiento | Mitigar: dimensionar y configurar pools, límites, timeouts, circuit breakers y pruebas de carga/degradación antes de habilitar concurrencia productiva. |
| Controles compensatorios | No exponer el servicio ni aceptar tráfico productivo sin límites y pruebas; el diseño de pooling no equivale a configuración ejecutada. |
| Fase de cierre | 0.6, 0.7 y pruebas de carga/operación. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de habilitar tráfico concurrente o cargas productivas. |

## Trazabilidad de amenazas a riesgos residuales

| Amenazas | Riesgo |
|---|---|
| S-01, S-03, E-06, E-07 | RR-001 |
| D-01, D-02, E-01, E-02, E-04, DOM-04, DOM-07 | RR-002; RR-008 para sincronización de dispositivo |
| T-01, T-02, E-03, D-07 | RR-003 |
| D-05 | RR-004 y RR-013 |
| R-01, R-02, R-03, R-04, D-03 | RR-005; RR-008 para auditoría offline |
| D-04, DS-01, DS-04 | RR-006; RR-010 para herramientas IA; RR-008 para sync |
| S-02, S-04, S-05, T-03, DS-05 | RR-012 |
| S-06, T-06, R-04, D-08, DS-06, E-08, DOM-06, DOM-07 | RR-008 |
| T-04, DS-03, T-08, D-09, D-10, DS-07 | RR-009 |
| D-11, E-09 | RR-010 |
| T-07 | RR-011 |
| T-05, E-05 técnico | RR-013 |
| D-06, DOM-03 | RR-014 |
| DS-02 | RR-015 |
| DOM-01, DOM-02, DOM-05 | Se cubren en el diseño de autorización/auditoría del módulo; mantener como Diseñado hasta pruebas de sus fases funcionales. |

## Riesgos cerrados

| ID | Descripción breve | Fecha de cierre | Evidencia |
|---|---|---|---|
| — | No hay riesgos cerrados en esta versión | — | — |
