# Estándar de privacidad y ciclo de vida de datos personales

**Versión:** 0.1.0 | **Estado:** Draft  
**Aplicabilidad:** cuando se procesen datos personales o datos sujetos a obligaciones de privacidad.

## Objetivo

Integrar privacidad en diseño, desarrollo, operación, proveedores y retiro del sistema.

## Requisitos

- Inventariar categorías de datos, titulares, finalidades, bases jurídicas, sensibilidad, ubicación, destinatarios y sistemas.
- Determinar roles de responsable/controlador y encargado/procesador por tratamiento y jurisdicción; no asumir un rol único para todos los datos.
- Recoger solo los datos necesarios y limitar su uso a finalidades documentadas.
- Definir retención por categoría, finalidad, trigger, obligación legal y acción final.
- No establecer retención indefinida sin fundamento documentado.
- Diseñar mecanismos para atender derechos aplicables: acceso, rectificación, eliminación, oposición, portabilidad, limitación y retiro de consentimiento, según jurisdicción.
- Mantener legal holds y excepciones legales con alcance, autoridad y revisión.
- Diseñar eliminación y anonimización verificables, incluyendo réplicas, caches, exports, backups y proveedores según obligaciones.
- Registrar consentimientos y preferencias con versión, momento, finalidad y evidencia cuando sea exigible.
- No agrupar consentimiento de marketing, términos, privacidad y cookies en una única aceptación.
- Evaluar transferencias internacionales, subencargados y contratos.
- Minimizar datos en logs, telemetría, analytics, soporte y entornos de prueba.
- Definir gestión de incidentes y notificación según plazos legales aplicables.

## Retención y backups

La eliminación de datos activos no implica que cada backup pueda alterarse inmediatamente. Definir expiración, aislamiento, restauración y reaplicación de solicitudes de borrado cuando corresponda.

## Revisión legal

Los textos, plazos, bases jurídicas y mecanismos deben validarse por jurisdicción con asesoría competente. Este estándar no sustituye asesoramiento legal.

## Verificación

Inventario actualizado, matriz de retención, pruebas de derechos, evidencia de consentimiento, auditoría de proveedores y simulacro de incidente.
