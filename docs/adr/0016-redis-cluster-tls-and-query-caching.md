# ADR-0016: Redis Cluster, TLS y caché distribuida de consultas

- Estado: **Accepted**
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: decisión aprobada explícitamente por el propietario del producto.
- Ámbito: infraestructura transversal de caché para los cuatro procesos y los módulos propietarios de consultas.
- Complementa: ADR-0001, ADR-0003, ADR-0004, ADR-0007, ADR-0008, ADR-0009, ADR-0010, ADR-0013 y ADR-0015.
- Especificación operativa vigente: [Redis Cluster, TLS y operación de caché distribuida](../architecture/redis-cache-operations.md).

## Contexto

Restaurant OS tiene cuatro procesos independientes y módulos con ownership exclusivo de sus datos. Algunas consultas de lectura pueden ser costosas para PostgreSQL y repetirse con mucha frecuencia: agregaciones, listados con filtros, datos de configuración, catálogos, resúmenes y vistas de lectura cuya reconstrucción consume CPU, I/O o conexiones.

Repetir esas consultas sin una política de caché puede aumentar la latencia, saturar los pools SQLx y PostgreSQL, elevar costos y reducir la capacidad disponible para operaciones transaccionales. Una caché local por proceso tampoco ofrece coherencia operativa ni reutilización entre réplicas.

Se necesita una capa de caché distribuida, segura y escalable, que reduzca trabajo repetido sin convertirse en fuente de verdad, sin mezclar la propiedad de datos entre módulos y sin debilitar las garantías de consistencia.

También debe distinguirse alta disponibilidad de particionamiento:

- **Redis Sentinel** supervisa una topología primaria con réplicas y coordina failover; no distribuye el espacio de claves entre shards.
- **Redis Cluster** particiona el espacio de claves entre nodos y proporciona replicación/failover propios del modo cluster.
- Sentinel y Redis Cluster son topologías alternativas; Sentinel no se añade encima de Redis Cluster.

El transporte entre procesos y la mensajería durable ya están definidos por ADR-0007 y ADR-0013. La observabilidad de Redis ya está incluida en ADR-0015. Este ADR concreta el uso de Redis como caché distribuida y sus controles de seguridad.

## Decisión

### 1. Redis como infraestructura transversal de caché

1. Adoptar Redis como caché distribuida compartida por los cuatro procesos, accesible desde los módulos propietarios mediante adaptadores de infraestructura.
2. Redis será una capa de aceleración de lecturas, no una base de datos de negocio ni una fuente de verdad.
3. PostgreSQL y los módulos propietarios conservan la autoridad sobre los datos. Una pérdida completa de Redis debe poder producir una caché fría y más lecturas al origen, pero nunca pérdida de datos de negocio ni corrupción de operaciones.
4. Los datos de caché son reconstruibles y descartables. No se utilizará esta instancia para almacenar como única copia sesiones, pagos, órdenes, inventario, trabajos durables, eventos, locks de negocio ni estados cuya pérdida afecte la corrección.
5. No se habilita por este ADR Redis como broker, cola durable, almacén de sesiones, motor de rate limiting ni mecanismo de coordinación de jobs. Esos usos requieren decisión y alcance propios.

### 2. Topología: Redis Cluster, no Sentinel

1. Adoptar **Redis Cluster** como topología objetivo para permitir particionamiento horizontal de claves, distribución de carga y failover entre nodos.
2. La topología productiva tendrá al menos tres nodos primarios/shards y réplicas para alta disponibilidad. La distribución de primarios y réplicas se hará entre dominios de fallo independientes cuando la infraestructura lo permita.
3. Redis Cluster administrará la asignación de hash slots, detección de nodos y failover. No se desplegará Sentinel sobre esta topología.
4. El crecimiento de capacidad se realizará agregando shards y rebalanceando slots de forma controlada, después de medir memoria, CPU, latencia, throughput, distribución de claves y límites de red.
5. El cliente Redis deberá ser compatible con Cluster: descubrimiento de topología, redirecciones MOVED/ASK, reconexión, actualización de slots, timeouts y reintentos acotados.
6. Las operaciones multi-key deberán respetar las restricciones de hash slots de Redis Cluster. Las claves que necesiten una operación atómica conjunta utilizarán hash tags únicamente cuando exista una razón funcional documentada y sin crear hotspots.
7. No se fijan número máximo de shards, capacidad por nodo, memoria, throughput, tamaño de instancia ni proveedor. Se dimensionarán con pruebas representativas y objetivos de servicio.
8. Redis Sentinel queda como alternativa válida para una futura instalación primaria-réplica no particionada, pero no forma parte de la topología elegida para este sistema mientras se mantenga Redis Cluster.

### 3. TLS y seguridad de transporte

TLS será obligatorio en todas las comunicaciones de Redis, sin excepciones para producción:

- Conexiones de clientes de los cuatro procesos hacia Redis.
- Replicación entre nodos.
- Bus de cluster entre nodos.
- Cualquier endpoint administrativo o de monitorización que admita transporte TLS.

Requisitos:

1. Validar la cadena de confianza y el nombre/SAN del certificado del servidor; queda prohibido desactivar la verificación de certificados en producción.
2. Utilizar TLS 1.2 como mínimo y preferir TLS 1.3 cuando la versión de Redis, bibliotecas cliente y plataforma lo soporten de forma compatible.
3. Utilizar certificados emitidos por una autoridad de confianza administrada; proteger las claves privadas fuera del repositorio y de los artefactos de build.
4. Diseñar rotación y renovación de certificados sin interrupción evitable, con solapamiento de confianza y procedimiento de reversión.
5. Evaluar mTLS para autenticar clientes mediante certificados cuando la plataforma y el modelo operativo lo permitan; en todo caso, TLS no reemplaza autenticación Redis mediante ACL.
6. Redis no tendrá puertos expuestos directamente a Internet. El acceso estará limitado a redes privadas, reglas de firewall/security groups y orígenes autorizados.
7. TLS también protegerá el tráfico del bus de cluster; no basta con cifrar únicamente las conexiones de aplicación.

Las versiones de Redis, bibliotecas cliente, protocolo TLS y autoridades certificadoras se seleccionarán en implementación según soporte vigente y compatibilidad probada. Este ADR no fija números de versión.

### 4. Autenticación, ACL y aislamiento entre módulos

1. Deshabilitar el acceso anónimo y utilizar ACL de Redis con identidades separadas por proceso/módulo o por unidad de confianza justificada.
2. Aplicar privilegio mínimo: cada identidad tendrá solo los comandos requeridos y acceso limitado a los patrones de claves que le pertenecen.
3. Los prefijos de claves identificarán, como mínimo, entorno, módulo propietario y familia/versión de caché. Ejemplo conceptual: `<env>:cache:<module>:<namespace>:v<schema>:<key>`.
4. Los prefijos no sustituyen ACL. Las reglas ACL deben limitar comandos y patrones de claves; no se considerará el número de base de datos Redis como frontera de seguridad.
5. Cada módulo solo administra sus entradas de caché. Un módulo no invalida ni lee arbitrariamente claves internas de otro módulo.
6. Los BFF no serán propietarios de cachés de dominio ni accederán directamente a claves privadas de módulos. Las consultas se resuelven mediante contratos y puertos del módulo propietario; una caché de borde HTTP futura requerirá diseño específico.
7. Las credenciales se gestionarán como secretos, con rotación, mínimo privilegio y sin incluirlas en Git, logs, trazas, métricas o documentación operativa pública.
8. Los entornos tendrán aislamiento de credenciales y claves. No se compartirán namespaces entre desarrollo, pruebas y producción.

### 5. Política de caché para consultas pesadas y frecuentes

Se utilizará principalmente el patrón **cache-aside**:

1. El módulo propietario recibe la consulta y construye una clave determinista con los parámetros normalizados.
2. Consulta Redis.
3. Ante hit, valida que el resultado corresponda al scope de tenant, permisos y versión esperados y devuelve el resultado.
4. Ante miss, ejecuta la consulta contra su fuente de verdad, construye el resultado y lo guarda en Redis con TTL.
5. Devuelve el resultado. La escritura de caché nunca forma parte de la transacción de negocio ni puede hacer fallar un commit de PostgreSQL.

Se cachearán las consultas que cumplan criterios verificables:

- costo significativo medido en CPU, I/O, latencia o conexiones;
- frecuencia/repetición suficiente para justificar almacenamiento;
- resultado reutilizable entre solicitudes dentro de un scope de autorización definido;
- tolerancia explícita a la antigüedad máxima que introduce la política de caché;
- estrategia definida de expiración e invalidación;
- tamaño y cardinalidad compatibles con el presupuesto de memoria.

La política aplica a todas las consultas que cumplan esos criterios, no indiscriminadamente a cada SELECT. No se habilitará caché global automática de consultas SQL ni se almacenarán resultados sin propietario, TTL, versión y estrategia de invalidación.

Cada consulta cacheable tendrá una ficha o configuración declarativa documentada con: módulo propietario, nombre estable de operación, parámetros incluidos en la clave, scope de tenant/usuario/permiso, TTL, tolerancia a staleness, eventos que invalidan, límite de tamaño, sensibilidad de datos y métricas de hit/miss.

### 6. Claves, aislamiento de tenant y privacidad

1. Las claves serán deterministas, acotadas y versionadas. Incluirán entorno, módulo, operación, versión del esquema de resultado y contexto de aislamiento necesario.
2. Los parámetros de consulta se normalizarán y se representarán mediante un hash estable cuando incluirlos directamente genere claves extensas o revele información.
3. Una entrada de datos de tenant nunca podrá ser reutilizada por otro tenant. El tenant scope formará parte de la clave cuando corresponda y será validado también en el flujo de lectura.
4. Si el resultado depende de usuario, rol, permisos, sucursal, ubicación, idioma, moneda, filtros o configuración contextual, ese contexto debe formar parte de la clave o la consulta no será compartible.
5. No se cachearán decisiones de autorización como sustituto de la comprobación vigente de permisos. Los cambios de permisos, membresías o estado de cuenta deberán aplicarse inmediatamente por la ruta de autorización, sin depender de una entrada cacheada antigua.
6. No almacenar secretos, credenciales, tokens, cookies, datos completos de pago ni payloads personales sensibles en la caché.
7. Los datos personales o de negocio sensibles se excluirán por defecto. Una excepción requiere clasificación, minimización, aislamiento, TTL y controles de acceso explícitos.
8. Las claves y valores no se registrarán completos en logs ni métricas.

### 7. TTL, expiración y política de memoria

1. Toda entrada tendrá TTL finito. No se admitirán entradas de caché de dominio sin expiración.
2. El TTL se definirá por operación según frecuencia de cambio, costo de reconstrucción, tolerancia de consistencia y criticidad; no existirá un TTL universal.
3. Añadir jitter aleatorio acotado al TTL para evitar expiraciones sincronizadas de grandes grupos de claves.
4. Los valores grandes tendrán límites de tamaño y no podrán consumir memoria sin presupuesto.
5. La política de expulsión se configurará para un workload de caché con expiración; se propone `allkeys-lfu` como punto de partida, sujeto a pruebas de carga y análisis de patrones reales.
6. Establecer presupuesto de memoria, umbrales de alerta y comportamiento ante presión de memoria. No permitir crecimiento ilimitado ni confiar en eviction como mecanismo normal de invalidación.
7. Las entradas deben ser reconstruibles tras eviction, failover, reinicio o vaciado completo.

### 8. Invalidación y coherencia con PostgreSQL

La invalidación será responsabilidad del módulo propietario y se coordinará con el commit de negocio:

1. El cambio de negocio y la intención durable de publicar el evento de invalidación se registran en la misma transacción local mediante Transactional Outbox, de acuerdo con ADR-0003 y ADR-0013.
2. La invalidación/reconstrucción distribuida se entrega mediante NATS JetStream cuando requiera durabilidad y recuperación. NATS Core no será el único mecanismo para invalidaciones que no pueden perderse.
3. Los consumidores serán idempotentes y procesarán redeliveries. Un fallo temporal de Redis no debe perder definitivamente la intención de invalidar.
4. Cada evento indicará el módulo/aggregate o scope afectado y la versión/secuencia necesaria para descartar eventos antiguos o fuera de orden.
5. La estrategia preferida será invalidación por claves/tags acotados o incremento de generación/versionado de namespace; evitar escanear y borrar indiscriminadamente todo Redis.
6. Una carga de caché iniciada antes de una invalidación no podrá reintroducir silenciosamente un valor obsoleto después de ella. Se utilizará versionado/generación o una operación atómica equivalente que verifique que la generación no cambió durante la carga.
7. Los cambios confirmados en PostgreSQL no dependerán de que Redis esté disponible para completar la transacción.
8. Las operaciones que requieran lectura estrictamente actualizada —por ejemplo, autorización, saldos, pagos, caja, disponibilidad de inventario o transiciones críticas— consultarán la fuente autoritativa o una ruta de consistencia fuerte explícitamente definida; no dependerán de una caché potencialmente obsoleta.
9. Se permitirá stale-while-revalidate únicamente en lecturas no críticas cuya tolerancia a datos antiguos esté documentada y acotada. No será el comportamiento predeterminado para información financiera, permisos o disponibilidad transaccional.
10. El uso de caché no habilita joins, FKs, vistas ni consultas directas entre schemas. Cada módulo cachea resultados que obtiene a través de su propio ownership y contratos permitidos.

### 9. Protección contra cache stampede y avalanchas

1. Implementar coalescencia de solicitudes concurrentes por clave (single-flight) dentro del proceso cuando sea posible.
2. Para coordinación entre réplicas podrá utilizarse un lease breve de regeneración de caché, con token aleatorio, vencimiento y liberación segura.
3. Un lease de caché solo reduce regeneraciones duplicadas; no es mecanismo de exclusión para operaciones de negocio ni reemplaza advisory locks/leases definidos en ADR-0003.
4. Si el lease expira o Redis falla, la corrección del negocio no dependerá de él. Se aplicarán límites de concurrencia, backoff con jitter y protección de carga sobre PostgreSQL.
5. Para claves muy calientes se evaluarán TTL jitter, stale-while-revalidate cuando sea seguro y regeneración anticipada controlada.
6. Las regeneraciones masivas o calentamientos de caché tendrán lotes, concurrencia y presupuesto limitados. No ejecutar cache warming sin medir el efecto sobre PostgreSQL.

### 10. Fallos, degradación y recuperación

1. Redis es una dependencia opcional para la corrección de negocio, pero importante para latencia y capacidad.
2. Ante timeout, desconexión, failover o error de Redis, la aplicación aplicará timeout corto, circuit breaker y fallback al origen cuando sea seguro.
3. El fallback tendrá concurrencia limitada y backpressure para impedir que una caída de Redis convierta una carga cacheada en una avalancha sobre PostgreSQL.
4. Si se alcanza el límite seguro del origen, se aplicará degradación controlada: colas de espera limitadas, respuestas de indisponibilidad/reintento apropiadas o reducción de funcionalidades no críticas; no se agotarán los pools SQLx.
5. Las escrituras de negocio continuarán sin esperar una escritura de caché. La caché podrá poblarse después del commit.
6. Tras failover o reinicio, aceptar una caché fría y reconstruir gradualmente. No lanzar una regeneración masiva simultánea.
7. No reintentar indefinidamente. Usar timeouts, backoff, jitter y límites por operación.
8. Los resultados de escritura inciertos se resolverán consultando la fuente de verdad; no se inferirán a partir del contenido de Redis.

### 11. Observabilidad y alertas

Conforme a ADR-0015, Redis y los clientes deberán exponer, como mínimo:

- disponibilidad, failovers, cambios de topología y estado de nodos;
- latencia y errores por familias de comandos;
- conexiones, reconexiones, timeouts y saturación de clientes;
- memoria usada, fragmentación, presión de memoria y evictions;
- hit ratio, miss ratio, expiraciones y tasa de regeneración;
- throughput, ancho de banda, CPU y distribución de carga por shard;
- replicación, retraso, estado de slots y errores del cluster;
- fallos de invalidación, retraso entre commit/evento/invalidation y generaciones obsoletas;
- fallback al origen, consultas regeneradas, cache stampedes y throttling.

Las métricas usarán etiquetas acotadas (proceso, módulo, operación normalizada, entorno y resultado). No usar claves, valores, tenant_id, user_id, event_id ni otros identificadores de alta cardinalidad como labels.

Las alertas cubrirán nodos no disponibles, quorum/failover, slots sin cubrir, memoria crítica, evictions anómalas, latencia elevada, hit ratio degradado, backlog de invalidaciones y aumento peligroso de fallback hacia PostgreSQL. Los umbrales se definirán mediante SLO y pruebas representativas.

### 12. Capacidad, límites y operación

Antes del despliegue productivo se definirán y probarán:

- memoria por shard y reserva operativa;
- número de shards y réplicas;
- conexiones por proceso/módulo y límites de clientes;
- timeouts, reintentos, circuit breakers y límites de concurrencia;
- tamaño máximo de claves/valores y lotes;
- TTL por familia de consultas;
- presupuesto de memoria por módulo y política de expulsión;
- distribución entre dominios de fallo;
- objetivos de disponibilidad, latencia, RPO/RTO de la infraestructura y procedimiento de recuperación;
- procedimiento de backup/restore de configuración y material operativo, sin tratar la caché como dato durable.

El dimensionamiento se basará en perfiles de tráfico, pruebas de carga, distribución de claves, crecimiento esperado y comportamiento durante pérdida de un nodo. No se fijan números universales sin mediciones.

## Alternativas consideradas

### Redis Sentinel con primario y réplicas

No elegido como topología objetivo. Aporta supervisión y failover de un conjunto primario-réplicas, pero no particiona el espacio de claves ni distribuye la carga de memoria y comandos entre shards. Podría ser adecuado para una instalación no fragmentada de menor escala, pero no satisface el objetivo de escalabilidad horizontal solicitado.

### Redis Cluster con Sentinel adicional

Rechazado. Redis Cluster incorpora su propio descubrimiento, particionamiento y failover. Sentinel no se añade para administrar el mismo cluster y mezclar ambas topologías incrementaría complejidad sin aportar la función de sharding que Sentinel no ofrece.

### Redis único sin alta disponibilidad

Rechazado para el objetivo de producción distribuida: introduce un punto único de fallo y límites de escalabilidad vertical.

### Caché local en cada proceso

No elegida como solución principal. Puede evaluarse como optimización L1 acotada en el futuro, pero no sustituye la caché distribuida y requiere una estrategia adicional de invalidación entre réplicas.

### Consultas repetidas directamente en PostgreSQL

No se adopta como estrategia general para consultas costosas y de alta repetición cuando la medición demuestra que la caché reduce carga y latencia. PostgreSQL continúa siendo la fuente autoritativa y destino de fallback.

## Consecuencias

### Positivas

- Reduce lecturas repetidas y presión sobre PostgreSQL y los pools SQLx.
- Permite distribuir memoria y carga mediante shards.
- Mantiene alta disponibilidad mediante réplicas y failover de Redis Cluster.
- Proporciona aislamiento por módulo/tenant, seguridad TLS y privilegio mínimo.
- Evita acoplar la corrección de negocio a la disponibilidad de Redis.
- Define invalidación durable y controlada a partir de cambios confirmados.

### Costos y riesgos

- Redis Cluster exige clientes compatibles, operación de slots, rebalanceo y pruebas de failover.
- La invalidación distribuida y el versionado de claves requieren disciplina por módulo.
- Un TTL incorrecto o una invalidación perdida puede exponer datos obsoletos.
- Una caché fría o un failover puede aumentar temporalmente la carga sobre PostgreSQL.
- Redis añade infraestructura, memoria, monitoreo, certificados, credenciales y costos.
- El uso inadecuado de claves calientes puede producir hotspots aunque exista sharding.

## Plan de adopción

La implementación deberá:

1. Seleccionar versión de Redis y cliente compatible con Cluster, TLS y ACL, con soporte vigente.
2. Diseñar topología de nodos, réplicas, dominios de fallo, red privada, certificados y rotación.
3. Definir identidades ACL y patrones de claves por módulo/proceso.
4. Diseñar el adaptador técnico de Redis sin mover ownership de consultas ni reglas de negocio a los BFF.
5. Inventariar y medir consultas candidatas; asignar TTL, scope, invalidación y presupuesto por consulta.
6. Integrar invalidación durable con Outbox/JetStream e idempotencia según ADR-0003/0013.
7. Implementar protección de stampede, circuit breaker, fallback y límites de carga.
8. Integrar métricas, logs, trazas y alertas conforme a ADR-0015.
9. Ejecutar pruebas de carga, aislamiento de tenant, expiración, invalidación concurrente, caída de Redis, failover, pérdida de shard, recuperación y caché fría.
10. Verificar que las operaciones críticas conservan consistencia y que Redis no se convierte en fuente de verdad.

## Estado de implementación

Este ADR está **Accepted**. La decisión arquitectónica está aprobada y vigente; eso no significa que Redis esté desplegado o configurado, ni que exista un cliente, adaptador, caché, TLS, ACL, cluster, Sentinel, invalidación o instrumentación implementados.

No crea crates, dependencias, código, contenedores, servicios, certificados, secretos, dashboards, roles ni configuración. No modifica SQL, migraciones, schemas, tablas ni datos de PostgreSQL.
