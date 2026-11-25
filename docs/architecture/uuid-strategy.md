# Estrategia UUIDv7 y transición de identificadores existentes

**Estado:** diseño aprobado — subfase 0.6
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.6
**Autoridad:** ADR-0012
**Base:** [Estrategia técnica de identificadores UUIDv7](./identifier-strategy.md)

---

## 1. Propósito

Concreta las decisiones operativas de ADR-0012 para la implementación:
dónde se genera el UUIDv7, cómo se valida, qué no se usa para y cómo
se planifica la transición de identificadores existentes.

Es un diseño; no modifica SQL, migraciones ni código.

---

## 2. Regla de generación por módulo

Cada módulo decide la autoridad de generación para cada entidad según su flujo:

| Situación | Autoridad de generación | Mecanismo |
|---|---|---|
| Entidad creada en una sola operación de persistencia | PostgreSQL o aplicación | `uuidv7()` en PostgreSQL 19 o crate Rust conforme a RFC 9562 |
| ID necesario antes de persistir (Saga, Outbox, contrato) | Aplicación | Crate Rust conforme a RFC 9562; fijado en versión |
| ID que viaja entre procesos antes de escritura | Aplicación | Crate Rust; propagado en contrato gRPC/evento |

**Reglas:**

- Nunca dos capas generan y reemplazan el ID de la misma entidad sin regla explícita.
- El crate Rust de generación se fija en versión en `Cargo.toml`; no se usa `latest`.
- La función `uuidv7()` de PostgreSQL solo se usa si la versión desplegada es ≥ 18;
  confirmar antes de usar.
- Los UUIDs recibidos se validan en formato y versión en cada frontera de entrada
  (ver catálogo de reglas de validación).

---

## 3. Usos prohibidos de UUIDv7

UUIDv7 **no se usa** para:

- sustituir `created_at` o `updated_at` como timestamp de negocio;
- decidir orden legal, comercial o contable de operaciones;
- demostrar precedencia causal entre eventos;
- sustituir folios, secuencias o numeraciones de negocio;
- resolver conflictos de concurrencia;
- determinar routing de lectura/escritura.

Cuando se necesite orden estricto, se usa un atributo, versión, secuencia monotónica
o mecanismo de coordinación explícito bajo el ownership del módulo.

---

## 4. Plan de transición de identificadores existentes

Las migraciones históricas en `migrations/` contienen identificadores en distintos formatos.
La transición a UUIDv7 se ejecuta módulo a módulo, nunca como un cambio global.

### 4.1 Prerequisito por módulo antes de migrar

Antes de iniciar la transición de cualquier módulo, completar el inventario:

- [ ] PKs, FKs, constraints, índices y columnas con referencias UUID en el schema del módulo.
- [ ] Referencias en campos JSONB, Outbox, Inbox, AUDIT y eventos publicados.
- [ ] IDs incluidos en contratos OpenAPI/Protobuf, webhooks e integraciones externas.
- [ ] Consumidores de otros módulos que referencian IDs de este módulo.
- [ ] Claves de idempotencia y deduplicación que usen IDs del módulo.
- [ ] Datos históricos y exportaciones que ya emitieron IDs.

### 4.2 Estrategia de coexistencia

Durante la transición, el módulo puede operar con un período de coexistencia:

1. Nuevas entidades generan UUIDv7.
2. Entidades existentes conservan su ID original hasta que se complete el backfill autorizado.
3. El módulo acepta referencias en ambos formatos durante la transición.
4. Se define un mapeo inequívoco entre ID anterior y UUIDv7 cuando aplique.

La transición de cada módulo requiere:

- Tarea SQL y migración separada, autorizada expresamente.
- Pruebas de integridad, backfill, compatibilidad y rollback.
- Coordinación con consumidores antes de retirar el formato anterior.

### 4.3 Lo que no se hace

- No reescribir migraciones históricas ya aplicadas.
- No cambiar IDs de módulos ajenos.
- No crear FKs entre schemas para facilitar la transición.
- No asumir que todos los módulos migran al mismo tiempo.

---

## 5. Estado de implementación

Diseño aprobado. No existen crates de generación configurados, funciones SQL ejecutadas
ni migraciones de transición planificadas para ningún módulo específico.
Cada módulo ejecuta su transición como tarea independiente cuando se implemente.
