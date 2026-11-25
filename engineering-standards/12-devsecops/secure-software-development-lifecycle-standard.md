# Estándar de ciclo de vida de desarrollo seguro

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Integrar seguridad y calidad en cada etapa del desarrollo, desde requisitos hasta mantenimiento y retiro.

## Requisitos

- Definir requisitos de seguridad y privacidad desde diseño.
- Realizar threat modeling para capacidades y cambios de alto riesgo.
- Aplicar revisión de código y separación de funciones para cambios sensibles.
- Usar SAST, SCA, secret scanning y análisis de infraestructura como código cuando aplique.
- Mantener inventario de dependencias directas y transitivas.
- Definir política de vulnerabilidades, severidad, SLA de remediación y excepciones.
- Verificar licencias y procedencia de dependencias.
- Proteger ramas, etiquetas y releases mediante controles de repositorio.
- Evitar que código no confiable de PR acceda a secretos o permisos privilegiados.
- Mantener SBOM y evidencia de construcción para productos y releases relevantes.
- Firmar o verificar artefactos cuando el riesgo y la plataforma lo permitan.
- Disponer de proceso de divulgación responsable y respuesta a vulnerabilidades.

## Gestión de vulnerabilidades

Priorizar por explotabilidad, exposición, impacto, disponibilidad de exploit y alcance. La severidad del scanner no debe ser el único criterio. Los riesgos críticos deben tener contención inmediata.

## Verificación

Evidencia de controles de repositorio, escaneo, revisión, remediación, SBOM, pruebas de permisos y ejercicio de respuesta.
