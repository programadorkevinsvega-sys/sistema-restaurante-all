# Criterios mínimos de calidad, profundidad y revisión de un estándar

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** todos los documentos normativos de esta biblioteca

## 1. Propósito

Evitar que un documento se considere estándar por contener solo principios genéricos, una lista superficial de herramientas o recomendaciones sin controles verificables. Este checklist define la profundidad mínima editorial y técnica. No obliga a que todos los documentos tengan la misma extensión: la profundidad debe ser proporcional al riesgo y a la especificidad del dominio.

## 2. Metadatos obligatorios

Cada estándar debe declarar:

- ID estable del inventario y título.

- Versión individual y estado documental.

- Propósito, alcance, exclusiones y disparadores de aplicabilidad.

- Responsable editorial, revisores requeridos y autoridad aprobadora (al pasar a Accepted).

- Fecha de publicación, última revisión y próxima revisión.

- Referencias técnicas/normativas con entidad, título, versión/edición, URL y fecha de verificación cuando sea posible.

- Dependencias, documentos relacionados y conflictos conocidos.

## 3. Contenido técnico mínimo

Cada estándar debe incluir, cuando aplique:

1. Contexto y objetivos de control.

2. Activos, actores, límites de confianza y responsabilidades.

3. Amenazas, abuso, fallos, riesgos operativos y escenarios adversos.

4. Requisitos normativos claros, atómicos y verificables; distinguir DEBE, DEBERÍA y PUEDE.

5. Condiciones y umbrales para adoptar mecanismos complejos, sin imponerlos universalmente.

6. Alternativas razonables, trade-offs, costos y consecuencias.

7. Seguridad, privacidad, accesibilidad, resiliencia y operación relevantes al dominio.

8. Pruebas de diseño, integración, carga, seguridad, recuperación o aceptación que correspondan.

9. Evidencias objetivas para demostrar cumplimiento.

10. Responsables de operación, respuesta, revisión y mantenimiento.

11. Antipatrones específicos del dominio, no una lista genérica repetida.

12. Procedimiento de excepción y referencias cruzadas a gobernanza.

## 4. Verificación y evidencia

Un requisito no es verificable si no puede identificarse:

- qué condición debe cumplirse;

- en qué componente, proceso o actividad;

- quién es responsable;

- cómo se prueba/inspecciona;

- qué evidencia queda;

- cuándo se revisa.

La evidencia puede ser una prueba automatizada, configuración inspeccionable, registro de auditoría, resultado de restauración, revisión documentada, aprobación, métrica o ejercicio operativo. La evidencia debe ser reproducible y proteger datos sensibles.

## 5. Referencias

- Priorizar fuentes primarias: especificaciones oficiales, estándares de organismos reconocidos, documentación del mantenedor y regulación aplicable.

- Registrar edición/versión exacta; no citar solo el nombre de una organización.

- Verificar que el enlace y la edición sigan vigentes en cada revisión.

- No atribuir requisitos a una fuente que no los contiene.

- Si una referencia no puede verificarse, marcarla como pendiente y no usarla como fundamento normativo.

- No declarar cumplimiento legal universal; la jurisdicción y el asesoramiento competente determinan obligaciones aplicables.

## 6. Revisión especializada

La revisión debe involucrar perfiles pertinentes al riesgo: arquitectura, desarrollo, seguridad, privacidad/legal, operaciones/SRE, QA, UX/accesibilidad, finanzas o expertos de dominio. Una persona puede cubrir más de un rol si tiene competencia demostrable; no se inventan aprobaciones.

## 7. Criterios de aceptación editorial

Un estándar no pasa a Accepted si:

- tiene contradicciones internas o con otros estándares sin resolución;

- contiene requisitos vagos no comprobables;

- usa ejemplos tecnológicos como mandato universal;

- omite amenazas/fallos relevantes al dominio;

- carece de pruebas/evidencias o responsables;

- contiene referencias rotas, obsoletas o no verificadas presentadas como autoridad;

- no tiene owner, reviewer, approver, versión, fecha y alcance;

- tiene secciones genéricas que no aportan al tema específico.

## 8. Revisión periódica

Revisar al menos anualmente y antes ante vulnerabilidad, cambio regulatorio, fin de soporte, cambio de arquitectura relevante, incidente, nueva técnica de ataque o nueva versión importante de la tecnología referenciada.
