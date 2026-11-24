> **Estado: superseded.** Este documento se conserva como referencia histórica. La fuente normativa vigente es [Reglas de implementación: pruebas y calidad](../docs/engineering/implementation-rules.md#6-pruebas-y-calidad). No añadir reglas nuevas aquí; actualizar la fuente vigente y registrar ADR cuando corresponda.

# Reglas de pruebas de rendimiento

## Alcance y estado

Estas reglas aplican a APIs, workers y flujos operativos de Restaurant OS
cuando exista código ejecutable que se pueda medir. La estrategia puede
definirse temprano; no se deben generar cargas ni afirmar capacidad para
componentes que aún no estén implementados.

Grafana k6 es el estándar del proyecto para pruebas de carga de APIs y
protocolos que soporte adecuadamente. Mantener los scripts y su configuración
versionados junto al proyecto y fijar la versión de k6 cuando se incorpore a
los entornos de ejecución; no depender de una versión flotante.

k6 no sustituye herramientas específicas para benchmarks de código Rust,
profiling o análisis de PostgreSQL. Usar otra herramienta para una prueba de
API solo cuando k6 no cubra el protocolo o la necesidad técnica; documentar el
motivo. Añadir herramientas solo cuando un riesgo o una pregunta de rendimiento
lo justifique. Esta regla no significa que k6 ya esté instalado, configurado o
integrado en CI.

## Diseño de escenarios y carga

- Medir flujos de negocio implementados, no endpoints sintéticos que omitan el
  comportamiento que se busca validar.
- Según la fase, priorizar flujos como autenticación, selección de empresa y
  sucursal, consulta de catálogo, toma de pedidos, actualización de cocina,
  cobro en sandbox, inventario, dashboard y exportaciones.
- Diferenciar usuarios virtuales (VUs), iteraciones, solicitudes por segundo y
  operaciones de negocio por segundo. Documentar qué representa cada medida.
- Elegir un modelo cerrado —concurrencia de usuarios controlada— o abierto
  —tasa de llegada controlada— según el comportamiento que se quiere estudiar.
  No presentar iteraciones por segundo como solicitudes por segundo sin
  medirlas.
- Establecer objetivo de carga, duración, datos, entorno, dependencias y
  criterios de interrupción antes de una ejecución significativa.
- No confundir la carga configurada con la carga realmente alcanzada. Analizar
  iteraciones descartadas, errores del generador y saturación de red o CPU del
  generador antes de atribuir resultados a la aplicación.
- No insertar pausas arbitrarias para aparentar una tasa de llegada o esconder
  degradaciones. Usar pausas solo cuando representen el comportamiento del
  usuario que se está modelando.

## Selección y frecuencia de pruebas

- Usar smoke tests de baja carga para comprobar que scripts y entornos
  controlados funcionan; no presentarlos como evidencia de capacidad.
- Ejecutar pruebas de carga normal para flujos críticos cuando haya una
  referencia de demanda.
- Realizar pruebas de estrés, picos, resistencia prolongada, breakpoint o
  escalabilidad solo cuando respondan una pregunta concreta y el entorno,
  recursos, supervisión y recuperación estén aprobados.
- Mantener ligeras las validaciones de Pull Request cuando haya un entorno
  adecuado. Programar o ejecutar antes de releases las pruebas más largas o
  costosas según su riesgo; no ejecutar stress tests indiscriminadamente en
  cada cambio.
- Repetir ejecuciones importantes y comparar solo resultados obtenidos con
  perfiles, datos, versiones e infraestructura equivalentes.

## Datos e integridad

- Utilizar tenants, sucursales, usuarios y registros sintéticos dedicados a
  pruebas, o datos cuyo uso esté expresamente autorizado.
- Preparar datasets con un mecanismo controlado y documentado. La preparación
  puede hacerse antes de la ventana medida; el flujo bajo evaluación debe
  atravesar la aplicación real cuando ese sea el objetivo.
- Separar datos y credenciales por entorno; generar claves idempotentes únicas
  por operación y controlar las colisiones intencionales.
- Probar en sandboxes las pasarelas de pago y otros proveedores externos.
  No emitir pagos ni enviar notificaciones reales, ni afectar pedidos o
  reservas operativos en pruebas ordinarias.
- Definir limpieza segura, idempotente y verificable, además de recuperación
  cuando una ejecución se interrumpa. Verificar integridad, duplicados
  indebidos y estado de los servicios después de la carga.

## Autorización y límites de seguridad

- Ejecutar carga solo contra entornos y destinos expresamente autorizados.
  Nunca probar infraestructura de terceros sin autorización.
- No realizar pruebas agresivas, destructivas, de estrés o breakpoint en
  producción. Cualquier prueba de producción de bajo riesgo requiere aprobación
  explícita, supervisión, límites de carga y criterios de interrupción.
- No evadir rate limits, WAF ni otros controles para aumentar la carga.
- Proporcionar credenciales mediante mecanismos seguros; nunca incluirlas en
  scripts, logs o reportes.
- Interrumpir la prueba si se alcanzan límites aprobados, se degrada la
  integridad o se compromete la disponibilidad. Confirmar recuperación antes
  de iniciar otra prueba significativa.

## Umbrales y línea base

- Derivar thresholds de requisitos, SLO aprobados, presupuestos de latencia y
  mediciones del entorno. No imponer valores globales de latencia, concurrencia,
  errores o recursos a todos los flujos.
- Usar checks funcionales y thresholds de métricas de manera complementaria.
  Comprobar respuestas y estados de negocio además del código HTTP.
- Evaluar percentiles —incluidos p95 y p99 cuando sean pertinentes—, errores,
  throughput, duración y carga realmente alcanzada. Los promedios por sí solos
  no describen las colas de latencia.
- Registrar una línea base reproducible para los flujos críticos cuando el
  entorno permita medirla. No comparar ejecuciones con condiciones
  incompatibles ni declarar regresiones o mejoras sin evidencia suficiente.
- No modificar carga, thresholds o filtros para ocultar fallos. Las
  excepciones deben documentar motivo, riesgo, alcance, responsable y duración.

## Observabilidad y cuellos de botella

- Correlacionar la carga de prueba con métricas de aplicación e infraestructura
  usando el stack de
  [observabilidad](./observabilidad.md), cuando esté implementado.
- Revisar conexiones, espera del pool, consultas, locks, transacciones y
  saturación de PostgreSQL conforme a [postgres.md](./postgres.md).
- Para procesos asíncronos, medir backlog, antigüedad, reintentos, fallos y
  tiempo de procesamiento; comprobar el efecto final y no solo la respuesta
  inicial. Para Outbox/Inbox, seguir [outbox.md](./outbox.md).
- Diferenciar la capacidad del sistema propio de la del generador de carga y de
  proveedores externos. Documentar simulaciones y sandboxes; no atribuir sus
  resultados al servicio real.
- No incluir secretos ni IDs de alta cardinalidad en etiquetas métricas.
  Correlacionar despliegues con su versión o commit cuando estén disponibles.

## Evidencia y aceptación

Para cada ejecución importante, registrar el comando o procedimiento, versión
de la herramienta, commit/build, entorno, perfil de carga, dataset, duración,
thresholds, carga alcanzada, errores, percentiles relevantes, recursos,
limitaciones y resultado.

Una prueba solo valida el alcance realmente medido. No afirmar que Restaurant
OS soporta una cantidad determinada de usuarios, que es escalable o que está
preparado para producción sin resultados reproducibles, condiciones explícitas
y métricas suficientes.

Seguir las reglas de
[testing](./testing.md) para el diseño y reporte de verificaciones y
[repository-governance](./repository-governance.md) para su integración en CI.
