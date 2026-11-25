# Estándar de estrategia de identificadores

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Definir identificadores estables, únicos dentro de su ámbito y seguros para contratos, persistencia e integración.

## Requisitos

- Cada tipo de identificador debe declarar ámbito de unicidad, propietario, formato, exposición y ciclo de vida.
- Los identificadores públicos no deben actuar como autorización ni sustituir comprobaciones de acceso.
- No exponer secuencias internas cuando ello revele información sensible o permita enumeración abusiva.
- Separar identidad técnica, número de negocio, token de acceso y clave de idempotencia.
- No usar timestamps, orden lexicográfico o UUID como sustituto de secuencia causal de eventos.
- Las claves naturales mutables no deben usarse como identidad técnica primaria sin justificación.
- Los identificadores distribuidos deben evaluar colisiones, generación offline, orden aproximado, filtración de metadatos y compatibilidad de bibliotecas.
- La transición de formato debe contemplar claves foráneas, índices, eventos, outbox/inbox, logs, caches, exports, URLs e integraciones.

## Selección

UUIDv4, UUIDv7, ULID, enteros, snowflake y claves naturales tienen propiedades diferentes. La elección debe basarse en requisitos medidos y documentarse en ADR; esta biblioteca no impone un formato universal.

## Migración

Una transición debe definir coexistencia temporal, mapeo de equivalencias, doble lectura/escritura si aplica, backfill, validación de referencias, corte, reversión y retiro de formato anterior.

## Verificación

Pruebas de unicidad, concurrencia, compatibilidad de serialización, privacidad y migración de referencias.
