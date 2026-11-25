# Estándar de excepciones y dispensas

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Permitir desviaciones controladas sin convertirlas en incumplimientos invisibles ni debilitar silenciosamente los controles.

## Requisitos

Toda excepción DEBE incluir:

1. Estándar y requisito exacto afectado.
2. Proyecto, sistema, componente y entorno dentro del alcance.
3. Motivo técnico, operativo, legal o económico.
4. Riesgo creado y escenarios de abuso/fallo.
5. Controles compensatorios y riesgo residual.
6. Responsable de aceptación del riesgo.
7. Fecha de aprobación y vencimiento.
8. Condiciones de revocación y plan de retorno a conformidad.
9. Evidencia y fecha de próxima revisión.

No se permiten excepciones que contradigan la ley o una obligación contractual no dispensable. No se debe usar una excepción para ocultar una vulnerabilidad crítica sin mitigación.

## Caducidad

Las excepciones deben tener fecha de expiración. La renovación exige reevaluación y evidencia actualizada; no se renuevan automáticamente.

## Riesgo crítico

Una excepción de riesgo crítico requiere autoridad ejecutiva y de seguridad definida por la organización, además de controles temporales y monitoreo reforzado. Si el riesgo no puede reducirse a un nivel aceptable, la funcionalidad o exposición debe permanecer deshabilitada.

## Criterios de conformidad

Todas las desviaciones de requisitos adoptados son localizables, aprobadas, acotadas y revisables.
