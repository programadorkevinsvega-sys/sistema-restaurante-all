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

## Cookies, preferencias y avisos

- Inventariar cookies, almacenamiento local, SDK y tecnologías similares por finalidad, proveedor, duración y categoría.

- Clasificar tecnologías estrictamente necesarias y no esenciales; obtener consentimiento previo para las no esenciales cuando la jurisdicción lo exija.

- Permitir aceptar, rechazar y configurar categorías con facilidad comparable, y ofrecer una vía accesible para retirar o modificar preferencias.

- No activar analítica, marketing o seguimiento no esencial antes del consentimiento cuando sea exigible.

- Conservar evidencia mínima de la versión del aviso, momento, categorías elegidas y contexto necesario para demostrar la preferencia.

- No agrupar consentimiento de cookies, aceptación de términos y condiciones, aviso de privacidad y marketing en una única acción.

- Mantener avisos contextuales y mecanismos de preferencia consistentes entre web, aplicaciones y canales aplicables.

- Los textos legales, bases jurídicas y obligaciones de consentimiento deben validarse por jurisdicción; este estándar no reemplaza revisión legal.

## Términos y condiciones

Cada producto debe determinar, con revisión jurídica por jurisdicción, qué términos aplican a la organización, usuarios, clientes empresariales, consumidores, integraciones y proveedores. La aceptación debe ser demostrable, versionada y separada de otros consentimientos cuando corresponda. La biblioteca no proporciona textos contractuales universales ni sustituye asesoría legal.
