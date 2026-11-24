# ADR-0015: Observabilidad integral de aplicaciones e infraestructura

- Estado: **Proposed**
- Propuesto: 2026-11-24
- Ámbito: los cuatro procesos, módulos, workers, infraestructura y servicios de datos/mensajería.
- Complementa: ADR-0003, ADR-0004, ADR-0007, ADR-0010 y ADR-0013.
- Especificación técnica: [Estrategia técnica de observabilidad](../architecture/observability-strategy.md).

## Contexto

Restaurant OS distribuye operaciones entre cuatro procesos independientes, módulos, PostgreSQL, NATS Core, NATS JetStream, Redis y proveedores externos. Una falla visible en una API puede originarse en cualquiera de esos componentes o en su interacción.

Los logs aislados no muestran tendencias; las métricas agregadas no explican qué paso produjo una demora; y una traza sin logs y métricas correlacionados ofrece contexto incompleto. Se necesita una estrategia común para detectar degradaciones y seguir operaciones entre procesos, módulos, workers, bases de datos y mensajería.

ADR-0004 ya establece W3C Trace Context. ADR-0013 define correlación de Sagas, comandos, eventos y workers. Este ADR no reemplaza esas decisiones: concreta la plataforma y las obligaciones de instrumentación.

## Decisión propuesta

### 1. Plataforma de observabilidad

Adoptar estándares abiertos con estos componentes:

1. **OpenTelemetry:** instrumentación y convenciones comunes; OpenTelemetry Collector para recibir, procesar, filtrar y exportar telemetría.
2. **Prometheus:** scraping y almacenamiento de métricas.
3. **Alertmanager:** agrupación, deduplicación, silenciamiento y enrutamiento de alertas.
4. **Grafana:** dashboards y exploración correlacionada de métricas, logs y trazas.
5. **Loki:** agregación y consulta de logs estructurados.
6. **Tempo:** almacenamiento y consulta de trazas distribuidas compatibles con OpenTelemetry.
7. **Exporters e integraciones mantenidas:** métricas de PostgreSQL, Redis, NATS/JetStream, sistema operativo, contenedores y demás infraestructura.

Prometheus, Loki y Tempo serán fuentes de datos diferenciadas; Grafana permitirá navegar entre ellas mediante trace_id y enlaces de correlación. Grafana no sustituye el almacenamiento ni la instrumentación.

Las versiones, imágenes, distribución, persistencia, dimensionamiento, despliegue y retención se fijarán durante la implementación, verificando compatibilidad y soporte vigentes. Este ADR no fija versiones ni autoriza desplegar servicios.

### 2. Cobertura obligatoria

La cobertura incluirá los cuatro procesos:

- Admin Platform Backend.
- Admin BFF.
- Public BFF.
- Public Backend.

También incluirá todos los módulos y workers, adaptadores local/gRPC/messaging, dispatchers Outbox, consumidores Inbox, procesos de Sagas y tareas programadas. Observar un módulo no concede permiso para leer o modificar sus tablas internas.

La infraestructura y servicios de soporte también tendrán cobertura integral:

- **PostgreSQL:** disponibilidad, conexiones, pools SQLx por módulo, latencia, transacciones, locks, deadlocks, consultas, checkpoints, WAL, vacuum/autovacuum, replicación cuando exista y capacidad.
- **NATS Core:** disponibilidad, conexiones, suscripciones, actividad, errores, tráfico y recursos.
- **NATS JetStream:** streams, consumers, almacenamiento, mensajes pendientes, acknowledgements pendientes, redeliveries, entregas, lag/antigüedad, errores, límites y capacidad.
- **Redis:** disponibilidad, latencia, conexiones, memoria, expiraciones, evictions, hit/miss, operaciones, persistencia y replicación cuando se utilice.
- **Sistema operativo y contenedores:** CPU, memoria, disco, filesystem, red, reinicios, límites y saturación.
- **Proveedores externos:** latencia, timeouts, errores y resultados observables desde nuestros adaptadores.

Redis y NATS no sustituyen PostgreSQL como fuente de verdad de los datos de negocio. La observabilidad no cambia esa regla ni crea ownership de datos compartidos.

### 3. Logs estructurados

1. Emitir logs estructurados, preferentemente JSON, con timestamp UTC, nivel, servicio/proceso, entorno, módulo cuando aplique, evento, resultado y contexto de correlación.
2. Conservar trace_id y span_id cuando exista una traza, además de request_id, correlation_id, causation_id, saga_id, command_id o event_id cuando correspondan. Son identificadores distintos.
3. Registrar errores, transiciones relevantes, fallos de dependencias, timeouts, reintentos, cambios de estado operativo y eventos de seguridad auditables.
4. Los logs no serán el registro de auditoría de negocio ni sustituirán eventos durables, Outbox/Inbox o historiales propios de cada módulo.
5. Nunca registrar contraseñas, tokens, secretos, claves, cookies, datos completos de pago ni payloads personales sensibles. Omitir o redactar campos sensibles antes de exportar.
6. No habilitar logging indiscriminado de consultas SQL con parámetros o payloads sensibles. Registrar duración, resultado y atributos seguros, no valores confidenciales.

### 4. Métricas

1. Exponer métricas de aplicación y runtime para solicitudes, latencia, errores, concurrencia, saturación, workers, colas, reintentos, timeouts y dependencias.
2. Adoptar RED para servicios (Rate, Errors, Duration) y USE para recursos (Utilization, Saturation, Errors), junto con métricas específicas de cada tecnología.
3. Medir pools SQLx por módulo: conexiones abiertas/ociosas/adquiridas, espera para adquirir, timeouts, saturación y errores. No fusionar pools ni acceder a tablas de otro módulo.
4. Medir Outbox/Inbox, NATS Core/JetStream, Redis, PostgreSQL y proveedores externos.
5. No usar identificadores de alta cardinalidad como trace_id, span_id, user_id, tenant_id, request_id, saga_id, event_id o IDs de pedido como etiquetas de métricas.
6. Las dimensiones permitidas serán acotadas y documentadas: servicio, entorno, módulo, operación normalizada y resultado. No incluir payloads ni información personal.

### 5. Trazas distribuidas

1. Usar OpenTelemetry para instrumentar HTTP, gRPC, operaciones de módulos, SQLx/PostgreSQL, Redis, NATS Core, JetStream, workers y llamadas a proveedores cuando las bibliotecas lo permitan.
2. Propagar W3C Trace Context conforme a ADR-0004 por HTTP, metadata gRPC, mensajes NATS, envelopes, Outbox/Inbox y workers.
3. Crear spans para operaciones relevantes y dependencias, con atributos seguros y nombres de cardinalidad controlada.
4. Mantener separados trace_id, span_id, request_id, correlation_id, causation_id, saga_id, command_id y event_id.
5. Una tarea asíncrona puede continuar el contexto causal propagado; cuando no corresponda continuar la misma traza, enlazar trazas mediante links de OpenTelemetry e identificadores de correlación.
6. El muestreo será configurable y consciente de errores/latencia, preservando trazas relevantes sin prometer captura del 100 % del tráfico.

### 6. Correlación, dashboards y alertas

Grafana permitirá navegar desde una métrica o alerta hacia trazas y logs relacionados, y desde una traza hacia logs de sus spans. La correlación técnica no sustituye autorización.

Dashboards y alertas cubrirán disponibilidad, latencia, errores, saturación, capacidad, pools PostgreSQL, bloqueos/consultas lentas, salud de NATS/JetStream, lag y redeliveries, Redis, workers, Outbox/Inbox y Sagas que requieran intervención.

Alertmanager gestionará reglas con umbrales y ventanas derivados de SLO/criticidad; no se fijan umbrales universales aquí. Cada alerta tendrá propietario, severidad, señal, condición de activación, guía de diagnóstico y procedimiento de respuesta.

### 7. Seguridad y aislamiento

1. Los endpoints de métricas, administración y diagnóstico no serán públicos; se limitarán a redes privadas y controles de acceso.
2. Los exporters usarán identidades de solo lectura y privilegios mínimos. PostgreSQL tendrá un rol específico de monitoreo, sin permisos de escritura, DDL, acceso general a datos de negocio ni BYPASSRLS. Su alcance se validará frente a las vistas estadísticas y versión objetivo.
3. Redis usará ACL/identidad de monitoreo limitada a comandos de diagnóstico necesarios. NATS protegerá endpoints de monitorización y credenciales administrativas.
4. Collectors y backends de telemetría tendrán autenticación, transporte protegido y controles de red.
5. No se expondrán datos de un tenant a otro mediante dashboards, consultas, logs o trazas. El acceso operativo a telemetría con contexto de tenant será restringido y auditado.
6. No incluir secretos ni datos personales en etiquetas, nombres de span, mensajes de error o atributos. Aplicar redacción antes de persistir telemetría.

### 8. Retención, costos y resiliencia

1. Definir retención independiente para métricas, logs y trazas, según entorno, criticidad, volumen, obligaciones legales y costo.
2. Controlar cardinalidad, volumen de logs, tamaño de spans, sampling, compresión y almacenamiento.
3. La pérdida temporal de observabilidad no debe detener automáticamente el procesamiento de negocio. SDKs/collectors tendrán colas y límites de memoria/disco acotados, timeouts y política de descarte/backpressure.
4. La plataforma se monitoreará a sí misma: disponibilidad de Prometheus, Alertmanager, Grafana, Loki, Tempo y Collectors; errores de ingestión, colas, retrasos, uso de disco y fallos de almacenamiento.
5. Los objetivos de disponibilidad, retención, RPO/RTO y dimensionamiento se definirán antes del despliegue productivo.

### 9. Ownership y límites

La plataforma es infraestructura transversal bajo infrastructure/; no es un módulo de negocio ni un backend adicional. No tendrá autoridad para modificar datos de negocio. Cada módulo será responsable de instrumentar sus operaciones y exponer señales seguras. No se crea schema compartido ni tabla de negocio de observabilidad.

## Alternativas consideradas

- **Solo logs:** rechazado; no permite analizar tendencias ni localizar la duración de cada dependencia.
- **Logs y métricas sin trazas:** rechazado; no reconstruye el recorrido de una operación.
- **Solución cerrada como fuente única:** no se adopta como requisito; se priorizan estándares abiertos e interoperabilidad.
- **Instrumentación independiente por módulo:** rechazada; fragmenta la correlación.

## Consecuencias

**Positivas:** diagnóstico desde el síntoma hasta la dependencia causante; visibilidad de aplicaciones e infraestructura; detección proactiva; correlación sin acoplar módulos; control de privacidad, cardinalidad, retención y costo.

**Costos y riesgos:** consumo adicional de CPU, memoria, red y almacenamiento; operación de varios componentes; riesgo de cardinalidad, telemetría sensible o costos elevados; necesidad de mantener instrumentación, dashboards y alertas.

## Plan de implementación futuro

1. Validar compatibilidad, versiones soportadas, licencias, seguridad y topología.
2. Diseñar configuración de OpenTelemetry SDK/Collector, pipelines, exporters y autenticación.
3. Instrumentar los cuatro procesos, módulos, workers y adaptadores.
4. Habilitar métricas y exporters de PostgreSQL, Redis, NATS/JetStream, sistema operativo y contenedores.
5. Configurar Prometheus, Alertmanager, Loki, Tempo y Grafana con persistencia, retención y controles de acceso.
6. Crear dashboards, alertas, SLOs, runbooks y pruebas de propagación/correlación.
7. Verificar carga, pérdida de telemetría, degradación del collector, cardinalidad, aislamiento y comportamiento ante indisponibilidad de observabilidad.

## Estado de implementación

Esta propuesta no implica que OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Alertmanager, exporters, dashboards, alertas o instrumentación estén instalados o desplegados. No crea crates, dependencias, servicios, contenedores, configuraciones ni cambios de infraestructura. Su aceptación requerirá aprobación explícita del propietario del producto y su implementación se realizará en una fase posterior.
