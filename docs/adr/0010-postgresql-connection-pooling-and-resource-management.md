# ADR-0010: PostgreSQL Connection Pooling y gestión de recursos

- Estado: **Accepted**
- Propuesto: 2026-11-24
- Aprobado: 2026-11-24
- Aprobación: decisión aprobada explícitamente por el propietario del producto.
- Complementa: ADR-0001, ADR-0003, ADR-0004, ADR-0007, ADR-0008 y ADR-0009.
- Fuente de referencia: estrategia ENSAMBRIA de Connection Pooling y Gestión de Conexiones PostgreSQL, adaptada a la arquitectura vigente de Restaurant OS.

## 1. Contexto

Restaurant OS utiliza inicialmente una instancia/servicio PostgreSQL compartido por cuatro procesos independientes. La propiedad de los datos no es compartida: cada módulo conserva schema, rol PostgreSQL, identidad de migración/runtime, directorio de migraciones e historial SQLx exclusivos, conforme a ADR-0001.

La topología contiene:
- Admin Platform Backend, propietario únicamente de PLATFORM.
- Public Backend, propietario de los otros 19 módulos de negocio.
- Admin BFF y Public BFF, procesos independientes de composición HTTP/OpenAPI sin propiedad ni acceso directo a la persistencia de negocio.

Por tanto, «un pool por backend» no puede interpretarse como un único pool con una única credencial para todos los módulos de Public Backend. Eso debilitaría el aislamiento por rol que ADR-0001 exige. Tampoco corresponde crear pools PostgreSQL de negocio para los BFF.

El pooling debe equilibrar reutilización, aislamiento de permisos, concurrencia, latencia y el límite global de conexiones de PostgreSQL. La cantidad de conexiones crece con los pools, los módulos, las réplicas y los procesos operativos; dimensionar cada pool de forma aislada no es suficiente.

## 2. Decisión

### 2.1 Propiedad e identidad de cada pool

1. Cada módulo que accede a PostgreSQL tendrá un pool SQLx runtime propio, asociado exclusivamente a la identidad PostgreSQL runtime de ese módulo.
2. El pool se construye y administra desde el composition root del proceso propietario, pero su configuración, credenciales, límites y métricas se atribuyen al módulo dueño.
3. Los pools son reutilizables y acotados; no se abre una conexión nueva por petición ni por consulta.
4. Ningún pool compartirá una credencial privilegiada o un rol global entre módulos para simplificar la conectividad.
5. El pool de un módulo solo puede ejecutar operaciones autorizadas sobre el schema y los objetos de ese módulo. No habilita acceso a tablas de otros módulos.
6. El pool es un recurso de infraestructura del módulo, no un crate, servicio de dominio ni propiedad de un BFF.

Aplicación por proceso:

| Proceso | Pools PostgreSQL de negocio |
|---|---|
| Admin Platform Backend | Pool runtime de PLATFORM |
| Public Backend | Un pool runtime independiente por cada uno de sus 19 módulos propietarios |
| Admin BFF | Ninguno |
| Public BFF | Ninguno |

La tabla describe el aislamiento lógico por módulo/rol. No prescribe que todos los pools deban abrir conexiones al arrancar: su creación y adquisición deben respetar límites de recursos y el comportamiento de arranque definido por la implementación.

### 2.2 Ciclo de vida y uso dentro del proceso

- Cada pool se crea una sola vez por instancia de proceso y se comparte entre las operaciones concurrentes del módulo propietario.
- Los repositorios/adaptadores SQLx del módulo reciben el pool de su propia composición; no consultan un registro global que permita seleccionar credenciales o pools de otros módulos.
- No se crea un pool por request, handler, transacción, repositorio ni tarea individual.
- El cierre del proceso detiene la admisión de trabajo, permite completar o cancelar operaciones según el graceful shutdown y cierra los pools.
- Los parámetros del pool son configuración operativa validada al iniciar. No se fijan aquí números universales para conexiones máximas/mínimas, tiempos o vida de conexión.
- La aplicación no debe depender de conexiones mantenidas permanentemente abiertas. La demanda real debe poder crecer dentro del máximo configurado y recuperarse al liberar conexiones.

### 2.3 Separación de tráfico y workers

1. Las solicitudes normales y los workers de un mismo módulo usan inicialmente el pool runtime de ese módulo, sujeto a límites de concurrencia y adquisición.
2. La concurrencia de workers, dispatchers Outbox, consumidores Inbox y jobs se limita por workload y por módulo. El trabajo en segundo plano no puede consumir ilimitadamente las conexiones disponibles ni impedir el servicio de solicitudes normales.
3. No se crea automáticamente un pool adicional por worker, job, consumidor o tipo de tarea.
4. Un pool separado para workers, lecturas, tareas administrativas u otra carga solo se permite cuando mediciones demuestren aislamiento de recursos, prioridades o patrones de conexión incompatibles. Debe incluirse en el presupuesto global y conservar el rol mínimo necesario del módulo.
5. Workers y jobs usan las credenciales del módulo propietario de los datos que procesan. No se les concede un rol global para atravesar ownership.
6. Los mecanismos de coordinación, leases, advisory locks, Outbox/Inbox e idempotencia siguen ADR-0003. El pool no sustituye esos mecanismos.

### 2.4 Presupuesto global de conexiones

El dimensionamiento debe realizarse desde el límite de PostgreSQL hacia los procesos, no sumando máximos arbitrarios por módulo.

Para cada escenario de despliegue se calculará:

[
C_{aplicacion} =
sum_{instancias y replicas}
sum_{pools de modulo}
C_{maximo configurado}
]

Y se reservará capacidad adicional para conexiones operativas, tales como migraciones controladas, administración, monitorización, mantenimiento y recuperación. El total presupuestado debe permanecer por debajo del límite efectivo de PostgreSQL con margen explícito.

El cálculo debe considerar, como mínimo:
- PLATFORM en cada réplica de Admin Platform Backend.
- Los 19 pools de módulos en cada réplica de Public Backend.
- Cualquier pool adicional aprobado para un workload aislado.
- Número máximo de réplicas simultáneas durante rolling deployments, escalado y recuperación.
- Conexiones de migración/operación, administración y monitorización.
- Capacidad reservada y margen ante fallos o picos.

El máximo de un pool no equivale a conexiones siempre abiertas. El dimensionamiento debe documentar máximos, demanda esperada, concurrencia y comportamiento real de adquisición.

No se aprobarán valores numéricos de max_connections, max_connections por pool, min_connections, timeouts ni número de réplicas mediante este ADR. Se definirán con inventario de despliegue, capacidad real de PostgreSQL, pruebas de carga y margen operativo documentado.

### 2.5 Transacciones y contexto de tenant

- Las transacciones deben ser breves y pertenecer a una única operación del módulo.
- No se mantiene una conexión ni una transacción abierta mientras se realizan llamadas HTTP/gRPC, publicaciones de mensajes, esperas externas o trabajo lento.
- Cuando una operación requiera contexto RLS del tenant, este se establece dentro de la transacción mediante el mecanismo aprobado, por ejemplo `SET LOCAL app.tenant_id`, antes de ejecutar consultas protegidas.
- El contexto local de tenant debe aplicarse en cada transacción que lo requiera. No se establece como estado de sesión persistente de una conexión reutilizable.
- Commit o rollback debe cerrar el alcance del contexto transaccional antes de devolver la conexión al pool.
- El contexto de tenant nunca sustituye autenticación, autorización, actor ni validaciones de pertenencia.
- Las políticas RLS, FORCE ROW LEVEL SECURITY, roles y grants siguen siendo los definidos por los requisitos y ADR-0001; este ADR no crea ni modifica políticas o SQL.

### 2.6 Timeouts, límites y backpressure

La configuración operativa debe definir y validar límites para:
- Espera de adquisición de conexión.
- Ejecución de consultas.
- Duración de transacciones.
- Espera de locks y operaciones de bloqueo.
- Llamadas remotas efectuadas fuera de transacciones.
- Apagado ordenado y drenaje de operaciones.

Los valores concretos se establecerán por workload con pruebas y objetivos de latencia; no se copian valores ilustrativos de ENSAMBRIA.

Ante saturación:
- No se acumulan tareas o peticiones sin límite esperando una conexión.
- Se aplican límites de concurrencia y backpressure.
- Se devuelve un error controlado y observable cuando no sea posible admitir trabajo dentro de los límites.
- Los reintentos se realizan solo cuando la operación sea segura/idempotente y con backoff/jitter según corresponda.
- No se reintentan indiscriminadamente transacciones que pudieron haber confirmado efectos.

### 2.7 Seguridad y credenciales

- Las credenciales runtime son específicas por módulo y no se almacenan en el repositorio.
- Se mantiene separación entre roles de migración y runtime conforme a ADR-0001; los pools de aplicación usan roles runtime sin DDL ni privilegios globales.
- Las conexiones usan TLS según la configuración segura del entorno y validación de certificados en despliegues que atraviesen redes no confiables.
- Los secretos se suministran mediante el mecanismo de secretos del entorno, con rotación operativa y sin exponerlos en logs, métricas o errores.
- Los BFF no reciben credenciales de PostgreSQL de negocio.
- Las credenciales de administración/operación se mantienen fuera de los pools runtime de módulos.

### 2.8 Observabilidad

Se deben poder observar, por módulo y por instancia de proceso, al menos:
- Conexiones en uso, ociosas y máximas configuradas.
- Adquisiciones exitosas, tiempo de espera y timeouts.
- Tiempo de espera en cola y duración de adquisición.
- Consultas/transacciones lentas y errores de conexión.
- Saturación, rechazos/backpressure y recuperación.
- Carga de workers frente a solicitudes normales.

Las métricas deben usar etiquetas de cardinalidad controlada, por ejemplo proceso, módulo, pool y tipo de workload. No deben incluir tenant_id, usuario, credenciales, connection string ni otros identificadores de alta cardinalidad o datos sensibles. La instrumentación debe integrarse con OpenTelemetry y W3C Trace Context conforme a ADR-0004.

### 2.9 PgBouncer y proxies de conexión

PgBouncer u otro proxy de conexiones queda como alternativa operativa opcional, no como dependencia obligatoria de la arquitectura inicial.

Solo se incorporará si las mediciones demuestran que resuelve un problema concreto de conexiones, escalado o administración. Antes de adoptarlo se debe validar el modo de pooling y su compatibilidad con SQLx, prepared statements, transacciones, parámetros de sesión, RLS y el uso de `SET LOCAL`. La adopción no puede debilitar la separación de roles ni el contexto transaccional.

### 2.10 Pruebas y validación

La estrategia de implementación deberá contemplar pruebas con PostgreSQL real para:
- Aislamiento de roles y schemas por módulo.
- RLS y contexto tenant en transacciones con conexiones reutilizadas.
- Concurrencia, adquisición y liberación de conexiones.
- Timeouts, saturación y backpressure.
- Transacciones largas, locks y consultas lentas.
- Workers/Outbox/Inbox compitiendo por recursos sin agotar la capacidad de solicitudes normales.
- Reinicio, graceful shutdown, pérdida de conexiones y recuperación.
- Escalado horizontal y rolling deployment dentro del presupuesto global.
- Comportamiento del proxy, solo si se adopta.

Una prueba con mocks no sustituye la validación de semántica PostgreSQL, roles, RLS, locks o pooling.

## 3. Alternativas consideradas

### Un único pool por proceso con un rol compartido

**Rechazada.** En Public Backend mezclaría las identidades de 19 módulos y debilitaría el aislamiento de ADR-0001. La unidad de pool runtime debe corresponder a la identidad del módulo.

### Un pool por petición, repositorio o worker

**Rechazada.** Multiplica conexiones y elimina la reutilización controlada. Los pools pertenecen al ciclo de vida de la instancia y módulo, no al de cada operación.

### Un pool PostgreSQL por BFF

**Rechazada.** Los BFF no son propietarios de persistencia de negocio y consumen contratos de los backends conforme a ADR-0007/0008/0009.

### Pool adicional obligatorio para todo worker

**No adoptada.** Añadir pools por defecto puede multiplicar el consumo sin aportar aislamiento útil. Se comienza con límites de concurrencia; los pools separados requieren evidencia y presupuesto.

### PgBouncer obligatorio desde el inicio

**No adoptada.** Se mantiene como opción condicionada a mediciones y pruebas de compatibilidad.

## 4. Consecuencias

Como decisión aceptada:
- La topología de cuatro procesos y el ownership de módulos permanecen sin cambios.
- Cada identidad runtime de módulo conserva un pool SQLx acotado y reutilizable dentro de cada instancia propietaria.
- Public Backend debe presupuestar la suma de los pools de sus 19 módulos por réplica.
- El dimensionamiento se vuelve una responsabilidad global de despliegue y operación, no una colección de valores aislados.
- Workers, jobs y solicitudes comparten inicialmente recursos del módulo con límites explícitos.
- RLS y contexto tenant deben ser transaccionales para evitar contaminación entre operaciones sobre conexiones reutilizadas.
- Se requieren métricas y pruebas de saturación, aislamiento y recuperación.
- PgBouncer no se introduce sin evidencia.
- La decisión no fija versiones de SQLx ni añade dependencias, tablas, schemas, roles o migraciones.

## 5. Plan de adopción propuesto

1. **Fundamentos:** inventariar módulos, roles runtime, procesos, réplicas, cargas y límites efectivos de PostgreSQL; definir responsables y formato del presupuesto.
2. **Implementación de pools:** construir un pool por identidad runtime de módulo, configurar límites/tiempos por entorno y propagarlo solo a los adaptadores/repositorios del módulo dueño.
3. **Concurrencia y seguridad:** limitar workers y solicitudes; verificar transacciones breves, RLS y contexto tenant; documentar backpressure.
4. **Observabilidad y pruebas:** instrumentar métricas por pool y ejecutar pruebas reales de carga, saturación, aislamiento y recuperación.
5. **Preparación de producción:** validar el presupuesto con el máximo de réplicas simultáneas, conexiones operativas, rolling deployments y margen; evaluar PgBouncer únicamente si los resultados lo justifican.

Las fases describen una secuencia propuesta. No declaran que los pools, métricas, pruebas, infraestructura ni despliegues estén implementados.

## 6. Criterios de aceptación de la decisión

- [ ] Se confirma un pool runtime por módulo/identidad, no un rol compartido por proceso.
- [ ] Se confirma que los BFF no tienen pools PostgreSQL de negocio.
- [ ] Se documenta el presupuesto total por número de réplicas y pools, incluyendo conexiones operativas.
- [ ] Se definen límites de adquisición, consulta, transacción, locks y concurrencia a partir de mediciones.
- [ ] Se establece cómo se protege la capacidad de solicitudes frente a workers.
- [ ] Se documenta el uso transaccional de RLS y contexto tenant en conexiones reutilizadas.
- [ ] Se definen métricas, pruebas de carga, saturación, aislamiento y recuperación.
- [ ] Se decide si PgBouncer queda fuera de la primera implementación o se justifica con evidencia.
- [ ] Se verifica que ninguna regla contradice ADR-0001, ADR-0003, ADR-0004, ADR-0007, ADR-0008 o ADR-0009.

## 7. Referencias

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](./0001-postgres-module-ownership-and-migrations.md).
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](./0003-stateless-outbox-inbox-and-jobs.md).
- [ADR-0004: W3C Trace Context en todos los contratos](./0004-w3c-trace-context.md).
- [ADR-0007: Topología de cuatro backends independientes y comunicación](./0007-four-independent-backends-and-communication.md).
- [ADR-0008: Distribución de módulos entre los cuatro procesos](./0008-module-ownership-across-four-processes.md).
- [ADR-0009: Límites de crates y dirección de dependencias](./0009-crate-boundaries-and-dependencies.md).
- [Estándar de arquitectura](../architecture/engineering-standard.md).
- [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md).
- [Reglas de implementación](../engineering/implementation-rules.md).

## 8. Estado de implementación

Este ADR está **Accepted**. No modifica ni acepta por sí mismo decisiones anteriores. La aceptación es una decisión documental: no crea pools, configura SQLx, cambia credenciales, modifica infraestructura, crea tablas o migraciones, ni ejecuta SQL o migraciones.
