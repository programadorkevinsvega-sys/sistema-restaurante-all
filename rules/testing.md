> **Estado: superseded.** Este documento se conserva como referencia histórica. La fuente normativa vigente es [Reglas vigentes de pruebas y calidad](../docs/engineering/implementation-rules.md#6-pruebas-y-calidad). No añadir reglas nuevas aquí ni resolver contradicciones desde este archivo; actualizar la fuente vigente y registrar ADR cuando corresponda.\n\n# Reglas de pruebas y calidad

## Alcance

Estas reglas aplican al monolito modular de Restaurant OS y a los componentes
que se implementen en cada fase. Las pruebas deben corresponder al código,
contratos y dependencias reales; los requisitos documentados no demuestran por
sí solos que una funcionalidad esté implementada.

Complementan las reglas de [PostgreSQL](./postgres.md) y
[observabilidad](./observabilidad.md). No duplican sus controles especializados.

## Reglas obligatorias

### 1. Inspeccionar antes de modificar

- Revisar la estructura, el dominio afectado, los contratos, migraciones,
  pruebas y convenciones existentes antes de cambiar código.
- Distinguir lo implementado de lo planificado y registrar los fallos
  preexistentes relevantes.
- No afirmar que una funcionalidad está probada basándose solo en su
  documentación o en pruebas escritas que no se ejecutaron.

### 2. Mantener el alcance y proteger los datos

- Hacer cambios precisos; no eliminar pruebas ni rebajar aserciones para hacer
  pasar una ejecución.
- No ejecutar pruebas destructivas, cobros reales ni operaciones irreversibles
  contra producción.
- Usar entornos aislados, credenciales de prueba y datos sintéticos o autorizados.
- No incluir secretos ni datos personales reales innecesarios en fixtures,
  reportes de prueba o logs.

### 3. Diseñar pruebas según riesgo

- Relacionar requisitos y riesgos con escenarios de prueba y resultados
  verificables.
- Priorizar seguridad, aislamiento entre tenants, integridad financiera,
  inventario, idempotencia, autorización y recuperación ante fallos.
- Probar resultados y errores esperados; no basta con comprobar que una
  operación devuelve algún resultado.
- Evitar pruebas frágiles que dependan del orden, la red, el reloj real o
  valores aleatorios no controlados.

### 4. Elegir el nivel correcto de prueba

- Usar pruebas unitarias para reglas de negocio aislables, límites,
  validaciones, transiciones de estado y cálculos.
- Usar pruebas basadas en propiedades cuando existan invariantes útiles; hacer
  reproducibles los casos que fallen.
- Usar mocks para aislar unidades, no como sustituto de integración con una
  dependencia cuyo comportamiento se necesita verificar.
- Usar dependencias reales en entornos aislados para probar persistencia,
  transacciones, RLS, colas, workers y contratos cuando corresponda.
- Añadir pruebas API/E2E cuando existan rutas y flujos ejecutables; no simular
  servicios que aún no existen.

### 5. Cubrir riesgos propios de Restaurant OS

Según las funciones implementadas, probar:

- Acceso de lectura, escritura y exportación entre tenants, empresas y
  sucursales; verificar autorización de aplicación y RLS.
- Reglas de permisos y alcance en el servidor, sin confiar en restricciones de
  interfaz o identificadores enviados por el cliente.
- Consistencia de dinero, impuestos, redondeos y zonas horarias.
- Idempotencia, solicitudes duplicadas, concurrencia, transiciones y
  restricciones únicas.
- Commit, rollback, errores parciales y recuperación de operaciones con varias
  escrituras.
- Migraciones desde una base vacía y desde versiones anteriores que el proyecto
  declare compatibles.
- Eventos duplicados, inválidos o reintentados; comprobar orden solo cuando el
  dominio lo requiera y no asumir entrega exactly-once extremo a extremo.
- Workers interrumpidos, leases expirados, reanudación, checkpoints y efectos
  duplicados.

No ejecutar escenarios de módulos o integraciones que todavía no estén
implementados.

### 6. Probar concurrencia, fallos y dependencias reales

- Probar las operaciones concurrentes que puedan violar invariantes o límites
  de negocio.
- Probar timeouts, cancelación, pérdida de conexión y recuperación cuando el
  componente dependa de esos comportamientos.
- Ejecutar pruebas de resiliencia o inyección de fallos solo en entornos
  controlados, con hipótesis, resultado esperado y verificación de integridad
  posterior.
- No añadir circuit breakers, fuzzers, mutation testing u otras herramientas
  sin un riesgo y un criterio de aceptación que lo justifiquen.

### 7. Medir calidad sin perseguir métricas vacías

- Evaluar cobertura por módulo, riesgo y flujo crítico; no usar un porcentaje
  global como prueba suficiente de calidad.
- Establecer líneas base y objetivos de rendimiento con condiciones
  reproducibles; no copiar umbrales de otro proyecto.
- Ejecutar cargas, benchmarks y fuzzing solo cuando haya código, escenarios y
  recursos apropiados.
- No añadir dependencias de testing antes de confirmar que el repositorio y la
  fase las necesitan.

### 8. Mantener validaciones reproducibles

- Ejecutar el comando más pequeño que cubra el cambio y escalar a suites mayores
  cuando el riesgo o el resultado lo requieran.
- Cuando existan CI y validaciones locales, usar los mismos comandos,
  configuración y criterios de aceptación.
- Adaptar los comandos a los manifests, herramientas y workflows existentes;
  no declarar verificaciones de Cargo, frontend o CI antes de que estén
  configurados.
- Probar migraciones contra PostgreSQL real cuando se valide su ejecución; el
  análisis sintáctico estático no demuestra que la migración aplique ni que su
  comportamiento sea correcto.

### 9. Informar evidencia y estado

Clasificar cada verificación como:

- **APROBADO:** ejecutada y satisfecha.
- **FALLIDO:** ejecutada y detectó un defecto o incumplimiento.
- **BLOQUEADO:** no pudo ejecutarse por una dependencia o condición documentada.
- **NO EJECUTADO:** todavía no se intentó.
- **NO APLICA:** existe una justificación técnica.

Al informar resultados, indicar el comando ejecutado, el alcance y los
bloqueos relevantes. No inventar conteos, resultados, cobertura ni cumplimiento.
El detalle del informe debe ser proporcional al cambio; los defectos críticos,
las pruebas bloqueadas y los riesgos residuales siempre deben quedar explícitos.

## Criterio de aceptación

Una verificación solo se considera completada cuando hay evidencia reproducible
para el alcance evaluado. No declarar un módulo seguro, íntegramente probado o
listo para producción en términos absolutos; describir lo probado y sus
limitaciones.
