# Reglas de PostgreSQL

## Contexto del proyecto

Restaurant OS inicia como un monolito modular en Rust, con SQLx y una base de
datos PostgreSQL compartida. Estas reglas aplican a la API y a los procesos de
trabajo. No implican crear un pool por módulo ni desplegar microservicios.

## Reglas obligatorias

### 1. Pools acotados y reutilizables

- Cada proceso crea sus pools al iniciar y los reutiliza durante su vida útil.
- No crear pools ni conexiones nuevas por petición, tenant o módulo.
- Compartir el pool mediante el estado del proceso y adquirir conexiones solo
  durante operaciones que realmente acceden a PostgreSQL.
- Validar la configuración al iniciar; fallar explícitamente ante valores
  inválidos.

### 2. Presupuesto global de conexiones

- Calcular el máximo agregado considerando réplicas máximas, procesos de API,
  workers y conexiones reservadas para migraciones, administración y monitoreo.
- Conservar margen operativo; no asignar a los pools toda la capacidad de
  PostgreSQL.
- Recalcular y aprobar el presupuesto antes de aumentar réplicas o límites.

### 3. Timeouts y saturación controlada

- Configurar límites para adquirir conexiones, ejecutar consultas y mantener
  transacciones o locks.
- Limitar la concurrencia de consultas y operaciones costosas.
- Ante saturación, devolver errores controlados y aplicar backpressure cuando
  corresponda; no abrir conexiones fuera del pool ni reintentar sin límite.
- Clasificar y observar por separado los errores de pool, conexión, consulta y
  lock.

### 4. Transacciones breves y contexto de tenant

- Establecer el tenant autorizado con `SET LOCAL app.tenant_id` dentro de la
  misma transacción que ejecuta las consultas protegidas por RLS.
- Obtener el tenant desde el contexto autenticado y autorizado, nunca confiar en
  un valor arbitrario enviado por el cliente.
- No ejecutar consultas protegidas antes de establecer el contexto ni dejar
  estado de tenant de sesión en una conexión reutilizable.
- Mantener las transacciones breves. No conservar una conexión durante llamadas
  HTTP/gRPC, operaciones de almacenamiento, esperas o generación de informes.
- El rol de runtime no debe ser propietario de tablas, superusuario ni tener
  `BYPASSRLS`; las migraciones usan una identidad separada.

### 5. Aislamiento de workers

- Limitar la concurrencia y el consumo de conexiones de Reporting,
  conciliaciones, outbox y otros trabajos asíncronos para que no agoten la
  capacidad necesaria para POS, pagos e identidad.
- Asignar un presupuesto por workload. Usar pools físicos separados solo cuando
  el aislamiento lo justifique; un límite de concurrencia sobre un pool
  compartido puede ser suficiente.
- Usar lotes acotados, checkpoints e idempotencia para trabajos que puedan
  reintentarse o reanudarse.

#### Reporting y exportaciones

- Consultar y extraer los datos con límites explícitos de filas, bytes,
  concurrencia y duración.
- Liberar la conexión y cerrar la transacción antes de renderizar, serializar,
  comprimir o subir un PDF, XLSX o CSV.
- No mantener una transacción SQL abierta durante operaciones con object
  storage o llamadas a Integrations.
- Ejecutar exportaciones grandes como trabajos asíncronos con concurrencia
  limitada; no cargar conjuntos ilimitados en memoria.

### 6. Pruebas con PostgreSQL real

- Probar en PostgreSQL real las políticas RLS, permisos, transacciones, locks y
  comportamiento del pool; los mocks no sustituyen estas pruebas.
- Verificar aislamiento entre tenants cuando se reutilizan conexiones, incluso
  después de `COMMIT`, `ROLLBACK` y cancelación.
- Probar límites y timeout del pool, concurrencia de workers y recuperación
  después de saturación o indisponibilidad de PostgreSQL.

### 7. Observabilidad sin datos sensibles

- Medir por proceso o workload las conexiones activas e inactivas, el máximo
  configurado, la espera de adquisición, los timeouts y los errores.
- Medir duración de consultas y transacciones, y la concurrencia de workers.
- No registrar credenciales, URLs de conexión, datos personales ni parámetros
  SQL sensibles.
- Definir alertas a partir de la capacidad medida y los objetivos operativos;
  no asumir umbrales universales.

### 8. Migraciones controladas

- Ejecutar migraciones desde un proceso controlado de despliegue, una sola vez
  por versión; nunca desde cada réplica de la aplicación.
- Usar una identidad de base de datos exclusiva para migraciones y mantenerla
  separada de la identidad de runtime.
- Coordinar la estrategia de migración para evitar carreras entre instancias.

## Decisiones que requieren evidencia

- No fijar máximos de conexiones ni timeouts copiando valores de otro proyecto.
  Definirlos con la capacidad real de PostgreSQL, el número máximo de réplicas
  y pruebas representativas de carga.
- PgBouncer no es obligatorio. Evaluarlo solo si las mediciones lo justifican y
  después de probar su compatibilidad con SQLx, prepared statements y el
  establecimiento transaccional del contexto de tenant.