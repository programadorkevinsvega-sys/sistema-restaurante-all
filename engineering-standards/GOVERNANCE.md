# Governance — Gobierno de la biblioteca

**Versión:** 0.2.0  
**Estado:** Draft

## 1. Autoridad y propósito

Este documento define cómo se redactan, revisan, aprueban, versionan, adoptan y retiran los estándares. Ningún estándar se considera aprobado solo por existir en el repositorio.

La biblioteca establece una base reutilizable. Cada proyecto conserva autoridad sobre sus decisiones concretas, siempre que documente y gestione desviaciones respecto de estándares adoptados. Los requisitos legales, contractuales y regulatorios aplicables no pueden dispensarse por preferencia.

## 2. Lenguaje normativo

- **DEBE / NO DEBE:** requisito obligatorio cuando el estándar ha sido adoptado y el requisito aplica.

- **DEBERÍA / NO DEBERÍA:** recomendación fuerte; apartarse requiere razón documentada.

- **PUEDE:** opción permitida, no obligación.

- **OBLIGATORIO CONDICIONAL:** requisito obligatorio solo cuando se cumple el disparador de aplicabilidad.

- **EJEMPLO:** ilustración no normativa.

Las palabras normativas no convierten por sí mismas un documento en política aprobada. Estado documental, aprobación y adopción deben ser explícitos.

## 3. Jerarquía

1. Leyes, regulación, contratos y obligaciones externas aplicables.

2. Políticas de seguridad, privacidad y riesgo aprobadas por la organización.

3. Estándares adoptados por el proyecto.

4. ADR aceptados del proyecto.

5. Especificaciones de diseño e implementación.

6. Procedimientos, guías y ejemplos.

Un ADR no puede anular una obligación legal. Una decisión local que se aparte de un estándar adoptado debe registrar excepción o proponer revisión. Un estándar general no impone arquitectura concreta si el proyecto no lo ha adoptado.

## 4. Estados documentales

- **Draft:** contenido en elaboración; no normativo.

- **In Review:** revisión técnica, seguridad, operaciones o legal en curso.

- **Accepted:** aprobado para publicación como estándar.

- **Deprecated:** disponible para proyectos existentes, pero no recomendado para nuevas adopciones.

- **Retired:** retirado; se conserva por trazabilidad.

La biblioteca y cada documento tienen estado propio. La aceptación de la biblioteca no implica que todos sus estándares sean obligatorios para todos los proyectos.

## 5. Responsabilidades y aprobación

Antes de pasar un estándar a Accepted, debe identificar:

- ID estable del inventario y versión individual.

- Autor/owner editorial responsable de mantenimiento.

- Revisores técnicos pertinentes y sus competencias.

- Revisión de seguridad cuando afecte superficies de ataque o controles.

- Revisión de privacidad/legal cuando afecte datos personales o regulación.

- Revisión de operaciones/SRE, QA, UX/accesibilidad o dominio cuando corresponda.

- Aprobador con autoridad definida por el gobierno de la biblioteca.

- Fecha de aprobación, vigencia, alcance y próxima revisión.

No inventar nombres, firmas ni aprobaciones. Mientras esos campos no estén asignados y la revisión no haya concluido, el documento permanece Draft o In Review.

## 6. Calidad técnica y editorial

Todo estándar debe satisfacer el [Checklist de calidad y revisión](./STANDARD-DOCUMENT-QUALITY-AND-REVIEW-CHECKLIST.md). La revisión debe comprobar coherencia, claridad normativa, aplicabilidad, testabilidad, amenazas, escenarios de fallo, alternativas, evidencia, referencias y consecuencias operativas.

Una mención de una tecnología o un enlace no equivale a control suficiente. Una cobertura parcial debe declararse; no se puede ocultar una brecha por similitud temática.

## 7. Cambios y trazabilidad

Los cambios se proponen mediante PR. El PR debe explicar motivación, problema, IDs y estándares afectados, dependencias, compatibilidad, impacto de seguridad/privacidad/costo/operación, migración y evidencia.

Los cambios normativos incompatibles requieren versión mayor o transición explícita. Cambios al catálogo y al inventario se realizan juntos; los IDs no se reutilizan. Mantener changelog, procedencia y decisiones de aprobación.

## 8. No conformidad y excepciones

Una no conformidad describe requisito, evidencia, impacto, severidad, responsable y fecha objetivo. Las excepciones siguen [el proceso de excepciones](./00-governance/standard-exception-and-waiver-process.md). La excepción debe tener alcance, aprobador, mitigaciones, expiración y plan de cierre.

## 9. Independencia de proyectos

Los documentos no deben contener nombres de productos consumidores, IDs de tenants, dominios privados, módulos exclusivos, secretos ni decisiones locales presentadas como universales. Los ejemplos deben ser sintéticos y sustituibles.

## 10. Revisión periódica

Cada estándar Accepted se revisa al menos anualmente o antes ante vulnerabilidad, cambio regulatorio, fin de soporte, cambio tecnológico, incidente o nueva amenaza. El responsable registra fecha, versión, resultado y acciones.

## 11. Publicación

Una versión publicada incluye changelog, versión, fecha, estados documentales, inventario con IDs estables, guía de adopción, matriz de cobertura y compatibilidad. No declarar certificación externa sin proceso independiente que la otorgue.
