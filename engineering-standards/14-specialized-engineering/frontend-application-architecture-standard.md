# Estándar de arquitectura de aplicaciones frontend

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Define arquitectura de clientes web y aplicaciones de interfaz, sin imponer framework.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Separar presentación, estado de interfaz, lógica de aplicación y acceso a servicios; evitar reglas de negocio críticas solo en frontend.

- Definir estrategia de renderizado (CSR/SSR/SSG/híbrida), routing, carga diferida, límites de bundle y estrategia de hidratación según SEO, privacidad y latencia.

- Centralizar cliente HTTP, serialización, manejo de errores, cancelación, timeouts y renovación segura de sesión.

- Gestionar estado local, remoto y derivado de forma diferenciada; evitar duplicación y estados imposibles.

- Formularios: etiquetas, validación accesible, errores por campo, prevención de doble envío y protección frente a pérdida accidental.

- Componentes con contratos, composición, diseño responsivo, tokens y pruebas; evitar sistemas de diseño paralelos sin gobernanza.

- Configuración pública separada de secretos; variables incluidas en bundles se consideran visibles.

- Definir compatibilidad de navegadores, fallback, observabilidad sin datos sensibles y estrategia de actualización.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.

- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.

- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.

- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.

- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.

## Amenazas y escenarios de fallo específicos

Evaluar XSS/DOM injection, CSRF, clickjacking, dependencias comprometidas, secretos expuestos en bundles/source maps, session fixation, race conditions de estado, caché de datos privados, hydration mismatch y abuso de APIs desde clientes modificados.

## Pruebas de aceptación mínimas

- Inspeccionar bundles, source maps y variables públicas para detectar secretos.

- Probar CSP, cookies, CORS/CSRF, XSS, navegación y expiración de sesión.

- Verificar que reglas de negocio y autorización se aplican en servidor, no solo en UI.

- Medir Core Web Vitals/latencia y tamaño de bundle en rutas críticas si aplica.

- Probar accesibilidad de formularios, foco, errores, teclado, lectores de pantalla y zoom.

- Verificar estados loading/empty/error/offline, cancelación de solicitudes y doble envío.

## Operación y evidencias

Conservar arquitectura de rutas/estado, inventario de dependencias, política de navegadores, resultados de accesibilidad/seguridad/performance y telemetría minimizada.
