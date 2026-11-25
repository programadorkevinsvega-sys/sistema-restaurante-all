# Estándar de modelo de errores de API

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proporcionar errores predecibles sin filtrar detalles internos.

## Requisitos

- Los errores públicos deben tener código estable, categoría, mensaje seguro y contexto de correlación.
- Separar validación, autenticación, autorización, conflicto, límite, dependencia temporalmente no disponible y error interno.
- No exponer stack traces, SQL, nombres internos de tablas, secretos, tokens, rutas sensibles ni datos de otros usuarios.
- Los errores de validación deben identificar campos de forma segura sin repetir valores sensibles.
- Los errores transitorios deben distinguirse de los permanentes para orientar reintentos.
- El cliente no debe inferir autorización a partir de mensajes de error.
- Las respuestas deben mantener formato consistente y documentado.
- Los códigos HTTP/RPC deben reflejar semántica y no detalles accidentales de implementación.

## Reintentos

Solo reintentar cuando la operación sea segura o esté protegida por idempotencia. Incluir Retry-After o metadata equivalente cuando aplique y evitar tormentas de reintentos.

## Verificación

Pruebas de contrato, ausencia de filtración, consistencia entre endpoints y comportamiento del cliente ante fallos transitorios.
