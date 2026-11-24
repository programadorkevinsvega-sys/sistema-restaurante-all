# Estrategia técnica de identificadores UUIDv7 y PostgreSQL

**Estado:** propuesta técnica vinculada a [ADR-0012](../adr/0012-uuid-v7-global-identifiers-and-postgresql.md); no es una política vigente hasta la aceptación del ADR.  
**Ámbito:** los cuatro procesos y todos los módulos de Restaurant OS.  
**Base técnica inicial:** PostgreSQL 19.0, versión estable publicada el 19 de noviembre de 2026.

## 1. Objetivo

Definir cómo debe entenderse y aplicarse la política aceptada de identificadores técnicos UUIDv7, qué beneficios se esperan, qué información puede revelar y qué condiciones deben cumplirse antes de migrar identificadores existentes.

La especificación no representa implementación. No modifica SQL, migraciones, datos, código, dependencias ni contratos ejecutables.

## 2. Alcance de identificadores

La política propuesta cubre identificadores técnicos de entidades y recursos: claves primarias, referencias relacionales dentro del módulo propietario, IDs intercambiados mediante contratos entre módulos/procesos, identificadores de eventos y referencias técnicas equivalentes.

Incluye identificadores técnicos existentes, aunque hoy sean UUIDv4 u otra versión UUID. También incluye identificadores sustitutos técnicos existentes basados en enteros cuando identifiquen entidades o recursos: su convergencia futura deberá ser planificada.

No cubre códigos de negocio con semántica propia, como SKU, folios fiscales, números visibles de pedido o factura, códigos de barras, números de serie comerciales ni otros valores que el negocio deba conservar por regulación, interoperabilidad o lectura humana.

Cada módulo conserva ownership exclusivo de sus entidades y datos. La política UUID no cambia schemas, roles, migraciones, historiales SQLx ni fronteras de módulos.

## 3. UUIDv4 y UUIDv7

| Propiedad | UUIDv4 | UUIDv7 |
|---|---|---|
| Construcción | Bits predominantemente aleatorios | Timestamp Unix en milisegundos en bits más significativos y bits restantes definidos por RFC 9562 |
| Orden temporal | No ofrece orden temporal | Los valores tienden a ordenarse según el instante de generación |
| Localidad B-tree | Inserciones pueden dispersarse por distintas páginas | Inserciones cronológicas tienden a concentrarse en páginas próximas |
| Información temporal | No codifica un timestamp de generación | Permite inferir aproximadamente el instante de generación |
| Uso propuesto | No será estándar para nuevos IDs técnicos | Estándar global para IDs técnicos |

UUIDv7 puede mejorar la localidad de inserción y el comportamiento de caché de índices B-tree respecto de UUIDv4 aleatorios. El resultado real depende de la carga, concurrencia, distribución de generación, patrón de escrituras, tamaño del índice y configuración de PostgreSQL; debe medirse con pruebas representativas.

### 3.1 Corrección de una simplificación habitual

No es correcto afirmar que un índice PostgreSQL con UUIDv4 debe estar completamente en memoria. PostgreSQL gestiona los índices mediante páginas y mecanismos de caché. La diferencia relevante es que inserciones aleatorias pueden requerir acceder y modificar páginas más dispersas, mientras que identificadores temporalmente ordenados tienden a mejorar la localidad.

UUIDv7 tampoco garantiza que cada inserción ocurra literalmente en la última página del índice. La concurrencia, los relojes de distintas instancias, los valores generados fuera de orden y el mantenimiento del índice pueden alterar el patrón.

## 4. PostgreSQL y generación nativa

PostgreSQL utiliza el tipo nativo `uuid` para almacenar identificadores UUID de distintas versiones. PostgreSQL 18 incorporó la función `uuidv7()`; PostgreSQL 19 la documenta como generador UUID versión 7. La función incorpora timestamp Unix con precisión de milisegundos, fracción submilisegundo y bits aleatorios.

La versión objetivo inicial propuesta es PostgreSQL 19.0. El proyecto debe mantener una política de actualización a la última versión mayor estable aprobada y sus actualizaciones menores/de seguridad, después de comprobar compatibilidad del stack.

La función nativa no determina por sí sola que todas las entidades deban generar su ID en SQL. Cada diseño de módulo deberá decidir la autoridad de generación para su flujo:

- Generación en PostgreSQL cuando la entidad se crea dentro de una operación de persistencia y el ID no se necesita antes del INSERT.
- Generación en aplicación cuando el ID deba existir antes de persistir, viajar por varios procesos o participar en un flujo distribuido previo a la escritura, usando un generador UUIDv7 compatible con RFC 9562.
- Evitar que dos capas generen y reemplacen el identificador de una misma entidad sin una regla explícita.

La elección concreta debe quedar documentada por módulo/caso de uso y validada contra PostgreSQL, SQLx y los contratos existentes. No se añade aquí una dependencia de generación ni se modifica un default SQL.

## 5. Orden temporal y semántica

UUIDv7 es aproximadamente ordenable por tiempo de generación, pero no es un reloj global ni una secuencia transaccional.

No usar UUIDv7 para:
- sustituir `created_at` o `updated_at`;
- decidir el orden legal, comercial o contable de operaciones;
- demostrar precedencia causal entre eventos;
- sustituir secuencias o folios de negocio;
- resolver conflictos de concurrencia por sí solo.

Si una operación necesita orden estricto, se modelará mediante un atributo, versión, secuencia o mecanismo de coordinación explícito y bajo el ownership correspondiente.

## 6. Exposición y protección de recursos

### 6.1 Riesgo temporal

La parte temporal de UUIDv7 permite inferir el momento aproximado en que se generó. Si el identificador aparece en una URL, respuesta API, log o integración, esa información puede quedar observable.

Esta característica no revela automáticamente el contenido del recurso ni el volumen total del sistema, pero puede facilitar correlaciones temporales. Se debe evitar publicar IDs innecesariamente en métricas o superficies públicas.

### 6.2 No cifrar todos los identificadores

No se aplicará cifrado general a UUIDv7 para presentarlos en interfaces o APIs.

- Hexadecimal y Base64 son representaciones/codificaciones, no cifrado.
- El cifrado determinista o reversible requiere gestión de claves y puede introducir complejidad de rotación, búsqueda, compatibilidad y correlación.
- Un UUID no debe considerarse secreto ni funcionar como capacidad de acceso.

Si un caso de uso necesita una referencia externa que no revele el ID interno, el módulo propietario puede definir un token opaco independiente, generado con aleatoriedad criptográfica suficiente. Debe tener unicidad, resolución, alcance, ciclo de vida y revocación definidos. La referencia opaca no reemplaza el UUIDv7 interno y no se crea automáticamente para todos los recursos.

### 6.3 Autorización obligatoria

Toda solicitud que utilice un identificador debe comprobar:
1. identidad y autenticación del actor;
2. permiso para la acción solicitada;
3. tenant, organización y alcance del recurso;
4. ownership del módulo que resuelve la operación.

Conocer un UUIDv7 o una referencia opaca no concede acceso. Los controles deben residir en el backend y en el módulo propietario, nunca exclusivamente en el frontend o BFF.

## 7. Migración futura de identificadores existentes

La convergencia de IDs existentes no debe ejecutarse como reemplazo directo de valores sin un inventario de dependencias.

### 7.1 Descubrimiento obligatorio

Por módulo, inventariar:
- PK, FK, constraints, índices, secuencias y columnas que contienen referencias.
- Referencias almacenadas en JSON/JSONB, Outbox, Inbox, auditoría, eventos y proyecciones.
- IDs incluidos en APIs, Protobuf, OpenAPI, webhooks, integraciones, exportaciones y archivos.
- Datos consumidos por otros módulos, procesos o sistemas externos.
- Jobs, claves de idempotencia, deduplicación y relaciones históricas que dependan del ID.

### 7.2 Estrategia de transición

El plan de migración de cada módulo debe decidir, con pruebas y análisis de compatibilidad, cómo:
- crear un mapeo inequívoco de ID anterior a UUIDv7;
- preservar relaciones y unicidad durante la coexistencia;
- propagar referencias nuevas a consumidores sin romper versiones activas;
- hacer backfill y validar que no queden referencias huérfanas;
- cambiar escrituras y lecturas de forma coordinada;
- tratar eventos y mensajes que aún contengan identificadores anteriores;
- actualizar integraciones externas y referencias ya emitidas;
- retirar los IDs anteriores únicamente cuando no queden consumidores dependientes;
- recuperar o revertir el despliegue sin perder correspondencias ni integridad.

No se impone aquí una técnica única de migración. El patrón dependerá del esquema, volumen, relaciones, disponibilidad requerida y compatibilidad de consumidores. No reescribir migraciones históricas ya aplicadas.

### 7.3 Aislamiento por módulo

Cada módulo realizará sus cambios bajo su propio ownership, schema, rol, directorio de migraciones e historial SQLx. No se crearán FKs ni consultas directas entre schemas de módulos distintos para facilitar la transición. Las referencias entre módulos seguirán usando contratos y los IDs definidos por los módulos propietarios.

Cualquier cambio SQL o ejecución de migración requerirá autorización expresa y una tarea separada. Este documento no concede esa autorización.

## 8. Validaciones requeridas antes de implementar

Antes de adoptar la política en código:
- confirmar la versión PostgreSQL y compatibilidad real del entorno;
- comprobar la función `uuidv7()` en el servidor objetivo si se pretende usarla;
- fijar y probar la biblioteca/generador UUIDv7 si se genera desde aplicación;
- verificar que todos los valores generados cumplen RFC 9562 y que se rechazan versiones no permitidas donde corresponda;
- medir inserciones y lecturas en índices B-tree con datos y concurrencia representativos;
- probar generación concurrente desde varias instancias y comportamiento ante relojes desincronizados;
- revisar contratos HTTP/gRPC/eventos y consumidores;
- completar pruebas de integridad, backfill, compatibilidad, rollback y recuperación para cada migración.

## 9. Referencias

- [ADR-0012: UUID versión 7 como identificador técnico global y PostgreSQL estable actual](../adr/0012-uuid-v7-global-identifiers-and-postgresql.md)
- [RFC 9562 — Universally Unique IDentifiers (UUIDs)](https://www.rfc-editor.org/rfc/rfc9562.html)
- [PostgreSQL 19 — UUID Type](https://www.postgresql.org/docs/19/datatype-uuid.html)
- [PostgreSQL 19 — UUID Functions](https://www.postgresql.org/docs/19/functions-uuid.html)
- [PostgreSQL 19 — Release 19](https://www.postgresql.org/docs/19/release-19.html)

## 10. Estado

**Propuesta técnica; pendiente de aprobación de ADR-0012.** No hay generación UUIDv7 implementada por este documento. No se han modificado archivos SQL, migraciones, datos, código, dependencias ni configuración de ejecución.
