# Reglas de gobierno del repositorio

## Alcance y estado

Estas reglas aplican al código, la documentación, las migraciones, los
workflows y los releases de Restaurant OS una vez que el proyecto tenga un
repositorio Git compartido. Definen prácticas de ingeniería; no prueban que Git
esté conectado a GitHub ni que sus controles estén configurados.

El espacio de trabajo actual no cuenta con un repositorio Git inicializado.
Hasta configurarlo, las protecciones de ramas, Pull Requests, CI y revisiones
son pendientes, no controles implementados. No declarar su cumplimiento sin
verificar la configuración efectiva del proveedor.

## Cambios y revisiones

- En un repositorio compartido, desarrollar en ramas enfocadas e integrar los
  cambios a la rama principal mediante Pull Requests. No hacer push directo a
  una rama principal protegida ni eludir sus verificaciones.
- Mantener cada Pull Request revisable e incluir objetivo, alcance, riesgos,
  pruebas ejecutadas y documentación o migraciones afectadas.
- Exigir que los checks aplicables terminen correctamente y que las
  conversaciones requeridas estén resueltas antes de integrar.
- Revisar funcionalidad, límites de dominio, propiedad de datos, seguridad,
  pruebas, documentación y compatibilidad según el riesgo del cambio.
- Si hay una sola persona mantenedora, permitir auto-revisión documentada sin
  presentarla como aprobación independiente. Cambios críticos de seguridad,
  autenticación, permisos, privacidad o infraestructura deben esperar revisión
  autorizada independiente cuando el riesgo lo requiera.
- No mezclar cambios sin relación ni reducir pruebas, aserciones o controles
  para conseguir una integración satisfactoria.

## Integración continua

- Configurar CI cuando existan manifests, comandos y componentes ejecutables.
  Los checks deben ser reproducibles y corresponder al código y a las
  dependencias reales.
- Ejecutar validaciones según los componentes afectados y sus dependencias;
  no omitir checks necesarios por filtros de rutas incompletos.
- No ocultar fallos de checks obligatorios con `continue-on-error`, exclusiones
  injustificadas o desactivación de pruebas.
- Mantener consistencia entre validaciones locales y CI. Para las pruebas y la
  evidencia, seguir [testing.md](./testing.md).
- Usar permisos mínimos en los workflows. No exponer secretos a código no
  confiable de Pull Requests ni conceder permisos de escritura si el workflow
  solo necesita leer y validar.
- Revisar cambios de workflows como cambios de seguridad. Fijar acciones
  externas a versiones inmutables cuando la política del repositorio lo
  requiera.
- Los cambios exclusivamente documentales deben ejecutar validaciones
  documentales apropiadas, no compilaciones y suites completas sin motivo.

## Secretos y dependencias

- No almacenar credenciales, tokens, claves privadas, DSN reales ni archivos
  `.env` con valores secretos en el repositorio.
- Si un secreto se expone, revocarlo o rotarlo de inmediato e investigar su
  alcance; borrar el archivo o el último commit no invalida el secreto expuesto.
- Mantener los lockfiles de aplicaciones y utilizar instalaciones
  reproducibles. En Rust, usar `Cargo.lock` y `--locked` cuando el workspace y
  los comandos correspondientes estén configurados.
- Elegir secret scanning, análisis de dependencias y otros controles según el
  riesgo, la plataforma y su disponibilidad. No documentar herramientas como
  activas hasta verificar su ejecución.

## Migraciones y releases

- Revisar y validar las migraciones de acuerdo con
  [postgres.md](./postgres.md); no ejecutar migraciones productivas desde un
  workflow genérico de CI.
- Mantener autorizados y verificables los procedimientos de despliegue y
  recuperación.
- Cuando existan releases, registrar versión, commit, cambios relevantes,
  migraciones y evidencia de validación. Adoptar Semantic Versioning solo si
  encaja con el modelo de publicación del producto.
- No confundir un merge, una etiqueta o un CI verde con la verificación de una
  release o un despliegue.

## Agentes y excepciones

- Los agentes de IA deben respetar el alcance autorizado, no inventar resultados
  de CI y no fusionar, publicar ni desplegar sin autorización.
- Las excepciones deben indicar regla, motivo, riesgo, alcance, responsable,
  duración, mitigación y condición de cierre. No deben convertirse en
  omisiones silenciosas o permanentes.

## Criterio de aceptación

Antes de integrar un cambio, debe poder identificarse qué se modificó, por qué,
qué validaciones se ejecutaron y qué riesgos o bloqueos permanecen. Informar el
estado real de los controles; si no existen o no se verificaron, declararlos
pendientes.
