> **Estado: propuestas e ideas no aprobadas.** Este documento conserva posibilidades para evaluar; no crea módulos, crates, schemas, responsabilidades ni compromisos de roadmap. Ninguna propuesta se considera arquitectura vigente hasta que se evalúe y, cuando corresponda, se apruebe mediante ADR y se incorpore a los documentos normativos.
>
> Las capacidades existentes mantienen la propiedad y responsabilidades definidas en [requisitos.md](./requisitos.md). Las ideas de esta lista no pueden reasignar ni duplicar esas responsabilidades.

Las que más valor tendrían

Motor de precios y promociones. Hoy las promociones aparecen como “Optional” y el catálogo maneja precios por sucursal. Un motor propio (reglas por horario, canal, cliente, cantidad, combos, cupones, prioridad y conflictos entre descuentos) evita que esa lógica quede regada entre ventas, catálogo y clientes. Es de lo que más toca un restaurante todos los días.
Motor de impuestos. Los impuestos aparecen por producto y por sucursal, pero sacar el cálculo a un módulo propio (IVA, impuesto al consumo, retenciones, propinas, redondeos) ayuda mucho en Colombia, donde las reglas cambian y deben quedar versionadas.
Aprobaciones y flujos de trabajo. Las veo mencionadas en compras, descuentos, transferencias y automatización. Un solo motor de aprobaciones, con doble aprobación y límites por monto, evita reimplementarlo en cada módulo.
Notificaciones y comunicaciones. WhatsApp, correo, SMS y alertas internas están en integraciones. Un módulo central con plantillas, preferencias, consentimiento y reintentos serviría a ventas, clientes, compras y cocina.
Documentos y archivos. Facturas de proveedores, contratos, soportes de gastos, fotos de productos. Un módulo único de almacenamiento con permisos, versiones y vínculos a cualquier entidad.

Útiles, pero más adelante
6. Reservas y recursos agendables genéricos. Ya lo planteas con mesas como recursos reservables. Si lo haces genérico, también sirve para citas, salones o equipos.
7. Tareas y checklists operativos. Apertura y cierre del local, limpieza, control de temperaturas, auditorías internas. Los restaurantes lo piden mucho y encaja con alertas y personal.
8. Gestión de dispositivos. Terminales, impresoras, pantallas, estado de conexión y versiones. Lo veo disperso entre organización e integraciones.
9. Importación y exportación masiva. Cargar menús, inventarios y clientes desde Excel es lo primero que un cliente nuevo va a pedir para migrar desde su sistema actual.
10. Soporte y base de conocimiento. Tickets, ayuda dentro del sistema y registro de incidencias, que ya esbozas en el módulo 0.

Otros que dependen del vertical
Control de activos fijos y mantenimiento (neveras, hornos, equipos), gestión de calidad e inocuidad (importante en alimentos) y delivery propio con repartidores, que ya contemplas.

/////////////////////////////////////////////////////////////////////////



1. Módulos adicionales que recomiendo para Core
Estos serían mis cinco candidatos principales:

22. Notifications — Notificaciones
Prioridad alta
- Notificaciones dentro del sistema.
- Correos electrónicos.
- SMS y notificaciones push.
- Preferencias de usuarios.
- Plantillas de mensajes.
- Confirmaciones de entrega y lectura.
- Notificaciones por empresa y sucursal.
Serviría para cualquier industria.




23. Document Management — Gestión documental
Prioridad alta
- Almacenamiento centralizado.
- Versiones de documentos.
- Documentos corporativos.
- Contratos y certificados.
- Permisos de acceso.
- Firma electrónica mediante proveedores.
- Retención y eliminación controlada.
- Hashes y trazabilidad.
Evitaría que cada módulo implemente su propio almacenamiento de archivos.




24. Search — Búsqueda empresarial
Prioridad alta
- Búsqueda global.
- Búsqueda de clientes.
- Búsqueda de productos.
- Búsqueda de documentos.
- Búsqueda de pedidos y transacciones.
- Filtros avanzados.
- Búsqueda por sucursal y empresa.
Un buscador central para toda la plataforma, respetando los permisos de cada módulo.




25. Scheduling & Booking — Programación y reservas de recursos
Muy recomendable
- Calendarios empresariales.
- Reservas de recursos.
- Disponibilidad.
- Asignación de espacios y equipos.
- Gestión de citas.
- Listas de espera.
- Prevención de conflictos de horarios.
Serviría para mesas de restaurantes, habitaciones de hoteles, citas y recursos de otras industrias. Requeriría separar el motor genérico de las reglas específicas de cada vertical.




26. AI Platform — Inteligencia artificial
Capacidad estratégica
- Administración de modelos de IA.
- Proveedores de modelos.
- Gestión de prompts.
- Agentes especializados.
- Herramientas autorizadas.
- Control de tokens y costos.
- Evaluaciones de calidad.
- Historial de conversaciones.
- Políticas de seguridad y permisos.
Tu propia capa de inteligencia artificial para todos los verticales.



2. Otros componentes que agregaría al Core
No todos necesitan convertirse en crates independientes.
Componente	Responsabilidad	Dónde lo pondría
Localization	Idiomas, formatos, zonas horarias y regionalización.	Core compartido
Usage Metering	Medición de usuarios, sucursales, almacenamiento, API e IA.	Platform
Feature Management	Activación de funcionalidades por tenant, marca y sucursal.	Platform
Approval Engine	Políticas y flujos de aprobación reutilizables.	Capacidad compartida, evitando duplicar aprobaciones actuales
Reference Data	Países, monedas, códigos y catálogos de referencia.	Core compartido
Device Management	Registro, configuración y estado de dispositivos.	Subdominio de Integrations inicialmente

Especialmente importante: tu documentación ya exige medir consumo de usuarios, sucursales, almacenamiento, API, automatizaciones e IA. Esto debería convertirse en una capacidad formal de Platform para controlar los límites y la facturación SaaS.


////////////////////////////////////////////////////////////////////


## **¿Qué podríamos hacer con Power BI?**
Permitir que los propietarios y administradores analicen el negocio mediante tableros interactivos:

- Ventas por empresa, marca y sucursal.
- Rentabilidad por producto.
- Comparaciones entre sucursales.
- Costos y gastos.
- Inventario y rotación.
- Desempeño de empleados.
- Comportamiento de clientes.
- Pronósticos y tendencias.
Por ejemplo, el propietario de una cadena de 30 restaurantes podría comparar el rendimiento de sus 30 sucursales en un solo tablero.

## **2. ¿Dónde encaja en nuestra arquitectura?**
No necesitamos crear otro módulo llamado Power BI.

Ya tenemos el módulo que debe proporcionar esa información: **Analytics**.