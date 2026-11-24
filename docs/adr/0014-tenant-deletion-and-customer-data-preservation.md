# ADR-0014: Baja de tenants y conservación de datos de clientes

- Estado: **Proposed**
- Propuesto: 2026-11-24
- Aprobación: pendiente de aprobación explícita del propietario del producto.
- Complementa: ADR-0001, ADR-0003, ADR-0008 y ADR-0013.
- Ámbito: eliminación de un tenant SaaS y tratamiento de los datos de clientes asociados a ese tenant.

## Contexto

Restaurant OS es una plataforma SaaS multi-tenant. Un tenant puede operar restaurantes, sucursales y otros recursos empresariales, y mantener relaciones con clientes finales que utilizan sus servicios.

La baja de un tenant no debe confundirse con la eliminación de las cuentas o los datos de las personas que fueron sus clientes. Una persona puede haber comprado en distintos momentos, conservar un perfil, necesitar consultar su historial o necesitar sus facturas aunque el restaurante deje de utilizar Restaurant OS.

Un borrado en cascada desde el tenant podría eliminar accidentalmente perfiles, historial y documentos que pertenecen o son necesarios para los clientes. También podría destruir registros que deben conservarse por obligaciones legales, fiscales, contables o probatorias. Además, eliminar millones de registros mediante una única transacción prolongada puede mantener locks, consumir conexiones y provocar una saturación agravada por reintentos concurrentes.

ADR-0001 establece ownership exclusivo por módulo: cada módulo conserva su schema, rol, migraciones e historial SQLx. ADR-0003 establece trabajo durable, lotes acotados, checkpoints, idempotencia, recuperación y backpressure. La baja debe respetar esas decisiones.

## Decisión propuesta

### 1. La baja del tenant no elimina los datos de sus clientes

1. Eliminar un tenant **no implica eliminar los clientes finales asociados a él**.
2. La baja del tenant no debe borrar ni invalidar el perfil del cliente, su identidad de cliente, su historial personal de actividad/relación ni los documentos que deba conservar, incluyendo sus facturas.
3. La eliminación del tenant afecta a los datos y recursos que pertenecen al tenant como organización usuaria de la plataforma; no convierte los datos del cliente final en datos descartables del tenant.
4. Los datos del cliente que deban permanecer disponibles para él se conservarán bajo el ownership del módulo que los administra. No se trasladará su propiedad a PLATFORM ni se creará una tabla compartida para conservarlos.
5. La conservación no concede acceso automático a otros tenants. Los datos preservados seguirán sujetos a autorización, aislamiento entre tenants y controles de privacidad. La baja de un tenant no habilita que otro tenant consulte perfiles, historial o facturas de sus clientes.

### 2. Datos propios del tenant que sí entran en la baja

La operación de baja deberá identificar y eliminar, desactivar o retirar del servicio los recursos que pertenecen exclusivamente al tenant, según su naturaleza y las obligaciones aplicables. Esto incluye, cuando corresponda, su configuración empresarial y operativa, sucursales, preferencias, catálogo y datos de operación, credenciales de integraciones, secretos, archivos y demás recursos propios.

La clasificación exacta se realizará por módulo propietario. Ningún coordinador podrá borrar directamente tablas de otros módulos ni utilizar cascadas entre schemas para ejecutar la baja.

### 3. Perfiles, historial y facturas de clientes

1. Los perfiles de clientes finales se conservan aunque el tenant que originó la relación sea eliminado.
2. El historial que pertenece al cliente y sea necesario para su consulta o continuidad se conserva. La baja del tenant no debe borrar compras, interacciones o antecedentes personales del cliente por el solo hecho de que estuvieran relacionados con ese tenant.
3. Las facturas y documentos emitidos que deban conservarse para el cliente o por obligaciones legales, fiscales, contables o probatorias se preservan con su integridad, autenticidad, trazabilidad y referencias necesarias.
4. Cuando una obligación legal exija conservar información del tenant, de la operación o del documento, esa información se mantiene durante el plazo aplicable, con acceso restringido y sin mantener activo al tenant ni sus credenciales.
5. La baja no debe alterar retroactivamente el contenido de facturas, documentos fiscales, registros contables ni evidencias que deban permanecer íntegros.
6. La conservación de una copia o registro para el cliente no implica que el tenant eliminado conserve acceso a la plataforma ni que sus usuarios puedan seguir operando.

### 4. Separación entre datos del tenant y datos del cliente

Cada módulo debe clasificar los datos que administra, al menos, en estas categorías conceptuales:

- **Datos propios del tenant:** recursos, configuración y operación que pertenecen a la organización usuaria y que pueden eliminarse o retirarse conforme a la política de baja.
- **Datos propios del cliente final:** perfil, identidad de cliente e historial que deben sobrevivir a la baja del tenant.
- **Documentos y registros sujetos a conservación:** facturas y evidencias cuya conservación prevalece sobre la eliminación ordinaria mientras exista una obligación o necesidad legítima aplicable.
- **Referencias y trazabilidad:** identificadores y relaciones mínimos necesarios para conservar integridad, auditoría y explicación histórica, sin mantener datos personales innecesarios.

La clasificación debe evitar tanto el borrado accidental de datos del cliente como la conservación indiscriminada de todos los datos del tenant. Cuando un registro mezcle información del tenant y del cliente, el módulo propietario deberá definir cómo separar, restringir, anonimizar o conservar sus componentes sin destruir el documento o historial que deba preservarse.

### 5. Ejecución segura y recuperable

La baja se ejecutará como un proceso durable, no como un único `DELETE` masivo ni como una cascada global.

El diseño de implementación deberá contemplar:

- Una operación de baja identificable y única por tenant, con estado consultable.
- Idempotencia: solicitudes repetidas para la misma baja no crean procesos destructivos paralelos.
- Protección contra nuevas operaciones incompatibles mientras la baja avanza, sin bloquear innecesariamente los datos de clientes que deben seguir disponibles.
- Participación de cada módulo mediante sus contratos públicos; cada módulo modifica exclusivamente sus propios datos.
- Lotes acotados, transacciones locales breves y checkpoints persistentes.
- Límites de concurrencia, backpressure y prioridad inferior al tráfico normal.
- Reintentos limitados con backoff y jitter; los reintentos no deben mantener conexiones esperando locks de una transacción masiva.
- Recuperación tras reinicios, deduplicación y reconciliación de resultados inciertos.
- Auditoría de la solicitud, actor autorizado, alcance, decisiones de conservación, resultados y excepciones.
- Verificación final de que los datos propios del tenant fueron tratados y de que los datos de clientes y documentos sujetos a conservación permanecen íntegros.

La coordinación multi-módulo debe respetar el ownership y los mecanismos durables aceptados en el repositorio. La aplicación concreta de Sagas se sujetará al estado de ADR-0013 y a su aceptación formal; este ADR no declara aceptado ADR-0013.

### 6. Acceso y seguridad después de la baja

- La baja revoca el acceso operativo del tenant y las credenciales, sesiones, integraciones y secretos que le pertenecen.
- La conservación de datos de clientes o documentos no mantiene activas las cuentas administrativas del tenant.
- Los datos retenidos por obligación legal o para consulta del cliente tendrán acceso limitado a los actores autorizados y durante el tiempo necesario.
- Los datos conservados no podrán reutilizarse para otros fines incompatibles con el propósito de conservación.
- Los logs, métricas y trazas no deben copiar perfiles, facturas completas, secretos ni datos personales innecesarios.

### 7. Límites de esta decisión

Este ADR define qué debe sobrevivir a la baja de un tenant. No define por sí solo:

- El procedimiento para que un cliente final solicite la eliminación de su propio perfil o datos.
- La eliminación de una identidad de usuario de IDENTITY ni sus membresías en otros tenants.
- Los plazos legales concretos de conservación por país, tipo de factura o documento.
- Los plazos de espera, periodo de gracia, cancelación o reversibilidad de una baja.
- El modelo físico de almacenamiento, tablas, columnas, FKs, políticas RLS, migraciones o contratos ejecutables.
- El detalle de anonimización de cada categoría de datos.

Esos aspectos requieren análisis y decisiones específicas, sin contradecir la regla de que la baja de un tenant no elimina los datos que pertenecen a sus clientes.

## Alternativas consideradas

### Borrar en cascada todos los registros relacionados con el tenant

**Rechazada.** Puede eliminar perfiles, historial y facturas de clientes que no solicitaron la eliminación, además de registros sujetos a conservación. También puede provocar transacciones enormes, locks prolongados y agotamiento del pool por reintentos.

### Conservar todos los datos del tenant indefinidamente

**Rechazada.** Confunde la preservación de datos del cliente con la retención indiscriminada de datos empresariales del tenant. La conservación debe limitarse a los datos del cliente y a los registros que tengan una razón válida para mantenerse.

### Un proceso central que borra directamente todos los schemas

**Rechazada.** Rompe el ownership por módulo, sus roles y sus historiales independientes establecidos por ADR-0001.

## Consecuencias

Si se acepta:

- La baja de un tenant y la eliminación de un cliente serán procesos distintos.
- Los perfiles e historiales de clientes finales no desaparecerán como efecto colateral de la baja del tenant.
- Las facturas y documentos sujetos a conservación mantendrán integridad y trazabilidad.
- Los módulos deberán distinguir datos del tenant, datos del cliente y registros sujetos a conservación.
- La baja será un proceso durable, acotado, idempotente y recuperable.
- La operación deberá preservar el aislamiento entre tenants incluso después de la baja.
- No se autoriza modificar SQL, migraciones ni implementar el proceso por aceptar este ADR.

## Referencias

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](./0001-postgres-module-ownership-and-migrations.md).
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](./0003-stateless-outbox-inbox-and-jobs.md).
- [ADR-0008: Distribución de módulos entre los cuatro procesos](./0008-module-ownership-across-four-processes.md).
- [ADR-0013: Consistencia distribuida y transacciones de negocio entre módulos](./0013-distributed-transactions-and-saga-consistency.md).
- [Requisitos generales](../../requisitos.md).

## Estado de implementación

**Propuesta documental; pendiente de aprobación explícita.** No se han creado tablas, schemas, contratos ejecutables, workers ni código. No se han modificado archivos SQL o migraciones ni se han ejecutado operaciones de base de datos.
