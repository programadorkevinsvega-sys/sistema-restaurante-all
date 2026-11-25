# Estándar base de seguridad de aplicaciones

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Establecer controles mínimos de seguridad desde el diseño hasta la operación.

## Requisitos

- Mantener inventario de activos, datos, actores, fronteras de confianza y superficies expuestas.
- Modelar amenazas para flujos críticos y actualizar el modelo ante cambios importantes.
- Aplicar defensa en profundidad y mínimo privilegio.
- Validar autenticación, autorización y contexto en el servidor; no confiar en controles de cliente.
- Validar entradas y codificar salidas según contexto.
- Proteger sesiones, tokens, secretos, claves y datos sensibles.
- Usar criptografía y protocolos mantenidos, con configuración segura.
- Registrar eventos de seguridad sin capturar credenciales o payloads sensibles.
- Mantener dependencias, runtime e imágenes soportados y corregir vulnerabilidades según severidad y exposición.
- Disponer de respuesta a incidentes, rotación de credenciales y recuperación.
- Probar controles negativos, abuso y aislamiento; no limitar la verificación a pruebas de flujo exitoso.

## Gestión de riesgo

Priorizar por impacto, probabilidad, exposición, facilidad de explotación y alcance. Los riesgos críticos no mitigados bloquean el lanzamiento de la superficie afectada.

## Verificación

Threat modeling, SAST, SCA, secret scanning, DAST cuando aplique, pruebas de autorización, revisión de configuración y ejercicios de incidentes.
