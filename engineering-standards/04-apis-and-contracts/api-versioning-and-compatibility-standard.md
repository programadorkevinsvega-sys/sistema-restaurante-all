# Estándar de versionado y compatibilidad de APIs

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Evolucionar interfaces sin romper consumidores de forma inesperada.

## Requisitos

- Cada contrato tiene versión o política de evolución inequívoca.
- Los cambios aditivos solo se consideran compatibles si consumidores existentes toleran la adición según el formato y el protocolo.
- Renombrar, eliminar, cambiar tipo, semántica, unidad, obligatoriedad o interpretación de un campo se trata como potencialmente incompatible.
- No reutilizar números de campo, nombres o identificadores retirados cuando el protocolo lo prohíba.
- La deprecación debe anunciar alternativa, plazo, consumidores afectados y métricas de uso.
- Mantener compatibilidad durante una ventana definida y basada en evidencia.
- Probar productor y consumidor con contratos publicados.
- Los eventos durables requieren políticas de compatibilidad más estrictas que una interfaz interna con despliegue coordinado.
- Versionar el contenido de eventos por separado de la versión del transporte cuando corresponda.

## Migración

Preferir expand/contract: añadir nuevo campo o endpoint, migrar consumidores, observar adopción y retirar el antiguo después de confirmar ausencia de uso. Para cambios incompatibles, coordinar release, compatibilidad temporal y rollback.

## Verificación

Pruebas automáticas de breaking changes, matriz de versiones consumidor/productor y telemetría de uso antes de retirar.
