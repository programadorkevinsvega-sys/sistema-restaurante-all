# ADR-0018: Privacidad, retención de datos, términos legales y consentimiento de cookies

- Estado: **Accepted**
- Aprobado: 2026-11-24
- Ámbito: tratamiento de datos personales y empresariales, documentación legal del servicio, retención y eliminación, tecnologías de seguimiento y preparación legal para el lanzamiento de Restaurant OS.
- Complementa: ADR-0001, ADR-0003, ADR-0008, ADR-0011, ADR-0014 y ADR-0015.
- Fase de ejecución: fase final de preparación para producción y lanzamiento, sin aplazar los controles técnicos y de privacidad que deben existir desde el diseño.

## Contexto

Restaurant OS será una plataforma SaaS multi-tenant que procesa información de propietarios, administradores, empleados, clientes finales, proveedores y otros usuarios. También manejará información empresarial, operativa, financiera, fiscal, de autenticación, seguridad, soporte y telemetría.

La plataforma tendrá superficies administrativas, públicas y de clientes, y podrá operar en más de una jurisdicción. Los datos no tienen todos el mismo propósito, propietario, sensibilidad, fundamento de tratamiento ni plazo de conservación. Una política única e indefinida sería insuficiente: puede llevar a conservar datos más tiempo del necesario, eliminar documentos que deben preservarse, reutilizar datos para finalidades incompatibles o confundir la responsabilidad del proveedor SaaS con la del tenant.

ADR-0014 ya establece que la baja de un tenant no elimina automáticamente perfiles, historial y documentos que pertenecen a sus clientes, y distingue esa operación de la eliminación individual solicitada por una persona. Este ADR desarrolla el marco general de privacidad y retención sin contradecir esa decisión.

La documentación legal no puede redactarse como un texto genérico que prometa cumplimiento universal. Los requisitos dependen de los países donde opere el servicio, de la ubicación y naturaleza de las personas afectadas, de los roles de las partes, de las finalidades y de los proveedores utilizados. Las versiones definitivas requieren revisión jurídica especializada antes de ofrecer el servicio en cada mercado.

## Decisión

### 1. Paquete legal obligatorio para el lanzamiento

Antes de habilitar el acceso productivo a clientes reales y abrir comercialmente el servicio, deberá existir y publicarse un paquete legal coherente, versionado, accesible y revisado para cada jurisdicción y modalidad de servicio aplicable:

1. **Política de privacidad:** explica quién trata los datos, qué categorías se recopilan, finalidades, roles, bases o fundamentos jurídicos aplicables, destinatarios, encargados y subencargados, transferencias internacionales, periodos o criterios de conservación, derechos de las personas, canales de contacto y mecanismos para ejercerlos.
2. **Política de retención y eliminación de datos:** define el ciclo de vida por categoría, finalidad y contexto, incluyendo conservación, bloqueo, anonimización, eliminación, excepciones legales y tratamiento de respaldos.
3. **Términos y condiciones del servicio:** regulan la relación contractual con los clientes SaaS y, cuando corresponda, los términos aplicables a usuarios finales. Deben cubrir como mínimo alcance del servicio, cuentas y autorizaciones, obligaciones de las partes, planes y pagos, uso permitido, propiedad intelectual, disponibilidad y soporte, integraciones, suspensión, terminación, exportación y devolución de datos, límites de responsabilidad y resolución de controversias, según validación jurídica.
4. **Acuerdo de tratamiento de datos (DPA) o anexo equivalente:** cuando la relación y la legislación aplicable lo requieran, define instrucciones, finalidades, confidencialidad, seguridad, asistencia en derechos, incidentes, subencargados, transferencias, auditoría y devolución/eliminación al terminar el servicio.
5. **Política de cookies y tecnologías similares:** describe tecnologías utilizadas en sitios y aplicaciones web, su finalidad, proveedor, duración, categoría y forma de gestionar preferencias.
6. **Banner y centro de preferencias de cookies:** permite informar y gestionar de manera clara las tecnologías no esenciales, cuando la normativa aplicable exija consentimiento u otra elección previa.
7. **Avisos complementarios:** avisos contextuales para formularios, registro, pagos, marketing, soporte, integraciones, analítica, grabaciones o funciones que recojan datos con finalidades específicas.

Los documentos deberán estar disponibles antes de que el usuario realice la acción a la que se refieren. No basta con publicar enlaces en el pie de página si la información o elección debe mostrarse en el punto de recopilación.

### 2. Roles de privacidad y responsabilidad por finalidad

No se asignará un único rol legal global a Restaurant OS para todos los datos.

- Para datos de cuenta, administración de la plataforma, contratación SaaS, facturación propia, seguridad y soporte, Restaurant OS determinará y documentará su rol conforme a la finalidad y a la legislación aplicable.
- Para datos de los clientes finales que un restaurante tenant incorpora al servicio, el tenant normalmente determinará las finalidades y medios esenciales de su relación con esas personas, mientras Restaurant OS procesará los datos siguiendo instrucciones documentadas cuando corresponda. La calificación concreta deberá validarse por actividad y jurisdicción.
- Puede haber tratamientos en los que Restaurant OS y el tenant actúen con roles distintos o independientes. No se presumirá que un DPA convierte todas las actividades en tratamiento por cuenta del tenant.
- Los contratos, avisos y flujos de derechos deben identificar quién responde por cada tratamiento y cómo se remiten o coordinan las solicitudes.

La documentación no debe transferir al usuario final responsabilidades que legalmente correspondan a otra parte ni presentar a Restaurant OS como responsable de decisiones que pertenecen al tenant.

### 3. Inventario, clasificación y minimización de datos

Cada módulo propietario deberá mantener identificadas las categorías de datos que trata, sus finalidades, sensibilidad, tenant/contexto, destinatarios, dependencias y reglas de ciclo de vida.

La clasificación deberá distinguir, como mínimo:

- Datos de cuenta e identidad.
- Datos de contacto y perfil de clientes finales.
- Datos de empleados y usuarios operativos.
- Datos empresariales, comerciales y de configuración del tenant.
- Datos de ventas, pagos, caja, contabilidad y facturación.
- Documentos sujetos a obligaciones fiscales, contables, contractuales o probatorias.
- Datos de autenticación, seguridad, prevención de fraude y auditoría.
- Preferencias, consentimientos y evidencia de elecciones.
- Logs, métricas, trazas y datos técnicos.
- Datos recibidos o compartidos por proveedores e integraciones.

Se recopilarán y conservarán solo los datos adecuados, pertinentes y necesarios para finalidades identificadas. No se utilizará el hecho de que un dato esté técnicamente disponible para justificar una finalidad nueva. Los usos secundarios, marketing, perfilado, analítica o entrenamiento de modelos requerirán análisis y fundamento propios; no se presumirá que están cubiertos por la aceptación de términos.

### 4. Política de retención y ciclo de vida

La política deberá establecer una matriz de retención por categoría y finalidad. Cada regla tendrá, como mínimo:

- Categoría y módulo propietario.
- Finalidad y fundamento aplicable.
- Responsable de la decisión de retención.
- Evento que inicia el plazo (por ejemplo, cierre de cuenta, fin de contrato, emisión del documento o última actividad relevante).
- Plazo concreto o criterio verificable, definido tras el análisis jurídico y operativo.
- Restricciones de acceso durante la conservación.
- Acción al vencer el plazo: eliminación, anonimización irreversible, agregación o conservación excepcional justificada.
- Dependencias, copias, exportaciones, proveedores y respaldos que deben tratarse.
- Excepciones por litigio, investigación, auditoría u obligación legal (legal hold), con alcance, responsable y revisión.
- Evidencia de ejecución y resultado.

No se establecerán plazos universales ni retención indefinida por comodidad técnica. Cuando un documento deba conservarse por una obligación legal, se limitará el acceso y el uso a lo necesario para esa obligación. La retención de facturas y registros sujetos a conservación deberá mantener integridad, autenticidad y trazabilidad, conforme a ADR-0014.

La expiración de una copia de respaldo puede ocurrir según su ciclo técnico y no debe confundirse con la disponibilidad inmediata de eliminación en cada soporte. El diseño deberá documentar cómo se propagan las solicitudes de eliminación, cómo se evita restaurar datos ya eliminados y cómo vencen las copias dentro de sus ciclos definidos.

### 5. Derechos y solicitudes de las personas

Antes del lanzamiento se definirán canales, responsables, verificación de identidad, alcance, plazos legales aplicables, trazabilidad y procedimientos para solicitudes de acceso, consulta, rectificación, actualización, oposición, portabilidad, limitación, retiro de consentimiento y eliminación, según los derechos reconocidos en cada jurisdicción.

Las solicitudes se enrutarán al módulo y a la parte que tenga ownership y responsabilidad sobre el tratamiento. Una solicitud no autoriza a un módulo a consultar o modificar directamente el schema de otro.

El procedimiento deberá contemplar:

- Solicitudes relacionadas con una cuenta de plataforma.
- Solicitudes sobre datos que un tenant administra de sus propios clientes.
- Solicitudes que afecten a varias relaciones o tenants.
- Verificación de identidad y prevención de divulgación a terceros.
- Excepciones justificadas por obligaciones legales, defensa de reclamaciones o conservación documental.
- Respuesta motivada cuando no proceda una eliminación total.
- Registro mínimo de la solicitud y de su resolución.

La eliminación individual de un cliente será distinta de la baja del tenant. Se respetará ADR-0014: la baja del tenant no elimina automáticamente datos de clientes ni documentos que deban conservarse. Este ADR no autoriza borrar facturas, evidencias o registros legalmente retenibles.

### 6. Cookies y tecnologías similares

La política y el gestor de preferencias deberán clasificar las tecnologías según su propósito y los requisitos de cada jurisdicción. Como mínimo, se evaluarán:

- **Estrictamente necesarias:** autenticación, seguridad, balanceo, protección de sesión y funciones solicitadas indispensables.
- **Preferencias:** recordar idioma, región u opciones elegidas.
- **Analítica y medición:** comprender uso y rendimiento.
- **Publicidad, marketing o seguimiento entre sitios:** cuando exista esa finalidad.

Reglas de diseño:

1. No se activarán cookies ni tecnologías no esenciales antes de obtener la elección válida cuando la legislación aplicable requiera consentimiento previo.
2. Las tecnologías estrictamente necesarias no se utilizarán para finalidades secundarias de analítica o publicidad.
3. Cuando sea obligatorio ofrecer consentimiento, el usuario podrá aceptar o rechazar las categorías no esenciales con claridad y facilidad comparable; no se ocultará el rechazo ni se utilizarán patrones engañosos.
4. La elección será granular por categoría cuando corresponda, informada, demostrable y revocable.
5. El centro de preferencias permanecerá accesible después de cerrar el banner para revisar o retirar elecciones.
6. La revocación detendrá nuevas operaciones no esenciales y actualizará los controles del navegador o aplicación según sea técnicamente posible; no se afirmará que puede retirar datos ya anonimizados o tratamientos anteriores lícitos.
7. Se registrará la versión del aviso, fecha/hora, categorías elegidas, estado y contexto mínimo necesario para demostrar la elección. No se registrarán más identificadores o datos que los necesarios.
8. Las tecnologías, proveedores, dominios, duración, transferencias y cambios de configuración se mantendrán en un inventario actualizado.
9. El banner será accesible, comprensible, adaptable a dispositivos y disponible en los idiomas soportados por el producto.
10. La obligación y el diseño de banner se evaluarán por superficie. Una aplicación nativa no se describirá automáticamente como si utilizara cookies web; se analizarán también SDKs y tecnologías equivalentes.

La aceptación de términos, la lectura de la política de privacidad y el consentimiento para cookies son actos distintos. No se agruparán en una casilla genérica ni se inferirá consentimiento de navegación, silencio o aceptación contractual.

### 7. Consentimientos, preferencias y comunicaciones

Los consentimientos que sean necesarios se solicitarán de forma específica por finalidad, separados de la aceptación contractual cuando corresponda. Se deberá poder demostrar qué se solicitó, qué versión se mostró, qué elección se realizó y cuándo, además de permitir su retiro.

Las comunicaciones comerciales, campañas, encuestas y canales como correo, SMS o mensajería tendrán controles de preferencias y exclusión según la normativa aplicable. El consentimiento para marketing no será condición automática para prestar el servicio principal.

Los registros de consentimiento y preferencias permanecerán bajo ownership del módulo responsable del tratamiento. No se crea una tabla compartida ni se modifica el ownership de módulos establecido en ADR-0001 y ADR-0008.

### 8. Proveedores, subencargados y transferencias

Antes de producción deberá existir un inventario de proveedores que reciban o puedan acceder a datos: alojamiento, correo, mensajería, analítica, pagos, soporte, monitoreo, IA, almacenamiento, copias de seguridad y demás integraciones.

Para cada proveedor se documentarán finalidad, categorías de datos, ubicación, rol, controles de seguridad, subencargados, retención, transferencias internacionales, contrato aplicable y procedimiento de terminación. La publicación de una lista de subencargados y los mecanismos de notificación o impugnación se ajustarán a los contratos y jurisdicciones aplicables.

No se enviarán datos personales a un proveedor nuevo ni se habilitará una integración productiva sin evaluación de privacidad, seguridad, finalidad, minimización y condiciones contractuales.

### 9. Seguridad, incidentes y auditoría

La privacidad se apoyará en los controles de seguridad ya definidos: mínimo privilegio, aislamiento multi-tenant, cifrado en tránsito y en reposo donde corresponda, gestión de secretos, control de acceso, trazabilidad y protección de respaldos.

Antes del lanzamiento deberán existir procedimientos documentados para detectar, evaluar, contener, investigar y responder a incidentes que afecten datos personales; determinar si existe obligación de notificación, a quién y dentro de qué plazo; preservar evidencias; coordinar al tenant cuando corresponda; y documentar decisiones y comunicaciones.

Los logs, métricas y trazas deberán seguir ADR-0015: no incluir contraseñas, tokens, payloads personales sensibles ni documentos completos. La retención de telemetría tendrá su propia finalidad y plazo, sin convertirse en un repositorio paralelo de datos de negocio.

### 10. Fase final obligatoria y condición de salida a producción

La preparación y aprobación del paquete legal definitivo se ubica en la **última fase del plan maestro, inmediatamente antes del lanzamiento productivo y comercial**. Esta fase no reemplaza las fases funcionales ni cambia el orden de construcción de módulos.

En esa fase se deberá:

1. Confirmar los países, mercados, tipos de cliente y superficies que se habilitarán en el lanzamiento.
2. Completar el inventario de tratamientos, datos, proveedores, transferencias y tecnologías de seguimiento reales.
3. Cerrar la matriz de retención y eliminación con plazos o criterios validados jurídicamente.
4. Preparar y publicar las versiones definitivas de privacidad, retención, términos, DPA cuando aplique y política de cookies.
5. Configurar el banner y centro de preferencias con comportamiento probado en todos los sitios y aplicaciones web incluidos.
6. Verificar los flujos de aceptación, consentimiento, retiro, derechos, baja de cuenta, baja de tenant y legal hold.
7. Obtener revisión y aprobación de asesoría jurídica competente para cada jurisdicción de lanzamiento, además de aprobación del responsable del producto y negocio.
8. Verificar que contratos, avisos, interfaz, SDKs, proveedores y comportamiento real coincidan; no publicar promesas que el producto no cumple.
9. Ejecutar pruebas de privacidad y seguridad, revisar accesibilidad e idiomas, y conservar evidencia de la validación.
10. Incorporar los documentos y controles en el checklist formal de Go/No-Go.

**No se autorizará el lanzamiento productivo para una jurisdicción o modalidad de servicio si falta documentación legal aplicable, revisión jurídica, configuración de consentimiento exigible, matriz de retención aprobada o procedimientos operativos de derechos e incidentes.** La aprobación para un mercado no implica autorización automática para otros mercados.

Esta ubicación final se refiere a la finalización, revisión jurídica, publicación y activación de los documentos y flujos definitivos. No permite posponer hasta el lanzamiento el diseño de privacidad, minimización, aislamiento, seguridad, auditoría, registro de consentimientos requeridos o capacidades de eliminación que deban construirse y probarse durante las fases anteriores.

### 11. Límites y decisiones que no se fijan en este ADR

Este ADR no determina:

- Países o jurisdicciones definitivas de lanzamiento.
- Plazos numéricos de retención por tipo de dato.
- Una base jurídica universal para todos los tratamientos.
- El texto legal definitivo de políticas, contratos o avisos.
- Si una tecnología específica requiere consentimiento en todos los mercados.
- Proveedores, cookies, SDKs, dominios o herramientas que aún no estén seleccionados.
- El procedimiento legal final para cada derecho en cada jurisdicción.
- Un módulo, schema, tabla compartida o arquitectura de persistencia nueva.
- Cambios a SQL, migraciones, contratos ejecutables o código.

Esos elementos se concretarán con el inventario real del producto, los mercados confirmados y revisión jurídica. Cualquier decisión técnica que cambie ownership, persistencia o arquitectura deberá respetar los ADR vigentes y, si corresponde, tramitar un ADR específico.

## Alternativas consideradas

### Redactar una política genérica y usarla en todos los países

**Rechazada.** No refleja necesariamente las diferencias de jurisdicción, roles, finalidades, transferencias, derechos y plazos.

### Posponer toda privacidad y retención hasta la última fase

**Rechazada.** La publicación final de documentos sí pertenece a la fase de lanzamiento, pero la minimización, seguridad, aislamiento, consentimiento cuando aplique, trazabilidad y diseño del ciclo de vida deben existir desde las fases que procesan los datos.

### Usar una sola aceptación para términos, privacidad y cookies

**Rechazada.** Son decisiones y obligaciones distintas; agruparlas impide una elección clara y demostrable.

### Conservar todos los datos indefinidamente para evitar errores

**Rechazada.** Incrementa exposición, costo y riesgo, y contradice la minimización y las reglas de conservación limitada.

### Eliminar automáticamente todo al cerrar un tenant

**Rechazada.** Contradice ADR-0014 y puede destruir perfiles de clientes y documentos que deban conservarse.

## Consecuencias

- El lanzamiento se convierte en una puerta formal de cumplimiento legal y privacidad, con evidencia verificable.
- Las políticas finales reflejarán el producto y proveedores realmente habilitados, no funcionalidades hipotéticas.
- Los periodos de retención se decidirán por categoría, finalidad y jurisdicción, no mediante un valor global.
- Los consentimientos y preferencias serán diferenciados, demostrables y revocables cuando corresponda.
- Los módulos conservan ownership de los datos y registros que administran.
- La fase final no exime de implementar controles técnicos de privacidad desde el diseño.
- No se considera que las políticas, banners, mecanismos de consentimiento, procesos de derechos o controles estén implementados por la creación o aceptación de este ADR.

## Referencias

- [ADR-0001: Ownership PostgreSQL y migraciones por módulo](./0001-postgres-module-ownership-and-migrations.md).
- [ADR-0003: Stateless, Outbox/Inbox y coordinación de jobs](./0003-stateless-outbox-inbox-and-jobs.md).
- [ADR-0008: Distribución de módulos entre los cuatro procesos](./0008-module-ownership-across-four-processes.md).
- [ADR-0011: Protección de contraseñas y controles de autenticación](./0011-password-hashing-and-authentication-security.md).
- [ADR-0014: Baja de tenants y conservación de datos de clientes](./0014-tenant-deletion-and-customer-data-preservation.md).
- [ADR-0015: Observabilidad integral de aplicaciones e infraestructura](./0015-integrated-observability-platform.md).
- [Roadmap](../../ROADMAP.md).

## Estado de implementación

**ADR aceptado; no implementado.** Este documento establece una decisión arquitectónica y una condición futura de lanzamiento. No se han redactado ni aprobado textos legales definitivos, no se ha contratado asesoría jurídica, no se han configurado banners o gestores de consentimiento, no se han creado tablas, schemas, contratos, endpoints ni código, y no se han modificado archivos SQL o migraciones.
