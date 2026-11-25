# Versionado y compatibilidad

**Versión del esquema:** 1.1  
**Estado:** Draft

## 1. Versionado semántico

La biblioteca utiliza MAJOR.MINOR.PATCH:

- **MAJOR:** cambios incompatibles en requisitos normativos, jerarquía, estructura, identificadores o interpretación.

- **MINOR:** nuevos estándares/temas, requisitos compatibles, controles adicionales o ampliaciones relevantes.

- **PATCH:** correcciones editoriales, enlaces y aclaraciones que no cambian el significado normativo.

La versión de la biblioteca no reemplaza la versión individual de cada estándar. Cada documento Accepted debe declarar su propia versión.

## 2. Inventario e identificadores

El inventario exhaustivo asigna IDs estables con prefijo STD para documentos normativos y TOP para temas de descubrimiento. Los IDs no dependen del título ni de la ruta y nunca se reutilizan. Renombrar o mover un documento no cambia su ID. Un estándar retirado conserva su ID y se marca como Retired; un tema retirado conserva trazabilidad.

Cada proyecto registra versión de biblioteca, versión/commit del inventario y fecha de adopción. Al actualizar, compara IDs nuevos, modificados, sustituidos y retirados; no debe asumir que dos versiones son equivalentes.

## 3. Compatibilidad y metadatos

Cada estándar Accepted debe indicar:

- ID, versión actual y estado.

- Fecha de vigencia y próxima revisión.

- Owner, reviewer y approver.

- Versiones sustituidas, si aplica.

- Periodo de transición.

- Alcance y perfiles afectados.

- Referencias técnicas/normativas y fecha de verificación.

No se actualiza silenciosamente un requisito incompatible en una revisión menor.

## 4. Cambios urgentes

Una vulnerabilidad crítica o cambio regulatorio puede justificar actualización extraordinaria. El changelog debe explicar motivo, riesgo, IDs afectados y acciones urgentes.

## 5. Deprecación y retiro

La deprecación incluye alternativa recomendada, fecha de anuncio y horizonte de retiro. El retiro conserva historia, referencias y relación con el sucesor; no reutiliza IDs ni deja enlaces internos rotos.

## 6. Adopción por proyecto

La adopción queda fijada a una versión y commit concretos. Una actualización de biblioteca no cambia automáticamente las obligaciones del proyecto: el propietario revisa el delta, aprueba la migración y actualiza su registro de adopción y matriz de conformidad.
