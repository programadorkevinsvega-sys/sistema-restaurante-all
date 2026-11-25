# Estándar de seguridad de frontend y aplicaciones web

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Reducir riesgos en navegadores, aplicaciones web y clientes que interactúan con APIs, asumiendo que el entorno del usuario y todo dato recibido o mostrado puede ser manipulado.

## Requisitos

- El frontend no es una frontera de autorización: toda operación sensible debe validarse en el servidor.
- Evitar XSS mediante APIs seguras de renderizado, codificación contextual y sanitización específica cuando se permita HTML no confiable.
- Evitar insertar contenido no confiable en HTML, scripts, estilos, URLs o atributos ejecutables.
- Definir una Content Security Policy (CSP) restrictiva, probarla y evolucionarla sin depender exclusivamente de políticas permisivas como unsafe-inline o unsafe-eval.
- Proteger operaciones basadas en cookies contra CSRF con estrategia adecuada al modelo de sesión, SameSite, tokens anti-CSRF y validación de origen cuando aplique.
- Configurar cookies de sesión con Secure, HttpOnly y SameSite apropiado; limitar Domain, Path, duración y alcance.
- Evitar almacenar credenciales, refresh tokens o secretos de larga duración en almacenamiento accesible a JavaScript cuando exista una alternativa más segura.
- Definir CORS con orígenes, métodos y headers explícitos; nunca usar CORS como sustituto de autenticación o autorización.
- Proteger contra clickjacking mediante políticas de framing apropiadas.
- Aplicar controles de redirección para evitar open redirects y validar destinos de enlaces externos.
- Mantener dependencias frontend actualizadas, inventariadas y escaneadas; reducir scripts de terceros y fijar su procedencia.
- No exponer secretos, claves privadas, tokens privilegiados ni configuraciones internas en bundles, source maps públicos o variables compiladas.
- Proteger flujos de autenticación, recuperación, logout, expiración, renovación y revocación de sesiones.
- Evitar que errores, estados de UI o cachés del navegador filtren datos de otra identidad o tenant.
- Definir protección de datos sensibles en clipboard, descargas, impresión, almacenamiento local y telemetría según el riesgo.
- Los controles de seguridad no deben depender de que el usuario mantenga actualizado o intacto el cliente.

## Verificación

Pruebas de XSS almacenado/reflejado/DOM, CSRF, clickjacking, CSP, CORS, open redirect, exposición de secretos, session fixation, logout/revocación y aislamiento de caché.
