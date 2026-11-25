# Governance — Gobierno de la biblioteca

**Versión:** 0.1.0  
**Estado:** Borrador inicial para revisión

## 1. Autoridad y propósito

Este documento define cómo se redactan, revisan, aprueban, versionan, adoptan y retiran los estándares de esta biblioteca. Ningún estándar debe considerarse aprobado solo por existir en el repositorio.

La biblioteca establece una base reutilizable. Cada proyecto conserva autoridad sobre sus decisiones concretas, siempre que documente y gestione cualquier desviación respecto de los estándares que haya adoptado.

## 2. Lenguaje normativo

- **DEBE / NO DEBE:** requisito obligatorio cuando el estándar ha sido adoptado y el requisito aplica.
- **DEBERÍA / NO DEBERÍA:** recomendación fuerte. Apartarse requiere una razón técnica documentada.
- **PUEDE:** opción permitida, no obligación.
- **OBLIGATORIO CONDICIONAL:** requisito obligatorio solo cuando se cumple el disparador de aplicabilidad descrito.
- **EJEMPLO:** ilustración no normativa.

Las palabras normativas no convierten por sí mismas un documento en una política aprobada. El estado, la aprobación y la adopción deben ser explícitos.

## 3. Jerarquía

1. Leyes, regulación, contratos y obligaciones externas aplicables.
2. Políticas de seguridad, privacidad y riesgo aprobadas por la organización.
3. Estándares adoptados por el proyecto.
4. ADR aceptados del proyecto.
5. Especificaciones de diseño e implementación.
6. Procedimientos, guías y ejemplos.

Un ADR no puede anular una obligación legal. Una decisión local que se aparte de un estándar adoptado debe registrar la excepción o proponer una revisión del estándar. Un estándar general no impone una arquitectura concreta si el proyecto no lo ha adoptado.

## 4. Estados documentales

- **Draft:** contenido en elaboración; no normativo.
- **In Review:** revisión técnica, seguridad, operaciones o legal en curso.
- **Accepted:** aprobado para publicación como estándar.
- **Deprecated:** aún disponible para proyectos existentes, pero no recomendado para nuevas adopciones.
- **Retired:** retirado; se conserva por trazabilidad.

La aceptación de la biblioteca no implica que todos sus estándares sean obligatorios para todos los proyectos.

## 5. Aprobación y responsabilidades

Cada estándar debe identificar:

- Autor o responsable editorial.
- Revisores técnicos pertinentes.
- Revisión de seguridad cuando afecte superficies de ataque o controles.
- Revisión de privacidad/legal cuando afecte datos personales o regulación.
- Aprobador con autoridad definida por el gobierno de la biblioteca.
- Fecha, versión y alcance de aprobación.

La revisión debe comprobar coherencia con otros estándares, claridad normativa, aplicabilidad, testabilidad, alternativas y consecuencias operativas.

## 6. Cambios

Los cambios se proponen mediante PR. El PR debe explicar:

- Motivación y problema que resuelve.
- Estándares afectados y dependencias.
- Compatibilidad con versiones ya adoptadas.
- Impacto en seguridad, privacidad, costo y operación.
- Plan de migración cuando cambie un requisito.
- Evidencia técnica y fuentes actuales para afirmaciones tecnológicas.

Los cambios normativos incompatibles requieren nueva versión mayor o una política de transición explícita.

## 7. No conformidad y excepciones

Una no conformidad debe describir requisito, evidencia, impacto, severidad, responsable y fecha objetivo. Las excepciones siguen [el proceso de excepciones](./00-governance/standard-exception-and-waiver-process.md).

## 8. Independencia de proyectos

Los documentos de esta biblioteca no deben contener nombres de productos consumidores, IDs de tenants, dominios privados, nombres de módulos exclusivos, secretos ni decisiones locales presentadas como universales. Los ejemplos deben ser sintéticos y sustituibles.

## 9. Revisión periódica

Cada estándar Accepted debe revisarse al menos una vez al año o antes cuando exista una vulnerabilidad relevante, cambio de regulación, fin de soporte, cambio tecnológico significativo o incidente que revele una brecha. La frecuencia concreta puede endurecerse por criticidad.

## 10. Publicación

Una versión publicada debe incluir changelog, versión, fecha, estados de documentos, guía de adopción y matriz de compatibilidad. No se debe afirmar certificación externa salvo que exista un proceso independiente que la otorgue.
