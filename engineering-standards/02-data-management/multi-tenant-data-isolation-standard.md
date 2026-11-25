# Estándar de aislamiento de datos multi-tenant

**Versión:** 0.1.0 | **Estado:** Draft  
**Aplicabilidad:** sistemas que procesan datos de más de una organización o cliente bajo una misma plataforma.

## Objetivo

Prevenir acceso, modificación, inferencia o exposición de datos entre tenants sin autorización explícita.

## Requisitos

- El tenant efectivo debe derivarse de contexto autenticado y autorizado, no confiarse a un identificador enviado por el cliente.
- Toda consulta, comando, job, evento y tarea de soporte debe conservar el contexto de tenant cuando corresponda.
- El aislamiento debe aplicarse en el backend propietario y reforzarse en persistencia cuando sea viable.
- Las políticas RLS, filtros de tenant y permisos deben probarse contra rutas positivas y negativas.
- Los caches, índices de búsqueda, objetos, archivos, exports, métricas y logs deben incorporar límites de tenant o clasificación apropiada.
- Los identificadores opacos no son controles de autorización.
- Los procesos batch y workers deben evitar contexto vacío, reutilizado o contaminado entre tareas.
- Las operaciones cross-tenant requieren permiso específico, finalidad, alcance y auditoría.
- Las copias de seguridad, restauraciones y entornos de prueba deben preservar aislamiento.
- Los datos compartidos explícitamente deben tener modelo de acceso separado y documentado.

## Ciclo de vida

La creación, suspensión, transferencia, exportación y eliminación de tenant deben ser procesos idempotentes, auditables y coordinados con propietarios de datos. El borrado de una organización no debe eliminar automáticamente datos que pertenecen a personas o que deban conservarse legalmente.

## Verificación

Pruebas automatizadas tenant A contra tenant B, fuzzing de IDs, pruebas de workers, cache poisoning, exportación y restauración. Las fugas cross-tenant críticas bloquean la liberación.
