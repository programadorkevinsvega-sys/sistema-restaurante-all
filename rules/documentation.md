# Reglas de documentación

## Alcance

Estas reglas aplican a la documentación pública e interna de Restaurant OS:
requisitos, roadmap, reglas, migraciones, contratos, guías y README que se
incorporen al proyecto.

La documentación debe describir el estado real del proyecto. No convierte una
propuesta, un esquema o una migración en una funcionalidad ejecutable.

## Fuentes de verdad

- [requisitos.md](../requisitos.md) conserva los requisitos de producto.
- [ROADMAP.md](../ROADMAP.md) conserva las fases y prioridades.
- Los documentos de `rules/` contienen reglas técnicas normativas.
- Las migraciones describen los cambios de esquema implementados; no prueban
  por sí solas que el sistema completo que las usaría esté terminado.

Enlazar a la fuente propietaria en vez de copiar su contenido. Si dos documentos
se contradicen, señalar y resolver la discrepancia; no elegir una versión sin
fundamento.

## Exactitud y estado de implementación

- Cada afirmación sobre capacidades, arquitectura, dependencias, configuración,
  comandos o pruebas debe poder verificarse en el código, los manifests, las
  migraciones, la configuración o las pruebas existentes.
- Diferenciar claramente lo planificado de lo implementado y probado.
- No afirmar que una funcionalidad está completa por existir solo una interfaz,
  contrato, migración, stub o prueba simulada.
- No afirmar que algo está desplegado en producción a partir de pruebas locales.
- Si un dato no puede verificarse, omitirlo o marcarlo explícitamente como
  pendiente.

Cuando sea necesario comunicar el estado de una capacidad, usar una etiqueta
consistente:

- `PLANNED`: planificada, no implementada.
- `IN_PROGRESS`: en desarrollo.
- `PARTIALLY_IMPLEMENTED`: implementación incompleta.
- `IMPLEMENTED`: implementada y verificada en el alcance indicado.
- `BLOCKED`: bloqueada por una condición o decisión documentada.
- `NOT_AVAILABLE`: no disponible.
- `DEPRECATED`: obsoleta o en retirada.

`IMPLEMENTED` no significa automáticamente que esté desplegada en producción.
Los resultados de pruebas se clasifican por separado conforme a
[testing.md](./testing.md).

## Seguridad y clasificación

- No incluir secretos, credenciales, tokens, DSN reales, datos personales,
  registros de clientes ni detalles privados de infraestructura.
- Usar placeholders ficticios en ejemplos; no copiar archivos `.env` reales ni
  configuraciones productivas.
- Documentar variables, comandos y valores solo cuando correspondan a elementos
  existentes y verificados.
- Mantener procedimientos operativos sensibles en ubicaciones con acceso
  apropiado. La clasificación interna no autoriza guardar secretos en texto.
- Revisar diagramas, capturas, enlaces y datos de ejemplo para evitar revelar
  información privada o presentar capacidades no existentes.

## README, comandos y referencias

- Crear un README cuando aporte una guía útil; no crear archivos vacíos,
  redundantes ni uno por cada módulo por obligación.
- Un README raíz debe resumir el proyecto y enlazar a las fuentes detalladas,
  no duplicarlas.
- Documentar instalación, ejecución y pruebas solo cuando existan herramientas,
  manifests y comandos reales que hayan sido revisados.
- No inventar endpoints, variables, versiones, dependencias, rutas o badges.
- Usar enlaces a documentos existentes y corregir referencias cuando se muevan
  archivos.

## Mantenimiento y validación

- Actualizar la documentación propietaria cuando un cambio altere requisitos,
  arquitectura, contratos, configuración, comandos o comportamiento relevante.
- Mantener la documentación especializada separada y enlazada: ver
  [postgres.md](./postgres.md), [observabilidad.md](./observabilidad.md),
  [testing.md](./testing.md), [outbox.md](./outbox.md),
  [repository-governance.md](./repository-governance.md) y
  [performance-testing.md](./performance-testing.md).
- Revisar Markdown, enlaces, rutas y exposición de datos sensibles con las
  herramientas que existan en el proyecto.
- Cuando haya CI, ejecutar validaciones documentales en cambios de
  documentación; no ejecutar suites de código completas para un cambio
  exclusivamente documental, salvo que el pipeline o el riesgo lo requieran.
- Informar qué se verificó realmente y qué quedó pendiente; no declarar
  validaciones que no se ejecutaron.

## Criterio de aceptación

La documentación modificada debe ser coherente con la fuente propietaria,
verificable, segura, enlazada correctamente y explícita sobre los límites o
pendientes relevantes. Su extensión debe ser proporcional a su propósito.
