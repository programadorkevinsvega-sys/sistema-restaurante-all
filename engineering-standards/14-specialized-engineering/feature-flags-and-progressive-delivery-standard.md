# Estándar de feature flags y entrega progresiva

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** activación gradual, experimentos y despliegues progresivos.

## Objetivo y alcance

Establecer controles para activar capacidades de forma reversible y reducir el riesgo de releases. No sustituye autorización ni controles de seguridad.

## Requisitos

- Clasificar flags como release, operación, experimento o configuración; cada flag tiene propietario, motivo, valor por defecto y fecha de expiración.

- La autorización se evalúa en el servidor y en cada operación. Un flag de interfaz nunca protege recursos.

- Definir targeting estable, aislamiento entre tenants/usuarios y privacidad de atributos usados para segmentar.

- Proteger el plano de control con RBAC, MFA cuando proceda, auditoría y aprobación para cambios de alto impacto.

- Entregar progresivamente por cohortes o porcentaje con métricas, umbrales de aborto y rollback documentados.

- Probar estados activo/inactivo, combinaciones, caché, consistencia entre instancias y comportamiento ante caída del proveedor de flags.

- Evitar explosión combinatoria; flags que afectan seguridad, datos o migraciones requieren estrategia compatible.

- Eliminar flags temporales y experimentos finalizados; excepciones permanentes necesitan ADR y revisión periódica.

## Antipatrones

Flags sin dueño/expiración, usar flags como permisos, targeting con datos sensibles sin base, y activar cambios irreversibles sin mecanismo de recuperación.

## Verificación

Inventario de flags, auditoría de cambios, pruebas de estados, evidencia de canary/rollback y reporte de flags vencidos.

## Amenazas y escenarios de fallo específicos

Evaluar exposición de funcionalidades por targeting incorrecto, filtración entre tenants, flag de seguridad manipulado, caída o latencia del proveedor, caché divergente, combinaciones incompatibles, canary sesgado y rollback que no revierte migraciones/datos.

## Pruebas de aceptación mínimas

- Verificar autorización independiente del flag en cada API/operación.

- Probar reglas de targeting, límites de cohortes, atributos sensibles y aislamiento entre tenants.

- Simular proveedor de flags no disponible, respuesta stale, caché inconsistente y valor por defecto seguro.

- Ensayar canary, umbral automático de aborto y rollback con métricas.

- Detectar flags vencidos, sin owner, sin propósito o con combinaciones no probadas.

## Operación y evidencias

Mantener inventario con owner, clasificación, fecha de expiración, targeting, valor por defecto, historial de cambios, alertas y reporte periódico de deuda de flags.
