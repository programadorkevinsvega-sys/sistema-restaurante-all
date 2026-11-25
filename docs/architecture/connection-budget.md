# Presupuesto de conexiones por proceso/módulo/réplica

**Estado:** diseño aprobado — subfase 0.6
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.6
**Autoridad:** ADR-0010, ADR-0001
**Base:** [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md)
**Documentos relacionados:**

- [Diseño PostgreSQL HA](./postgresql-ha-design.md)

---

## 1. Propósito y límites

Define la estructura del presupuesto de conexiones PostgreSQL. Los valores numéricos concretos
(tamaños de pool, `max_connections`, límites por módulo) se dimensionan con carga real medida
antes de producción. Este documento establece la estructura, las reglas y los límites por capas;
no inventa números universales.

---

## 2. Principios del presupuesto

- El total de conexiones del servidor (`max_connections`) es finito. El presupuesto lo distribuye
  entre todos los consumidores sin excederlo.
- Cada módulo tiene pool propio; no existe un pool compartido entre módulos.
- Los BFF no tienen pool PostgreSQL de negocio.
- El presupuesto incluye: pools de escritura, pools de lectura elegible, conexiones de migración,
  conexiones de backup, monitoreo, replicación y margen operativo.
- El margen operativo reserva conexiones para rolling deployments, herramientas de administración
  y emergencias; no se consume en operación normal.

---

## 3. Capas del presupuesto

```
max_connections (servidor)
├── Replicación física           (standby síncrono + asíncronos + wal_sender slots)
├── Backup y archivado           (backup_reader; solo durante ventanas de backup)
├── Monitoreo                    (monitoring_reader; conexiones de exporter)
├── Migración                    (cada *_migrator; solo durante ventanas de migración)
├── Administración y emergencia  (DBA y operaciones; margen reservado)
└── Aplicación
    ├── Admin Platform Backend
    │   └── PLATFORM
    │       ├── pool escritura   (platform_runtime → primario)
    │       └── pool lectura     (platform_runtime readonly → réplica; si aplica)
    └── Public Backend
        ├── IDENTITY
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── ORGANIZATION
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── CATALOG
        │   ├── pool escritura
        │   └── pool lectura     ← elegible (listados, búsquedas)
        ├── SALES
        │   └── pool escritura   ← solo primario (decisiones críticas)
        ├── PAYMENTS
        │   └── pool escritura   ← solo primario (financiero crítico)
        ├── CASH
        │   └── pool escritura   ← solo primario
        ├── KITCHEN
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── INVENTORY
        │   └── pool escritura   ← solo primario (disponibilidad para decisión)
        ├── PROCUREMENT
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── PRODUCTION
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── BILLING
        │   └── pool escritura   ← solo primario (fiscal crítico)
        ├── FINANCE
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── WORKFORCE
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── CUSTOMERS
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── INTEGRATIONS
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── AUTOMATION
        │   ├── pool escritura
        │   └── pool lectura (si aplica)
        ├── ANALYTICS
        │   └── pool lectura     ← principalmente réplica
        ├── AUDIT
        │   └── pool escritura   ← solo primario (integridad de auditoría)
        └── REPORTING
            └── pool lectura     ← réplica; consultas costosas acotadas
```

---

## 4. Módulos con pool de lectura elegible

Solo los módulos cuyas consultas cumplen los criterios de elegibilidad definidos en
`postgresql-ha-and-read-replicas.md` tienen pool de lectura separado.

| Módulo | Pool lectura | Justificación |
|---|---|---|
| CATALOG | Sí | Listados y búsquedas de alta frecuencia; staleness aceptable |
| ANALYTICS | Sí (principal) | Dashboards y agregaciones; toleran retraso |
| REPORTING | Sí | Informes y exportaciones costosas; acotadas por cuota |
| WORKFORCE | Sí | Consultas de horarios y asistencia históricas |
| CUSTOMERS | Sí | Historial y segmentación; no para decisiones en tiempo real |
| PROCUREMENT | Sí | Consultas de proveedores y cotizaciones históricas |
| PRODUCTION | Sí | Consultas de recetas y rendimientos; no disponibilidad operativa |
| FINANCE | Sí | Reportes contables; no saldos en tiempo real |
| PAYMENTS | No | Financiero crítico; siempre primario |
| SALES | No | Decisiones de pedido requieren consistencia inmediata |
| CASH | No | Caja y arqueos; consistencia inmediata |
| BILLING | No | Documentos fiscales; consistencia inmediata |
| INVENTORY | No | Disponibilidad para decisión; siempre primario |
| IDENTITY | No | Sesiones y permisos; consistencia inmediata |
| AUDIT | No | Escritura de auditoría; siempre primario |

---

## 5. Parámetros a dimensionar por módulo

Antes de producción, cada módulo define:

| Parámetro | Descripción |
|---|---|
| `pool_write_min` | Conexiones mínimas mantenidas al primario |
| `pool_write_max` | Conexiones máximas al primario |
| `pool_read_min` | Conexiones mínimas a réplica (si aplica) |
| `pool_read_max` | Conexiones máximas a réplica (si aplica) |
| `acquire_timeout` | Tiempo máximo de espera para obtener conexión del pool |
| `idle_timeout` | Tiempo antes de cerrar conexión ociosa |
| `max_lifetime` | Vida máxima de una conexión antes de reemplazarla |
| `staleness_max` | Retraso máximo tolerado en réplica (ms) para este módulo |

Los valores se derivan de: carga medida, concurrencia esperada, latencia objetivo,
instancias del proceso y presupuesto global del servidor.

---

## 6. Reglas de operación del pool

- Tras failover, los pools descartan conexiones obsoletas y reconectan al nuevo endpoint.
- `SET LOCAL app.tenant_id` se ejecuta en cada transacción; nunca se reutiliza de la conexión anterior.
- Las transacciones son breves; no se mantienen abiertas esperando operaciones externas.
- Un pool agotado aplica backpressure; no crea conexiones ilimitadas.
- Si la réplica supera `staleness_max`, el pool de lectura falla al primario o rechaza la consulta según criticidad.

---

## 7. Estado de implementación

Diseño aprobado. No existen pools configurados, credenciales emitidas ni
`max_connections` fijado. Los valores numéricos se dimensionan en la subfase 0.7
con la infraestructura real.
