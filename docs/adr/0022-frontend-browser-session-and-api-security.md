# ADR-0022: Seguridad del frontend, navegador, sesiones y APIs de borde

- Estado: **Proposed**
- Fecha: 2026-11-25
- Ámbito: aplicaciones web, navegador, recursos estáticos, cookies, sesiones web, BFF y exposición HTTP.
- Complementa: ADR-0002, ADR-0007, ADR-0008, ADR-0011, ADR-0018, ADR-0019 (si se acepta), ADR-0020, ADR-0021 y ADR-0025.
- Aprobación: pendiente de aprobación explícita.

## Contexto

El navegador está bajo control del usuario: puede modificar formularios, rutas, encabezados, almacenamiento y peticiones. XSS, CSRF, robo de sesión, scripts de terceros, CORS permisivo y contenido activo pueden comprometer cuentas/datos. Los BFF son procesos separados y no propietarios de datos; la autorización de dominio permanece en módulos propietarios.

## Decisión propuesta

### 1. Modelo de confianza

Todo dato del navegador es no confiable. La validación frontend mejora UX; el backend repite validación, autorización y reglas de negocio. Campos ocultos/deshabilitados, rutas no visibles y botones ocultos no son seguridad. No confiar en precios, totales, descuentos, permisos, tenant, propietario o estados enviados por el cliente. No incluir secretos privados ni credenciales de infraestructura en bundles o mapas de fuentes públicos.

### 2. Sesiones y cookies

Cuando la autenticación web utilice cookies:
- usar Secure, HttpOnly y SameSite apropiado;
- limitar Domain y Path; no compartir cookies entre subdominios sin necesidad;
- rotar identificador de sesión tras autenticación y elevación de privilegios;
- definir expiración por inactividad y duración absoluta;
- revocar al cerrar sesión, cambiar credenciales/privilegios o detectar compromiso;
- no incluir tokens en URLs, query strings ni fragmentos;
- no almacenar tokens de larga duración/secretos en localStorage o sessionStorage;
- limpiar estado local y cachés privadas al cerrar sesión o cambiar de tenant;
- impedir que service workers/cachés sirvan contenido privado a otra sesión.

Refresh tokens, MFA, recuperación y credenciales siguen ADR-0011. Este ADR no redefine contraseñas.

### 3. CSRF

Para sesiones autenticadas mediante cookies: tokens anti-CSRF vinculados a sesión o mecanismo equivalente, validación de Origin y Referer cuando corresponda, métodos/tipos de contenido restringidos, ninguna mutación por GET. SameSite no es defensa única. Si se adopta autenticación sin cookies, documentar análisis de CSRF y riesgos equivalentes de robo/reutilización de credenciales.

### 4. XSS y contenido activo

Mantener escaping contextual por defecto. Evitar sinks DOM inseguros e inserción directa de HTML no confiable. Si se requiere HTML enriquecido, sanitizar con biblioteca mantenida y allowlist estricta. Tratar contenido de usuarios, proveedores, integraciones e IA como no confiable. Rechazar esquemas activos como javascript:. No servir HTML/SVG no confiable en el mismo origen. Abrir enlaces externos sin acceso innecesario a window.opener. CSP es defensa adicional, no sustituto de codificación/sanitización.

### 5. CSP y cabeceras

Adoptar CSP restrictiva con nonces o hashes cuando sea viable. Evitar unsafe-inline y unsafe-eval; excepciones requieren justificación, alcance, responsable y revisión. Evaluar default-src, script-src, style-src, img-src, font-src, connect-src, object-src 'none', base-uri, frame-ancestors y form-action. Configurar Referrer-Policy, X-Content-Type-Options: nosniff, Permissions-Policy y HSTS cuando HTTPS esté preparado. Probar primero CSP report-only y establecer paso a enforcement; no dejarla indefinidamente en observación.

### 6. CORS, orígenes y WebSockets

Allowlist explícita de orígenes; no combinar credenciales con wildcard; no reflejar cualquier Origin; restringir métodos/headers. CORS no autentica ni autoriza. WebSockets validan origen, identidad, permisos por canal/recurso, límites y revocación. Endpoints internos no se protegen solo ocultando rutas. Redirecciones y URLs de retorno usan destinos permitidos.

### 7. Seguridad de APIs en el borde

Los BFF aplican controles de transporte: tamaño de body/headers, timeouts, rate limits, concurrencia, métodos, protocolo y errores seguros, alineados con ADR-0025. La autorización de dominio y propiedad del recurso permanecen en backend/módulo conforme a ADR-0021. BFF no consulta PostgreSQL de negocio ni duplica políticas como autoridad única.

### 8. Dependencias y terceros

Mantener inventario de dependencias/scripts; revisar vulnerabilidades, mantenimiento y licencias; fijar versiones y revisar lockfiles; aplicar SRI cuando proceda; limitar tags, widgets y analítica; no cargar scripts remotos arbitrarios definidos por tenants. Supply chain se desarrolla en ADR-0024.

### 9. Datos, privacidad y errores

Minimizar datos enviados al navegador; no exponer datos sensibles en URLs, historial, telemetría frontend o errores. Configurar Cache-Control para respuestas sensibles. Descargas y previsualizaciones requieren autorización del módulo propietario. No mostrar stack traces, consultas, tokens o secretos. Respetar ADR-0018 para consentimiento y tecnologías de seguimiento.

### 10. Pruebas de aceptación

Probar XSS almacenado/reflejado/DOM, CSRF, session fixation, expiración/revocación, CORS, clickjacking, CSP, caché entre usuarios, cambio de tenant, manipulación de campos, enlaces externos, WebSockets, descargas y secretos en bundles.

## Alternativas consideradas

- Tokens de larga duración en localStorage como patrón por defecto: rechazado por exposición ante XSS.
- SameSite como única defensa CSRF: rechazado.
- CORS abierto: rechazado.
- Ocultar controles frontend como autorización: rechazado.
- CSP como sustituto de codificación: rechazado.

## Consecuencias

Reduce robo de sesión, XSS, CSRF y exposición accidental. CSP estricta y cookies seguras requieren pruebas de compatibilidad y mantenimiento de scripts externos.

## Límites

No elige framework, proveedor de identidad, gestor de cookies ni dominios productivos. No implementa cabeceras, cookies, endpoints ni configuración.

## Plan futuro

Inventariar aplicaciones/orígenes/scripts; definir flujos web con ADR-0011/0018; configurar sesiones, CSRF, CSP, CORS y cabeceras; clasificar cachés; auditar terceros; ejecutar pruebas de navegador.

## Estado de implementación

Proposed. No afirma que CSP, CSRF, CORS, cookies, cabeceras o controles frontend estén implementados.
