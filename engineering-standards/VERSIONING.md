# Versionado y compatibilidad

**Versión del esquema:** 1.0  
**Estado:** Borrador inicial

## Versionado semántico

La biblioteca utiliza MAJOR.MINOR.PATCH:

- **MAJOR:** cambios incompatibles en requisitos normativos, jerarquía, estructura o interpretación.
- **MINOR:** nuevos estándares, requisitos compatibles, controles adicionales o ampliaciones relevantes.
- **PATCH:** correcciones editoriales, enlaces, aclaraciones que no cambian el significado normativo.

La versión de la biblioteca no reemplaza la versión individual de cada estándar. Cada documento Accepted debe declarar su propia versión.

## Compatibilidad

Cada estándar debe indicar:

- Versión actual.
- Estado.
- Fecha de vigencia.
- Versiones sustituidas, si aplica.
- Periodo de transición.
- Proyectos o perfiles afectados, si se publica un perfil de adopción.

Un proyecto debe registrar qué versión adoptó. No se debe actualizar silenciosamente un requisito incompatible en una revisión menor.

## Cambios urgentes

Una vulnerabilidad crítica o cambio regulatorio puede justificar una actualización extraordinaria. El changelog debe explicar el motivo, el riesgo y las acciones urgentes.

## Deprecación y retiro

La deprecación debe incluir alternativa recomendada, fecha de anuncio y horizonte de retiro. El retiro debe conservar la historia y evitar enlaces rotos.
