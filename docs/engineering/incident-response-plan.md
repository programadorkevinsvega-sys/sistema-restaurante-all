# Plan de respuesta a incidentes y ejercicios

**Estado:** diseño aprobado — subfase 0.8
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.8
**Autoridad:** ADR-0026
**Documentos relacionados:**

- [Runbooks de respuesta a incidentes](./incident-response-runbooks.md)
- [Matriz de alertas](./alert-matrix.md)
- [Catálogo de eventos auditables](./audit-events-catalog.md)

---

## 1. Ciclo de respuesta

Toda respuesta a incidente sigue este ciclo:

```text
Preparación → Detección → Triage → Contención → Erradicación → Recuperación → Comunicación → Postmortem
```

### 1.1 Preparación (antes de que ocurra el incidente)

- Inventario de activos, procesos y módulos con sus propietarios.
- Responsables designados por área (Ops, Dev, Security).
- Accesos de emergencia documentados y probados.
- Runbooks actualizados y accesibles sin depender del sistema afectado.
- Backups verificados periódicamente.
- Canal de comunicación de incidentes definido (no depende de los sistemas afectados).

### 1.2 Detección y registro

1. La alerta llega por Alertmanager o es reportada manualmente.
2. Abrir un ticket/issue de incidente con timestamp de detección.
3. Asignar severidad inicial según la matriz de alertas.
4. Preservar evidencia inmediatamente: logs, trazas, eventos de auditoría.
5. No borrar ni modificar nada hasta tener copias de evidencia.

### 1.3 Triage

1. Identificar activos afectados: procesos, módulos, tenants, datos.
2. Determinar el alcance: ¿cuántos tenants? ¿qué datos? ¿desde cuándo?
3. Evaluar posible exfiltración, corrupción o pérdida de disponibilidad.
4. Confirmar o ajustar la severidad.
5. Asignar responsable principal y escalar si necesario.

### 1.4 Contención

Acciones posibles según el tipo de incidente:

- Revocar credenciales, sesiones o tokens comprometidos.
- Bloquear una integración o proveedor externo.
- Aislar un tenant o proceso si el impacto lo justifica.
- Restringir tráfico hacia un componente afectado.
- Deshabilitar temporalmente una funcionalidad mientras se investiga.

**Regla:** contener sin destruir evidencia ni eliminar datos bajo legal hold.

### 1.5 Erradicación

- Corregir la causa raíz (bug, configuración, credencial comprometida, dependencia).
- Parchear o reconstruir artefactos afectados.
- Rotar secretos si hubo exposición.
- Verificar que la causa raíz está eliminada antes de restaurar.

### 1.6 Recuperación

- Restaurar desde backup si hubo pérdida de datos (ver plan backup/PITR).
- Reconciliar operaciones que quedaron en estado inconsistente.
- Verificar integridad de los datos después de la restauración.
- Reactivar el componente o tenant afectado gradualmente.
- Monitorear activamente durante el período post-recuperación.

### 1.7 Comunicación

| Audiencia | Cuándo | Qué comunicar |
|---|---|---|
| Responsables internos | Al detectar | Alerta inicial con severidad estimada |
| Equipo técnico | Durante triage | Alcance, estado y necesidad de apoyo |
| Tenants afectados | Cuando hay impacto confirmado | Qué ocurrió, impacto en sus datos/operación, acciones tomadas |
| Autoridades regulatorias | Según jurisdicción y tipo de dato | Según evaluación jurídica por jurisdicción; no asumir plazos universales |

La comunicación a tenants y autoridades se coordina con revisión jurídica antes de enviar.
No se prometen plazos de notificación sin conocer las jurisdicciones y contratos aplicables.

### 1.8 Postmortem

Dentro de las 72 horas de cerrado el incidente (o antes para incidentes críticos):

- Cronología de eventos con timestamps.
- Causa raíz (no culpables: buscar fallos de sistema, proceso o diseño).
- Impacto: tenants afectados, duración, datos comprometidos/perdidos.
- Decisiones tomadas y su justificación.
- Acciones correctivas con responsable y fecha límite.
- Mejoras a runbooks, alertas, procesos o arquitectura.

El postmortem se comparte con el equipo y queda registrado. No se publica externamente sin revisión.

---

## 2. Clasificación de severidad

| Severidad | Criterio | Tiempo objetivo de respuesta |
|---|---|---|
| Critical | Pérdida de datos, exposición de credenciales, cruce de tenants, servicio completamente caído | Respuesta inmediata; < 15 min para contención inicial |
| High | Degradación severa de servicio, intento de escalada, fallo de backup | < 1 hora para triage completo |
| Medium | Degradación parcial, alertas de capacidad, anomalías sin impacto confirmado | < 4 horas |
| Low | Alertas de mantenimiento, incidencias menores sin impacto en tenants | Horario laboral siguiente |

Los tiempos objetivo son de diseño y se ajustan con el equipo real antes de producción.

---

## 3. Responsables por área

| Área | Responsabilidad durante incidente |
|---|---|
| Ops | Infraestructura, bases de datos, red, monitoreo y disponibilidad |
| Dev | Código, módulos, workers, Sagas y diagnóstico de bugs |
| Security | Incidentes de seguridad, credenciales, auditoría y comunicación regulatoria |
| Producto | Decisiones de impacto en tenants y comunicación a clientes |

Antes de producción se designan personas concretas para cada rol y se documentan sus datos de contacto en un lugar accesible sin depender de los sistemas afectados.

---

## 4. Plan de ejercicios

Los siguientes ejercicios se ejecutan antes de exponer superficies productivas:

| Ejercicio | Tipo | Objetivo |
|---|---|---|
| Failover de PostgreSQL | Técnico | Verificar que el clúster HA promueve un standby y los procesos reconectan |
| Revocación de sesiones masiva | Técnico | Verificar que todas las sesiones de un tenant pueden revocarse inmediatamente |
| Rotación de emergencia de secreto | Técnico | Verificar el runbook de rotación de emergencia end-to-end |
| Restauración PITR | Técnico | Restaurar la base a un instante específico en entorno aislado y verificar datos |
| Fallo de NATS y recuperación de Outbox | Técnico | Verificar que los mensajes en Outbox se publican correctamente cuando NATS se restaura |
| Tabletop: compromiso de cuenta privilegiada | Tabletop | Recorrer el ciclo completo de respuesta sin ejecutar acciones reales |
| Tabletop: exfiltración de datos de un tenant | Tabletop | Identificar cómo se detectaría, contendría y comunicaría |
| Tabletop: ransomware en infraestructura | Tabletop | Identificar puntos de aislamiento, backups disponibles y tiempo de recuperación |
| Simulacro de alerta falsa | Técnico | Verificar que los runbooks diferencian una alerta real de un falso positivo |

Los ejercicios técnicos se ejecutan en entornos de staging o aislados; nunca en producción sin aprobación explícita.

---

## 5. Estado de implementación

Plan aprobado como diseño. No existen responsables designados, canales de comunicación
configurados ni ejercicios ejecutados. Se completan antes de exponer cualquier
superficie productiva.
