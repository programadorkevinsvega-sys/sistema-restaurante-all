# Estándar de esquemas y migraciones de bases de datos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Gestionar cambios de persistencia de forma reproducible, revisable y segura para datos existentes.

## Requisitos

- Las migraciones deben estar versionadas, ordenadas, inmutables después de aplicarse y asociadas a un propietario.
- Debe existir historial de migraciones por unidad de ownership o por el límite que defina la arquitectura.
- Las migraciones de producción deben ejecutarse con identidad privilegiada separada del runtime.
- Las aplicaciones no deben requerir privilegios DDL en operación normal.
- Los cambios deben analizar bloqueo, volumen, tiempo, compatibilidad y consumo de recursos.
- Preferir migraciones expand/contract: añadir estructura compatible, desplegar lectores/escritores, migrar datos por lotes y retirar lo antiguo después de verificar.
- Las migraciones de datos deben ser idempotentes o contar con checkpoints y recuperación.
- No ejecutar cambios destructivos sin backup verificado, plan de reversión o roll-forward y aprobación.
- El rollback de esquema no debe asumirse seguro si ya hubo escrituras con el nuevo formato.
- Las restricciones de integridad deben permanecer activas o tener una estrategia temporal explícita.

## Operación

- Probar migraciones con volúmenes representativos.
- Medir locks y duración.
- Definir ventana, monitoreo y criterio de aborto.
- Validar datos antes y después.
- Registrar versión de aplicación compatible con cada versión de esquema.

## Verificación

Pruebas desde esquema vacío y desde versiones soportadas, migración de datos, compatibilidad de despliegue y recuperación.
