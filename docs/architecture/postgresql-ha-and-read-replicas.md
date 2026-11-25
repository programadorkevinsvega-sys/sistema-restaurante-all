# PostgreSQL: clúster de alta disponibilidad y réplicas de lectura

**Estado:** especificación técnica aprobada y vigente conforme a ADR-0012 Accepted, complementada por ADR-0010 Accepted y ADR-0015 Accepted.  
**Ámbito:** Admin Platform Backend y Public Backend; todos los módulos propietarios de persistencia PostgreSQL. Los BFF no acceden directamente a PostgreSQL de negocio.  
**Versión objetivo:** PostgreSQL 19.0 como versión estable objetivo inicial, conforme a la política de actualización aceptada.  
**Naturaleza:** especificación documental; no implica despliegue ni implementación.

## 1. Objetivo y principios

Esta especificación desarrolla la decisión de operar PostgreSQL en un clúster de alta disponibilidad y utilizar réplicas de lectura para escalar consultas elegibles.

- PostgreSQL sigue siendo la fuente de verdad transaccional.
- Un único primario acepta escrituras.
- Standbys físicos mantienen copias mediante WAL.
- Las réplicas son destinos de solo lectura, nunca autoridad para decisiones críticas que exijan consistencia inmediata.
- El routing depende de consistencia y frescura requeridas, no del verbo SQL aislado.
- Cada módulo conserva schema, rol, migraciones e historial SQLx propios.
- Los BFF consumen contratos gRPC y no reciben credenciales PostgreSQL.
- Alta disponibilidad no sustituye backups ni recuperación PITR.
- Redis, conforme a ADR-0016, sigue siendo caché y no reemplaza PostgreSQL.

## 2. Topología lógica

La topología objetivo es PostgreSQL HA single-writer con replicación física streaming.

```text
                 Gestor HA / consenso / fencing
                              |
                     Endpoint de escritura
                              |
                       PostgreSQL Primary
                         /           \
                WAL streaming       WAL streaming
                    /                   \
          Standby síncrono       Standby(s) asíncronos
             / hot standby          / hot standby
                    \                   /
                     Endpoint de lectura
                              |
                 Pools de lectura por módulo
```

El diagrama representa responsabilidades lógicas, no productos ni despliegues ya existentes.

### 2.1 Nodos y dominios de fallo

- Objetivo de producción: primario más al menos dos standbys cuando la infraestructura y el presupuesto lo permitan.
- Distribuir nodos entre dominios de fallo independientes; evitar que primario y standbys dependan de la misma máquina, zona o almacenamiento.
- Al menos un standby será candidato de failover. Los nodos que atiendan consultas operarán en hot standby.
- Los standbys son copias físicas del clúster completo; no son shards por módulo ni bases independientes para repartir ownership.
- El número definitivo de nodos, zonas y capacidad se dimensiona con carga, latencia, RPO/RTO y pruebas.

### 2.2 Primario único, gestor HA y fencing

- Solo el primario vigente acepta escrituras.
- El gestor HA determina salud, elegibilidad, promoción y publicación de endpoints.
- Antes de habilitar escrituras en un nuevo primario debe impedirse que el antiguo siga aceptándolas (fencing).
- DNS o un health check por sí solos no son consenso ni evitan split-brain.
- Las aplicaciones no promueven nodos ni deciden independientemente cuál es el primario.
- La tecnología concreta de HA, proxy, consenso y fencing se seleccionará en el diseño de despliegue, sin imponer proveedor.

### 2.3 Replicación síncrona y asíncrona

- Streaming replication transporta WAL desde el primario a standbys.
- La política de durabilidad define qué commits esperan confirmación síncrona y qué standbys forman el quorum.
- Para commits cuya garantía lo requiera, el diseño operativo tendrá al menos un standby síncrono elegible. La indisponibilidad de este standby tendrá comportamiento explícito y monitorizado; no se rebajará silenciosamente la garantía de durabilidad.
- Standbys asíncronos permiten añadir destinos de lectura y recuperación con menor costo de confirmación, pero pueden quedar atrasados.
- La promoción de una réplica asíncrona puede perder transacciones que el primario confirmó pero la réplica aún no recibió. Su uso exige RPO explícito.
- No se anunciará cero pérdida de datos sin que configuración y pruebas demuestren la garantía para el escenario concreto.

## 3. Endpoints y enrutamiento

Deben existir endpoints lógicos estables separados:

| Endpoint | Destino | Uso |
|---|---|---|
| Escritura | Primario vigente | Transacciones, escrituras y lecturas críticas |
| Lectura | Réplicas hot standby saludables | Consultas de solo lectura con staleness permitido |
| Administración | Endpoint restringido | Mantenimiento y tareas privilegiadas |

Los endpoints pueden implementarse mediante proxy o servicio de descubrimiento compatible con el gestor HA. El cliente no debe fijar IPs individuales.

### 3.1 Catálogo de consultas elegibles

Cada operación candidata a réplica debe registrar módulo propietario, operación, propósito, parámetros/scope tenant, consistencia requerida, staleness máxima, dependencia de escrituras previas, sensibilidad, timeout, concurrencia, tamaño de resultado, métricas y fallback.

**Primario obligatorio:**
- escrituras, comandos y transacciones de negocio;
- autorización, permisos e identidad/estado de sesión autoritativo;
- pagos, cobros, saldos, caja y conciliación;
- disponibilidad de inventario usada para aceptar una operación;
- idempotencia, deduplicación y decisiones de workflow;
- lecturas que determinan inmediatamente una escritura posterior;
- lecturas posteriores a una escritura cuando deban reflejarla;
- cualquier operación que dependa de la última versión confirmada.

**Réplica elegible:**
- reporting y analítica;
- dashboards y agregaciones no críticas;
- listados, búsquedas y consultas costosas/frecuentes que toleren retraso;
- exploración histórica con frescura declarada.

La palabra SELECT no convierte automáticamente una consulta en elegible. La clasificación depende de la semántica del negocio.

### 3.2 Read-your-writes y consistencia

- Después de una escritura confirmada, las lecturas dependientes permanecen en el primario durante el alcance de consistencia requerido.
- Una operación puede leer desde réplica cuando se confirme que esta aplicó al menos el LSN requerido o cuando el caso de uso permita explícitamente retraso.
- Puede utilizarse un token de consistencia basado en LSN para esperar a que una réplica alcance una escritura anterior.
- Si no se verifica la frescura, se lee desde el primario o se devuelve un resultado controlado; nunca se presenta una lectura obsoleta como fuerte.
- No se infiere causalidad por UUIDv7, relojes de aplicación o trace_id.
- No se mezclan nodos dentro de una misma transacción.

### 3.3 Lag y conflictos de recuperación

- El endpoint de lectura excluye réplicas no saludables o que excedan el lag permitido para el workload.
- El routing considera lag de recepción y de replay/aplicación.
- Consultas largas pueden entrar en conflicto con la aplicación de WAL y ser canceladas. Cada workload tendrá límites y manejo de cancelación.
- No se desactivan indiscriminadamente los mecanismos de recuperación para conservar consultas largas.
- Si ninguna réplica cumple la frescura requerida, el fallback al primario solo ocurre si existe presupuesto de capacidad; de lo contrario se aplica rechazo o reintento limitado según criticidad.

## 4. Pooling SQLx y aislamiento de módulos

Conforme a ADR-0010:

- Cada módulo conserva identidad runtime y pool lógico propios.
- El pool de escritura apunta al endpoint del primario.
- Los módulos con consultas elegibles pueden tener un pool de lectura separado, acotado y asociado a una identidad del mismo módulo con permisos de solo lectura.
- No se crea un pool por réplica física, petición o consulta; el endpoint de lectura resuelve nodos elegibles.
- Los pools de lectura no ejecutan DDL, migraciones ni escrituras. Los permisos PostgreSQL de solo lectura son defensa adicional.
- El pool de lectura nunca usa credenciales más privilegiadas que el pool de escritura.
- El presupuesto global suma pools de escritura y lectura, instancias de procesos, rolling deployments y conexiones operativas.
- Tras failover, los pools descartan conexiones obsoletas y reconectan a endpoints estables.
- Las transacciones son breves y permanecen en un único nodo.
- RLS y contexto tenant se establecen transaccionalmente en cada conexión reutilizada; nunca se conserva estado de sesión que pueda filtrarse al siguiente tenant.
- Los BFF no poseen pools PostgreSQL de negocio.

La réplica física contiene schemas de todos los módulos, pero los roles siguen limitados por ADR-0001. No se permiten consultas cross-schema, FKs, joins ni accesos directos entre módulos por el hecho de compartir una réplica.

## 5. Seguridad

### 5.1 Transporte y red

- TLS obligatorio para conexiones de aplicación, administración y replicación.
- Validar cadena de confianza y hostname/SAN; nunca desactivar validación en producción.
- TLS 1.2 como mínimo y TLS 1.3 preferido cuando los componentes sean compatibles.
- Red privada para tráfico PostgreSQL; no publicar puertos de base de datos en Internet.
- Separar rutas de aplicación, replicación y administración cuando la infraestructura lo permita.
- Cifrado en reposo habilitado para volúmenes, snapshots y backups de producción.

### 5.2 Identidades y privilegios

- Roles runtime independientes por módulo conforme a ADR-0001.
- Identidad de solo lectura para pools dirigidos a réplicas, con permisos mínimos sobre el schema del módulo.
- Identidad de replicación dedicada, con privilegios específicos y acceso de red limitado.
- Roles de migración separados de runtime; DDL solo contra el primario y mediante proceso controlado.
- Roles de administración fuera de procesos de negocio.
- Rotación de secretos y certificados; no almacenar credenciales en Git, imágenes ni logs.
- La réplica no es una frontera de seguridad: autorización y aislamiento siguen vigentes.

### 5.3 Datos sensibles

- No enviar datos personales, credenciales, tokens o payloads sensibles a logs/telemetría.
- El acceso de lectura no implica permiso para exportar datos masivamente.
- Aplicar límites de consultas, timeout, concurrencia y volumen de resultados.
- Auditar accesos privilegiados y operaciones de administración.

## 6. Backups y recuperación

La estrategia de backup es independiente de la replicación:

1. Backups base consistentes y archivado continuo de WAL.
2. Recuperación a punto en el tiempo (PITR) para volver antes de errores humanos o corrupción lógica.
3. Copias fuera del dominio de fallo del clúster y protegidas contra borrado accidental/malicioso.
4. Cifrado en tránsito y reposo, control de acceso y retención conforme a política de datos.
5. Verificación de integridad y pruebas periódicas de restauración completa y PITR.
6. Runbooks para pérdida del primario, pérdida de zona, corrupción, pérdida de WAL, réplica irrecuperable y restauración.
7. Medición del tiempo real de recuperación y comparación con RTO.

Una réplica propaga DELETE, corrupción lógica y errores de aplicación. No sustituye un backup aislado.

## 7. WAL, slots y almacenamiento

- Vigilar generación, archivado, envío, recepción y replay de WAL.
- Definir límites de retención de WAL y replication slots.
- Alertar ante slots inactivos, crecimiento de WAL retenido, disco bajo y atraso.
- Evitar que una réplica desconectada llene el almacenamiento del primario.
- Si el WAL requerido ya no está disponible, reconstruir el standby desde una base consistente.
- Incluir WAL, backups, snapshots y crecimiento de datos en el dimensionamiento.

## 8. Migraciones y cambios de esquema

- Las migraciones SQLx se ejecutan contra el primario.
- Cada módulo conserva su directorio de migraciones e historial SQLx.
- Una migración se aplica una sola vez por módulo/versión, no una vez por nodo.
- Las réplicas reciben cambios de esquema por replicación física.
- DDL se planifica considerando locks, duración, compatibilidad temporal y replicación.
- No se ejecutan escrituras ni migraciones en hot standby.
- Este documento no autoriza modificar SQL ni ejecutar migraciones.

## 9. Observabilidad y alertas

Conforme a ADR-0015, integrar OpenTelemetry Collector, Prometheus, Alertmanager, Grafana, Loki y Tempo.

Métricas mínimas:
- rol/estado y disponibilidad por nodo;
- conexiones activas, idle, máximas y saturación;
- latencia, locks y deadlocks;
- WAL generado, archivado, enviado, recibido y reproducido;
- lag de recepción y aplicación;
- replication slots y WAL retenido;
- conflictos hot standby y consultas canceladas;
- estado de endpoints y pools de lectura/escritura;
- failovers, promoción, fencing y reconexión;
- antigüedad de backup, salud de archivado WAL y éxito de restauración;
- CPU, memoria, IOPS, almacenamiento y crecimiento.

Alertas con responsable y runbook para primario no disponible, rol ambiguo, pérdida de quorum/fencing, standby síncrono no disponible, lag fuera de límites, WAL/slots retenidos, disco bajo, pool agotado, conflictos hot standby, backup vencido, archivado detenido y failover repetido.

Usar etiquetas de baja cardinalidad. No incluir tenant_id, user_id, IDs de evento, trace_id ni valores únicos como labels.

## 10. Capacidad, SLO y pruebas

Antes de producción se dimensionan y prueban nodos, CPU, memoria, IOPS, almacenamiento, standbys, conexiones, pools por módulo, carga de escritura, proporción de lecturas elegibles, lag tolerable, RPO/RTO, quorum síncrono, límites de consultas largas, retención WAL, backups y PITR.

Pruebas obligatorias:
- caída abrupta del primario y failover;
- fencing del primario anterior y prevención de split-brain;
- pérdida del standby síncrono y comportamiento de commits;
- promoción de standby asíncrono y validación de RPO;
- lag y exclusión de réplicas obsoletas;
- read-your-writes con LSN o retorno al primario;
- confirmación de que consultas críticas nunca se enrutan a réplica;
- agotamiento de pools y backpressure;
- conflictos de recovery y consultas largas;
- WAL retenido, slot inactivo y reconstrucción de réplica;
- pérdida de zona, backup y restauración PITR;
- rolling deployment, reconexión y migración de esquema;
- aislamiento de roles, RLS y contexto tenant.

RPO/RTO, límites de lag, capacidad, conexiones, retención, umbrales y SLO son parámetros operativos a dimensionar y probar; no son una aprobación arquitectónica pendiente ni se fijan números universales aquí.

## 11. Alternativas descartadas

- **Un único PostgreSQL sin standby:** punto único de fallo.
- **Multi-primary:** conflictos de escritura y complejidad innecesaria para el modelo actual.
- **Todas las lecturas a réplicas:** rompe consistencia inmediata y read-your-writes.
- **Sharding como sinónimo de clúster HA:** incorrecto; replicación física mantiene copias completas.
- **Réplicas como backup:** no protege frente a errores lógicos propagados.
- **Rol compartido entre módulos:** contradice ADR-0001.
- **BFF conectados directamente a PostgreSQL:** contradice ADR-0007/0008.

## 12. Referencias

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](../adr/0001-postgres-module-ownership-and-migrations.md)
- [ADR-0010: PostgreSQL Connection Pooling y gestión de recursos](../adr/0010-postgresql-connection-pooling-and-resource-management.md)
- [ADR-0012: UUIDv7 global y PostgreSQL HA](../adr/0012-uuid-v7-global-identifiers-and-postgresql.md)
- [ADR-0015: Observabilidad integral](../adr/0015-integrated-observability-platform.md)
- [ADR-0016: Redis Cluster, TLS y caché distribuida](../adr/0016-redis-cluster-tls-and-query-caching.md)
- [PostgreSQL 19 — High Availability, Load Balancing, and Replication](https://www.postgresql.org/docs/19/high-availability.html)
- [PostgreSQL 19 — Backup and Restore](https://www.postgresql.org/docs/19/backup.html)
- [PostgreSQL 19 — SSL Support](https://www.postgresql.org/docs/19/ssl-tcp.html)

## 13. Estado de implementación

**Especificación técnica aprobada y vigente; implementación pendiente.** No se han desplegado nodos, réplicas, proxies, gestores HA, certificados, backups, exporters ni alertas. No se han añadido dependencias ni modificado SQL, migraciones, schemas, roles o datos.
