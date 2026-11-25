# Registro de riesgos residuales

**Estado:** vigente
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.3
**Fuente:** [Modelo de amenazas](./threat-model.md) y [Matriz de control](./threat-control-matrix.md)

---

## Lectura del registro

Un riesgo residual es una amenaza para la que no existe aún un control implementado y verificado,
o cuyo control tiene limitaciones conocidas. Cada entrada incluye:

- **ID:** referencia al ID de amenaza en `threat-model.md`.
- **Descripción:** qué riesgo permanece abierto.
- **Motivo:** por qué el control no está implementado todavía.
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
| Controles compensatorios | El repositorio no tiene superficies públicas desplegadas. No hay endpoints expuestos en esta etapa. |
| Fase de cierre | 0.4 — Identidad, autorización y aislamiento |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Si se expone cualquier endpoint antes de completar 0.4 |

### RR-002 — Aislamiento multi-tenant y RBAC (D-01, D-02, E-01, E-02, E-04)

| Campo | Valor |
|---|---|
| ID amenazas | D-01, D-02, E-01, E-02, E-04 |
| Descripción | No existen RLS, roles PostgreSQL por módulo ni lógica de autorización RBAC/ABAC implementada. |
| Motivo | Depende de 0.4 (modelo de identidad) y 0.6 (diseño de PostgreSQL y RLS). |
| Controles compensatorios | No hay base de datos en producción ni datos reales expuestos en esta etapa. |
| Fase de cierre | 0.4 y 0.6 |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Si se crean tablas o se exponen datos antes de completar 0.4 y 0.6 |

### RR-003 — Validación de entradas en fronteras (T-01, T-02, E-03, D-07)

| Campo | Valor |
|---|---|
| ID amenazas | T-01, T-02, E-03, D-07 |
| Descripción | No existe política de validación implementada en ninguna frontera (BFF, backend, gRPC, workers). |
| Motivo | Depende de 0.5 (política transversal de validación de entradas). |
| Controles compensatorios | No hay endpoints expuestos ni datos de entrada procesados en esta etapa. |
| Fase de cierre | 0.5 |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de implementar cualquier endpoint o consumer |

### RR-004 — Secretos de infraestructura (D-05 parcial)

| Campo | Valor |
|---|---|
| ID amenazas | D-05 |
| Descripción | No existe gestor de secretos configurado. Los secretos de infraestructura (DSN, claves API, certificados) no tienen ciclo de rotación ni revocación automatizado. |
| Motivo | Depende de 0.7 (infraestructura, red, secretos y criptografía). Gitleaks en CI detecta exposición accidental en repositorio, pero no gestiona secretos operativos. |
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
| Controles compensatorios | No hay BFF desplegado públicamente en esta etapa. |
| Fase de cierre | 0.7 y Fase 1 (despliegue inicial de BFF) |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de exponer cualquier BFF a tráfico externo |

### RR-007 — Aprobación independiente de PR (riesgo de gobernanza)

| Campo | Valor |
|---|---|
| ID amenazas | E-05 (parcial) |
| Descripción | El Ruleset `protect-main` tiene `Required approvals: 0` porque el repositorio tiene un único propietario. No existe revisión humana independiente de los cambios mergeados. |
| Motivo | Decisión operativa explícita del propietario del producto. Con un solo colaborador no es posible revisión independiente. |
| Controles compensatorios | PR obligatorio para todo cambio; CI con markdownlint, validación de enlaces y Gitleaks activos; historial Git completo. |
| Fase de cierre | Cuando se incorpore un segundo colaborador con escritura |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Al incorporar cualquier colaborador con permisos de escritura |

---

## Riesgos cerrados

| ID | Descripción breve | Fecha de cierre | Evidencia |
|---|---|---|---|
| — | No hay riesgos cerrados en esta versión | — | — |
