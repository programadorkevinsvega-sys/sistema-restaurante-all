# Registro de riesgos residuales

**Estado:** vigente
**Versión:** 1.3
**Fecha:** 2026-11-25
**Fase:** 0.3/0.4
**Fuente:** [Modelo de amenazas](./threat-model.md) y [Matriz de control](./threat-control-matrix.md)

## Lectura del registro

Un riesgo residual es una amenaza para la que no existe aún un control implementado y verificado,
o cuyo control tiene limitaciones conocidas. Los SQL históricos del repositorio son la base de
datos diseñada para cada módulo. La presencia de tablas, constraints o DDL RLS en esos archivos
no demuestra que se hayan trasladado a las rutas canónicas, aplicado en una instancia ni probado.

Cada entrada conserva ID, descripción, motivo, tratamiento, controles compensatorios, fase de
cierre, propietario y condición de revisión. Tratamiento no equivale a aceptación formal ni a
cierre. La aceptación formal requiere aprobación explícita del propietario del producto.

## Riesgos abiertos

### RR-001 — Autenticación y sesiones

| Campo | Valor |
|---|---|
| Descripción | No hay flujos ejecutables verificados de autenticación, sesiones, rotación de tokens ni controles de navegador. |
| Motivo | El diseño de identidad está en 0.4; implementación funcional en fases posteriores. |
| Tratamiento | Mitigar: implementar y probar autenticación/sesiones antes de exponer superficies. |
| Estado | Abierto |

### RR-002 — Aislamiento multi-tenant y RBAC

| Campo | Valor |
|---|---|
| Descripción | Existe DDL histórico RLS en determinados módulos/tablas, pero no se ha acreditado aplicación ni cobertura completa; tampoco provisión de roles runtime/migrator ni lógica ejecutable RBAC/ABAC probada. |
| Motivo | Modelo y contrato en 0.4; distribución canónica de SQL, reconciliación de referencias cross-schema, roles y verificación de RLS en 0.6 y fases funcionales. |
| Tratamiento | Mitigar: inventariar DDL sin reescribir históricos ahora; trasladar/corregir SQL mediante cambios autorizados, provisionar roles y probar RLS/autorización antes de exponer datos. |
| Controles compensatorios | No hay base de datos productiva ni datos reales expuestos en esta etapa. |
| Fase de cierre | Diseño: 0.4. SQL/roles/RLS: 0.6 y fases funcionales. |
| Propietario | @programadorkevinsvega-sys |
| Condición de revisión | Antes de trasladar/corregir SQL, aplicar migraciones, provisionar roles o exponer datos. |

### RR-003 — Validación de entradas

| Campo | Valor |
|---|---|
| Descripción | Política transversal de validación no implementada. |
| Motivo | Depende de 0.5. |
| Tratamiento | Definir y probar validación por frontera antes de habilitar endpoints y consumers. |
| Fase de cierre | 0.5 |

### RR-004 — Secretos de infraestructura

| Campo | Valor |
|---|---|
| Descripción | Gestor de secretos y ciclo operativo de rotación/revocación aún no configurados. |
| Motivo | Depende de 0.7; Gitleaks no gestiona secretos operativos. |
| Tratamiento | AWS Secrets Manager, IAM y KMS según ADR-0028; desplegar y probar en 0.7. |
| Controles compensatorios | Gitleaks activo en CI; sin infraestructura productiva desplegada. |
| Fase de cierre | 0.7 |

### RR-005 — Auditoría y detección

| Campo | Valor |
|---|---|
| Descripción | AUDIT/observabilidad, alertas, runbooks y respuesta a incidentes no operativos. |
| Motivo | Depende de 0.8. |
| Tratamiento | Implementar y probar auditoría, detección y respuesta. |
| Fase de cierre | 0.8 |

### RR-006 — DDoS y abuso de APIs

| Campo | Valor |
|---|---|
| Descripción | WAF, rate limiting y protección DDoS no configurados. |
| Motivo | Depende de infraestructura y BFF desplegados. |
| Tratamiento | Desplegar controles antes de exponer BFF. |
| Fase de cierre | 0.7 y Fase 1 |

### RR-007 — Revisión independiente no disponible

| Campo | Valor |
|---|---|
| Descripción | Proyecto con un único mantenedor; no existe segunda revisión humana independiente. |
| Motivo | Restricción organizativa conocida. |
| Tratamiento | PR obligatorio, revisión propia estructurada y CI; no simular revisión independiente. |
| Controles compensatorios | PR, CI y Ruleset verificados. |
| Estado | Riesgo organizativo conocido; no bloquea el modelo actual. |

### RR-008 — Dispositivos POS y operación offline

| Campo | Valor |
|---|---|
| Descripción | Enrolamiento/revocación, protección local, sync e idempotencia offline no implementados ni verificados. |
| Motivo | Depende de 0.4, 0.5, 0.7, 0.8 y 0.10. |
| Tratamiento | No habilitar sincronización productiva hasta completar pruebas. |
| Fase de cierre | 0.4/0.5/0.7/0.8/0.10 y fases funcionales |

### RR-009 — Backups y recuperación

| Campo | Valor |
|---|---|
| Descripción | Cifrado, aislamiento y restauración de backups/objetos no implementados ni probados. |
| Motivo | Depende de datos e infraestructura. |
| Tratamiento | Implementar copias protegidas y restauración probada; no considerar réplicas como backups. |
| Fase de cierre | 0.6/0.7/0.8/0.9 y fase 10.7 |

### RR-010 — IA y herramientas externas

| Campo | Valor |
|---|---|
| Descripción | Política técnica para datos, contexto, permisos, prompt injection y acciones IA no implementada. |
| Motivo | Integraciones IA futuras requieren evaluación y contrato. |
| Tratamiento | No habilitar proveedores/modelos con datos o acciones hasta aprobar controles. |
| Fase de cierre | Antes de cada integración IA |

### RR-011 — Aislamiento de caché Redis

| Campo | Valor |
|---|---|
| Descripción | Namespaces, invalidación y pruebas de aislamiento no implementados. |
| Motivo | Depende de Redis y autorización. |
| Tratamiento | Definir namespaces por tenant/alcance; no cachear datos sensibles hasta verificar. |
| Fase de cierre | 0.6/0.7 y fases funcionales |

### RR-012 — Identidad de servicios y mensajería

| Campo | Valor |
|---|---|
| Descripción | mTLS, identidades de workload, contexto firmado, ACL NATS y protección replay no implementados ni probados. |
| Motivo | Diseño en 0.4; certificados/identidades y mensajería dependen de 0.7/0.9. |
| Tratamiento | Aplicar ADR-0028; no conectar procesos ni aceptar eventos externos sin autenticación, autorización e idempotencia. |
| Fase de cierre | 0.4/0.7/0.9 y fases de integración |

### RR-013 — Cadena de suministro

| Campo | Valor |
|---|---|
| Descripción | SCA integral, SBOM, procedencia/firma de artefactos y despliegue protegido no acreditados. |
| Motivo | CI actual valida documentación y secretos; no es pipeline de release. |
| Tratamiento | Incorporar controles antes de publicar o desplegar artefactos. |
| Fase de cierre | 0.2/0.7 y fases de despliegue |

### RR-014 — Integridad de pagos

| Campo | Valor |
|---|---|
| Descripción | Flujo PSP, tokenización, autorización de reversos y pruebas financieras no implementados. |
| Motivo | Depende de fases de pagos/caja y proveedor. |
| Tratamiento | No procesar pagos reales hasta implementar y probar integración e idempotencia. |
| Fase de cierre | Fase 2 y preparación de producción |

### RR-015 — Disponibilidad PostgreSQL

| Campo | Valor |
|---|---|
| Descripción | Pools, circuit breakers, timeouts y límites no implementados ni dimensionados. |
| Motivo | Depende de 0.6 y pruebas de carga. |
| Tratamiento | Dimensionar, configurar y probar antes de tráfico productivo. |
| Fase de cierre | 0.6/0.7 y pruebas de carga |

## Trazabilidad de amenazas a riesgos residuales

| Amenazas | Riesgo |
|---|---|
| S-01, S-03, E-06, E-07 | RR-001 |
| D-01, D-02, E-01, E-02, E-04, DOM-04, DOM-07 | RR-002; RR-008 para sincronización offline |
| T-01, T-02, E-03, D-07 | RR-003 |
| D-05 | RR-004 y RR-013 |
| R-01, R-02, R-03, D-03 | RR-005 |
| DS-01, DS-04 | RR-006; RR-010 para IA |
| S-02, S-04, S-05, T-03, DS-05 | RR-012 |
| S-06, T-06, R-04, D-08, DS-06, E-08, DOM-06, DOM-07 | RR-008 |
| T-04, T-08, D-09, D-10, DS-07 | RR-009 |
| D-11, E-09 | RR-010 |
| T-07 | RR-011 |
| T-05, E-05 técnico | RR-013 |
| D-06, DOM-03 | RR-014 |
| DS-02 | RR-015 |

## Riesgos cerrados

No hay riesgos cerrados en esta versión.
