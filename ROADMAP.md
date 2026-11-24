# Restaurant OS - Roadmap

## Vision

Construir una plataforma integral de gestion, operacion, automatizacion e inteligencia empresarial para restaurantes con multiples sucursales.

Restaurant OS no sera solo un programa para tomar pedidos, imprimir facturas y cobrar. Sera una plataforma que:

- Registre las operaciones en tiempo real.
- Consolide la informacion de todas las sucursales.
- Permita administrar una empresa central con operaciones independientes por sucursal.
- Detecte problemas y oportunidades operativas.
- Automatice procesos repetitivos.
- Apoye decisiones mediante reportes e inteligencia artificial.

## Responsabilidad de este documento

Este roadmap define fases, dependencias y entregables. [requisitos.md](./requisitos.md)
es la fuente de verdad para requisitos, propietarios de dominio y ubicacion de
los crates; [promt.md](./promt.md) define el orden de trabajo por lotes. Las
fases no cambian esos propietarios ni crean una estructura paralela.

## Propiedad de módulos y estructura física

Los dominios conservan sus responsabilidades lógicas y se implementan una sola
vez bajo `backend/<backend-propietario>/modules/<modulo>/`. Según ADR-0008,
PLATFORM pertenece a Admin Platform Backend y todos los demás módulos de
negocio pertenecen a Public Backend. Admin BFF y Public BFF no son propietarios
de dominios ni de persistencia de negocio.

`crates/` contiene únicamente bibliotecas técnicas neutrales, contratos
versionados y adaptadores. No contiene módulos propietarios de negocio.
KITCHEN y PRODUCTION mantienen sus responsabilidades gastronómicas; CATALOG
mantiene productos y agrupaciones comerciales genéricas. Esta separación es de
propiedad de dominio, no una división física Core/Restaurant vertical.

## Topología de ejecución de los cuatro backends

La topología de Restaurant OS está compuesta por cuatro procesos/binarios independientes:

- Admin Platform Backend: propietario de PLATFORM.
- Admin BFF: composición de APIs administrativas; sin módulos propietarios de negocio.
- Public BFF: composición de APIs públicas y operativas; sin módulos propietarios de negocio.
- Public Backend: propietario de los demás módulos de negocio canónicos.

La distribución y las rutas físicas están definidas en ADR-0008 y en la matriz de `requisitos.md`.

Los BFF son procesos independientes, no están integrados dentro de los backends ni existe un único BFF compartido. Admin Platform Backend aloja PLATFORM; Public Backend aloja los demás módulos de negocio. Admin BFF y Public BFF realizan composición y exposición HTTP/OpenAPI, sin ownership de dominios ni persistencia de negocio. Entre procesos se utiliza gRPC para solicitudes/respuestas, NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda. Dentro de cada backend, los módulos que comparten proceso se comunican mediante contratos públicos y puertos/traits locales; los eventos durables usan Outbox/Inbox. Docker Compose debe representar cuatro servicios independientes. Esta es la topología objetivo y no evidencia de que el despliegue ya esté implementado.

## Modelo SaaS

Restaurant OS sera una plataforma multiempresa con clientes externos.

- Nombre provisional: Restaurant OS.
- Plataforma SaaS de gestion integral de restaurantes.
- Arquitectura multiempresa, multimarca y multisucursal.
- Jerarquia: plataforma, tenant, grupo empresarial, empresa legal, marca, sucursal.
- Contexto operativo: area, estacion, bodega, caja y terminal.
- Toda operacion debe conservar tenant, empresa legal, marca y sucursal.
- Permitir consolidacion sin mezclar obligaciones fiscales.
- Permitira administrar cadenas propias y clientes externos.
- Permitira restaurantes independientes, cadenas de cafeterias, bares y otros formatos.
- Mantendra un nucleo central de datos aislados, usuarios, suscripciones, seguridad, IA y automatizaciones.
- Incluir administracion global interna de tenants.
- Clasificar capacidades como Core, Restaurant Pack u Optional.
- Activar verticales por tenant, marca o sucursal.
- Mantener mesas, cocina y recetas como capacidades del pack de restaurantes.
- Utilizar conceptos generales de recursos, produccion y cumplimiento.
- Incluir planes, licencias, suscripciones y facturacion SaaS.
- Configurar limites por plan y por tenant.
- Medir usuarios, sucursales, almacenamiento, API, automatizaciones e IA.
- Mantener soporte, incidencias y estado global de servicios.
- Administracion empresarial por tenant.
- Gestion de empresas, grupos empresariales y marcas.
- Gestion de sucursales, areas, estaciones y bodegas.
- Configuracion fiscal, monetaria e tributaria.
- Cajas, terminales, impresoras y horarios.
- Objetivos comerciales por sucursal.
- Herencia central con excepciones locales.
- Operacion diaria del restaurante con POS y pedidos.
- Mesas, reservas, espera y asignacion de meseros.
- Cocina y bar KDS con pantallas de preparacion.
- Domicilios, recogida y seguimiento de entregas.
- Division de cuentas, pagos mixtos y propinas.
- Descuentos, devoluciones y anulaciones.
- Modalidades para restaurante, cafeteria, bar y comida rapida.
- Modalidad de delivery con repartidores y seguimiento.
- Funcionalidades activables por tenant, marca o sucursal.
- Catalogo central por categorias, productos y variantes.
- Presentaciones, modificadores y productos compuestos.
- Ingredientes representados como productos inventariables.
- Recetas y subrecetas versionadas por PRODUCTION; precios y disponibilidad por
  sucursal en CATALOG.
- Rendimientos y fichas tecnicas bajo propiedad de PRODUCTION.
- Combos, promociones y agrupaciones comerciales genericas en CATALOG; menus gastronomicos por horario en Restaurant vertical.
- Precios e impuestos por sucursal.
- Recetas centrales con excepciones locales controladas por PRODUCTION.
- Consumo de INVENTORY segun la receta efectiva versionada.
- Gestion de bodegas e inventarios por sucursal.
- Materias primas, productos terminados y lotes.
- Entradas, salidas, ajustes y conteos fisicos.
- Mermas, desperdicios y vencimientos.
- Kardex y trazabilidad completa.
- Solicitudes y recepciones de mercancia.
- Transferencias y inventario en transito.
- Lotes, vencimientos y conteos fisicos.
- Reservas de existencias y ajustes trazables.
- Solicitudes, ordenes, recepciones y facturas de proveedores.
- Contabilidad por plan de cuentas y periodos.
- Conciliaciones bancarias y documentos fiscales.
- Clientes, fidelizacion, empleados y asistencia.
- Predicciones y hallazgos de IA con trazabilidad.
- Existencias minimas y maximas.
- Clientes, CRM y historial de consumo.
- Segmentacion y recuperacion de clientes.
- Puntos, cupones y promociones.
- Tarjetas de regalo.
- Campañas y encuestas.
- Proveedores, solicitudes y cotizaciones.
- Ordenes de compra y aprobaciones.
- Recepcion de mercancia y facturas recibidas.
- Cuentas por pagar e historial de precios.
- Comparacion y calificacion de proveedores.
- Programacion y compras centralizadas.
- Soportara una cadena propia administrada desde una cuenta central.
- Permitira que propietarios externos creen y administren sus propios negocios.
- Permitira gestionar restaurantes independientes y cadenas externas.
- Mantendra datos, usuarios, permisos, configuraciones e integraciones separados por tenant.
- Impedira el acceso cruzado entre clientes.
- Aplicara aislamiento de tenant en APIs, base de datos y almacenamiento.

## Prioridades centrales

1. Multi-sucursal real.
2. Inventario conectado automaticamente con recetas y costos.
3. Automatizaciones visuales creadas por administradores.
4. IA empresarial basada en datos reales.
5. Prediccion y prevencion de problemas operativos.

El producto debe medir su valor por su capacidad de aumentar ganancias y reducir perdidas.

## Principio fundamental

El sistema debe diseñarse desde el inicio como una plataforma multiempresa y multisucursal.

- Una empresa puede tener varias sucursales.
- Cada sucursal opera de manera independiente.
- Cada sucursal tiene empleados, caja, inventario, ventas y gastos propios.
- La administracion central puede ver informes consolidados y comparativos.
- Los permisos dependen del cargo, la empresa y la sucursal.
- Todas las entidades principales deben incluir el contexto de empresa y sucursal.
- La primera sucursal se implementara sobre la misma arquitectura utilizada por las sucursales futuras.

## Arquitectura objetivo

Decisión inicial:

- Implementar un monolito modular bien organizado en Rust.
- Organizar el repositorio como Cargo workspace; cada módulo es un crate bajo el backend que lo posee.
- Construir cada proceso como binario independiente. Admin Platform Backend contiene PLATFORM; Public Backend contiene los demás módulos de negocio; los BFF contienen composición y transporte, no dominios propietarios.
- Mantener Admin Platform Backend, Admin BFF, Public BFF y Public Backend como cuatro procesos separados.
- Los dos BFF exponen sus superficies HTTP/OpenAPI a los frontends correspondientes; los backends de plataforma y público exponen sus contratos de backend.
- Docker Compose debe definir cuatro servicios de aplicación independientes. Esta es la topología objetivo, no evidencia de que ya esté implementada.
- Aplicar arquitectura hexagonal y DDD dentro de cada modulo.
- Las llamadas síncronas entre módulos que comparten un mismo backend usan puertos/traits locales; las solicitudes/respuestas que cruzan procesos usan gRPC con Tonic y Protobuf versionado. NATS Core y NATS JetStream se utilizan para señales efímeras y eventos durables, respectivamente, según corresponda.
- Utilizar Outbox y consumidores idempotentes para eventos.
- Mantener modulos independientes por dominio y con interfaces claras.
- Utilizar PostgreSQL como base de datos principal.
- Diseñar aislamiento multi-tenant desde el primer dia.
- Iniciar con una base PostgreSQL compartida y un schema PostgreSQL independiente por módulo.
- Reservar bases dedicadas para clientes Enterprise.
- Separar dominios en esquemas: platform, identity, organization y operaciones.
- Mantener una base PostgreSQL compartida inicialmente, con propiedad por dominio.
- Implementar PLATFORM bajo `backend/admin-platform-backend/modules/platform/` y los demás dominios bajo `backend/public-backend/modules/<modulo>/`, según [ADR-0008](docs/adr/0008-module-ownership-across-four-processes.md) y la matriz de [requisitos.md](./requisitos.md).
- Priorizar platform, identity, organization, catalog, sales, payments,
  inventory, billing y audit en el nucleo compartido.
- Diseñar esquemas audit, analytics y integrations por responsabilidad.
- Crear tablas iniciales por dominio segun las fases implementadas.
- Priorizar platform, identity, organization, catalog, sales y audit.
- Agregar inventory, procurement, finance y automatizacion conforme a su fase.
- Implementar billing independiente de ventas para documentos fiscales.
- Utilizar UUID en entidades principales.
- Usar NUMERIC para precios y contabilidad.
- Aplicar RLS y contexto de tenant.
- Definir despliegue Shared Database / Schema per Module: una base compartida inicialmente y un schema PostgreSQL por módulo.
- Permitir migracion posterior a infraestructura dedicada Enterprise.
- Definir despliegues compartidos, base dedicada y entorno dedicado.
- Registrar ubicacion, version y estado de infraestructura por tenant.
- Migrar tenants sin reconstruir datos.
- Sincronizar cambios incrementales antes del cambio.
- Definir ventana controlada de cambio.
- Verificar integridad antes de habilitar destino.
- Modelar suscripciones, planes versionados y addons.
- Separar facturacion SaaS de facturacion fiscal de restaurantes.
- Versionar planes y precios comerciales.
- Personalizar limites por tenant mediante overrides.
- Mantener infraestructura asignada y cobros por consumo.
- Distinguir empresa legal, marca y sucursal.
- Validar tenant en todas las relaciones de dominio.
- Modelar relaciones empresariales, comerciales y operativas por dominio.
- Mantener movimientos de inventario como libro inmutable.
- Utilizar UUID como clave primaria principal.
- Aplicar claves foraneas compuestas por tenant.
- Configurar restricciones de unicidad y valores por dominio.
- Separar pedidos, pagos, comprobantes y documentos fiscales.
- Diccionario SQL para empresas, marcas, sucursales y recursos.
- Zona horaria propia por sucursal.
- Identidad global con membresias independientes por tenant.
- Roles y permisos aislados por empresa.
- Alcance por sucursal, marca y entidad legal.
- Implementar historial, eliminacion logica y versionamiento.
- Coordinar ventas, pagos e inventario mediante transacciones locales por módulo, Outbox/Inbox e idempotencia; los procesos entre dominios usan Saga y compensaciones, nunca una transacción SQL global.
- Implementar frontend administrativo con Next.js, React y TypeScript.
- Implementar POS con React, TypeScript y PWA.
- Evaluar Tauri para integracion nativa de escritorio.
- Implementar backend Rust con un Cargo workspace.
- Compilar los cuatro procesos como binarios independientes: Admin Platform Backend con PLATFORM, Public Backend con los demás módulos de negocio y los dos BFF como procesos de composición. Se comunican mediante gRPC y NATS Core/JetStream según el tipo de interacción.
- Utilizar Axum, PostgreSQL y SQLx.
- Aplicar independencia, puertos y inversion de dependencias.
- Prohibir dependencias circulares y persistencia cruzada.
- Probar cada modulo con implementaciones simuladas.
- Utilizar Axum para REST y WebSockets.
- Usar contratos y adaptadores locales entre módulos dentro de cada backend; usar Tonic/gRPC para solicitudes/respuestas entre procesos y NATS Core/JetStream para mensajería efímera/durable, según corresponda.
- Exponer API REST documentada con OpenAPI.
- Utilizar WebSockets para actualizacion en tiempo real.
- Utilizar Redis para caché y coordinación cuando sea necesario.
- Utilizar NATS Core para señales efímeras y NATS JetStream para mensajería durable, según corresponda. Esta decisión no afirma que la infraestructura ya esté instalada o activa; mientras el dispatcher durable no publique a JetStream, Outbox con polling mediante `FOR UPDATE SKIP LOCKED` permite reclamar y procesar los eventos pendientes.
- Utilizar almacenamiento compatible con S3.
- Iniciar analitica en PostgreSQL y evaluar ClickHouse al crecer.
- Utilizar OpenTelemetry y Grafana para observabilidad.
- Construir y ejecutar migraciones por dependencias para los dominios
  platform, identity, organization, catalog, sales, payments, cash, kitchen,
  inventory, procurement, production, billing, finance, workforce, customers,
  integrations, automation, analytics, audit y reporting.
- Implementar CATALOG con fuente maestra por marca.
- Permitir excepciones locales sin modificar el maestro.
- CATALOG versiona publicaciones y precios; PRODUCTION versiona recetas.
- Permitir catalogos independientes por sucursal.
- Respetar aislamiento de tenant en toda operacion.
- Mantener trazabilidad de pagos, inventario, contabilidad y acciones de IA.

Los nombres anteriores identifican dominios; no son IDs numericos. Los
prefijos de las migraciones existentes (`modulo_N`) representan su secuencia
historica de instalacion, no una identidad de dominio. Una migracion adicional
de Procurement no crea un dominio Purchasing ni justifica renumerar archivos
ya aplicados.
- Aplicar contexto de un único tenant por operación.
- Reforzar aislamiento con PostgreSQL RLS y claves compuestas.
- Organizar reglas y acceso a datos dentro de cada modulo.
- Evitar escritura cruzada directa entre modulos.
- Comunicar ventas e inventario mediante interfaces o eventos.
- Usar claves idempotentes en operaciones POS.
- Diseñar autorizacion RBAC + ABAC.
- Registrar permisos concretos por accion y modulo.
- Definir alcance por tenant, grupo, empresa, marca y sucursal.
- Definir limites por importe, cantidad y contexto.
- Implementar aprobacion individual y doble aprobacion.
- Prohibir acceso privado automatico del soporte SaaS.
- Exponer APIs internas y publicas.
- Utilizar colas de eventos para procesos asincronos.
- Usar almacenamiento local para operaciones offline.
- Evitar decenas de microservicios desde el inicio.
- Extraer servicios solo cuando el volumen, la carga o los limites operativos lo justifiquen.

### Plataforma central

- Administracion general.
- Inteligencia artificial.
- Control empresarial.
- Configuracion corporativa.
- Reportes consolidados.
- Permisos globales y por sucursal.

### Operacion por sucursal

- Punto de venta.
- Caja y turnos.
- Mesas y comandas.
- Cocina y despachos.
- Inventario local.
- Compras y recepciones.
- Empleados y horarios.
- Gastos locales.
- Clientes y ventas.

### Modulos compartidos

- Inventarios.
- Contabilidad.
- Personal.
- Compras.
- Proveedores.
- Clientes y CRM.
- Reportes.
- Automatizaciones.

## Fase 0 - Fundaciones

Objetivo: establecer las bases tecnicas y operativas del producto.

- Definir el modelo de dominios y limites de modulos.
- Definir desde esta fase la arquitectura offline-first del POS: identificadores
  creados por el dispositivo, persistencia local durable, idempotencia,
  sincronizacion, conflictos y politicas de caja, pagos y numeracion fiscal.
- Diseñar el modelo multiempresa y multisucursal.
- Definir roles, permisos y alcance por sucursal.
- Definir convenciones de APIs, eventos y validaciones.
- Configurar el monorepo y los entornos de desarrollo.
- Configurar Docker, base de datos y observabilidad.
- Crear los paquetes compartidos.
- Establecer CI/CD y pruebas automatizadas.
- Crear usuario exclusivo para migraciones.
- Ejecutar la aplicacion sin propiedad de tablas ni BYPASSRLS.
- Configurar RLS y contexto de tenant por transaccion.
- Usar gestor de secretos para credenciales.
- Probar backups y restauraciones antes de produccion.

Entregable:

- Arquitectura aprobada.
- Entorno de desarrollo reproducible.
- Estructura base del repositorio.

## Fase 1 - Plataforma e identidad

Objetivo: habilitar empresas, sucursales, usuarios y permisos.

- Gestion de empresas u organizaciones.
- Gestion de sucursales.
- Registro y autenticacion de usuarios.
- Invitaciones y alta de usuarios.
- Roles y permisos granulares.
- Permisos por sucursal.
- Sesiones y auditoria.
- Configuracion regional de cada sucursal.
- Moneda, impuestos y formatos.
- Centro de configuracion empresarial.
- Informacion tributaria y numeraciones.
- Registrar dispositivos por sucursal y provisionar rangos fiscales autorizados
  sin solapamiento, sujetos a validacion normativa.
- Configuracion de moneda, zona horaria e idiomas.
- Impresoras y dispositivos por sucursal.
- Metodos de pago y plantillas de documentos.
- Parametros generales y notificaciones.
- Configuracion individual y central selectiva por sucursal.
- Crear y activar sucursales.
- Asignar administradores y empleados.
- Configurar cajas, bodegas, cocinas y mesas.
- Configurar impresoras y metodos de pago.
- Definir horarios, precios, impuestos y objetivos.
- Aplicar herencia central y excepciones por sucursal.
- Aplicar configuraciones centrales a todas o algunas sucursales.
- Mantener excepciones y excepcion por sucursal.
- Comparar resultados y activar o desactivar sucursales.

Entregable:

- Administracion central funcional.
- Cambio seguro de sucursal.
- Matriz inicial de permisos.

## Fase 2 - Catalogo y ventas basicas

Objetivo: disponer del flujo minimo operativo de un restaurante.

CATALOG y SALES aportan las capacidades base; el menu, los modificadores y los
flujos de servicio propios del restaurante pertenecen a los módulos gastronómicos responsables dentro del backend propietario.

- Categorias y productos.
- Variantes y modificadores.
- Precios por sucursal.
- Catalogo central por marca y empresa.
- Variantes, presentaciones y modificadores.
- Combos y promociones.
- Menus gastronomicos por horario y sucursal, propiedad de Restaurant vertical y compuestos con productos de CATALOG.
- Impuestos por producto.
- Catalogo centralizado con configuraciones por sucursal.
- Categorias, productos, fotos, descripciones y variantes.
- Adiciones, extras, combos y promociones.
- Impuestos y productos agotados.
- Precios locales sin alterar las demas sucursales.
- Usuarios de caja.
- Apertura y cierre de caja.
- Creacion de pedidos.
- Tipos de venta: mesa, mostrador y delivery.
- Metodos de pago.
- Descuentos y anulaciones.
- Impresion de facturas y comprobantes.
- Dashboard operativo basico de la sucursal.
- Ventas del dia, numero de pedidos y ticket promedio.
- Cajas abiertas y pedidos pendientes.
- Gastos registrados durante el dia.
- Apertura y cierre de cuentas.
- Modificadores y descuentos autorizados.
- Division y union de cuentas.
- Cambio de mesa y transferencia entre meseros.
- Pagos mixtos, propinas y devoluciones.
- Reimpresion de comprobantes y facturacion electronica.
- Pedidos para llevar, domicilio y recogida.
- Clientes frecuentes.
- Registrar ventas y operaciones de caja admitidas sin conexion usando
  persistencia local durable e identificadores generados en el POS antes del
  primer envio.
- Sincronizar y reintentar operaciones pendientes sin duplicar ventas, pagos ni
  movimientos; recuperar la cola tras reiniciar el dispositivo.
- Permitir solo los metodos de pago y documentos fiscales autorizados para
  operacion offline; bloquear la emision fiscal si el dispositivo no tiene un
  rango valido asignado.

Entregable:

- Primer POS operativo para una sucursal.
- Flujo completo desde el pedido hasta el cobro.
- Flujo offline de venta y caja para las operaciones habilitadas, probado con
  reconexion, reintentos y recuperacion local.
- Vision inicial de los indicadores operativos diarios.
- Operacion segura de cuentas, pagos y devoluciones.

## Fase 3 - Operacion de mesas y cocina

Objetivo: conectar ventas, servicio y preparacion.

Esta fase implementa capacidades de Restaurant vertical. ORGANIZATION conserva
la identidad de los recursos fisicos y SALES los pedidos/cuentas genericos; el
vertical coordina mesas, reservas, servicio y comandas.

- Gestion de zonas y mesas.
- Estados de mesa.
- Mapa visual de mesas.
- Tiempo de ocupacion y numero de personas.
- Mesas reservadas y comandas por mesa.
- Division de productos entre comensales.
- Creacion de planos y zonas de los salones.
- Capacidad y ubicacion visual de cada mesa.
- Asignacion de meseros.
- Reservaciones por telefono y pagina web.
- Lista de espera y estimacion de tiempo.
- Historial de visitas y control de no presentados.
- Notificaciones de reservas y cambios.
- Alertas por mesas ocupadas demasiado tiempo.
- Alertas por pedidos demorados sin salida.
- Separacion de pedidos.
- Comandas.
- Kitchen Display System.
- Estados de preparacion.
- Tiempos de servicio.
- Alertas de demoras.
- Impresion o envio de tickets.
- Recepcion automatica de comandas desde el POS.
- Separacion de pedidos por estaciones.
- Cocina caliente, fria, bebidas, postres y estaciones especiales.
- Prioridad de pedidos y cronometro de preparacion.
- Estado individual de cada producto.
- Identificacion de pedidos retrasados.
- Marcado de productos listos y notificacion al mesero.
- Historial de tiempos de preparacion.
- Analisis de tiempos por plato y sucursal.
- Deteccion de cuellos de botella.
- Calculo de tiempos estimados de entrega.
- Alertas predictivas por riesgo de demora.

Entregable:

- Operacion coordinada entre camareros, caja y cocina.

## Fase 4 - Inventario, recetas y produccion

Objetivo: controlar insumos y costos de productos.

INVENTORY permanece en Core y es propietario del ledger. Las recetas y la
produccion culinaria pertenecen a PRODUCTION dentro de Restaurant vertical, que
solicita movimientos a INVENTORY mediante contratos.

- Productos, unidades y conversiones.
- Insumos e inventario por sucursal.
- Kardex y movimientos.
- Compras y recepciones.
- Merma y ajustes.
- Recetas y despiece.
- Versiones de recetas y subrecetas bajo propiedad de PRODUCTION.
- Ordenes y lotes de produccion con consumo y salida registrados por INVENTORY.
- Costeo de productos.
- Alertas de stock minimo.
- Conteo fisico.
- Transferencias entre sucursales.
- Inventario central y por sucursal.
- Materias primas y productos terminados.
- Unidades de medida, lotes y vencimientos.
- Entradas, salidas, ajustes y conteos parciales.
- Mermas y desperdicios.
- Consumo automatico de ingredientes por receta.
- Rendimientos, porciones y conversiones de unidades.
- Kardex y trazabilidad.
- Inventario en transito entre sucursales.
- Costo de preparacion, rendimientos, mermas y fichas tecnicas de produccion.

Entregable:

- Costo real por producto.
- Inventario trazable por sucursal.

## Fase 5 - Compras y proveedores

Objetivo: automatizar la reposicion y el abastecimiento.

- Proveedores.
- Listas de precios.
- Solicitudes de compra.
- Ordenes de compra.
- Recepcion parcial y completa.
- Costos historicos.
- Evaluacion de proveedores.
- Sugerencias de compra.
- Automatizacion de pedidos recurrentes.
- Solicitudes, cotizaciones y comparacion de proveedores.
- Aprobaciones por importe y rol.
- Recepcion parcial, completa y de diferencias.
- Facturas de proveedores y costos de transporte.
- Compras centralizadas y compras directas por sucursal.
- Compras recurrentes y historial de precios.
- Propuesta automatica cuando el inventario este bajo.
- Registro fiscal y comercial de proveedores.
- Productos suministrados y condiciones de pago.
- Precios historicos y calificacion de proveedores.
- Historial de compras y documentos contractuales.
- Cuentas por pagar y fechas de vencimiento.
- Lectura automatizada de facturas con revision humana.
- Solicitud de mercancia desde otra sucursal.
- Aprobacion de transferencias.
- Registro del responsable del envio.
- Inventario en transito.
- Confirmacion de recepcion y diferencias.
- Costo y trazabilidad de transferencias.

Entregable:

- Ciclo completo de abastecimiento.

## Fase 6 - Personal y clientes

Objetivo: administrar recursos humanos y relaciones comerciales.

- Empleados por sucursal.
- Contratos y roles.
- Horarios y turnos.
- Asistencia.
- Comisiones.
- Propinas.
- Rendimiento individual.
- Registro de empleados, cargos y departamentos.
- Horarios, turnos y asignaciones por sucursal.
- Control de entrada, salida, horas extra y descansos.
- Ausencias, permisos y vacaciones.
- Distribucion de propinas y comisiones.
- Historial de actividad y rendimiento por empleado.
- Prediccion de personal necesario segun ventas esperadas.
- Alertas por exceso o falta de personal.
- Registro de clientes.
- Fidelizacion.
- CRM basico.
- Segmentacion de clientes.
- Historial de compras, preferencias y frecuencia de visitas.
- Ticket promedio y registro de cumpleaños.
- Puntos, cupones, descuentos y tarjetas de regalo.
- Campañas de marketing por sucursal y segmento.
- Encuestas de satisfacción.
- Registro y revocacion de consentimientos.
- Deteccion de clientes con abandono de frecuencia.
- Propuesta de campañas de recuperacion.
- Integracion con canales de pedidos.
- CRM, historial de consumo y segmentacion.
- Puntos, cupones y tarjetas de regalo.
- Promociones, campañas y encuestas.
- Empleados, contratos, cargos y departamentos.
- Horarios, turnos y asignaciones.
- Vacaciones, ausencias y horas extra.
- Propinas y comisiones.
- Evaluaciones y rendimiento.

Entregable:

- Gestion operativa de personal y clientes.

## Fase 7 - Contabilidad, facturacion y finanzas

Objetivo: convertir las operaciones en informacion financiera confiable.

- Plan contable.
- Centros de costo.
- Ingresos y gastos.
- Cuentas por pagar y cobrar.
- Integracion fiscal.
- Facturacion electronica.
- Conciliacion de caja.
- Arqueos.
- Gastos por sucursal.
- Reportes financieros.
- Ingresos y egresos consolidados.
- Cuentas por pagar y cobrar.
- Flujo de caja.
- Estado de resultados y balance general.
- Centros de costos y costos operativos.
- Calculo de impuestos.
- Conciliacion bancaria.
- Cierre controlado de periodos.
- Exportacion contable e integracion externa.
- Rentabilidad individual y consolidada por sucursal.
- Apertura y cierre de caja por sucursal.
- Base inicial, retiros y entradas de efectivo.
- Tesoreria, ingresos y gastos consolidados.
- Cuentas por cobrar y cuentas por pagar.
- Conciliaciones bancarias y de pasarelas.
- Centros de costos y plan de cuentas.
- Asientos contables y cierres de periodo.
- Balance general y estado de resultados.
- Flujo de caja y reportes tributarios.
- Arqueos parciales y finales.
- Diferencias de caja con responsable y motivo.
- Pagos en efectivo, tarjetas y transferencias.
- Conciliacion con pasarelas de pago.
- Gastos operativos y soportes.
- Trazabilidad de cada movimiento y empleado.
- Integracion independiente con la DIAN.
- Factura electronica de venta.
- Documento equivalente electronico POS cuando corresponda.
- Notas credito y notas de ajuste.
- IVA e impuesto nacional al consumo por producto.
- Numeraciones fiscales por sucursal y punto de venta.
- Identificacion tributaria de la empresa.
- Reportes contables y tributarios.
- Proteccion y trazabilidad de documentos fiscales.
- Respuesta y acuse de documentos electronicos.
- Operacion fiscal controlada durante desconexion.

Entregable:

- Consolidados financieros por sucursal y empresa.

## Fase 8 - Analytics e inteligencia

Objetivo: pasar de registrar datos a producir informacion accionable.

- Dashboard ejecutivo central.
- Vista consolidada de todas las sucursales.
- Vista individual por sucursal.
- Ventas del dia, semana y mes.
- Comparacion de ventas entre sucursales.
- Comparacion contra periodos anteriores.
- Ganancias y margenes estimados.
- Numero de pedidos y ticket promedio.
- Productos mas vendidos y menos vendidos.
- Inventario critico por sucursal.
- Alertas de perdidas y su origen.
- Empleados trabajando y cajas abiertas.
- Pedidos pendientes y gastos del dia.
- Ventas por sucursal, hora y producto.
- Margen y rentabilidad.
- Analisis de inventario.
- Rotacion de productos.
- Comparacion entre sucursales.
- Deteccion de patrones.
- Anomalias de ventas y caja.
- Analista financiero con datos reales.
- Analista de inventario y recomendaciones de compra.
- Analista de ventas y promociones.
- Predicciones de ventas, demanda y consumo.
- Prediccion de personal y compras futuras.
- Deteccion de descuentos, anulaciones y gastos anomalos.
- Asistente administrativo con instrucciones en lenguaje natural.
- Acciones asistidas sujetas a autorizacion.
- Fuentes, incertidumbre y auditoria de respuestas.
- Pronosticos de demanda.
- Sugerencias de compra.
- Alertas operativas.
- Consultas asistidas por IA.
- Reportes de ventas por dia, hora, producto y sucursal.
- Productos mas y menos vendidos.
- Margen y rentabilidad por producto.
- Rotacion, perdidas y vencimientos.
- Ventas y productividad por empleado.
- Diferencias y movimientos de caja.
- Frecuencia y consumo de clientes.
- Precios historicos y desempeno de proveedores.
- Tiempos y retrasos de cocina.
- Rankings y comparativos de sucursales.
- Filtros por fecha, sucursal, empleado, categoria y producto.
- Dashboards generales y por sucursal.
- Comparativos entre marcas y empresas legales.
- KPIs de ventas, costos y rentabilidad.
- Reportes de inventario, compras y clientes.
- Reportes de empleados, cocina y caja.
- Reportes personalizados y exportacion.
- Constructor visual de flujos y reglas automaticas.
- Disparadores, condiciones, acciones y aprobaciones.
- Prediccion de ventas, inventarios y compras.
- Deteccion de anomalias y recomendaciones comerciales.
- Asistente empresarial y analisis de rentabilidad.
- AI Sales para ventas y demanda.
- AI Inventory para inventario y abastecimiento.
- AI Finance para costos, gastos y rentabilidad.
- AI Operations para cocina y tiempos de servicio.
- AI Marketing para clientes y promociones.
- AI Manager para coordinacion y consultas generales.
- Respuestas con datos, periodo, confianza y supuestos.
- Catalogo inicial de eventos de dominio.
- Ejecucion mediante disparador, condicion y accion.
- Aprobaciones y auditoria de resultados.
- Automatizacion de inventario bajo y productos agotados.
- Alertas de pedidos retrasados y caja con diferencias.
- Recuperacion de clientes, ventas anormales y cierres diarios.
- Facturacion electronica e integracion DIAN.
- Pasarelas de pago y plataformas de domicilios.
- WhatsApp, correo electronico y SMS.
- API publica, webhooks y integracion contable.
- Dispositivos POS, impresoras y lectores.
- Integracion con cajones, pantallas y terminales de pago.

Entregable:

- Dashboard central con alertas y recomendaciones.

## Fase 9 - Automatizacion e integraciones

Objetivo: reducir trabajo manual y conectar canales externos.

- Reglas de automatizacion.
- Alertas por eventos.
- Motor visual de reglas con disparadores, condiciones y acciones.
- Automatizacion de reposicion de inventario.
- Solicitud de compra y aprobacion automatica o manual.
- Automatizacion de cierre y diferencias de caja.
- Deteccion de retrasos en cocina y elevacion de prioridad.
- Deteccion de caidas de ventas por sucursal.
- Retrasos programados, aprobaciones y notificaciones.
- Registro de ejecucion, reintentos y manejo de errores.
- Integraciones de pagos.
- Integraciones fiscales.
- Centro de integraciones por empresa y sucursal.
- WhatsApp Business para pedidos y atencion.
- Google Maps para direcciones y domicilios.
- Integracion DIAN y facturacion electronica.
- Pasarelas de pago y conciliacion.
- Analitica externa y automatizacion externa.
- API propia, autenticacion, webhooks y versionado.
- Delivery y marketplaces.
- WhatsApp y reservas.
- Pedidos desde pagina web y aplicacion propia.
- Gestion centralizada de canales digitales.
- Repartidores internos y externos.
- Zonas de cobertura y tarifas de domicilio.
- Asignacion manual y automatica de repartidores.
- Estados y seguimiento de entregas.
- Control de tiempos de preparacion y entrega.
- Integracion con plataformas externas de delivery.
- Importacion y exportacion.
- Webhooks.
- Integraciones contables.
- Integraciones de proveedores.

Entregable:

- Flujos automatizados configurables.

## Fase 10 - Escala, resiliencia y portal cliente

Objetivo: operar de forma continua con mayor volumen y disponibilidad.

- Portal de clientes.
- Reservas y pedidos propios.
- Seguimiento de pedidos.
- Fidelidad y promociones.
- Resiliencia de sincronizacion ante desconexiones prolongadas y multiples
  dispositivos.
- Herramientas de conciliacion y revision humana para conflictos que no puedan
  resolverse con reglas deterministas.
- Optimizacion de cache, almacenamiento local y recuperacion a escala.
- La Fase 10 amplía la resiliencia; no posterga el flujo offline de venta y caja
  requerido desde las primeras fases del POS.
- Colas y procesamiento asincrono.
- Alta disponibilidad.
- Ciberseguridad avanzada.
- Auditorias y cumplimiento.

Entregable:

- Plataforma preparada para crecimiento multi-sucursal.

## Orden recomendado de construccion funcional

0. Administración central del sistema (Superadministrador).
1. Empresa y multisucursal.
2. Usuarios y seguridad.
3. Catálogo de productos.
4. Inventario.
5. Proveedores y compras.
6. Menú, recetas y producción.
7. POS y ventas.
8. Pagos.
9. Caja y operaciones de efectivo.
10. Clientes y fidelización.
11. Reportes y auditoría.

Los numeros identifican lotes funcionales y no dominios tecnicos, crates ni
migraciones. Los lotes 1-11 corresponden al orden del prompt inicial; el lote 0
de PLATFORM es una fundacion previa. Los encabezados funcionales historicos
1-18 de requisitos.md son areas de producto, no esta misma secuencia ni IDs de
dominio. Este recorrido puede solaparse con la construccion de dominios y el
orden SQL, que se define por dependencias de datos.

## Plan maestro de desarrollo

Estimacion orientativa para un equipo pequeño y experimentado: 28 a 45 semanas. Las fases pueden solaparse con equipos paralelos.

### Fase 0 - Arquitectura y fundamentos

Duracion orientativa: 3 a 5 semanas.

- Construir la fundacion PLATFORM de administracion central (referencia
  funcional heredada 0).
- Registrar y controlar empresas y sucursales.
- Administrar planes, suscripciones y funcionalidades.
- Configurar monitoreo, soporte y seguridad global.
- Aplicar acceso temporal y auditado para soporte.
- Arquitectura multi-tenant.
- Fundamentos offline-first del POS: identificadores creados en el dispositivo,
  persistencia local durable, sincronizacion idempotente, conflictos y reglas
  de caja, pagos y numeracion fiscal.
- Base de datos.
- Autenticacion.
- Permisos.
- Empresas y sucursales.
- Diseño visual.
- Infraestructura y despliegue.

Resultado: plataforma base funcional.

### Fase 1 - POS y operacion

Duracion orientativa: 6 a 10 semanas.

- Productos.
- Pedidos.
- Mesas (Restaurant vertical, sobre recursos de ORGANIZATION).
- Cajas.
- Pagos.
- Cocina KDS (Restaurant vertical).
- Impresoras.
- Facturacion.
- Venta y caja offline para las operaciones habilitadas, incluida la
  recuperacion local y sincronizacion sin duplicados.
- Emision fiscal offline solo con numeracion vigente previamente asignada al
  dispositivo y punto de venta.

Resultado: un restaurante puede operar.

### Fase 2 - Administracion empresarial

Duracion orientativa: 5 a 8 semanas.

- Inventario.
- Recetas versionadas, órdenes y lotes bajo la responsabilidad de PRODUCTION, dentro del backend propietario.
- Compras.
- Proveedores.
- Transferencias.
- Gastos.
- Clientes.

Resultado: gestion integral de sucursales.

### Fase 3 - SaaS comercial

Duracion orientativa: 4 a 6 semanas.

- Registro de clientes.
- Planes.
- Suscripciones.
- Limites.
- Pagos recurrentes.
- Panel superadministrador.
- Onboarding.

Resultado: Restaurant OS puede comercializarse.

### Fase 4 - Analitica y automatizacion

Duracion orientativa: 5 a 8 semanas.

- Dashboards.
- Reportes.
- Eventos.
- Automatizaciones.
- Alertas.
- Predicciones iniciales.

Resultado: gestion inteligente.

### Fase 5 - IA y expansion

Duracion orientativa: 5 a 8 semanas.

- AI Manager.
- Agentes especializados.
- CRM avanzado.
- Pedidos digitales.
- API publica.
- Integraciones adicionales.

Resultado: ecosistema empresarial.

### Validaciones antes del lanzamiento

- Dos empresas no pueden acceder a datos de la otra.
- Una sucursal no puede ver informacion no autorizada.
- Las ventas pueden registrarse sin conexion.
- La sincronizacion no duplica ventas.
- Una venta actualiza correctamente el inventario.
- Las recetas calculan correctamente sus costos.
- Las cajas cuadran.
- Los pagos y devoluciones conservan trazabilidad.
- La facturacion cumple requisitos fiscales.
- Los cierres de periodos no alteran datos historicos.
- Varias terminales pueden operar simultaneamente.
- Las copias de seguridad pueden restaurarse.
- Se completan pruebas de carga, seguridad, recuperacion y concurrencia.

Las certificaciones, homologaciones, demoras de proveedores y estabilizacion comercial pueden adicionar tiempo.

## Decisiones innegociables

1. Multi-tenant nativo.
2. Multiempresa y multimarca.
3. Multi-sucursal.
4. Permisos granulares.
5. Offline-first.
6. Arquitectura modular.
7. API propia.
8. Motor de eventos.
9. IA conectada a datos reales.
10. Auditoria completa.

Desde el comienzo tambien se deben establecer versionamiento de API, migraciones de base de datos, pruebas automatizadas y entornos separados de desarrollo, pruebas y produccion.

## Recomendacion final

Construir Restaurant OS como un ecosistema integrado, no como pantallas aisladas.

Una venta debe conectar POS, pedido, cocina, pago, facturacion, inventario, finanzas y analitica. Una sola operacion debe actualizar los procesos correspondientes y conservar trazabilidad.

La misma arquitectura debe servir desde una cafeteria con una caja hasta una cadena con cien sucursales, varias marcas y varias empresas legales.

## Criterios transversales

- Multiempresa y multisucursal desde el inicio.
- Separacion estricta de datos por organizacion.
- Permisos por cargo y ubicacion.
- Auditoria de acciones sensibles.
- API documentada.
- Eventos de dominio.
- Idempotencia en operaciones financieras.
- Manejo de moneda, impuestos y zonas horarias.
- Accesibilidad e internacionalizacion.
- Roles funcionales por cargo y responsabilidad.
- Permisos por accion, modulo, importe y sucursal.
- Separacion de funciones en operaciones sensibles.
- Auditoria de cambios, aprobaciones y sesiones.
- Superadministrador, propietario, gerente y administradores de sucursal.
- Cajeros, meseros, cocineros, inventaristas y contadores.
- Observabilidad desde el primer despliegue.
- Crear indices segun consultas reales.
- Evaluar pg_trgm para busquedas de texto.
- Particionar tablas de alto volumen por fecha.
- Contabilidad balanceada por asiento y reversos.
- Transferencias con estados y ajustes de diferencias.
- Pruebas unitarias, de integracion y extremo a extremo.
- Respaldo y recuperacion ante desastres.
- Rendimiento medible.
