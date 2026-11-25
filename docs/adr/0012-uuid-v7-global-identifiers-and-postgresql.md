# ADR-0012: UUID versión 7 como identificador técnico global y PostgreSQL estable actual

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: decisión original aprobada por el propietario del producto; ampliación de PostgreSQL HA, clúster y réplicas de lectura solicitada y aprobada explícitamente el 2026-11-24.
- Complementa: ADR-0001, ADR-0007, ADR-0008 y ADR-0009.
- Ámbito: todos los módulos y procesos de Restaurant OS.

## Contexto

El sistema necesita identificadores técnicos que funcionen entre procesos y módulos, no dependan de una secuencia central y mantengan buenas propiedades de localidad al insertarse en índices PostgreSQL. El proyecto también necesita una política uniforme para evitar que cada módulo elija versiones UUID o estrategias incompatibles.

UUIDv4 ofrece generación aleatoria, pero sus valores no siguen el orden temporal. Las inserciones en índices B-tree pueden distribuirse por distintas páginas y producir peor localidad de inserción. UUIDv7 incorpora una marca temporal Unix en milisegundos en sus bits más significativos, por lo que los valores generados cronológicamente tienden a agruparse en el orden del índice.

UUIDv7 tiene una implicación de privacidad: la marca temporal permite estimar cuándo se generó un identificador. Un UUID, independientemente de su versión, tampoco constituye una credencial ni una prueba de autorización.

A fecha de aceptación de esta decisión, PostgreSQL 19.0 es la versión estable más reciente, publicada el 19 de noviembre de 2026. PostgreSQL incorpora generación nativa UUIDv7 mediante `uuidv7()` desde PostgreSQL 18; la versión 19 documenta esta función y el tipo `uuid`.

## Decisión

### 1. Política global de identificadores técnicos

1. UUID versión 7 conforme a RFC 9562 será el formato único de identificador técnico para las entidades y recursos del sistema.
2. La política comprende los cuatro procesos, los 20 módulos, claves primarias, claves foráneas internas del mismo módulo, referencias entre módulos, identificadores de eventos y demás identificadores técnicos UUID definidos por los contratos.
3. La política se aplica tanto a identificadores nuevos como a los identificadores técnicos existentes: los identificadores heredados deberán converger a UUIDv7 mediante una transición futura planificada. No se mantendrán UUIDv4 como estándar permanente para entidades.
4. También se evaluarán y migrarán los identificadores sustitutos técnicos existentes que hoy utilicen tipos enteros, cuando identifiquen entidades o recursos. La conversión futura debe conservar identidad lógica y todas sus referencias.
5. No se convertirán a UUID los identificadores de negocio cuyo significado sea un código o número humano, fiscal, comercial u operativo: SKU, folios fiscales, números visibles de pedido, códigos de barras, números de factura u otros equivalentes. Esos valores conservan su semántica y reglas propias; no sustituyen al identificador técnico de la entidad.
6. No se adoptarán UUIDv1, UUIDv3, UUIDv4, UUIDv5 ni UUIDv6 como alternativas para nuevos identificadores técnicos. Los UUID históricos de otras versiones solo existirán durante la transición aprobada.

### 2. PostgreSQL como plataforma objetivo

1. PostgreSQL 19.0 será la versión estable objetivo inicial del proyecto a la fecha de esta propuesta.
2. El estándar operativo será utilizar la última versión mayor estable de PostgreSQL oficialmente publicada y aprobada para el proyecto, con sus actualizaciones menores y de seguridad soportadas. La versión objetivo debe revisarse en cada ciclo de actualización; no se fija PostgreSQL 19 como una versión perpetua.
3. La compatibilidad de drivers, SQLx, herramientas, extensiones, backups, replicación y despliegue deberá verificarse antes de cada actualización mayor.
4. PostgreSQL conserva el tipo nativo `uuid`; la política de versión se refiere al algoritmo con el que se generan los valores, no a un tipo de columna diferente.
5. PostgreSQL 18 y posteriores proporcionan `uuidv7()`. En PostgreSQL 19 esta función es una capacidad nativa disponible. Su presencia no autoriza a modificar migraciones ni archivos SQL en este cambio documental.

### 2.1 Clúster PostgreSQL, alta disponibilidad y réplicas de lectura

1. PostgreSQL se desplegará en producción como un clúster de alta disponibilidad **single-writer**: un único primario acepta escrituras y uno o más nodos standby reciben WAL mediante replicación física streaming. No se adopta multi-primary.
2. La topología objetivo contempla al menos tres nodos de datos cuando la infraestructura lo permita: un primario y dos standbys distribuidos entre dominios de fallo independientes. Los standbys podrán configurarse como candidatos de failover y como hot standby de solo lectura. El número final de nodos y su distribución se dimensionarán según capacidad, latencia entre zonas, RPO/RTO y pruebas de recuperación.
3. La replicación física mantiene una copia del clúster PostgreSQL completo; no particiona schemas o tablas por módulo ni constituye sharding. Cada réplica contiene los datos de todos los módulos, pero los roles y permisos de cada módulo siguen limitando qué objetos puede consultar. La replicación nunca concede permisos adicionales.
4. Se utilizará streaming replication con política de durabilidad explícita. El diseño operativo deberá incluir al menos un standby síncrono para los commits cuya garantía de durabilidad lo requiera, y podrá disponer de standbys asíncronos para escalar lecturas y recuperación geográfica. La política de quorum y el nivel de confirmación síncrona se configurarán de forma que las garantías declaradas de RPO no dependan de una degradación silenciosa. La pérdida del standby síncrono debe tener un comportamiento operativo explícito, monitorizado y documentado.
5. La replicación asíncrona puede presentar retraso y perder transacciones todavía no recibidas/aplicadas si se promueve una réplica atrasada. Por tanto, una réplica asíncrona no es fuente autoritativa para decisiones críticas ni garantiza cero pérdida de datos. La selección de candidato a promoción considerará WAL recibido y aplicado, estado de salud y RPO admisible.
6. El failover será coordinado por un gestor de alta disponibilidad con mecanismo de consenso/quórum y **fencing** que impida al primario anterior aceptar escrituras después de la promoción. No se confiará únicamente en DNS, health checks aislados ni decisiones independientes de cada aplicación. La tecnología concreta de gestor, proxy, consenso y fencing se definirá en la arquitectura de despliegue, sin imponer aquí un proveedor.
7. Se expondrán endpoints estables y diferenciados para escritura y lectura. El endpoint de escritura dirigirá exclusivamente al primario confirmado por el gestor de HA. El endpoint de lectura incluirá solo réplicas saludables, en hot standby y dentro de los límites operativos de lag. Tras failover, las conexiones obsoletas deberán descartarse y los pools deberán reconectarse al destino correcto.
8. El enrutamiento de lectura será explícito y consciente de consistencia:
   - Escrituras, transacciones que modifican estado y lecturas que requieren consistencia inmediata se ejecutan en el primario.
   - Consultas costosas, frecuentes, analíticas o de reporting podrán ejecutarse en réplicas si el caso de uso tolera el retraso y declara su requisito de frescura.
   - Autorización, identidad/estado de sesión autoritativo, pagos, saldos, caja, disponibilidad de inventario, idempotencia, estado de workflows y cualquier lectura que determine una escritura posterior permanecerán en el primario, salvo una garantía de consistencia específica y demostrada.
9. Se preservará **read-your-writes**: después de confirmar una escritura, las lecturas dependientes de ella usarán el primario durante el alcance de consistencia requerido. Una lectura podrá enviarse a réplica cuando se haya verificado que esta aplicó al menos el LSN requerido o cuando el caso de uso acepte explícitamente staleness. El simple balanceo entre réplicas no garantiza consistencia.
10. Una transacción completa permanecerá en un único nodo. No se dividirán transacciones entre primario y réplica ni se enviarán escrituras a hot standby. Los conflictos de recuperación, cancelaciones de consultas largas y retraso de replay deberán tratarse según la criticidad del workload.
11. Cada módulo conserva su schema, rol, permisos, migraciones e historial SQLx independientes. DDL y migraciones se ejecutarán de forma controlada contra el primario, una sola vez por módulo/versión; nunca se ejecutarán migraciones de aplicación directamente en cada réplica.
12. El clúster no sustituye backups. Se mantendrán backups base y archivado continuo de WAL para recuperación PITR, almacenados fuera del dominio de fallo del clúster, protegidos contra borrado/cifrado malicioso y cifrados en tránsito y reposo. Se probarán restauraciones completas y recuperación a punto en el tiempo. Una réplica que recibe borrados o corrupción lógica del primario no es un backup independiente.
13. Replication slots, retención de WAL y almacenamiento tendrán límites, alertas y runbooks para impedir que una réplica desconectada retenga WAL indefinidamente y agote el disco del primario. Si una réplica no puede recuperar el WAL necesario, se reconstruirá desde una base consistente.
14. Las conexiones de aplicación, administración y replicación utilizarán TLS con validación de certificados y nombres de servidor. Las identidades de replicación serán dedicadas y de privilegio mínimo. El tráfico de base de datos permanecerá en redes privadas; secretos y certificados tendrán rotación controlada. El cifrado en reposo se habilitará en el almacenamiento de producción.
15. Conforme a ADR-0015, se observarán por nodo y endpoint: rol, salud, conexiones, latencia, locks, deadlocks, WAL generado/archivado/recibido, lag de recepción y replay, replication slots, WAL retenido, conflictos de hot standby, failovers, duración de promoción, errores de conexión, capacidad, backups y pruebas de restauración.
16. El enrutamiento de consultas a réplicas debe integrarse con los pools SQLx por módulo definidos en ADR-0010. Se conservarán identidades runtime y aislamiento de permisos; el pool de lectura nunca usará una credencial más privilegiada que el pool de escritura.
17. RPO, RTO, umbrales de lag, número definitivo de réplicas, quorum, retención, capacidad, regiones, límites de consulta y tecnología de failover son parámetros operativos que se dimensionarán y validarán mediante pruebas antes de producción. No se fijan valores universales en este ADR.

### 3. Generación y orden

1. Todo generador que produzca identificadores técnicos deberá generar UUIDv7 conforme a RFC 9562.
2. PostgreSQL 19 ofrece `uuidv7()` como generador nativo. La selección de la autoridad de generación para cada flujo (base de datos o aplicación) deberá definirse en el diseño de implementación del módulo y evitar que una misma entidad tenga generadores incompatibles.
3. La generación distribuida debe considerar relojes, concurrencia, reinicios y generación en distintas instancias. No se asumirá que el orden lexicográfico garantiza un orden global estricto entre todos los nodos.
4. UUIDv7 facilita la localidad de inserción en índices B-tree frente a UUIDv4 aleatorios, pero no garantiza que todo el índice permanezca en memoria ni que todas las inserciones se realicen literalmente al final de una única página.
5. No se utilizará el UUID como sustituto de `created_at`, secuencias de negocio, orden de transacciones, causalidad ni relojes de eventos. Cuando el orden sea un requisito funcional, se modelará explícitamente.

### 4. Exposición y privacidad

1. UUIDv7 no es secreto, contraseña, token de sesión ni mecanismo de autorización.
2. Se puede exponer un UUIDv7 en APIs, URLs o contratos cuando el recurso requiera una referencia estable, considerando que permite inferir aproximadamente el instante de generación.
3. Toda operación sobre un recurso debe validar autenticación, autorización, tenant y alcance del recurso en el módulo propietario. Conocer o adivinar un identificador nunca concede acceso.
4. No se cifrarán sistemáticamente los UUIDv7 para mostrarlos. Codificar un UUID en hexadecimal, Base64 u otra representación reversible no es cifrado.
5. Cuando un caso de uso necesite ocultar el identificador interno o desacoplar una referencia externa, podrá utilizar un identificador público opaco separado, aleatorio y criptográficamente seguro. Su ciclo de vida, unicidad, revocación y resolución pertenecerán al módulo propietario. No reemplazará al UUIDv7 interno.
6. Las referencias opacas no se crearán por defecto para todos los recursos; requieren una necesidad de privacidad, integración o estabilidad externa documentada.
7. Los logs, métricas, trazas y eventos no deben exponer información sensible innecesaria. El timestamp contenido en UUIDv7 debe considerarse metadato temporal potencialmente observable.

### 5. Migración de identificadores existentes

La convergencia de identificadores actuales a UUIDv7 será una iniciativa futura, separada y planificada por módulos. Antes de modificar datos o esquemas deberá:

- inventariar claves primarias, foráneas, índices, constraints, vistas, triggers y referencias de cada módulo;
- localizar referencias almacenadas fuera de las tablas relacionales: JSON/JSONB, Outbox, Inbox, auditoría, eventos, cachés, archivos, integraciones y sistemas externos;
- definir un mapeo inequívoco entre cada identificador anterior y su UUIDv7 nuevo;
- preservar relaciones, unicidad, ownership, tenant, historial, idempotencia, contratos HTTP/gRPC, eventos y consumidores;
- diseñar compatibilidad temporal y estrategia de despliegue/rollback entre versiones coexistentes;
- planificar backfill, validación de integridad, cambio de lecturas/escrituras y retirada de claves antiguas;
- coordinar cada módulo bajo su ownership y sus migraciones e historial SQLx independientes;
- definir tratamiento de referencias externas ya emitidas y consumidores que no puedan actualizarse simultáneamente.

No se autoriza una conversión improvisada en sitio, una sustitución parcial de claves ni la reescritura de migraciones históricas. Cada migración concreta requerirá su propio plan, revisión y autorización expresa.

### 6. Alcance de esta decisión documental

Este ADR no modifica columnas, defaults, constraints, índices, datos, contratos ejecutables, archivos SQL ni migraciones. Tampoco instala dependencias, cambia código o ejecuta operaciones en PostgreSQL. La implementación y la transición de datos quedan pendientes de tareas futuras autorizadas.

## Consecuencias

### Alta disponibilidad, escalabilidad de lectura y operación

- Un primario escritor mantiene una autoridad única para modificar datos y evita conflictos de escritura multi-primary.
- Standbys físicos permiten failover y, en modo hot standby, capacidad de lectura adicional.
- El routing por consistencia evita enviar decisiones críticas a réplicas potencialmente atrasadas.
- La replicación física refleja el clúster completo y no cambia el ownership lógico ni los permisos por módulo.
- Backups base más WAL archivado permiten PITR; las réplicas por sí solas no protegen frente a errores lógicos propagados.
- El clúster, failover, fencing, réplicas, WAL y routing aumentan el costo y la complejidad operativa; requieren pruebas, alertas y runbooks.
- La replicación síncrona mejora la durabilidad de commits confirmados según su configuración, pero añade latencia y puede afectar disponibilidad cuando no hay standby elegible.
- La replicación asíncrona reduce el costo de confirmación, pero permite lecturas obsoletas y una ventana de pérdida de datos en ciertos failovers.

### Beneficios esperados

- Política uniforme de identificadores técnicos entre módulos y procesos.
- Mejor localidad temporal de inserción en índices B-tree frente a UUIDv4 aleatorios.
- Generación distribuida sin depender de una secuencia global central.
- Compatibilidad con el tipo UUID nativo de PostgreSQL y generación UUIDv7 nativa en PostgreSQL 19.
- Contratos más consistentes al migrar identificadores heredados a una sola versión.

### Costos y riesgos

- UUIDv7 expone una aproximación del momento de generación.
- La transición de identificadores existentes puede ser compleja por referencias internas, eventos, integraciones y datos históricos.
- La generación en múltiples instancias requiere considerar relojes y concurrencia.
- La migración puede afectar contratos y consumidores externos; requiere compatibilidad temporal y pruebas de integridad.
- UUID no elimina la necesidad de índices, caché, autorización ni aislamiento multi-tenant.

## Alternativas consideradas

- **Mantener UUIDv4 para los identificadores existentes y usar UUIDv7 solo para los nuevos:** rechazado porque perpetúa dos estándares y no satisface la decisión de convergencia global.
- **Usar UUIDv4 para ocultar el momento de creación:** rechazado como estándar de identificadores técnicos; la privacidad de referencias externas se resuelve con tokens opacos separados cuando exista necesidad.
- **Usar enteros secuenciales como identificadores técnicos globales:** rechazado por acoplar generación a secuencias y facilitar inferencia de volumen/orden.
- **Cifrar todos los UUID antes de exponerlos:** rechazado porque agrega complejidad de claves y representación sin sustituir autorización; se prefieren referencias opacas independientes cuando corresponda.
- **Un único servidor PostgreSQL sin standby:** rechazado como topología de producción por mantener un punto único de fallo.
- **Multi-primary:** rechazado porque introduce conflictos de escritura y complejidad de consistencia que no se justifican en la arquitectura actual.
- **Enviar todas las lecturas a réplicas asíncronas:** rechazado porque puede devolver datos obsoletos y romper read-your-writes o decisiones críticas.
- **Usar réplicas como sustituto de backups:** rechazado porque los errores lógicos y eliminaciones también se replican.
- **Sharding como parte de esta decisión:** no adoptado; la replicación física no distribuye automáticamente datos entre nodos.

## Referencias

- [RFC 9562 — Universally Unique IDentifiers (UUIDs)](https://www.rfc-editor.org/rfc/rfc9562.html)
- [PostgreSQL 19 — UUID Type](https://www.postgresql.org/docs/19/datatype-uuid.html)
- [PostgreSQL 19 — UUID Functions](https://www.postgresql.org/docs/19/functions-uuid.html)
- [PostgreSQL 19 — Release 19](https://www.postgresql.org/docs/19/release-19.html)
- [PostgreSQL 19 — High Availability, Load Balancing, and Replication](https://www.postgresql.org/docs/19/high-availability.html)
- [PostgreSQL 19 — Backup and Restore](https://www.postgresql.org/docs/19/backup.html)
- [PostgreSQL 19 — SSL Support](https://www.postgresql.org/docs/19/ssl-tcp.html)

## Estado de implementación

**Decisión documental aceptada.** No se han modificado archivos SQL ni migraciones, no se han alterado datos, no se han añadido dependencias y no se ha implementado generación UUIDv7 en código.
