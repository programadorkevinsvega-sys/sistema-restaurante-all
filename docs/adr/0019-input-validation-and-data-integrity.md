# ADR-0019: Validación de entradas, contratos y protección de integridad de datos

- Estado: **Accepted**
- Aprobado: 2026-11-25
- Ámbito: transversal a los cuatro procesos, todos los módulos, contratos HTTP/gRPC, workers, mensajería e integraciones.
- Complementa: ADR-0001, ADR-0002, ADR-0007, ADR-0008, ADR-0009, ADR-0011, ADR-0012, ADR-0014, ADR-0015 y ADR-0018.
- Especificación técnica: [Validación de entradas y contratos de datos](../architecture/input-validation-and-data-contracts.md).

## Contexto

Restaurant OS recibe entradas desde clientes web y móviles, Admin BFF, Public BFF, llamadas gRPC, integraciones, proveedores, workers, NATS Core/JetStream, importaciones y tareas internas. Ninguna fuente se considera confiable por el solo hecho de pertenecer al sistema.

Una validación incompleta puede provocar corrupción de datos, estados imposibles, agotamiento de recursos, exposición de información, errores de autorización o vulnerabilidades como inyección, mass assignment, traversal y SSRF.

La validación no puede residir exclusivamente en formularios ni BFF. Tampoco sustituye autorización, aislamiento multi-tenant, codificación contextual de salida, consultas parametrizadas ni restricciones de integridad PostgreSQL.

La arquitectura ya establece que OpenAPI es la fuente de verdad HTTP, Protobuf la fuente de verdad gRPC, cada módulo es dueño de sus reglas y datos, los BFF no poseen dominios y cada módulo conserva schema, rol, migraciones e historial SQLx independientes.

## Problema

Se necesita una política uniforme y verificable que determine dónde se valida cada dato, quién es responsable, cómo se definen tipos y límites, cómo se manejan entradas maliciosas, cómo se protegen contexto y ownership, cómo se devuelven errores seguros y cómo se prueban los límites.

## Decisión

### 1. Validación en capas y ownership

1. Toda entrada externa o interna se considera no confiable hasta ser validada por el componente que la consume.
2. La validación se distribuye por fronteras:
   - **Frontend:** validación de experiencia de usuario; no constituye control de seguridad.
   - **BFF HTTP:** parseo, estructura, tipos, formatos, tamaño y restricciones declaradas por OpenAPI.
   - **Frontera backend/gRPC:** vuelve a validar cada mensaje recibido, aunque provenga de un BFF o proceso interno.
   - **Aplicación del módulo:** precondiciones del caso de uso, combinaciones permitidas y reglas de aplicación.
   - **Dominio del módulo:** invariantes y transiciones válidas.
   - **Persistencia propietaria:** restricciones de integridad como última defensa.
3. El backend propietario es la autoridad final de las reglas de su dominio. La validación en BFF nunca permite omitir la validación del módulo.
4. Workers, consumidores NATS, importadores, tareas programadas y procesos de recuperación aplican las mismas reglas que sus operaciones equivalentes.
5. Cada módulo valida sus propios datos. No se crea un módulo central dueño de todas las reglas ni se importan implementaciones internas ajenas.
6. Admin Platform Backend valida PLATFORM; Public Backend valida sus módulos propietarios. Admin BFF y Public BFF validan solicitudes HTTP y componen contratos, sin adquirir ownership de reglas ni datos.
7. Solo se compartirán primitivas técnicas neutrales. Tipos, reglas, catálogos y restricciones de dominio pertenecen al módulo propietario.

### 2. Clases de validación

Se distinguen:
1. **Estructural:** presencia, nulabilidad, tipo, forma, cardinalidad, campos permitidos y profundidad.
2. **Sintáctica:** formato y representación, como UUID, fecha, correo, teléfono o decimal.
3. **Semántica:** coherencia entre campos, rangos y combinaciones.
4. **Dominio:** invariantes, transiciones y reglas del módulo.
5. **Estado/concurrencia:** precondiciones dependientes del estado persistido, verificadas dentro de la operación protegida.
6. **Autorización:** decisión separada sobre si el actor puede operar sobre el recurso y tenant.
7. **Integridad de persistencia:** restricciones del schema propietario.

Un formato válido no implica que la operación sea válida, autorizada o posible en el estado actual.

### 3. Contratos y validación runtime

1. OpenAPI describe parámetros, cuerpos, respuestas, formatos, nulabilidad y restricciones HTTP.
2. Protobuf describe mensajes gRPC y se complementa con reglas explícitas cuando los tipos no sean suficientes.
3. Los contratos generados no se editan manualmente. Las fuentes y generadores siguen ADR-0002.
4. Las restricciones declaradas no sustituyen validación runtime en las fronteras backend.
5. Las reglas de dominio no se duplican como autoridad en BFF ni se trasladan a contratos de transporte.
6. Endurecer restricciones puede romper clientes existentes; esos cambios se revisan como cambios de contrato.
7. Los campos dinámicos solo se permiten cuando el contrato define allowlist, tipos, tamaño, profundidad y reglas.

### 4. Tipos, formatos y límites

1. Cada campo define tipo, requerido/opcional, nulabilidad, límites, formato, precisión, escala y reglas de cardinalidad aplicables.
2. Se rechazan conversiones ambiguas, coerciones permisivas, truncamientos y desbordamientos silenciosos.
3. Importes, tasas y cantidades que requieren precisión decimal usan representación decimal exacta; no se acepta punto flotante binario como representación autoritativa de dinero.
4. Fechas y horas distinguen fecha civil, hora local e instante. Los instantes requieren zona/offset inequívoco o UTC según contrato.
5. UUID cumple formato y versión global establecidos por ADR-0012. Un UUID válido no demuestra existencia, pertenencia ni autorización.
6. Enums aceptan solo valores definidos; no se mapean valores desconocidos a estados por defecto.
7. Ausente y null tienen semánticas diferenciadas cuando el contrato lo requiera.
8. Las cadenas definen límites explícitos; se distinguen bytes y caracteres Unicode cuando importe. No se truncan entradas.
9. Colecciones definen cardinalidad máxima y reglas de duplicados.
10. Objetos anidados definen profundidad y tamaño máximos.
11. Toda ruta tiene límites finitos de transporte y recursos. Los límites concretos de campos y endpoints se documentan por contrato/módulo, se dimensionan y se prueban; no se inventa un límite universal.

### 5. Normalización

1. Solo se normaliza cuando existe regla explícita por tipo de campo y propósito.
2. No se alteran silenciosamente texto libre, contraseñas, tokens, secretos, firmas, claves de idempotencia ni identificadores opacos.
3. Recortar espacios, cambiar mayúsculas, normalizar Unicode o canonicalizar URLs requiere regla específica y compatibilidad documentada.
4. No se eliminan caracteres para transformar una entrada inválida en una aparentemente segura.
5. Se conserva la distinción entre valor original y normalizado cuando importe para auditoría, firma, consentimiento o evidencia.
6. Las comparaciones y deduplicaciones usan la representación canónica definida por el módulo.

### 6. Campos desconocidos y mass assignment

1. Las escrituras HTTP usan esquemas explícitos y rechazan campos desconocidos por defecto, salvo extensión documentada.
2. Campos de solo lectura, ownership, estado interno, auditoría, permisos, rol, tenant, actor y metadatos calculados por servidor no son asignables directamente por el cliente.
3. Los DTO de entrada son específicos por operación; no se enlaza el body a entidades completas ni modelos de persistencia.
4. Las actualizaciones parciales definen semántica de ausente, null y valor.
5. Protobuf conserva la compatibilidad de campos desconocidos propia del formato cuando corresponda, pero ningún campo desconocido se usa para decisiones de seguridad o negocio.
6. Los mapas dinámicos tienen allowlist de claves, tipos y límites.

### 7. Seguridad y multi-tenancy

1. Tenant efectivo, actor, roles y permisos provienen de contexto autenticado por servidor, no de valores libres en body, query o headers no confiables.
2. Si el cliente incluye un tenant selector, el backend comprueba que coincide con el contexto autenticado y que el actor puede operar allí.
3. Cada módulo comprueba ownership y autorización sobre sus recursos. UUID difícil de adivinar no es autorización.
4. Se aplican controles de acceso y RLS conforme a los ADR de seguridad/persistencia; validar entradas no sustituye estos controles.
5. Los errores no revelan existencia de recursos de otros tenants cuando facilite enumeración.
6. No se aceptan timestamps de auditoría, actor de auditoría, estado interno, flags privilegiados o campos calculados del cliente, salvo comando explícito y autorizado.

### 8. Consultas, filtros y paginación

1. Campos de ordenamiento, dirección, filtros y operadores se validan contra allowlists por endpoint.
2. No se interpolan columnas, identificadores, operadores ni fragmentos SQL recibidos. Los valores usan consultas parametrizadas.
3. Filtros definen límites de cantidad, profundidad, longitud y complejidad.
4. Paginación define máximo de página, cursores y orden estable.
5. Cursores opacos se validan y protegen contra manipulación; no constituyen autorización ni tenant.
6. Reportes/exportaciones tienen cuotas, timeouts y concurrencia según costo.
7. El cliente no solicita columnas, joins o recursos fuera de la superficie publicada por el contrato.

### 9. Archivos y contenido binario

1. Cada carga define tamaño máximo, cantidad, tipos permitidos, cuotas y límites de dimensiones/duración cuando aplique.
2. No se confía en nombre, extensión ni Content-Type declarados; se inspecciona el contenido real.
3. Nombres de archivo no se usan directamente como rutas.
4. Se previenen traversal, sobrescrituras, archivos políglotas peligrosos, descompresión explosiva y consumo desproporcionado.
5. Formatos admitidos se decodifican con bibliotecas mantenidas y límites de recursos; se aplica análisis antimalware/cuarentena cuando corresponda.
6. Archivos se almacenan fuera de rutas ejecutables y se sirven con autorización y cabeceras seguras.
7. Validar archivo no sustituye autorización, escaneo, aislamiento ni retención.

### 10. URLs e integraciones

1. URLs se validan según propósito, esquemas y destinos permitidos.
2. Cuando el servidor consume una URL suministrada por usuario/proveedor, aplica anti-SSRF: allowlists cuando sea viable, rechazo de redes privadas/reservadas, validación DNS y destino efectivo, control de redirecciones, puertos, tiempo y tamaño.
3. No se permite acceso a servicios internos, metadatos cloud ni redes administrativas mediante entradas controlables por usuario.
4. Tokens y secretos de integración tienen tratamiento específico y nunca se registran.
5. Respuestas externas son entradas no confiables y se validan antes de mapear o persistir.

### 11. Inyección y codificación de salida

1. SQL usa parámetros; validar entradas no es defensa suficiente contra SQL injection.
2. Se codifica según contexto de salida (HTML, atributo, URL, JavaScript, CSS, JSON y logs). No existe sanitizador universal.
3. HTML enriquecido solo se admite con política explícita y biblioteca mantenida.
4. Datos son texto plano por defecto; no se ejecutan como código, plantilla, expresión, consulta o comando.
5. Comandos, rutas, expresiones regulares y búsquedas evitan concatenación insegura y tienen límites.

### 12. Estado, concurrencia e idempotencia

1. Reglas dependientes de estado —saldo, disponibilidad, permisos vigentes, transiciones— se verifican dentro de transacción, bloqueo o control optimista apropiado.
2. Una consulta previa en BFF no garantiza que el estado siga vigente.
3. Conflictos concurrentes se distinguen de errores sintácticos.
4. Claves de idempotencia validan formato y alcance; no otorgan autorización. Reutilizar clave con payload distinto sigue la política de idempotencia de la operación.
5. Se respetan ADR-0003 y ADR-0013 para Outbox/Inbox, deduplicación, reintentos y Sagas.

### 13. Errores y respuestas

1. Los errores usan códigos estables, mensaje seguro, ruta de campo cuando aplique y correlación no sensible.
2. Se distinguen solicitud malformada, campo inválido, valor semántico inválido, regla de dominio, conflicto de estado, tamaño excedido, tipo no admitido y límite de recursos.
3. HTTP: 400 sintaxis/estructura, 413 tamaño, 415 tipo no admitido, 422 contenido semánticamente inválido, 409 conflicto de estado y 429 límite de frecuencia/recursos. Cada contrato documenta excepciones justificadas.
4. gRPC: códigos equivalentes, especialmente INVALID_ARGUMENT, FAILED_PRECONDITION, ALREADY_EXISTS y RESOURCE_EXHAUSTED.
5. No se incluyen stack traces, SQL, nombres internos, secretos, valores sensibles ni datos que faciliten enumeración.
6. Rutas de campo y códigos son estables; no dependen de mensajes internos de bibliotecas.
7. Errores inesperados se registran internamente con correlación y respuesta genérica.
8. Errores de negocio no se disfrazan como errores de formato.

### 14. Límites de recursos y abuso

1. Toda entrada tiene límites finitos de bytes, cantidad, profundidad, tiempo y memoria.
2. Se limitan concurrencia, fan-out, consultas, decodificación de archivos, expresiones de búsqueda y validaciones externas.
3. Endpoints públicos y de autenticación aplican rate limiting y controles antiabuso según riesgo, coordinados entre réplicas cuando corresponda.
4. Mensajes inválidos permanentes no se reintentan indefinidamente; se clasifican y ponen en cuarentena/DLQ conforme a mensajería.
5. Límites operativos se dimensionan y observan conforme a ADR-0015.

### 15. Persistencia e integridad

1. Cada módulo mantiene restricciones de integridad de sus propios datos.
2. NOT NULL, CHECK, UNIQUE y FK permitidas son defensa final, no sustituyen validación de aplicación.
3. No se crean FKs, joins ni consultas entre schemas de módulos distintos, conforme ADR-0001.
4. Errores de persistencia se traducen a errores seguros sin exponer tablas, constraints o SQL.
5. Un chequeo previo no reemplaza manejo de carreras de unicidad/concurrencia.
6. Este ADR no autoriza cambios SQL, migraciones, schemas, roles ni datos.

### 16. Observabilidad y privacidad

1. Métricas agregadas por servicio/módulo/operación/código, evitando alta cardinalidad.
2. Logs y trazas pueden incluir clase/código de validación y correlación, nunca contraseñas, tokens, cookies, secretos, payloads completos ni datos personales sensibles.
3. Valores rechazados, IDs de usuario, correos, tenant IDs y payloads no se usan como labels.
4. Se minimiza y redacta diagnóstico conforme ADR-0015 y ADR-0018.

### 17. Pruebas obligatorias de implementación

- Pruebas unitarias de límites, formatos, nulabilidad, normalización y dominio.
- Pruebas de frontera HTTP/gRPC con entradas malformadas y campos desconocidos.
- Pruebas de contrato y compatibilidad OpenAPI/Protobuf.
- Pruebas de autorización y aislamiento multi-tenant, incluyendo IDs válidos de otro tenant.
- Pruebas de concurrencia, unicidad e idempotencia.
- Fuzz/property testing de parsers, deserialización, cursores y estructuras complejas.
- Pruebas de mass assignment, inyección, traversal, SSRF, archivos maliciosos y abuso de recursos.
- Pruebas de regresión y carga.
- Pruebas de consumidores de eventos para mensajes inválidos, cuarentena y redrive.

Los tests no deben sustituir la frontera real por mocks y presentar el resultado como validación real.

## Alternativas consideradas

- **Validar solo en frontend/BFF:** rechazada; existen entradas gRPC, eventos, workers e integraciones y el BFF no posee reglas de dominio.
- **Servicio central de validación:** rechazado; centralizaría reglas de módulos independientes y no podría validar autoritativamente su estado.
- **Confiar solo en tipos Rust/OpenAPI/Protobuf:** rechazado; no cubren por sí solos dominio, autorización, estado ni límites de recursos.
- **Sanitizador universal:** rechazado; la transformación depende del contexto y puede corromper datos.
- **Solo constraints PostgreSQL:** rechazado; no cubren todas las superficies ni dan feedback apropiado.
- **Todas las reglas en crates/shared:** rechazado; shared solo admite primitivas técnicas neutrales.

## Consecuencias

**Positivas:** defensa en profundidad, ownership preservado, menos mass assignment y entradas ambiguas, errores consistentes, aislamiento más fuerte y pruebas negativas sistemáticas.

**Costos:** contratos más precisos, validadores por módulo, consumo adicional de CPU/memoria, catálogo de errores estable y políticas específicas para archivos, URLs, filtros e importaciones.

## Límites

No se selecciona una biblioteca Rust concreta ni framework; no se fijan todos los límites numéricos de endpoints; no se redefinen reglas de negocio; no se autorizan cambios de contratos existentes, SQL, migraciones, schemas, roles o datos. Las dependencias se seleccionarán al implementar, verificando mantenimiento, seguridad y compatibilidad con el workspace real.

## Referencias

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](./0001-postgres-module-ownership-and-migrations.md).
- [ADR-0002: OpenAPI, Protobuf y código generado](./0002-openapi-protobuf-generated-clients.md).
- [ADR-0008: Distribución de módulos entre los cuatro procesos](./0008-module-ownership-across-four-processes.md).
- [ADR-0009: Límites de crates y dirección de dependencias](./0009-crate-boundaries-and-dependencies.md).
- [ADR-0011: Protección de contraseñas y controles de autenticación](./0011-password-hashing-and-authentication-security.md).
- [ADR-0012: UUIDv7 global y PostgreSQL](./0012-uuid-v7-global-identifiers-and-postgresql.md).
- [ADR-0015: Observabilidad integral](./0015-integrated-observability-platform.md).
- [ADR-0018: Privacidad, retención y consentimiento](./0018-privacy-data-retention-legal-terms-and-cookie-consent.md).
- [Estándar general de arquitectura](../architecture/engineering-standard.md).

## Estado de implementación

**Decisión aceptada; no implementada.** No se han agregado bibliotecas, dependencias, validadores, middleware, DTO, contratos, endpoints, pruebas ni configuración. No se han modificado archivos SQL, migraciones, schemas, roles ni datos.
