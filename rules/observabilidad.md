# Reglas de observabilidad y monitoreo

## Alcance

Estas reglas aplican al monolito modular de Restaurant OS, sus módulos, API,
interfaces, workers y dependencias operativas. La telemetría es transversal:
no modifica la propiedad de datos ni los límites entre dominios.

La observabilidad registra el comportamiento técnico para detectar y diagnosticar
fallos. No sustituye a Audit, que conserva la trazabilidad funcional y de negocio.

Instrumentar cada componente cuando se implemente y antes de habilitarlo en
producción. La documentación de una herramienta no demuestra que esté instalada,
configurada o recibiendo datos.

## Stack estándar del proyecto

| Componente | Responsabilidad |
|---|---|
| OpenTelemetry | Instrumentación y propagación estándar de logs, métricas y trazas. |
| OpenTelemetry Collector | Recibir, procesar y exportar telemetría a los destinos definidos. |
| Prometheus | Recolectar y consultar métricas. |
| Loki | Almacenar y consultar logs. |
| Tempo | Almacenar y consultar trazas. |
| Grafana | Dashboards y exploración de métricas, logs y trazas. |
| Alertmanager | Agrupar, deduplicar y gestionar alertas de Prometheus. |
| Sentry | Errores inesperados y rendimiento de aplicaciones, especialmente en interfaces. |

OpenTelemetry es la interfaz de instrumentación; el Collector es la capa de
recepción y procesamiento. Sentry complementa el stack y no sustituye logs,
métricas, trazas, alertas ni Audit.

La instrumentación enviará telemetría al Collector. Los datos se exportarán a
Prometheus, Loki y Tempo según su señal; Grafana los presentará y Prometheus
enviará alertas a Alertmanager. Sentry recibirá los eventos de error y
rendimiento aprobados. La topología puede evolucionar, pero no se deben inventar
destinos, credenciales ni canales de notificación.

## Reglas obligatorias

### 1. Instrumentación y registros

- Implementar logs estructurados, métricas y trazas según la naturaleza del
  componente.
- Registrar servicio, entorno, versión, módulo y resultado cuando sean
  pertinentes.
- No elevar errores de negocio esperados —por ejemplo, una validación rechazada—
  a errores técnicos ni enviarlos automáticamente a Sentry.
- Clasificar errores como validación, autorización, negocio, persistencia,
  dependencia, timeout o inesperados.

### 2. Correlación

- Propagar contexto de trazas y correlación entre API, módulos, eventos y
  workers cuando el flujo lo permita.
- Mantener diferenciados `trace_id`, `span_id`, `request_id`, `correlation_id`,
  `causation_id` y `event_id`.
- Tratar los identificadores recibidos del cliente como metadatos de
  diagnóstico, no como identidad ni autorización.
- No crear métricas con etiquetas de alta cardinalidad, como IDs de usuario,
  pedido, pago, petición o tenant.

### 3. Privacidad y seguridad

- No registrar contraseñas, tokens, secretos, datos de tarjetas ni información
  personal o sensible innecesaria.
- Redactar datos en el origen y aplicar filtros adicionales en el Collector
  cuando corresponda.
- Restringir y auditar el acceso a la plataforma de observabilidad.
- Los identificadores de tenant solo se incluirán en logs o trazas si son
  necesarios, están minimizados y su acceso está controlado; nunca usarlos como
  etiquetas métricas sin una cardinalidad acotada y justificada.

### 4. Métricas de servicios, base de datos y workers

- Para API y comunicaciones internas, medir tasa, errores y duración con rutas y
  operaciones normalizadas.
- Observar saturación y errores de recursos: CPU, memoria, disco, red, conexiones,
  pools y colas.
- Para workers, medir ejecuciones, duración, resultados, reintentos, fallos,
  backlog y antigüedad del trabajo pendiente.
- Para PostgreSQL, observar conexiones, espera del pool, timeouts, consultas
  lentas y locks conforme a [postgres.md](./postgres.md).
- No registrar cada reintento como una alerta independiente; agrupar señales por
  componente y tipo de trabajo.

### 5. Salud y alertas

- Diferenciar liveness (el proceso sigue vivo) de readiness (puede recibir
  trabajo) y no convertir dependencias opcionales en una causa automática de
  indisponibilidad global.
- Basar las alertas en impacto, saturación sostenida o riesgo; no copiar
  umbrales de otro proyecto.
- Toda alerta que requiera intervención debe tener severidad, responsable,
  condición de recuperación y procedimiento de atención.
- Alertmanager gestionará las alertas configuradas. No inventar ni habilitar
  destinos de notificación sin aprobación.
- Definir SLI y SLO para flujos críticos con evidencia. Un SLO no es un SLA ni
  una promesa contractual.

### 6. Releases y despliegues

- Asociar la telemetría a servicio, entorno, versión y build o commit cuando
  estén disponibles.
- Después de cada despliegue, verificar salud, errores, latencia y operaciones
  críticas del componente afectado.
- Correlacionar regresiones con releases sin atribuir causalidad únicamente por
  coincidencia temporal.

### 7. Pruebas y aceptación

- Verificar formato de logs, propagación de contexto, redacción y límites de
  cardinalidad.
- Probar que una falla del Collector o de un destino de telemetría no interrumpe
  las operaciones de negocio.
- Probar la generación, agrupación y recuperación de alertas pertinentes.
- Validar las integraciones con servicios reales de prueba cuando corresponda;
  mocks y configuración escrita no demuestran recepción efectiva.
- No declarar instrumentación, alertas, SLO ni cobertura como implementados sin
  evidencia verificable.

## Despliegue por fases

OpenTelemetry, Collector, Prometheus, Loki, Tempo, Grafana, Alertmanager y Sentry
son componentes aprobados para el stack objetivo; su disponibilidad no implica
que ya estén desplegados. Incorporar y verificar cada componente con el primer
flujo real que lo necesite, sin afirmar cobertura de servicios aún inexistentes.

Definir retención, sampling, volumen, acceso y costes antes de habilitar
telemetría de producción. No fijar límites, objetivos SLO ni umbrales de alerta
sin mediciones y responsables operativos.