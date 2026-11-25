# Redis Cluster, TLS y operación de caché distribuida

**Estado:** especificación técnica vigente y aprobada, subordinada a ADR-0016 Accepted.
**Ámbito:** caché distribuida transversal para los cuatro procesos y consultas elegibles de los módulos propietarios.
**Naturaleza:** contrato de diseño y operación para una implementación futura; no acredita infraestructura desplegada.

## 1. Propósito y autoridad

Esta especificación desarrolla ADR-0016 sin modificar sus decisiones. Si existe discrepancia, ADR-0016 es la autoridad arquitectónica y esta especificación concreta su operación.

Redis es una capa de aceleración reconstruible. PostgreSQL y el módulo propietario siguen siendo la fuente autoritativa. Redis no adquiere ownership de datos, reglas de negocio, sesiones, pagos, inventario, trabajos durables, eventos, locks de negocio ni coordinación de jobs.

La caché distribuida se utiliza en consultas costosas y repetidas cuando mediciones, tolerancia de staleness, aislamiento y política de invalidación justifican su uso. No se cachea indiscriminadamente cada SELECT.

## 2. Topología y disponibilidad

- La topología objetivo es Redis Cluster, no Redis Sentinel.
- La base de producción tendrá al menos tres primarios/shards y réplicas en dominios de fallo independientes cuando la infraestructura lo permita.
- Redis Cluster administra hash slots, descubrimiento, redirecciones MOVED/ASK, replicación y failover. No se añade Sentinel al mismo clúster.
- El cliente debe soportar topología Cluster, refresh de slots, reconexión, timeouts y reintentos acotados.
- Las operaciones multi-key deben respetar hash slots. Los hash tags se reservan para operaciones atómicas justificadas y se vigila que no creen hotspots.
- El escalado horizontal se realiza agregando shards y rebalanceando slots de manera controlada, con medición previa de memoria, CPU, latencia, throughput y distribución de claves.
- No se fija un número máximo de shards, capacidad por nodo, proveedor o tamaño de instancia sin pruebas representativas.
- Los endpoints de cliente y administración se mantienen en red privada, sin exposición directa a Internet.

La pérdida de un nodo no debe causar pérdida de datos de negocio. Una caché fría es un modo degradado aceptable; la recuperación debe evitar regeneraciones masivas simultáneas.

## 3. Transporte y seguridad

TLS es obligatorio en producción para conexiones de todos los procesos clientes, replicación entre nodos, bus de cluster y endpoints administrativos/monitorización que admitan TLS.

1. TLS 1.2 como mínimo y TLS 1.3 preferido cuando la plataforma y los clientes lo soporten.
2. Validación de cadena de confianza y hostname/SAN. Se prohíbe desactivar la validación de certificados.
3. Certificados de una autoridad administrada; claves privadas y secretos fuera de Git, logs, trazas, métricas y artefactos.
4. Rotación con solapamiento de confianza y procedimiento de reversión.
5. mTLS puede añadirse como autenticación de transporte, pero no reemplaza ACL de Redis.
6. Acceso restringido mediante redes privadas, firewall/security groups y orígenes autorizados.
7. Identidades ACL separadas por proceso/módulo o unidad de confianza documentada. Deshabilitar acceso anónimo.
8. Privilegio mínimo por comandos y patrones de claves. Los prefijos de clave no sustituyen ACL.
9. Separación de credenciales y namespaces entre entornos.
10. Los BFF no son propietarios de caché de dominio ni reciben acceso indiscriminado a claves privadas de módulos.

Las versiones de Redis y bibliotecas cliente se seleccionarán al implementar según soporte vigente, compatibilidad Cluster/TLS/ACL y pruebas de seguridad; esta especificación no fija versiones de software.

## 4. Ownership y límites entre módulos

- Cada módulo administra únicamente las entradas derivadas de sus propias consultas y datos.
- Ningún módulo puede leer, invalidar o modificar arbitrariamente claves privadas de otro módulo.
- Los BFF llaman a contratos de módulos propietarios; no consultan PostgreSQL ni claves de dominio directamente.
- Los módulos no acceden a schemas ajenos para poblar caché.
- Una vista agregada que combine varios módulos debe construirse mediante contratos/eventos y tener un propietario definido; Redis no crea una excepción al ownership.
- PLATFORM puede cachear únicamente datos que pertenecen a PLATFORM o resultados que obtiene mediante contratos autorizados, sin duplicar ownership de IDENTITY ni otros módulos.

## 5. Modelo de claves

Formato conceptual: environment:cache:owner-module:operation:v-result-version:scope:parameter-digest.

La construcción debe normalizar parámetros y filtros; incluir tenant scope, usuario, rol, permisos, sucursal, idioma, moneda, zona horaria u otro contexto cuando cambie el resultado; evitar PII, tokens o parámetros sensibles en claro; incorporar versión del resultado; limitar longitud y cardinalidad; e impedir reutilización entre tenants o permisos distintos.

Los valores se serializan con formato versionado y límites explícitos de tamaño. Una entrada inválida, incompatible o de versión desconocida se trata como miss y se elimina de forma segura.

## 6. Elegibilidad de consultas y patrón cache-aside

Cada operación cacheable tendrá una ficha con módulo propietario, nombre estable, justificación basada en mediciones, parámetros de clave, scope de tenant/usuario/permisos, sensibilidad, TTL, tolerancia máxima a staleness, eventos de invalidación, tamaño máximo, presupuesto de memoria y métricas.

Flujo cache-aside:

1. El módulo valida identidad, autorización y scope requerido.
2. Construye la clave determinista.
3. Consulta Redis con timeout corto.
4. En hit, valida versión y contexto; nunca usa una entrada de otro tenant o scope.
5. En miss, consulta su propia fuente autoritativa.
6. Guarda el resultado con TTL finito y límites de tamaño, si la política permite cachearlo.
7. Devuelve la respuesta sin convertir la escritura de caché en parte de la transacción de negocio.

No se cachean por defecto secretos, credenciales, tokens, cookies, datos completos de pago ni payloads personales sensibles. Toda excepción requiere clasificación, minimización, aislamiento, TTL y controles documentados.

## 7. TTL, memoria y expulsión

- Toda entrada tiene TTL finito; el TTL se determina por operación y tolerancia a staleness.
- Añadir jitter acotado para evitar expiraciones sincronizadas.
- Limitar tamaño por valor, número de entradas y presupuesto de memoria.
- allkeys-lfu es la política inicial a evaluar mediante pruebas, no una garantía de que será óptima para todo workload.
- Alertar sobre presión de memoria, fragmentación y evictions anómalas.
- Eviction, reinicio, failover o flush deben poder producir una caché fría sin pérdida de datos autoritativos.

## 8. Invalidación durable y prevención de datos obsoletos

1. El módulo registra el cambio y la intención durable de invalidación en la misma transacción local mediante Outbox.
2. El dispatcher publica la intención por NATS JetStream, conforme a ADR-0003, ADR-0013 y ADR-0017.
3. El consumidor aplica invalidación idempotente y confirma el procesamiento según el protocolo durable.
4. El evento incluye propietario, agregado/scope afectado, versión o secuencia y contexto de trazabilidad necesario.
5. Se prefiere invalidación por clave/tags acotados o incremento de generación/versionado de namespace. Se evita SCAN masivo como mecanismo ordinario.
6. Eventos duplicados se procesan idempotentemente; eventos antiguos o fuera de orden no pueden retroceder la generación.
7. Un error temporal de Redis no elimina la intención durable. Se reintenta con backoff y límites; se monitoriza el retraso de invalidación.
8. Una carga iniciada antes de la invalidación no puede reinsertar silenciosamente un valor obsoleto después. La escritura debe comprobar generación/versión actual o utilizar una operación atómica equivalente.
9. La confirmación del cambio de negocio no depende de que Redis esté disponible.
10. NATS Core no es el único mecanismo para invalidaciones cuya pérdida dejaría datos obsoletos fuera de la tolerancia declarada.

Los parámetros exactos del sobre de evento reutilizan los contratos y metadatos ya definidos por Outbox/Inbox. No se crea un esquema duplicado de eventos dentro de Redis.

## 9. Consistencia y lecturas críticas

Redis no reemplaza controles de consistencia. Autenticación, autorización, permisos, pagos, reembolsos, saldos, caja, movimientos financieros, disponibilidad transaccional de inventario, validaciones de límites y transiciones críticas consultan la fuente autoritativa o una ruta de consistencia fuerte; nunca una caché potencialmente obsoleta como única comprobación.

La caché puede utilizarse para vistas informativas y consultas no críticas cuando la tolerancia de staleness está explícita. Stale-while-revalidate solo se permite para operaciones que lo declaren y nunca se activa como comportamiento general. El uso de Redis no autoriza FKs, joins, vistas ni consultas directas entre schemas.

## 10. Protección contra stampede y carga de origen

- Aplicar single-flight local para agrupar regeneraciones concurrentes de una misma clave cuando sea posible.
- Se permiten leases breves para reducir regeneraciones duplicadas entre réplicas, con token aleatorio, expiración y liberación segura.
- Un lease de caché no es lock de negocio, no garantiza exclusión transaccional y no sustituye advisory locks/leases de jobs.
- Aplicar TTL jitter, límites de concurrencia, backpressure y presupuestos de regeneración.
- El calentamiento anticipado se limita por lotes, concurrencia y ventana operativa.
- Tras failover o caché fría, la regeneración es gradual.
- Si Redis falla, el fallback a PostgreSQL está limitado; un circuito abierto no debe producir una avalancha de consultas.
- Cuando el origen alcance límites seguros, se aplica degradación controlada, no agotamiento ilimitado de pools SQLx.

## 11. Fallos y degradación

Redis es opcional para la corrección, pero relevante para latencia/capacidad. Se requieren timeouts cortos, circuit breaker, reconexión con backoff+jitter, reintentos acotados, fallback seguro y limitado, escrituras de negocio independientes de Redis, resolución de resultados inciertos en la fuente de verdad y reconstrucción gradual tras failover. El fallo de Redis no provoca pérdida de Outbox ni de eventos de invalidación.

Se documentan procedimientos de failover, rebalanceo, recuperación de slots, rotación de certificados, ACL, caché fría y retorno gradual a operación normal.

## 12. Observabilidad

Conforme a ADR-0015, observar disponibilidad, nodos, failovers, slots, latencia, throughput, errores, timeouts, reconexiones, conexiones, memoria, fragmentación, evictions, hit/miss ratio, expiraciones, regeneraciones, tamaño de entradas, replicación, retraso de invalidaciones, fallback, circuit breakers, stampede y throttling.

No utilizar claves, valores, tenant_id, user_id, event_id ni identificadores únicos como labels. Los logs no incluyen secretos, valores cacheados ni datos personales sensibles.

Las alertas cubren indisponibilidad, slots sin cubrir, memoria crítica, failover anómalo, latencia, errores, evictions, retraso de invalidación y aumento peligroso de fallback a PostgreSQL. Los umbrales se derivan de SLO y pruebas.

## 13. Dimensionamiento y operación

Antes de producción se prueban y documentan shards y réplicas; memoria por nodo y reserva; conexiones y límites de clientes; throughput, latencia y hotspots; TTL por consulta; límites de tamaño y concurrencia; pérdida de primario/réplica/shard; failover, rebalanceo y caché fría; SLO; impacto del fallback sobre PostgreSQL; y rotación de certificados y credenciales.

No se fijan valores universales sin perfiles de tráfico y pruebas representativas. Los valores cacheados no requieren backup como datos de negocio; sí deben preservarse de forma segura la configuración, políticas, certificados y material operativo para reconstruir el servicio.

## 14. Pruebas de aceptación

La implementación debe demostrar aislamiento entre tenants y módulos; compatibilidad Cluster y redirecciones MOVED/ASK; TLS, certificados, ACL y rotación; TTL, jitter y memoria; invalidación durable, duplicados y eventos fuera de orden; prevención de stale refill; single-flight y leases; timeout, circuit breaker y backpressure; consistencia crítica y read-your-writes; pérdida de nodo, failover, rebalanceo y caché fría; observabilidad sin datos sensibles; y carga representativa que proteja PostgreSQL.

Mocks no sustituyen pruebas de integración con Redis Cluster real ni pruebas de failover.

## 15. Runbooks mínimos

Se mantienen procedimientos para nodo primario/shard no disponible, slots sin cubrir, failover, memoria y evictions, certificado vencido o rotación fallida, credencial ACL comprometida, invalidación retrasada, caché fría y fallback excesivo, stampede/clave caliente y reconstrucción del clúster.

Cada runbook identifica señales, impacto, acciones seguras, rollback, verificación y criterios de escalamiento.

## 16. Parámetros que se dimensionan en operación

La decisión arquitectónica está aceptada. Shards y réplicas definitivos, memoria, CPU, throughput, conexiones, timeouts, concurrencia, TTL por consulta, SLO y umbrales de alertas se dimensionan y validan mediante pruebas antes del despliegue correspondiente; no son decisiones arquitectónicas pendientes de aprobación.

## 17. Estado de implementación

ADR-0016 y esta especificación están aprobados como documentación vigente. No se ha desplegado Redis ni se ha creado cliente, adaptador, configuración, clúster, certificados, ACL, dashboards, alertas o pruebas de integración por el hecho de aprobar estos documentos.

Esta especificación no crea crates, dependencias, código, contenedores, servicios, secretos, roles PostgreSQL, tablas, schemas ni migraciones. No modifica archivos SQL ni datos.
