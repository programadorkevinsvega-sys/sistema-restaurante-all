# ADR-0018: Privacidad, protección de datos, retención y cumplimiento legal antes del lanzamiento

- Estado: **Proposed**
- Propuesto: 2026-11-24
- Aprobación: pendiente de revisión explícita del propietario del producto.
- Complementa: ADR-0001, ADR-0003, ADR-0008, ADR-0011, ADR-0014, ADR-0015 y ADR-0016.
- Ámbito: tratamiento de datos personales y no personales sujetos a obligaciones de privacidad, documentos legales del servicio, conservación y eliminación, tecnologías de almacenamiento local y cookies, y preparación para el lanzamiento de Restaurant OS.

## Contexto

Restaurant OS será una plataforma SaaS multi-tenant que puede tratar datos de representantes y usuarios de empresas clientes, empleados, proveedores, clientes finales de restaurantes, visitantes de sitios y portales, y personas que interactúen con canales digitales. Los datos pueden circular por los cuatro procesos, módulos propietarios, proveedores externos, almacenamiento, observabilidad, mensajería, caché, copias de seguridad y herramientas de soporte.

El cumplimiento no se resuelve publicando una única política genérica. La plataforma debe poder explicar qué datos trata, para qué finalidad, bajo qué rol y fundamento aplicable, quién accede a ellos, a quién se comunican, dónde se procesan, durante cuánto tiempo se conservan y cómo se atienden los derechos de las personas.

La relación SaaS también exige distinguir los tratamientos en los que el operador de Restaurant OS actúa como responsable independiente (por ejemplo, administración de cuentas SaaS, facturación propia, seguridad y cumplimiento) de aquellos en los que actúa como encargado/procesador siguiendo instrucciones del tenant. La calificación depende del tratamiento real y de la legislación aplicable; no se asignará un único rol contractual a todos los datos.

ADR-0014 ya determina que la baja de un tenant no elimina automáticamente los perfiles, historial ni facturas que pertenecen a sus clientes finales. Esta decisión debe convivir con los derechos individuales de las personas, los plazos legales de conservación y las obligaciones de eliminación, restricción o anonimización. La conservación no puede convertirse en retención ilimitada ni en acceso cruzado entre tenants.

La plataforma necesita términos contractuales claros para clientes SaaS y, cuando existan canales de interacción directa, condiciones apropiadas para usuarios finales. También debe informar y gestionar cookies y tecnologías similares de forma compatible con los territorios en los que opere.

La jurisdicción de lanzamiento, las entidades legales operadoras, las categorías exactas de datos, los proveedores, los flujos internacionales y las finalidades comerciales aún deben concretarse antes de publicar documentos jurídicos. Por tanto, este ADR establece principios técnicos y una puerta obligatoria de preparación preproducción; no pretende sustituir el análisis ni la aprobación de asesoría jurídica competente.

## Decisión propuesta

### 1. Privacidad desde el diseño y responsabilidad por tratamiento

1. La privacidad y la protección de datos son requisitos transversales de producto, arquitectura, seguridad, operación y contratación; no se limitan a una página legal ni a una tarea de frontend.
2. Antes de habilitar cada tratamiento se documentarán, como mínimo: finalidad específica, categorías de personas y datos, origen, rol de Restaurant OS y del tenant, fundamento jurídico aplicable, destinatarios/proveedores, ubicación y transferencias, controles, plazo o criterio de conservación y mecanismo para atender derechos.
3. Se aplicarán minimización de datos, limitación de finalidad, acceso por necesidad, exactitud, protección desde el diseño y por defecto, separación de tenants y conservación limitada.
4. No se recopilarán campos, identificadores, telemetría ni atributos personales solo porque puedan resultar útiles en el futuro. Cada dato debe tener una finalidad definida y un responsable.
5. No se reutilizarán datos de un tenant para beneficiar a otro tenant ni para finalidades propias incompatibles. Los usos agregados o analíticos deberán evaluar riesgo de reidentificación y aplicar controles adecuados.
6. La información personal no se incluirá por defecto en logs, trazas, métricas, mensajes, claves de caché, nombres de archivos, URLs ni etiquetas de observabilidad. Cualquier excepción requerirá necesidad documentada, minimización, acceso restringido y retención específica.
7. Los datos enviados a proveedores externos, incluidos proveedores de IA, analítica, mensajería, pagos, soporte o almacenamiento, requieren finalidad autorizada, evaluación del proveedor, contrato apropiado, instrucciones, controles de seguridad y análisis de transferencias cuando aplique. No se enviarán datos personales a un proveedor por mera conveniencia técnica.
8. Se mantendrá un inventario de tratamientos y un registro de proveedores/subencargados, incluyendo servicios, categorías de datos, finalidad, ubicación, transferencias, medidas y estado contractual.
9. Se evaluará la necesidad de evaluaciones de impacto, análisis de riesgo, consultas regulatorias u otros mecanismos exigidos por cada jurisdicción y por la sensibilidad/escala del tratamiento.

### 2. Roles de Restaurant OS y de los tenants

1. Los contratos y avisos distinguirán los tratamientos en los que el operador de Restaurant OS actúa como responsable independiente de aquellos en los que actúa como encargado/procesador del tenant.
2. El tenant conserva la responsabilidad sobre las finalidades y las instrucciones de los tratamientos que determine como responsable, según el marco legal aplicable. Restaurant OS no debe presentar al tenant como responsable de tratamientos que el operador determine por cuenta propia.
3. Restaurant OS definirá y documentará sus finalidades propias, incluyendo las que correspondan a administración de cuentas SaaS, seguridad, prevención de abuso, facturación del servicio, soporte y cumplimiento.
4. Cuando aplique, se formalizarán acuerdos de tratamiento de datos (DPA/encargo), instrucciones documentadas, confidencialidad, medidas de seguridad, asistencia en derechos, incidentes, auditorías, subencargados, transferencias y devolución/eliminación al terminar el servicio.
5. No se asumirá que un único aviso o contrato cubre automáticamente a todos los tenants, países, marcas, sucursales o canales.

### 3. Avisos y política de privacidad

1. Antes de recopilar datos personales mediante una interfaz, formulario, integración o canal, la persona recibirá la información exigida para ese tratamiento y jurisdicción, en lenguaje claro, accesible y disponible en los idiomas necesarios.
2. La política de privacidad pública será coherente con el inventario real de tratamientos y explicará, según corresponda:
   - identidad y datos de contacto del responsable y, cuando aplique, de su representante o delegado de protección de datos;
   - categorías de personas y datos tratados;
   - finalidades y fundamentos jurídicos aplicables;
   - fuentes de los datos y si su entrega es obligatoria u opcional;
   - destinatarios, proveedores y categorías de subencargados;
   - transferencias internacionales, países o garantías aplicables;
   - criterios y plazos de conservación;
   - derechos, canales y procedimiento para ejercerlos;
   - decisiones automatizadas o elaboración de perfiles cuando sean relevantes;
   - medidas generales de protección, gestión de incidentes y cambios del aviso;
   - información específica para menores cuando el producto y la legislación hagan pertinente ese tratamiento.
3. Se publicarán avisos específicos o complementarios cuando el contexto lo requiera, por ejemplo, formularios, portal de clientes, pedidos, campañas, selección de personal, integraciones o funcionalidades de IA.
4. La política no prometerá anonimato, eliminación inmediata, seguridad absoluta, ausencia de transferencias ni plazos que la operación real no pueda garantizar.
5. El aviso informativo no se utilizará como sustituto de un consentimiento cuando la ley exija consentimiento, ni se solicitará consentimiento para tratamientos cuya base jurídica sea otra cuando ello resulte improcedente.

### 4. Política y calendario de retención de datos

1. Se establecerá una matriz de retención por categoría de información, finalidad, módulo propietario, rol de tratamiento, jurisdicción, evento que inicia el cómputo, plazo o criterio, excepción legal, acción al vencer y evidencia de ejecución.
2. No existirá un plazo universal para todos los datos ni se conservarán datos personales indefinidamente por defecto.
3. Los plazos concretos se determinarán a partir de las obligaciones aplicables en cada país y del propósito documentado. No se inventarán plazos fiscales, contables, laborales, comerciales, de seguridad o de prescripción.
4. La matriz cubrirá como mínimo:
   - cuentas, credenciales, sesiones y registros de autenticación;
   - perfiles y relaciones de clientes finales;
   - datos de empleados, representantes y usuarios de tenants;
   - ventas, pagos, facturas, documentos fiscales y registros contables;
   - pedidos, reservas, historial comercial y fidelización;
   - soporte, comunicaciones y reclamaciones;
   - auditoría, seguridad, fraude e incidentes;
   - consentimientos, preferencias y evidencias de aceptación contractual;
   - integraciones, webhooks y archivos importados/exportados;
   - logs, trazas, métricas, analítica, caché y mensajería durable;
   - copias de seguridad, snapshots, exportaciones y entornos no productivos.
5. Al vencer el plazo o desaparecer la finalidad, el módulo propietario ejecutará eliminación, anonimización irreversible o restricción/bloqueo cuando corresponda. La seudonimización no se presentará como anonimización.
6. Los registros que deban conservarse por obligación legal, defensa de reclamaciones, integridad documental u otra excepción válida se aislarán, limitarán a la finalidad de conservación y tendrán fecha o evento de revisión.
7. Una retención excepcional o legal hold debe registrar autoridad/causa, categorías, alcance, responsable, fecha de inicio, revisión y liberación. No se utilizará como excusa genérica para conservar todo el perfil.
8. La política incluirá copias de seguridad, réplicas, cachés, JetStream, exportaciones y sistemas de terceros. Cuando una eliminación no pueda propagarse inmediatamente a una copia inmutable, se documentará el ciclo de expiración, aislamiento, prohibición de restaurar datos borrados al entorno activo y reaplicación de eliminaciones tras restauración.
9. Los entornos de desarrollo, pruebas y demostración utilizarán datos sintéticos o anonimizados; las copias de producción requieren autorización, controles y justificación específica.
10. Cada módulo conserva el ownership de sus datos, schema, rol, migraciones e historial SQLx conforme a ADR-0001 y ADR-0008. No se crea una tabla central que permita a un módulo borrar directamente datos de los demás.

### 5. Derechos de las personas y solicitudes de privacidad

1. Existirá un canal visible y documentado para solicitudes de acceso, consulta, corrección, actualización, portabilidad, oposición, revocación de consentimiento, restricción y eliminación, según los derechos reconocidos en cada jurisdicción.
2. El procedimiento verificará identidad y autoridad de quien solicita, limitará la exposición de datos, registrará la solicitud y su alcance, aplicará plazos legales y comunicará el resultado o las razones de una excepción.
3. Las solicitudes se enrutarán a los módulos propietarios mediante sus contratos y procesos autorizados; ningún BFF ni coordinador consultará o modificará directamente schemas ajenos.
4. Se distinguirán: eliminación de cuenta de usuario, eliminación de perfil de cliente final, baja de tenant, terminación contractual y supresión de datos de una persona. Son operaciones distintas y no deben activar borrados globales por asociación.
5. ADR-0014 permanece vigente: la baja de un tenant no elimina por sí misma perfiles, historial ni facturas de sus clientes finales. Una solicitud individual posterior se resolverá dato por dato, preservando documentos y registros sujetos a conservación legal y restringiendo su tratamiento cuando proceda.
6. Cuando la eliminación total no sea legalmente posible, se informará qué categorías se conservan, por qué, durante cuánto tiempo o bajo qué criterio, quién puede acceder y qué usos quedan prohibidos.
7. Se mantendrá evidencia mínima de la solicitud, verificación, decisión, ejecución, excepción y respuesta, sin retener innecesariamente el contenido personal que se pretendía eliminar.

### 6. Consentimientos y preferencias

1. El consentimiento se utilizará solo cuando sea la base adecuada y exigida para la finalidad concreta; no se mezclará con aceptación de términos, registro de cuenta ni acceso a funcionalidades no relacionadas.
2. Cada consentimiento será específico, informado, libre, inequívoco y demostrable conforme a la ley aplicable. No habrá casillas premarcadas, consentimiento implícito por continuar ni interfaces engañosas.
3. Se registrarán la persona o identificador correspondiente, finalidad/categoría, texto y versión presentada, fecha/hora, canal, acción afirmativa, alcance y posterior revocación.
4. La revocación será accesible y no más difícil que otorgar el consentimiento. Se propagará a los sistemas y proveedores pertinentes dentro de los plazos aplicables.
5. Las preferencias de comunicaciones comerciales, cookies y otras finalidades se mantendrán separadas y no se inferirán unas de otras.
6. La prueba del consentimiento se conservará por el plazo justificado para demostrar cumplimiento, con acceso limitado y eliminación al vencer su finalidad/obligación.

### 7. Cookies y tecnologías similares: banner y centro de preferencias

1. Antes de activar cookies o tecnologías similares no esenciales sujetas a consentimiento, el sitio o aplicación web obtendrá el consentimiento previo que exija la jurisdicción. La clasificación se basará en la finalidad y comportamiento reales, no solo en el nombre técnico de la cookie.
2. Las tecnologías estrictamente necesarias para prestar una función solicitada o mantener seguridad/autenticación podrán operar bajo la excepción legal aplicable, pero deberán describirse en el aviso/catálogo correspondiente. No se clasificarán como necesarias herramientas de publicidad o analítica por conveniencia.
3. El banner inicial ofrecerá opciones claras y equivalentes para aceptar, rechazar las tecnologías no esenciales y configurar preferencias, sin patrones oscuros ni penalización visual para rechazar.
4. Las categorías opcionales estarán desactivadas por defecto cuando se requiera opt-in. No se cargarán scripts, píxeles, SDK, almacenamiento o llamadas de terceros no esenciales antes del consentimiento válido.
5. El centro de preferencias permitirá revisar y cambiar la elección, retirar consentimiento y consultar categorías/proveedores. El acceso a preferencias permanecerá disponible después de cerrar el banner.
6. Se guardará evidencia de la versión del aviso, categorías elegidas, fecha/hora, ámbito del sitio, región/regla aplicada y cambios posteriores. La expiración o renovación del consentimiento seguirá el plazo legal y la política aprobada.
7. Se mantendrá un inventario actualizado de cookies y tecnologías similares: nombre/identificador, proveedor, finalidad, categoría, duración, tipo (propia/tercero), datos tratados y transferencias.
8. No se usarán fingerprinting ni mecanismos equivalentes para eludir preferencias o reconstruir identificadores rechazados.
9. La solución cubrirá las superficies web públicas y administrativas que realmente utilicen estas tecnologías. No se instalará un banner en una interfaz que no las utilice; tampoco se omitirá consentimiento por tratarse de una interfaz administrativa si la ley lo exige.
10. La implementación deberá probarse por región, navegador, estado de consentimiento, rechazo, retirada, expiración, navegación y carga de terceros. El rechazo debe impedir técnicamente la carga no esencial, no limitarse a ocultar una preferencia en la interfaz.

### 8. Términos y condiciones y documentos contractuales

1. Antes de comercializar el SaaS se publicarán términos del servicio para la relación B2B con los tenants, coherentes con el producto, planes, pagos, límites, soporte, disponibilidad, suspensión, terminación, propiedad intelectual, uso aceptable, responsabilidades, garantías, limitaciones permitidas, resolución de controversias y ley aplicable.
2. Cuando existan funcionalidades de interacción directa con personas que no sean usuarios contractuales del tenant, se determinará si requieren términos de usuario final, condiciones de pedidos/reservas u otros avisos contractuales separados.
3. Los términos SaaS, el DPA/encargo, la política de privacidad, la política de cookies y las condiciones de usuario final serán documentos diferenciados cuando tengan destinatarios, funciones o bases jurídicas distintas.
4. La aceptación contractual será expresa cuando corresponda, antes de quedar vinculado el usuario, con acceso al texto completo y sin casillas premarcadas. No se considerará el simple uso como aceptación si la ley o el tipo de contrato exige aceptación expresa.
5. Se registrarán sujeto/tenant, documento y versión, fecha/hora, canal, acción de aceptación y evidencia técnica proporcional. La aceptación no debe almacenar copias innecesarias de datos sensibles.
6. Los cambios materiales tendrán control de versión, fecha de vigencia, aviso y nueva aceptación cuando lo exija la ley o cambien condiciones que requieran consentimiento contractual.
7. Los documentos anteriores se conservarán de forma íntegra durante el plazo necesario para demostrar qué condiciones aplicaban, con acceso restringido y retención definida.
8. No se inventarán razón social, domicilio, representante legal, correo de privacidad, jurisdicción, garantías, SLA, límites de responsabilidad ni compromisos comerciales. Se completarán con datos aprobados y revisión jurídica.

### 9. Seguridad, incidentes y proveedores

1. Los controles de seguridad seguirán ADR-0011, ADR-0015 y los estándares vigentes: mínimo privilegio, segregación, cifrado, gestión de secretos, auditoría, monitoreo, respuesta a incidentes y aislamiento de tenants.
2. Se mantendrá un procedimiento de incidentes de datos personales que contemple detección, contención, preservación de evidencia, evaluación de impacto, decisión de notificación, comunicación a clientes/autoridades/personas y plazos por jurisdicción.
3. Los plazos de notificación no se fijarán de forma universal: se derivarán de la ley y de los contratos aplicables y deberán estar operativamente respaldados.
4. Antes de habilitar un proveedor que procese datos personales se revisarán finalidad, categorías, ubicación, subencargados, medidas, retención, eliminación, incidentes, transferencias, auditoría y condiciones de terminación.
5. Las transferencias internacionales se identificarán y se habilitarán solo con mecanismo, garantías, avisos y evaluación exigidos por la jurisdicción aplicable.
6. El soporte con acceso a datos de clientes será temporal, justificado, de mínimo privilegio, auditado y sujeto a confidencialidad; se preferirán datos redactados o entornos controlados.

### 10. Publicación, versiones y evidencia

1. Cada documento legal tendrá propietario, jurisdicciones, idioma, versión, fecha de publicación, fecha de vigencia, estado y registro de revisión/aprobación.
2. Los textos publicados deberán corresponder a los tratamientos, proveedores, funcionalidades, cookies y condiciones comerciales realmente activos en producción.
3. Se mantendrán versiones anteriores accesibles cuando sea necesario para acreditar la relación contractual o el aviso vigente en un momento determinado.
4. Los avisos, consentimientos, términos y preferencias no se editarán retroactivamente para aparentar una aceptación anterior.
5. Los documentos jurídicos públicos se mantendrán fuera de los ADR técnicos como artefactos de producto y legales, con control de cambios, revisión autorizada y publicación coordinada.
6. El equipo técnico no sustituye la revisión de abogado o profesional competente en protección de datos para cada jurisdicción de lanzamiento.

### 11. Puerta obligatoria de lanzamiento

La publicación en producción para usuarios reales quedará bloqueada hasta completar y evidenciar, como mínimo:

- Jurisdicciones iniciales, entidades operadoras, mercados, categorías de usuarios y canales de tratamiento identificados.
- Inventario de datos y actividades de tratamiento revisado y aprobado.
- Roles de responsable/encargado y contratos con tenants definidos.
- Matriz de retención por categoría y jurisdicción aprobada, incluyendo excepciones, legal holds, backups y proveedores.
- Política de privacidad y avisos específicos redactados, revisados jurídicamente, publicados y accesibles.
- Términos SaaS, DPA/encargo y, cuando aplique, términos de usuario final revisados y publicados.
- Inventario de cookies/tecnologías similares y banner/centro de preferencias probados en las regiones objetivo.
- Consentimientos y preferencias demostrables, revocables y propagados correctamente.
- Procedimientos de derechos de personas, eliminación, exportación, rectificación y reclamaciones probados.
- Procedimiento de incidentes y notificaciones con responsables, canales y plazos por jurisdicción.
- Proveedores/subencargados, transferencias internacionales y contratos revisados.
- Evidencia de controles de acceso, aislamiento multi-tenant, minimización, cifrado, redacción de logs y eliminación/retención.
- Aprobación formal del responsable legal/privacidad designado y del propietario del producto.
- Evidencia de pruebas de aceptación y responsable operativo para mantener documentos, preferencias y plazos actualizados.

No se habilitará tracking no esencial, campañas, tratamiento de datos sensibles, transferencias o finalidades nuevas solo porque exista un banner genérico. Cada capacidad requiere su evaluación y habilitación conforme a esta decisión.

### 12. Límites y asuntos que deben concretarse antes de producción

Este ADR no determina todavía:
- Países de lanzamiento ni leyes concretas aplicables.
- Identidad legal, domicilio, representante, delegado o contacto oficial del operador.
- Plazos numéricos de conservación por tipo de registro.
- Texto jurídico final de políticas, términos, DPA o avisos.
- Proveedores y ubicaciones definitivas de hosting, analítica, pagos, IA, correo, soporte y cookies.
- Categorías concretas de cookies y duraciones hasta inspeccionar la aplicación y sus proveedores reales.
- SLA contractual, garantías, límites de responsabilidad, ley/foro aplicables o política comercial.
- Un fundamento jurídico universal para cada tratamiento.
- Tablas, schemas, columnas, contratos ejecutables, endpoints, UI, CMP, scripts, SDK, infraestructura o migraciones.

Estos datos no se inventarán para completar plantillas. Se definirán con el producto real, la jurisdicción de lanzamiento y revisión jurídica.

## Consecuencias

- Privacidad, retención y cumplimiento se convierten en requisitos transversales verificables y en una condición de go/no-go para producción.
- La documentación legal se publica al final, pero los controles técnicos necesarios deben diseñarse e implementarse desde las fases en que se recopilan o procesan datos.
- La baja de tenant, la eliminación de una cuenta y la eliminación de datos de una persona permanecen como procesos diferentes.
- Los módulos conservan ownership de los datos y ejecutan solicitudes sobre sus propios registros; no se crea un módulo o schema central de datos personales.
- Los plazos de retención se vuelven explícitos, justificables y auditables; se evita tanto la eliminación de documentos que deban conservarse como la retención ilimitada.
- El banner de cookies debe controlar técnicamente la carga de tecnologías opcionales y no ser un aviso visual sin efecto.
- Términos, avisos y consentimientos deben poder versionarse y probar qué texto aceptó o recibió cada persona.
- La salida a producción depende de revisión jurídica y evidencia operativa; no basta con que los documentos existan en el repositorio.

## Alternativas consideradas

### Publicar una política genérica y un banner estándar sin inventario

**Rechazada.** No garantiza que los textos reflejen los tratamientos, proveedores, cookies, finalidades ni jurisdicciones reales y puede dar una falsa apariencia de cumplimiento.

### Definir un único plazo de retención para todos los datos

**Rechazada.** Los datos de autenticación, facturación, documentos fiscales, soporte, analítica y copias de seguridad tienen finalidades y obligaciones diferentes.

### Eliminar todos los datos al cancelar un tenant

**Rechazada.** Contradice ADR-0014 y puede destruir perfiles, historial y facturas de clientes finales, además de registros sujetos a conservación.

### Mantener todos los datos indefinidamente para evitar riesgos legales

**Rechazada.** Aumenta exposición, costos y tratamiento innecesario, y contradice el principio de conservación limitada.

### Activar cookies analíticas y publicitarias antes de mostrar el banner

**Rechazada.** Una elección posterior no corrige la carga previa cuando se requiere consentimiento previo.

### Considerar que aceptar términos implica aceptar privacidad y cookies

**Rechazada.** Son actos, finalidades y bases jurídicas diferentes; deben presentarse y registrarse por separado cuando corresponda.

### Posponer toda consideración de privacidad hasta el lanzamiento

**Rechazada.** La privacidad por diseño debe acompañar el desarrollo; lo que se reserva para la fase final es la validación jurídica integral, publicación de textos definitivos y cierre de la puerta de producción.

## Relación con ADR anteriores

- **ADR-0001 y ADR-0008:** mantienen ownership exclusivo por módulo, schema, rol, migraciones e historial SQLx. Este ADR no crea tablas compartidas ni altera la distribución de los cuatro procesos.
- **ADR-0003 y ADR-0013:** proporcionan mecanismos durables e idempotentes para solicitudes y procesos distribuidos cuando corresponda; no crean un coordinador con acceso directo a schemas ajenos.
- **ADR-0011:** mantiene controles de autenticación, credenciales, sesiones y protección de cuentas.
- **ADR-0014:** sigue rigiendo la baja de tenants y conservación de datos de clientes; este ADR añade el marco para solicitudes individuales y plazos de conservación, sin contradecir su regla.
- **ADR-0015:** mantiene observabilidad segura y minimización de datos personales en logs, métricas y trazas.
- **ADR-0016:** caché y claves deben respetar minimización, aislamiento, expiración y eliminación; Redis no se convierte en fuente de retención legal.
- **ADR-0017:** los mensajes durables y sus políticas de retención deben respetar clasificación, minimización y plazos; JetStream no sustituye el historial legal ni la fuente autoritativa.

## Estado de implementación

**Propuesta documental; no implementada.** Este ADR no publica políticas ni términos legales, no configura un banner o CMP, no instala cookies ni scripts, no crea inventarios de tratamientos, tablas, schemas, contratos, endpoints, interfaces, SDK, proveedores ni automatizaciones. No modifica archivos SQL o migraciones, no ejecuta SQL y no implementa código. La decisión requiere aprobación explícita y su ejecución se planifica en la fase final de preparación para producción, manteniendo privacidad por diseño durante todas las fases anteriores.
