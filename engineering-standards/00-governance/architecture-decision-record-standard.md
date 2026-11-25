# Estándar de Architecture Decision Records (ADR)

**Versión:** 0.1.0 | **Estado:** Draft  
**Aplicabilidad:** todos los proyectos con decisiones técnicas de impacto relevante.

## Objetivo

Mantener un registro auditable de decisiones que afectan arquitectura, seguridad, datos, operación, costo, compatibilidad o evolución del sistema.

## Cuándo crear un ADR

Se DEBE crear o actualizar un ADR cuando una decisión:

- Cambie límites de dominio, ownership, procesos o dependencias.
- Seleccione o sustituya una tecnología con impacto significativo.
- Modifique persistencia, consistencia, seguridad, privacidad o disponibilidad.
- Cree una obligación operativa, regulatoria o contractual.
- Introduzca una excepción a un estándar adoptado.
- Tenga consecuencias difíciles o costosas de revertir.

No se requiere un ADR para cada cambio rutinario de implementación.

## Estructura mínima

1. Identificador estable y título.
2. Estado y fechas de propuesta, aceptación y sustitución.
3. Contexto y problema.
4. Fuerzas y restricciones.
5. Decisión en lenguaje preciso.
6. Alternativas consideradas, incluida la opción de no cambiar.
7. Consecuencias positivas, negativas y riesgos.
8. Seguridad, privacidad, disponibilidad y costo cuando apliquen.
9. Plan de migración o transición.
10. Pruebas y evidencia necesarias.
11. Responsables y aprobadores.
12. Referencias a estándares, requisitos y ADR relacionados.

## Estados

- **Proposed:** propuesta sin aprobación.
- **Accepted:** decisión aprobada y vigente.
- **Rejected:** propuesta evaluada y descartada.
- **Deprecated:** decisión reemplazada o no recomendada.
- **Superseded:** sustituida por otro ADR, con enlace explícito.

El estado Accepted indica aprobación de la decisión, no implementación. La implementación debe tener tareas y evidencias independientes.

## Requisitos de calidad

- La decisión debe ser inequívoca y comprobable.
- No debe ocultar incertidumbres ni convertir parámetros pendientes de medición en decisiones ficticias.
- Debe distinguir decisiones arquitectónicas de parámetros operativos que requieren dimensionamiento.
- Debe explicar qué queda fuera de alcance.
- Debe registrar conflictos con documentos históricos y declarar qué fuente prevalece.
- Debe describir consecuencias y migración para sistemas existentes.

## Revisión y cambio

Un ADR Accepted no se edita para reescribir la historia. Si cambia la decisión, se crea un nuevo ADR que lo sustituya o se actualiza con historial explícito, según la política del proyecto.

## Criterios de conformidad

- Las decisiones relevantes tienen ADR.
- Los ADR Accepted no se presentan como propuestas pendientes.
- La implementación no se declara existente por el mero estado Accepted.
- Las excepciones y sustituciones son trazables.
