# Estándar de ciclo de vida y revisión documental

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Asegurar que la documentación técnica sea coherente, mantenible, verificable y útil durante todo el ciclo de vida del sistema.

## Requisitos

- Cada documento normativo DEBE tener título, propósito, alcance, estado, versión, propietario y fecha de revisión.
- Debe identificarse la fuente de verdad cuando existan documentos relacionados.
- Los enlaces internos deben ser relativos y validarse automáticamente.
- Los términos normativos deben usarse de forma consistente.
- Los ejemplos deben marcarse como ejemplos y no contradecir requisitos.
- La documentación debe actualizarse en el mismo cambio que altera el comportamiento, contrato o control descrito.
- Las afirmaciones tecnológicas sensibles al tiempo deben citar documentación oficial y registrar la fecha de consulta.
- Los documentos obsoletos deben marcarse como deprecated o retirarse con enlaces de reemplazo; no deben quedar silenciosamente vigentes.

## Revisión

La revisión debe evaluar exactitud, claridad, aplicabilidad, seguridad, privacidad, operabilidad, compatibilidad y testabilidad. Los documentos críticos deben tener revisión de un responsable distinto del autor.

## Automatización

El repositorio DEBERÍA ejecutar lint de Markdown, validación de enlaces, detección de secretos, comprobación de metadatos y pruebas de ejemplos cuando sea viable.

## Criterios de conformidad

- Documentos vigentes identificables.
- No hay enlaces internos rotos.
- No existen contradicciones normativas sin resolución.
- Cambios de código y documentación permanecen sincronizados.
