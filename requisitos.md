# Requisitos generales

## Responsabilidad de los documentos

- Este archivo es la fuente de verdad para requisitos, propiedad de dominios y
  limites entre capacidades compartidas y verticales.
- [promt.md](./promt.md) define instrucciones y lotes de trabajo; no redefine
  propietarios ni ubicaciones.
- [ROADMAP.md](./ROADMAP.md) organiza fases y entregables; no crea otra
  clasificación de dominios.

## Vision del producto

Restaurant OS sera una plataforma integral para gestionar restaurantes con multiples sucursales. No se limitara a registrar pedidos y pagos: tambien debe apoyar la operacion, controlar recursos, automatizar procesos y generar inteligencia empresarial.

## Modelo SaaS multiempresa

Restaurant OS sera una plataforma SaaS que atendera una cadena propia y tambien clientes externos.

### Arquitectura vertical configurable

Las funcionalidades de restaurantes se conservaran como el primer vertical completo del sistema.

- Core: capacidad base reutilizable por distintos verticales.
- Restaurant Pack: capacidades propias de restaurantes.
- Optional: capacidad activable por tenant, marca o sucursal.

Las mesas, comandas, cocina, recetas gastronomicas y domicilios no deben integrarse como dependencias obligatorias del nucleo.

- Las mesas pueden representarse como recursos reservables.
- Las comandas pertenecen a KITCHEN y no son ordenes/lotes de PRODUCTION.
- La cocina puede representarse como un centro de produccion.
- Las estaciones pueden representarse como centros de trabajo.
- Las recetas gastronomicas pertenecen a PRODUCTION; su formula puede
  reutilizar conceptos genericos como BOM sin trasladar el flujo culinario a Core.
- Los domicilios pueden representarse como cumplimiento de pedidos.

Otros verticales podran utilizar conceptos generales sin crear dependencias a mesas, cocinas o recetas gastronomicas.

### Limite de propiedad y ubicación de módulos

- Los cuatro procesos son independientes: Admin Platform Backend, Admin BFF,
  Public BFF y Public Backend.
- Según [ADR-0008](docs/adr/0008-module-ownership-across-four-processes.md),
  Admin Platform Backend es propietario únicamente de PLATFORM. Public Backend
  es propietario de todos los demás módulos de negocio canónicos.
- Admin BFF y Public BFF son procesos de composición y exposición HTTP/OpenAPI;
  no poseen dominios, schemas ni tablas de negocio.
- PLATFORM vive en
  `backend/admin-platform-backend/modules/platform/`; los demás módulos
  canónicos viven en `backend/public-backend/modules/<modulo>/`.
- Cada módulo pertenece a un único backend y conserva su lógica, contratos,
  persistencia, schema, rol, migraciones e historial SQLx.
- `crates/` contiene únicamente capacidades técnicas compartidas, contratos
  versionados y adaptadores. No aloja módulos propietarios de negocio.
- Las reglas gastronómicas siguen perteneciendo a KITCHEN, PRODUCTION y las
  capacidades propias del servicio de restaurante. Su propiedad lógica no
  cambia por la nueva distribución física.
- CATALOG conserva la propiedad de productos y agrupaciones comerciales
  genéricas. El menú gastronómico, cursos, modificadores culinarios y reglas
  de servicio no se trasladan a CATALOG.
- Ningún módulo puede acceder directamente a las tablas de otro módulo.

## Arquitectura empresarial

### Plataforma

Restaurant OS sera el SaaS de gestion que presta el servicio a distintos propietarios.

### Jerarquia obligatoria

La plataforma debe gestionar esta estructura:

1. Plataforma Restaurant OS.
2. Tenant o cliente SaaS.
3. Grupo empresarial.
4. Empresa legal.
5. Marca comercial.
6. Sucursal.
7. Area operativa.
8. Estacion.
9. Bodega.
10. Caja.
11. Terminal POS.

El tenant siempre sera obligatorio para cualquier operacion empresarial, aunque el usuario no deba administrarlo directamente. El grupo empresarial es opcional. Las relaciones entre empresa legal, marca y sucursal deben permitir herencia fiscal y excepciones controladas.

### Tenant

- Representa al cliente que contrata Restaurant OS.
- Separa datos de otros clientes SaaS.
- Puede contener varios grupos empresariales.
- Puede contener varias empresas legales.
- Puede contener varias marcas.
- Puede contener varias sucursales.

### Grupo empresarial

- Es opcional.
- Agrupa empresas relacionadas bajo un mismo propietario.
- Permite consolidaciones segun los permisos.
- Puede contener varias empresas legales.
- No reemplaza la identidad fiscal de cada empresa.

### Empresa legal

- Representa la entidad fiscal y contable.
- Tiene datos tributarios propios.
- Tiene identificacion fiscal propia.
- Puede operar varias marcas.
- Puede tener varias sucursales.
- Mantiene libros, documentos y cuentas segun su configuracion.
- Permite separar obligaciones tributarias entre entidades relacionadas.

### Marca comercial

- Representa el nombre comercial o formato.
- Puede ser un restaurante, cafeteria, bar, franquicia u otra identidad.
- Puede pertenecer a una empresa legal.
- Puede operar varias sucursales.
- Puede tener catalogo central propio.
- Puede compartir recursos con otras marcas solo dentro del tenant autorizado.

### Sucursal

- Representa el lugar fisico donde opera el negocio.
- Pertenece a una marca.
- Debe tener una empresa legal efectiva asignada para sus operaciones fiscales.
- Puede heredar la empresa legal predeterminada de la marca.
- Puede tener una excepcion fiscal por sucursal cuando la configuracion lo permita.
- Tiene cajas, cocinas, bodegas, areas y terminales.
- Tiene inventario, ventas, gastos y personal propios.

### Area

- Representa una division interna de la sucursal.
- Ejemplos: cocina, salon, bar y terraza.
- Puede contener mesas, estaciones o recursos.

### Estacion

- Representa un punto especializado de preparacion.
- Ejemplos: parrilla, bebidas y postres.
- Puede recibir productos asignados desde el KDS.

### Bodega

- Representa un lugar de almacenamiento.
- Puede pertenecer a una sucursal.
- Puede almacenar materias primas o productos terminados.
- Puede tener responsables y ubicaciones internas.

### Caja

- Representa un punto de cobro.
- Pertenece a una sucursal.
- Puede estar asociada a uno o varios terminales.
- Mantiene apertura, movimientos y cierres.

### Terminal

- Representa un dispositivo POS.
- Tiene identificador unico.
- Pertenece a una caja, sucursal y tenant.
- Puede tener numeracion fiscal reservada.
- Puede operar offline segun la configuracion.

### Contexto obligatorio de operaciones

Toda operacion debe conocer:

- Tenant al que pertenece.
- Grupo empresarial, cuando aplique.
- Empresa legal asociada.
- Marca comercial asociada.
- Sucursal donde ocurre.
- Usuario responsable.
- Caja o terminal, cuando aplique.
- Area o estacion, cuando aplique.
- Bodega, cuando aplique.

No se debe permitir mezclar operaciones entre empresas legales, marcas o sucursales sin una relacion autorizada y registrada.

### Nombre y alcance

Restaurant OS sera el nombre provisional de la plataforma.

- Plataforma SaaS de gestion integral de restaurantes.
- Arquitectura multiempresa.
- Arquitectura multimarca.
- Arquitectura multisucursal.
- Preparada para restaurantes independientes, cadenas, cafeterias, bares y otros formatos.

### Jerarquia

- Empresa A: cadena propia.
- Empresa B: cliente externo con restaurante independiente.
- Empresa C: cliente externo con cadena de cafeterias.
- Empresa N: futuros clientes.
- Cada empresa puede tener una o varias marcas.
- Cada marca puede operar una o varias sucursales.
- El nucleo central aplica aislamiento de datos, usuarios, suscripciones y seguridad.

### Tipos de usuarios empresariales

- Cuenta propia de la empresa operadora de restaurantes.
- Propietarios externos que contratan la plataforma.
- Cadenas externas que administran multiples sucursales.
- Restaurantes independientes que utilizan el sistema.

Todos los usuarios deben operar sobre la misma plataforma, pero dentro de una empresa o tenant aislado.

### Principios de aislamiento

- Separar los datos de cada tenant.
- Separar usuarios y roles por tenant.
- Separar sucursales por tenant.
- Separar configuraciones por tenant.
- Separar catalogos y precios por tenant.
- Separar inventarios por tenant.
- Separar clientes y proveedores por tenant.
- Separar reportes y analitica por tenant.
- Separar integraciones y credenciales por tenant.
- Impedir cualquier acceso cruzado entre tenants.

### Jerarquia empresarial

- Tenant o cuenta SaaS.
- Empresa u organizacion.
- Marca.
- Sucursal.
- Usuarios.
- Cajas y dispositivos.
- Modulos configurados.

Una cuenta propia puede administrarse como cualquier otro tenant, salvo por las funciones operativas propias del proveedor SaaS.

## Grupo A - Administracion de la plataforma SaaS

Modulo interno utilizado por el propietario y operadores de Restaurant OS para administrar todos los tenants.

## Módulo 0 - Administración central del sistema (referencia funcional heredada)

Este módulo permite al propietario o administrador principal controlar toda la plataforma SaaS antes de administrar empresas individuales.

### Administración de empresas

- Crear empresas registradas.
- Editar empresas registradas.
- Activar empresas.
- Suspender empresas.
- Eliminar o anonimizar empresas según las políticas aplicables.
- Consultar el historial de cambios de cada empresa.
- Registrar motivos y responsables de cambios sensibles.

### Administración de sucursales

- Visualizar sucursales de todas las empresas.
- Consultar estado de las sucursales.
- Gestionar sucursales dentro de los permisos establecidos.
- Activar o suspender sucursales desde el control central.
- Comparar actividad y estado general entre empresas.

### Superadministradores

- Crear superadministradores autorizados.
- Revocar acceso superadministrador.
- Separar administración global de acceso a datos privados.
- Mantener registro de quienes tuvieron acceso al control total.
- Aplicar aprobaciones adicionales para operaciones sensibles.

### Planes y suscripciones

- Administrar licencias.
- Administrar vencimientos.
- Administrar límites de usuarios, sucursales y terminales.
- Administrar funcionalidades contratadas.
- Administrar periodos de prueba.
- Administrar renovaciones y suspensiones.

### Control de módulos

- Habilitar funcionalidades por empresa.
- Deshabilitar funcionalidades por empresa.
- Aplicar excepciones de plan.
- Respetar dependencias entre módulos.
- Registrar cambios y motivo.

### Monitoreo general

- Consultar actividad de las empresas.
- Consultar estado de sus servicios.
- Consultar ventas agregadas solo cuando exista autorización.
- Consultar uso de almacenamiento, API, automatizaciones e IA.
- Generar alertas por suspensión, vencimiento o consumo excesivo.

### Configuración global

- Administrar parámetros generales de la plataforma.
- Administrar regiones y despliegues.
- Administrar integraciones globales.
- Administrar plantillas SaaS.
- Administrar políticas de soporte y retención.

### Seguridad global

- Registrar auditoría de acceso.
- Registrar cambios administrativos.
- Administrar sesiones globales.
- Detectar accesos anómalos.
- Revocar sesiones y credenciales.
- Mantener trazabilidad independiente de la auditoría empresarial.

### Soporte

- Acceder a información de una empresa solo mediante autorización temporal.
- Justificar el motivo del acceso.
- Limitar el alcance y duración.
- Permitir enmascaramiento o anonimización.
- Revocar automáticamente el acceso al cerrar el caso.
- Registrar todas las acciones realizadas durante soporte.

### Diferencias entre administradores

| Tipo | Alcance |
|---|---|
| Superadministrador | Toda la plataforma y todas las empresas |
| Administrador de empresa | Su empresa y las sucursales autorizadas |
| Administrador de sucursal | Su sucursal y sus operaciones autorizadas |
| Empleado | Funciones permitidas por rol |

El Módulo 0 debe construirse antes de los demás porque define el registro, control y relación de todas las empresas dentro de Restaurant OS.

### Submodulos

1. Panel de administracion global.
2. Gestion de clientes o tenants.
3. Registro de nuevos restaurantes.
4. Activacion y desactivacion de cuentas.
5. Planes y suscripciones.
6. Facturacion de los servicios SaaS.
7. Gestion de pagos.
8. Control de licencias.
9. Limites de usuarios.
10. Limites de sucursales.
11. Modulos habilitados por plan.
12. Gestion de pruebas gratuitas.
13. Renovaciones.
14. Suspensiones.
15. Historial de clientes.
16. Soporte tecnico.
17. Registro de incidencias.
18. Estado de servicios.
19. Uso de almacenamiento.
20. Consumo de IA y automatizaciones.

### Panel global

- Consultar tenants activos y suspendidos.
- Consultar facturacion y pagos SaaS.
- Consultar uso agregado.
- Consultar incidencias.
- Comparar consumo entre tenants.
- Mostrar alertas operativas de la plataforma.

### Gestion de tenants

- Crear tenants.
- Registrar datos del cliente SaaS.
- Crear contactos administrativos.
- Activar cuentas.
- Desactivar cuentas.
- Suspender temporalmente.
- Eliminar o anonimizar datos segun politicas.
- Mantener historial de cambios.

### Suscripciones

- Crear planes.
- Configurar precios.
- Configurar vigencias.
- Configurar periodos de prueba.
- Configurar renovaciones.
- Configurar suspensiones.
- Configurar reactivaciones.
- Registrar facturas SaaS.
- Registrar pagos recibidos.
- Registrar facturas vencidas.
- Mantener historial de suscripciones.

### Ejemplo de planes

| Caracteristica | Basico | Profesional | Enterprise |
|---|---:|---:|---:|
| Sucursales | 1 | 5 | Personalizable |
| POS | Si | Si | Si |
| Inventario | Basico | Avanzado | Avanzado |
| Compras | Basico | Si | Si |
| Reportes | Basicos | Avanzados | Personalizados |
| IA | Limitada | Avanzada | Avanzada |
| API | No | Limitada | Completa |
| Soporte | Estandar | Prioritario | Especializado |

Los planes son ejemplos configurables y no deben quedar escritos directamente en el codigo.

### Limites configurables

- Limite de usuarios.
- Limite de sucursales.
- Limite de dispositivos.
- Limite de almacenamiento.
- Limite de API.
- Limite de reportes programados.
- Limite de automatizaciones.
- Limite de ejecuciones de IA.
- Limite de integraciones.
- Modulos habilitados.
- Ventanas y periodos de consumo.

Los limites deben administrarse por plan y por tenant, permitiendo excepciones autorizadas.

### Uso y consumo

- Medir usuarios activos.
- Medir sucursales activas.
- Medir almacenamiento utilizado.
- Medir llamadas API.
- Medir ejecuciones de automatizaciones.
- Medir consultas y acciones de IA.
- Medir incidentes y soporte.
- Generar alertas por exceso de consumo.
- Permitir facturacion adicional segun configuracion.

### Incidencias y soporte

- Registrar solicitudes de soporte.
- Registrar incidencias.
- Clasificar severidad.
- Asignar responsables.
- Registrar tiempos de respuesta.
- Registrar estado de resolucion.
- Mantener historial por tenant.
- Mostrar estado global de servicios.

### Requisitos de seguridad

- Separar administracion SaaS de administracion de cada tenant.
- Restringir el acceso a superadministradores autorizados.
- Registrar todas las acciones de administracion.
- Evitar que soporte acceda a datos sensibles sin aprobacion.
- Permitir mascaramiento o anonimizacion.
- Mantener auditoria independiente del servicio SaaS.

## Grupo B - Administracion empresarial

Modulo utilizado por propietarios y administradores internos de un tenant para configurar su organizacion comercial.

### Submodulos

- Empresas.
- Grupos empresariales.
- Marcas.
- Sucursales.
- Configuracion fiscal.
- Configuracion de moneda.
- Impuestos.
- Horarios.
- Salones.
- Areas.
- Estaciones.
- Bodegas.
- Cajas.
- Terminales.
- Impresoras.
- Objetivos comerciales.
- Configuracion centralizada.
- Configuraciones particulares por sucursal.

### Gestion empresarial

- Crear grupos empresariales.
- Crear empresas legales.
- Crear marcas comerciales.
- Crear sucursales.
- Activar o desactivar entidades.
- Asociar sucursales a una empresa legal y marca.
- Consultar estructuras consolidadas.
- Restringir operaciones fuera del alcance autorizado.

### Configuracion operativa

- Configurar datos fiscales.
- Configurar moneda.
- Configurar impuestos.
- Configurar horarios.
- Configurar salones.
- Configurar areas.
- Configurar estaciones.
- Configurar bodegas.
- Configurar cajas.
- Configurar terminales POS.
- Configurar impresoras.
- Configurar objetivos comerciales.
- Configurar metas por sucursal.

### Herencia de configuraciones

- Mantener valores centrales administrados por empresa o tenant.
- Permitir que las sucursales hereden valores centrales.
- Permitir excepciones autorizadas por sucursal.
- Permitir excepciones por marca.
- Permitir excepciones por empresa legal.
- Mostrar el origen del valor efectivo.
- Permitir diferenciar valor central, heredado y local.
- Recalcular configuraciones cuando cambie el valor central.
- Evitar sobrescribir excepciones locales sin autorizacion.
- Mantener historial de cambios y responsable.

### Ejemplo de precios

El administrador puede definir un precio central de $25.000 para una hamburguesa. Las sucursales heredaran ese precio, mientras una sucursal autorizada puede definir una excepcion local sin modificar las demas sucursales.

### Alcance centralizado

- Aplicar configuraciones a toda la empresa.
- Aplicar configuraciones a marcas seleccionadas.
- Aplicar configuraciones a sucursales seleccionadas.
- Aplicar configuraciones solo a entidades que heredan el valor central.
- Previsualizar cambios antes de ejecutarlos.
- Programar cambios futuros.
- Permitir reversion controlada.

### Requisitos por sucursal

- Las configuraciones locales deben pertenecer al tenant correspondiente.
- Las sucursales deben respetar la empresa legal asociada.
- Las marcas deben tener catalogos independientes o compartidos segun configuracion.
- Los cambios fiscales deben aplicarse solo a entidades autorizadas.
- Los terminales deben operar con configuracion vigente de su sucursal.

## Grupo C - Operacion del restaurante

Modulo utilizado para las operaciones diarias dentro de una sucursal.

### Operacion principal

- Punto de venta.
- Pedidos.
- Mesas.
- Reservas.
- Lista de espera.
- Meseros.
- Comandas.
- Cocina KDS.
- Bar KDS.
- Pantallas de preparacion.
- Entregas.
- Domicilios.
- Pedidos para recoger.
- Division de cuentas.
- Pagos mixtos.
- Descuentos.
- Propinas.
- Devoluciones.
- Anulaciones.
- Cierre de pedidos.

### Capacidades comunes

El nucleo operativo debe compartir:

- Catalogo de productos.
- Modelo de pedidos.
- Gestion de clientes.
- Medios de pago.
- Caja.
- Impresion.
- Estados de preparacion.
- Facturacion.
- Inventario.
- Auditoria.

Las modalidades deben activar o desactivar capacidades sin duplicar el nucleo.

### Modalidades de negocio

| Modalidad | Funcionalidades |
|---|---|
| Restaurante | Mesas, meseros y comandas |
| Cafeteria | Mostrador y pedidos rapidos |
| Bar | Mesas, cuentas abiertas y productos por ronda |
| Comida rapida | Turnos, combos y preparacion rapida |
| Delivery | Direcciones, repartidores y seguimiento |

### Activacion por entidad

- Activar capacidades por tenant.
- Activar capacidades por marca.
- Activar capacidades por sucursal.
- Permitir varias modalidades en una sucursal.
- Mantener parametros propios de cada modalidad.
- Evitar interfaces o sistemas separados para cada tipo de negocio.
- Mostrar solo operaciones habilitadas segun configuracion.

### Requisitos operativos

- Todo pedido debe indicar sucursal, marca y modalidad aplicable.
- Toda operacion debe respetar permisos y caja activa.
- Los estados deben ajustarse a la modalidad sin cambiar el nucleo.
- Las herramientas especiales deben integrarse con inventario y contabilidad.
- Los canales externos deben llegar al mismo modelo de pedido.

## Grupo D - Productos, menu y produccion

Esta agrupacion funcional no define propiedad tecnica. CATALOG es propietario
de productos comerciales y agrupaciones comerciales genericas; Restaurant
vertical es propietario de menus gastronomicos y reglas de servicio; PRODUCTION
es propietario de recetas, formulas y ordenes de produccion; INVENTORY conserva
existencias y movimientos; KITCHEN coordina la preparacion de pedidos de clientes.

### Catalogo comercial (CATALOG)

- Categorias.
- Productos.
- Variantes.
- Presentaciones.
- Modificadores.
- Adiciones.
- Combos.
- Promociones.
- Disponibilidad.
- Precios.
- Impuestos por producto.

### Recetas y produccion (PRODUCTION)

- Definir receta central.
- Definir subrecetas.
- Registrar cantidades por unidad.
- Registrar rendimiento.
- Registrar merma esperada.
- Registrar porciones.
- Calcular costo de produccion.
- Calcular costo unitario.
- Calcular margen.
- Vincular productos con ingredientes.
- Vincular modificadores con consumos adicionales.
- Vincular componentes de combos.
- Crear ordenes y lotes de produccion; registrar materiales consumidos y
  productos obtenidos mediante referencias a INVENTORY.

### Menús gastronómicos y servicio (Restaurant vertical)

- Componer menús gastronómicos con referencias a productos de CATALOG.
- Configurar menús por horario, sucursal, día y temporada.
- Configurar cursos, modificadores culinarios y reglas de servicio.
- Configurar productos y menús para mostrador, mesa o delivery.

### Variantes por sucursal

- Permitir aplicar recetas centrales o excepciones de PRODUCTION por sucursal.
- Permitir sustituciones locales de ingredientes y rendimientos controlados.
- Mantener fichas tecnicas y costos de produccion versionados.
- Permitir precios locales.
- Permitir impuestos locales segun configuracion fiscal.

Un producto comercial de CATALOG puede referenciar una receta efectiva de
PRODUCTION. La formula y su version no se duplican en CATALOG.

### Disponibilidad comercial (CATALOG)

- Activar o desactivar productos por sucursal.
- Configurar disponibilidad comercial por horario.
- Configurar agotados temporales.
- Configurar restricciones de venta.

La composición y programación de menús gastronómicos corresponde a Restaurant vertical, que utiliza los productos y referencias comerciales de CATALOG.

### Requisitos por sucursal

- La disponibilidad debe calcularse dentro de la sucursal.
- El consumo de inventario debe usar la receta efectiva de la sucursal.
- PRODUCTION debe resolver la receta y version efectiva aplicable a la sucursal.
- El costo debe utilizar insumos y precios de la sucursal cuando existan.
- Las excepciones deben conservar usuario y fecha.
- El POS debe usar solo productos disponibles para su contexto.

## Grupo E - Inventario y logistica

Modulo operativo para controlar existencias y movimientos en bodegas y sucursales.

### Inventario

- Bodegas.
- Inventarios por sucursal.
- Materias primas.
- Productos terminados.
- Kardex.
- Movimientos.
- Entradas.
- Salidas.
- Ajustes.
- Conteos fisicos.
- Mermas.
- Desperdicios.
- Lotes.
- Vencimientos.
- Trazabilidad.
- Transferencias.
- Solicitudes de mercancia.
- Recepciones.
- Consumo de recetas.
- Existencias minimas.
- Existencias maximas.

### Operaciones

- Registrar entradas por compra o produccion.
- Registrar salidas por venta o consumo.
- Registrar ajustes autorizados.
- Registrar conteos parciales y completos.
- Registrar merma y desperdicio.
- Registrar recepcion parcial o completa.
- Registrar solicitudes entre sucursales.
- Registrar transferencias y recepciones.
- Mantener inventario en transito.

### Trazabilidad

- Identificar lote.
- Identificar fecha de vencimiento.
- Identificar bodega origen.
- Identificar bodega destino.
- Identificar proveedor o sucursal origen.
- Identificar pedido o receta consumida.
- Mantener historial completo de movimientos.

### Consumo automatico

- Consumir ingredientes al confirmar ventas o preparacion segun politica.
- Solicitar a PRODUCTION la receta efectiva y versionada del producto vendido.
- INVENTORY registra el consumo mediante movimientos propios; SALES no escribe
  directamente en el ledger ni en las tablas de recetas.
- Convertir unidades.
- Aplicar rendimientos y porciones.
- Revertir consumo ante devoluciones o anulaciones segun configuracion.
- Evitar consumos duplicados por reintentos.

### Requisitos por sucursal

- Los saldos deben separarse por sucursal y bodega.
- Las existencias minimas y maximas deben configurarse localmente.
- Las transferencias deben indicar origen y destino.
- Los ajustes deben requerir motivo y aprobacion segun rol.
- Los reportes deben detectar faltantes, vencimientos y desperdicios.

## Grupo F - Compras y proveedores

Modulo para gestionar abastecimiento, cotizaciones, recepciones y obligaciones con proveedores.

### Proveedores

- Registrar proveedores.
- Registrar datos fiscales y contactos.
- Registrar productos suministrados.
- Registrar condiciones de pago.
- Registrar precios historicos.
- Comparar proveedores.
- Calificar proveedores.
- Mantener historial de compras.
- Registrar contratos y documentos.

### Compras

- Solicitudes de compra.
- Cotizaciones.
- Ordenes de compra.
- Aprobaciones.
- Recepcion de mercancia.
- Recepcion parcial o completa.
- Facturas recibidas.
- Cuentas por pagar.
- Historial de precios.
- Comparacion de proveedores.
- Programacion de compras.
- Compras centralizadas.
- Compras locales por sucursal.

### Flujo de compra

1. Crear solicitud.
2. Solicitar cotizaciones.
3. Comparar proveedores.
4. Aprobar proveedor y condiciones.
5. Emitir orden de compra.
6. Recibir mercancia.
7. Conciliar cantidades y precios.
8. Registrar factura.
9. Programar pago.
10. Mantener trazabilidad hasta el inventario.

### Recepcion y conciliacion

- Vincular recepcion con orden de compra.
- Vincular facturas con recepcion.
- Registrar diferencias de cantidad.
- Registrar diferencias de precio.
- Registrar lotes y vencimientos.
- Registrar costos de transporte.
- Registrar pagos parciales.
- Registrar cuentas por pagar.
- Programar vencimientos.

### Compras centrales y locales

- Comprar centralmente para varias sucursales.
- Distribuir mercancia recibida.
- Permitir compras directas por sucursal.
- Respetar limites de aprobacion.
- Mantener proveedores globales o locales.
- Consolidar compras por tenant.

### Requisitos por sucursal

- Las solicitudes pueden pertenecer a una sucursal o a una compra central.
- Las recepciones deben registrarse en la bodega correspondiente.
- Las facturas deben indicar empresa legal y sucursal.
- Los reportes deben comparar proveedores y costos por sucursal.
- Las aprobaciones deben respetar roles e importes.

## Grupo G - Clientes, fidelizacion y marketing

Vista funcional compuesta por CUSTOMERS para perfiles, consentimientos, segmentos y fidelizacion; AUTOMATION para campañas; e INTEGRATIONS para entrega y seguimiento de comunicaciones.

### CRM

- CRM de clientes.
- Registro de datos de contacto.
- Historial de consumo.
- Segmentacion.
- Sucursales visitadas.
- Preferencias.
- Frecuencia de visitas.
- Ticket promedio.
- Cumpleanos.
- Consentimientos.
- Historial de comunicaciones.

### Fidelizacion

- Puntos.
- Reglas de acumulacion.
- Canje de puntos.
- Fidelizacion por sucursal.
- Fidelizacion por marca.
- Fidelizacion central por tenant.
- Cupones.
- Beneficios y cupones de fidelizacion; las reglas de promociones pertenecen a los dominios comerciales que las aplican.
- Tarjetas de regalo.
- Saldos de tarjetas.
- Vigencia de beneficios.

### Marketing

- Definir reglas y calendario de campañas en AUTOMATION.
- Seleccionar segmentos autorizados de CUSTOMERS.
- Emitir beneficios de fidelizacion o cupones mediante CUSTOMERS.
- Entregar comunicaciones y registrar resultados de canal mediante INTEGRATIONS.
- Medir adopcion y conversion en ANALYTICS.
- Consultar y respetar preferencias y consentimientos vigentes de CUSTOMERS.

### Experiencia

- Encuestas.
- Opiniones.
- Calificacion de atencion.
- Notificaciones.
- Recordatorios de reservas.
- Confirmaciones de pedidos.
- Estados de domicilio.
- Mensajes de recuperacion.

### Recuperacion

- Detectar clientes que dejaron de visitar.
- Comparar frecuencia historica.
- Calcular riesgo de abandono.
- Recomendar incentivos.
- Respetar limites de comunicacion.
- Medir resultados de recuperacion.

### Requisitos por sucursal

- Los clientes pueden compartirse dentro del tenant.
- El consumo puede consolidarse por marca y sucursal.
- Los beneficios deben indicar el alcance permitido.
- Las campañas de AUTOMATION pueden ser centrales o locales.
- Los datos personales deben respetar permisos y consentimientos.

## Grupo H - Personal y recursos humanos

Modulo para administrar empleados, contratos, horarios, asistencia y compensaciones.

### Registro laboral

- Empleados.
- Contratos.
- Cargos.
- Departamentos.
- Estado laboral.
- Datos personales protegidos.
- Asignacion principal por sucursal.
- Asignaciones temporales.

### Horarios y turnos

- Crear turnos.
- Crear horarios.
- Asignar empleados.
- Controlar cambios de turno.
- Detectar conflictos.
- Configurar turnos por sucursal.
- Mantener historial de asignaciones.

### Asistencia

- Entrada y salida.
- Descansos.
- Vacaciones.
- Ausencias.
- Permisos.
- Horas extras.
- Retrasos.
- Correcciones autorizadas.
- Reportes de asistencia.

### Compensaciones

- Workforce mantiene las condiciones contractuales de remuneracion y aporta turnos y asistencia a los procesos de nomina.
- El calculo y pago de nomina, propinas, comisiones, bonificaciones y sus reglas de distribucion pertenecen a Finance/Payroll; esa capacidad sigue pendiente de implementacion.
- La distribucion de propinas debe mantener trazabilidad y separarse de los importes de venta.

### Rendimiento

- Rendimiento por empleado.
- Evaluaciones.
- Ventas atendidas.
- Pedidos procesados.
- Ticket promedio.
- Puntualidad.
- Horas trabajadas.
- Registro de actividad.
- Comparacion por turno y sucursal.
- Las metricas de ventas y propinas se consolidan desde SALES/FINANCE; las predicciones de demanda pertenecen a ANALYTICS, que puede consumir capacidades transversales de IA.

### Requisitos por sucursal

- Los empleados pueden asignarse a varias sucursales autorizadas.
- Los horarios deben pertenecer a una sucursal.
- Las compensaciones deben calcularse dentro del contexto correspondiente.
- Los reportes deben respetar restricciones de datos laborales.
- Los cambios deben conservar auditoria.

## Grupo I - Finanzas y contabilidad

Modulo para administrar resultados, tesoreria, contabilidad y obligaciones tributarias.

### Operacion financiera

- Caja.
- Tesoreria.
- Gastos.
- Ingresos.
- Cuentas por cobrar.
- Cuentas por pagar.
- Conciliaciones.
- Pagos bancarios.
- Movimientos de efectivo.

### Contabilidad

- Centros de costos.
- Contabilidad por sucursal.
- Contabilidad por empresa legal.
- Plan de cuentas.
- Asientos contables.
- Partidas automaticas.
- Ajustes contables.
- Cierres contables.
- Apertura de periodos.
- Reapertura autorizada.

### Estados financieros

- Balance general.
- Estado de resultados.
- Flujo de caja.
- Rentabilidad por sucursal.
- Rentabilidad por marca.
- Consolidacion empresarial.
- Comparaciones de periodos.

### Tributacion

- Reportes tributarios.
- Impuestos por producto.
- IVA.
- Impuesto nacional al consumo cuando corresponda.
- Facturacion electronica.
- Conciliacion fiscal.
- Exportacion contable.

### Conciliaciones

- Conciliar caja.
- Conciliar bancos.
- Consultar diferencias de liquidaciones conciliadas por PAYMENTS.
- Conciliar cuentas por pagar.
- Conciliar cuentas por cobrar.
- Identificar diferencias.
- Mantener historial de resolucion.

### Requisitos por sucursal

- Las operaciones pueden pertenecer a una sucursal o empresa central.
- Los centros de costos deben indicar contexto valido.
- Los estados individuales deben separarse por sucursal.
- Los estados consolidados deben agrupar solo entidades autorizadas.
- Los registros fiscales deben respetar la empresa legal correspondiente.

## Grupo J - Reportes y Business Intelligence

Modulo para convertir datos operativos en indicadores, comparativos y decisiones empresariales.

### Dashboards

- Dashboard general.
- Dashboard por sucursal.
- Dashboard por marca.
- Dashboard por empresa legal.
- Dashboard consolidado del tenant.
- Indicadores KPI.
- Comparativos.
- Metas frente a resultados.

### Reportes operativos

- Ventas.
- Costos.
- Rentabilidad.
- Inventarios.
- Compras.
- Clientes.
- Empleados.
- Cocina.
- Caja.
- Domicilios.
- Reservas.
- Automatizaciones.

### Personalizacion

- Reportes personalizados.
- Filtros por fecha.
- Filtros por sucursal.
- Filtros por marca.
- Filtros por empleado.
- Filtros por categoria y producto.
- Filtros por canal.
- Campos seleccionables.
- Agrupaciones.
- Comparacion de periodos.
- Exportacion de datos.
- Programacion de reportes.

### Requisitos de BI

- Respetar los permisos por tenant y sucursal.
- Indicar moneda y zona horaria.
- Separar datos por empresa legal cuando sea necesario.
- Mostrar hora de actualizacion.
- Diferenciar datos estimados y reales.
- Permitir exportaciones autorizadas.
- Mantener consistencia entre dashboards y reportes.

## Grupo K - Automatizacion e inteligencia artificial

Modulo transversal para reglas visuales, predicciones, deteccion de riesgos y asistencia empresarial.

### Constructor visual

- Constructor visual de flujos.
- Reglas automaticas.
- Disparadores.
- Condiciones.
- Acciones.
- Retrasos programados.
- Aprobaciones.
- Alertas.
- Reintentos.
- Manejo de errores.
- Registro de ejecucion.

### Inteligencia artificial

- Asistente empresarial.
- Consultas sobre datos reales.
- Prediccion de ventas.
- Prediccion de inventarios.
- Prediccion de compras.
- Prediccion de personal.
- Deteccion de anomalias.
- Recomendaciones comerciales.
- Analisis de rentabilidad.
- Analisis de margen.
- Analisis de desperdicios.
- Recuperacion de clientes.

### Acciones asistidas

- Preparar solicitudes de compra.
- Preparar promociones.
- Generar alertas.
- Comparar sucursales.
- Crear informes.
- Preparar cambios operativos.
- Mantener acciones pendientes de aprobacion.

### Requisitos de seguridad

- Respetar permisos por tenant y sucursal.
- Limitar acciones delicadas.
- Solicitar aprobacion para pagos, anulaciones y cambios de inventario.
- Mostrar fuente y periodo de las respuestas.
- Indicar incertidumbre de predicciones.
- Mantener auditoria de instrucciones y ejecuciones.

## Grupo L - Integraciones y tecnologia

Modulo transversal para conectar servicios externos, comunicaciones, dispositivos y sistemas contables.

### Integraciones fiscales y contables

- Facturacion electronica.
- Integracion con la DIAN.
- Documentos equivalentes POS.
- Notas credito y ajustes.
- Integracion contable.
- Conciliacion de documentos fiscales.

### Pagos y canales

- Pasarelas de pago.
- WhatsApp Business.
- Correo electronico.
- SMS.
- Plataformas de domicilios.
- Aplicaciones de terceros.
- Redes de delivery.

### API y eventos

- API publica.
- API privada.
- Webhooks.
- Versionado.
- Autenticacion.
- Permisos por cliente de API.
- Limites de uso.
- Trazabilidad de llamadas.

### Hardware

- Dispositivos POS.
- Impresoras.
- Lectores de codigos.
- Cajones de dinero.
- Pantallas de cocina.
- Terminales de pago.
- Integracion con hardware.

### Operacion de integraciones

- Activar integraciones por tenant.
- Activar integraciones por sucursal.
- Gestionar credenciales seguras.
- Registrar estado y errores.
- Permitir reintentos.
- Mantener historial de sincronizacion.
- Evitar duplicar operaciones externas.

### Requisitos de seguridad

- Cifrar credenciales.
- Restringir permisos.
- Registrar configuracion y cambios.
- Permitir revocacion.
- Mantener trazabilidad entre evento interno y resultado externo.

## Diseño de base de datos

La base principal sera PostgreSQL con un modelo multi-tenant desde el primer dia.

### Especificación técnica v1.0

Arquitectura definitiva:

- Shared Database, Schema per Module: una base PostgreSQL compartida inicialmente y un schema PostgreSQL por módulo.
- Tenant Isolation mediante tenant_id.
- PostgreSQL Row-Level Security.
- Dedicated Deployment Option para clientes Enterprise.
- Mismo modelo de datos en infraestructura compartida y dedicada.
- Migracion de tenant sin reconstruir su estructura de informacion.

Modelo comercial:

- Planes de suscripcion.
- Cobros adicionales por consumo o funcionalidades.
- Limites configurables por plan y por tenant.
- Posibilidad de infraestructura dedicada para Enterprise.

### Estrategia inicial

- Utilizar una base compartida.
- Cada módulo administra sus propias tablas dentro de su schema PostgreSQL; no hay tablas compartidas entre módulos.
- Aislar estrictamente los datos por tenant.
- No crear una base independiente por restaurante inicialmente.
- Permitir bases dedicadas posteriormente para clientes Enterprise.
- Utilizar migraciones reproducibles.
- Utilizar claves foráneas y restricciones únicamente dentro del schema y límite de propiedad del mismo módulo.
- Las referencias entre módulos usan IDs estables y contratos; no crean FKs, joins, vistas ni consultas directas entre schemas.
- Utilizar indices segun patrones de consulta.

### Tenant compartido

- Todas las entidades operativas deben incluir tenant_id.
- Las consultas deben validar tenant_id.
- Las reglas deben impedir relaciones cruzadas.
- Las sucursales deben pertenecer al tenant correspondiente.
- Las credenciales externas deben estar aisladas por tenant.

### Schemas PostgreSQL por módulo

Cada fila identifica un schema PostgreSQL real y exclusivo del módulo propietario; no son namespaces lógicos intercambiables. No se comparten tablas entre módulos.

| Schema PostgreSQL | Contenido y responsabilidad del módulo | Prioridad |
|---|---|---|
| platform | SaaS, planes y suscripciones | Alta |
| identity | Usuarios y permisos | Alta |
| organization | Empresas y sucursales | Alta |
| catalog | Productos, variantes, precios y agrupaciones comerciales genericas | Alta |
| production | Recetas versionadas, fichas tecnicas y ordenes/lotes gastronomicos (Restaurant vertical) | Alta |
| sales | Pedidos, cuentas y ciclo comercial generico | Alta |
| kitchen | Cocina, comandas y preparacion gastronomica (Restaurant vertical) | Alta |
| inventory | Inventarios y movimientos | Alta |
| procurement | Compras y proveedores | Media |
| payments | Metodos, transacciones, capturas y reembolsos | Alta |
| cash | Cajas, turnos y movimientos de efectivo | Alta |
| customers | CRM y fidelizacion | Media |
| workforce | Personal y turnos | Media |
| finance | Tesoreria, cuentas y contabilidad | Media |
| billing | Documentos fiscales | Alta |
| integrations | Conectores, credenciales, webhooks y dispositivos | Alta |
| automation | Flujos automatizados | Media |
| analytics | Indicadores, tendencias, modelos semanticos y dashboards | Media |
| audit | Auditoria y trazabilidad | Alta |
| reporting | Plantillas, generacion, exportacion y distribucion de informes | Media |

Cada schema PostgreSQL pertenece a un único módulo. No se permiten namespaces lógicos que sustituyan el aislamiento mediante schemas PostgreSQL.

No se debe crear una base independiente por cada dominio o restaurante inicialmente. Los módulos comparten una base PostgreSQL, pero cada uno conserva sus tablas, rol, migraciones e historial SQLx exclusivos dentro de su schema. Las transacciones son locales al módulo.

### Integridad

- Definir claves primarias y restricciones de unicidad.
- Las claves foráneas solo pueden relacionar tablas del mismo módulo/schema; las referencias cross-module son IDs lógicos validados mediante contratos.
- Definir indices de tenant y sucursal.
- Evitar datos huérfanos.
- Registrar versiones de configuracion.
- Mantener fechas y zonas horarias.
- Utilizar identificadores unicos para operaciones offline.

### Escalamiento posterior

- Medir volumen por tenant.
- Separar lectura analitica cuando sea necesario.
- Permitir indices y particiones.
- Permitir bases dedicadas para Enterprise.
- Permitir replicas de lectura.
- No ocultar consultas sin aislamiento del tenant.

### Jerarquia definitiva

- Restaurant OS: plataforma SaaS.
- Tenant: cliente propietario.
- Grupo empresarial: opcional.
- Empresa legal: identidad fiscal y contable.
- Marca comercial: restaurante, bar, cafeteria, franquicia u otra identidad.
- Sucursal: ubicacion fisica.
- Bodega: almacenamiento dentro de una sucursal.
- Caja: punto de cobro.
- Terminal: dispositivo POS.
- Area: zona fisica.
- Mesa: recurso dentro de un area.
- Estacion: punto de preparacion.

Todas las entidades operativas deben relacionarse con el tenant y, cuando corresponda, con la sucursal.

### Precision comercial y tributaria

Un tenant puede tener varias empresas legales.

- Una empresa legal puede operar varias marcas.
- Una marca puede estar presente en varias sucursales.
- La estructura comercial no debe confundirse con la estructura tributaria.
- Una marca no necesariamente corresponde a una empresa legal distinta.
- Una sucursal no necesariamente tiene un NIT independiente.
- Las operaciones comerciales pueden consolidarse sin mezclar datos fiscales.
- Los documentos fiscales deben asociarse a la empresa legal correcta.

### Matriz de aislamiento

| Informacion | Nivel de propiedad |
|---|---|
| Planes comerciales | Plataforma |
| Suscripciones | Tenant |
| Usuarios | Plataforma y membresia por tenant |
| Empresas legales | Tenant |
| Marcas | Tenant |
| Sucursales | Tenant |
| Productos | Tenant |
| Precios | Tenant y sucursal |
| Inventarios | Tenant y bodega |
| Ventas | Tenant y sucursal |
| Pagos | Tenant y operacion |
| Configuracion | Plataforma, tenant y sucursal |

Las relaciones entre registros de distintos tenants deben estar prohibidas.

Ejemplo:

- Un pedido del tenant A no puede utilizar un producto del tenant B.
- Una sucursal del tenant A no puede usar una bodega del tenant B.
- Una venta del tenant A no puede pagar con una caja del tenant B.
- Las manipulaciones directas de API deben validarse con el tenant activo.

## Tablas principales iniciales

Esta estructura representa los dominios iniciales. No obliga a crear todas las tablas en la primera fase.

### Plataforma SaaS

- tenants
- tenant_settings
- subscription_plans
- subscriptions
- subscription_invoices
- subscription_payments
- plan_features
- tenant_feature_overrides
- usage_records
- support_tickets

### Empresas y sucursales

- business_groups
- legal_entities
- brands
- locations
- location_settings
- departments
- areas
- stations
- warehouses
- registers
- terminals
- printers

### Usuarios y permisos

- users
- user_profiles
- tenant_memberships
- employee_profiles
- roles
- permissions
- role_permissions
- user_roles
- access_scopes
- user_location_assignments
- sessions
- audit_logs

### Productos y catalogo

- categories
- products
- product_variants
- product_modifiers
- modifier_groups
- product_prices
- product_location_settings
- units_of_measure
- unit_conversions
- combos
- combo_items
- menus
- menu_items

### Produccion y recetas

- recipes
- recipe_versions
- recipe_components
- recipe_component_alternatives
- recipe_steps
- production_orders
- production_order_materials
- production_batches
- material_transactions
- material_transaction_lines
- output_reports
- output_report_lines

### Ventas y operacion

- orders
- order_items
- order_item_modifiers
- order_taxes
- order_discounts
- order_status_history
- table_sessions
- reservations
- waitlist
- receipts

Pagos, cajas y recursos fisicos se describen en sus dominios propietarios; esta lista no implica que SALES almacene esas entidades.

### Cocina

- kitchen_tickets
- kitchen_ticket_items
- kitchen_stations
- preparation_events
- preparation_times
- kitchen_status_history

### Inventario

- inventory_items
- stock_balances
- stock_movements
- stock_movement_items
- stock_counts
- stock_count_items
- stock_transfers
- stock_transfer_items
- stock_lots
- stock_adjustments
- waste_records
- inventory_reservations

### Compras y proveedores

- suppliers
- supplier_products
- purchase_requests
- purchase_orders
- purchase_order_items
- goods_receipts
- goods_receipt_items
- supplier_invoices
- supplier_invoice_items

### Finanzas

- chart_of_accounts
- accounting_periods
- journal_entries
- journal_entry_lines
- expenses
- expense_categories
- receivables
- payables
- bank_accounts
- bank_transactions
- reconciliations

### Clientes y personal

- customers
- customer_addresses
- customer_visits
- loyalty_accounts
- loyalty_transactions
- promotions
- campaigns
- employees
- employee_contracts
- employee_shifts
- attendance_records
- tips

### Automatización y datos analíticos

- automation_workflows
- workflow_versions
- workflow_triggers
- workflow_executions
- workflow_steps
- workflow_approvals
- notifications
- anomaly_events
- forecasts

La capacidad de IA es transversal y no tiene schema ni tablas propios aprobados actualmente. Si una función requiere persistencia, los datos pertenecen al módulo dueño del proceso y se guardan en su schema. Conversaciones, configuración y medición de consumo no deben materializarse como tablas de un supuesto módulo `AI` sin un ADR nuevo.

### Criterios de modelado

- Las tablas deben incluir tenant_id cuando sean datos multitenant.
- Las entidades operativas deben incluir sucursal o empresa cuando aplique.
- Las claves pueden dividirse o consolidarse al definir relaciones reales.
- Las tablas financieras deben mantener integridad e idempotencia.
- Las tablas historicas deben preservar trazabilidad.
- Las tablas analiticas pueden ser derivadas o materializadas.

### Modelo entidad-relacion - Plataforma SaaS

Entidades principales del dominio comercial:

- tenants
- tenant_settings
- subscriptions
- subscription_plans
- plan_versions
- plan_features
- tenant_addons
- addons
- subscription_items
- usage_records
- saas_invoices
- subscription_payments

### Relaciones principales

- Un tenant tiene suscripciones.
- Una suscripcion usa una version de plan.
- Un plan puede tener varias versiones.
- Una version de plan define limites y funcionalidades.
- Un tenant puede contratar addons.
- Un addon puede facturarse por cantidad o consumo.
- Las suscripciones generan items facturables.
- Los registros de uso generan cobros adicionales.
- Las facturas SaaS pertenecen al tenant que contrata Restaurant OS.
- Los pagos de suscripcion se registran contra las facturas SaaS.

### Modelo comercial

El modelo puede cobrar por:

- Plan base.
- Sucursales adicionales.
- Terminales adicionales.
- Usuarios adicionales.
- Almacenamiento.
- Consumo de IA.
- Automatizaciones ejecutadas.
- Integraciones premium.
- Infraestructura dedicada.
- Servicios adicionales.

Los limites deben definirse en plan_versions y tenant_feature_overrides.

### Diccionario de plataforma SaaS

| Tabla | Campos principales | Descripcion |
|---|---|---|
| tenants | id, name, slug, status | Clientes de la plataforma |
| tenant_settings | tenant_id, settings | Configuracion general |
| subscription_plans | id, code, name | Planes comerciales |
| plan_versions | plan_id, version, price | Versiones de planes |
| plan_features | plan_version_id, feature_code | Funcionalidades incluidas |
| subscriptions | tenant_id, plan_version_id, status | Suscripciones |
| addons | code, billing_type, name | Servicios adicionales |
| tenant_addons | tenant_id, addon_id, quantity | Adicionales contratados |
| subscription_items | subscription_id, description, amount | Componentes cobrados |
| usage_records | tenant_id, metric_code, quantity | Consumo facturable |
| saas_invoices | tenant_id, subtotal, tax, total | Facturas de la plataforma |
| saas_invoice_items | invoice_id, description, amount | Detalle de cobros |
| saas_payments | invoice_id, amount, provider_ref | Pagos recibidos |
| tenant_deployments | tenant_id, deployment_type, region | Infraestructura asignada |
| tenant_feature_overrides | tenant_id, feature_code, enabled | Excepciones comerciales |

### Consideraciones comerciales

- Los limites no deben guardarse directamente en tenants.
- Los limites deben pertenecer a las versiones de los planes.
- Los limites pueden personalizarse por tenant.
- Los cobros adicionales deben tener un catalogo propio.
- Los conceptos de cobro deben tener reglas de medicion.
- Las suscripciones deben conservar la version contratada.
- Los precios contratados deben conservarse historicamente.
- Un cambio de precio futuro no debe modificar facturas anteriores.

Ejemplo de limites:

```json
{
  "max_locations": 5,
  "max_users": 25,
  "max_terminals": 10,
  "max_storage_gb": 20,
  "max_monthly_ai_requests": 1000,
  "offline_enabled": true,
  "advanced_analytics": true
}
```

### Diccionario de organizacion

| Tabla | Campos principales | Descripcion |
|---|---|---|
| business_groups | id, tenant_id, name | Grupos empresariales |
| legal_entities | id, tenant_id, tax_id, legal_name | Entidades legales |
| brands | id, tenant_id, legal_entity_id, name | Marcas comerciales |
| locations | id, tenant_id, brand_id, code, timezone | Sucursales |
| departments | id, tenant_id, location_id, name | Departamentos |
| areas | id, tenant_id, location_id, area_type | Areas fisicas |
| stations | id, tenant_id, area_id, name, station_type | Estaciones de preparacion |
| tables | id, tenant_id, area_id, table_number, capacity | Mesas |
| warehouses | id, tenant_id, location_id, code | Bodegas |
| registers | id, tenant_id, location_id, code | Cajas |
| terminals | id, tenant_id, register_id, device_code | Dispositivos POS |
| printers | id, tenant_id, location_id, printer_type | Impresoras |
| location_settings | location_id, settings | Configuracion particular |

### Requisitos organizacionales

- Cada tabla operativa debe incluir tenant_id cuando corresponde.
- La marca debe relacionarse con la entidad legal correspondiente.
- La sucursal debe relacionarse con la marca y el tenant.
- Las areas deben relacionarse con una sucursal.
- Las estaciones deben relacionarse con areas o areas operativas.
- Las mesas deben relacionarse con areas.
- Las bodegas deben relacionarse con sucursales.
- Las cajas deben relacionarse con sucursales.
- Los terminales deben relacionarse con cajas y sucursales.
- Las impresoras deben relacionarse con sucursales o recursos operativos autorizados.

Cada sucursal debe tener su propia zona horaria.

- La zona horaria debe aplicarse a ventas, turnos y reportes.
- La zona horaria debe almacenarse como identificador IANA cuando sea posible.
- Las empresas internacionales pueden tener sucursales en zonas horarias diferentes.
- Las fechas internas deben conservarse con precision UTC y presentarse en zona local.

### Diccionario de identidad y permisos

| Tabla | Campos principales | Descripcion |
|---|---|---|
| users | id, email, status | Identidad global |
| user_profiles | user_id, display_name | Perfil del usuario |
| tenant_memberships | tenant_id, user_id, status | Acceso a una empresa |
| roles | tenant_id, code, name | Roles |
| permissions | code, description | Catalogo de permisos |
| role_permissions | role_id, permission_id | Permisos por rol |
| membership_roles | membership_id, role_id, scope | Roles asignados |
| access_scopes | scope_type, scope_id | Alcances de autorizacion |
| employee_profiles | user_id, tenant_id, employee_number | Perfil laboral |
| sessions | user_id, device_id, expires_at | Sesiones |
| user_location_assignments | tenant_id, user_id, location_id | Sucursales permitidas |
| audit_logs | actor, action, entity, timestamp | Auditoria |

### Identidad y membresias

- La identidad de usuario es global.
- Los permisos pertenecen a cada tenant.
- Las membresias permiten acceso a empresas independientes.
- Un usuario puede trabajar para varios tenants.
- Una sesion debe indicar tenant activo.
- Un usuario debe cambiar de tenant dentro de sus membresias autorizadas.
- El rol se asigna dentro de una membresia.
- Los roles no deben compartirse automaticamente entre tenants.

### Alcances

- Los roles pueden tener alcance global de tenant.
- Los roles pueden tener alcance por grupo empresarial.
- Los roles pueden tener alcance por empresa legal.
- Los roles pueden tener alcance por marca.
- Los roles pueden tener alcance por sucursal.
- Los roles pueden tener alcance por area o estacion.
- Las asignaciones de sucursal deben limitar operaciones.

### Auditoria

- Las sesiones deben conservar dispositivo y expiracion.
- Los cambios de rol deben quedar auditados.
- Los cambios de permisos deben quedar auditados.
- Las asignaciones de sucursal deben quedar auditadas.
- Los accesos sensibles deben registrar actor y contexto.

### Diccionario de catalogo

| Tabla | Campos principales | Descripcion |
|---|---|---|
| categories | name, parent_id | Categorias jerarquicas |
| products | tenant_id, sku, name, product_type | Productos |
| product_variants | product_id, name | Presentaciones |
| product_prices | product_id, location_id, price | Precios por ubicacion |
| product_location_settings | product_id, location_id, availability | Disponibilidad |
| modifier_groups | name, selection_rules | Grupos de modificadores |
| product_modifiers | product_id, modifier_id | Modificadores asociados |
| menus | name, schedule | Menus |
| menu_items | menu_id, product_id | Productos del menu |
| combos | name, price | Combos |
| combo_items | combo_id, product_id | Componentes |
| units_of_measure | code, name, dimension | Unidades |
| unit_conversions | from_unit, to_unit, factor | Conversiones |

### Diccionario de produccion

| Tabla | Campos principales | Descripcion |
|---|---|---|
| recipes | tenant_id, recipe_code, output_catalog_variant_id | Formula de produccion |
| recipe_versions | recipe_id, version_number, yield_quantity | Version inmutable de receta |
| recipe_components | recipe_version_id, inventory_stock_item_id, quantity | Insumos de una receta |
| recipe_steps | recipe_version_id, step_number | Pasos de preparacion |
| production_orders | recipe_version_id, idempotency_key, order_status | Orden planificada de produccion |
| production_batches | production_order_id, inventory_lot_id, batch_status | Lote producido y referencia al lote fisico |
| material_transactions | production_order_id, inventory_movement_id | Consumo o salida registrado en INVENTORY |

### Productos inventariables

- Los ingredientes deben representarse como products inventariables.
- Cada ingrediente debe tener tipo, unidad y configuracion de inventario.
- Las recetas de PRODUCTION deben referenciar insumos de INVENTORY mediante
  identificadores y contratos publicos, no mediante escritura en tablas ajenas.
- Los modificadores pueden consumir ingredientes adicionales.
- Los combos pueden referenciar productos comerciales; la receta aplicable se
  resuelve en PRODUCTION.
- Los costos pueden calcularse desde unidades e ingredientes.
- Las conversiones deben aplicarse antes de descontar existencias.

### Versiones y excepciones

- Las recetas de PRODUCTION deben tener version.
- Los precios deben tener vigencia por sucursal.
- Los menus deben tener horario.
- La disponibilidad debe ser configurable por sucursal.
- Los cambios de receta deben conservar la version anterior y no alterar
  ordenes de produccion ya iniciadas.

### Separacion de facturacion

Las facturas SaaS que Restaurant OS cobra a sus clientes no deben mezclarse con las facturas fiscales emitidas por los restaurantes.

- Las facturas SaaS pertenecen al dominio platform o billing SaaS.
- Las facturas fiscales de restaurantes pertenecen al esquema billing.
- Los clientes SaaS no deben administrar documentos fiscales ajenos.
- Los pagos SaaS no deben contabilizarse como cobros operativos de sucursales.
- Los consumos deben trazarse por tenant y periodo.

### Diccionario de ventas y operacion

| Tabla | Campos principales | Descripcion |
|---|---|---|
| orders | tenant_id, location_id, order_number, status | Pedidos |
| order_items | order_id, product_id, quantity | Detalle del pedido |
| order_item_modifiers | order_item_id, modifier_id | Personalizaciones |
| order_discounts | order_id, discount_type, amount | Descuentos |
| order_taxes | order_id, tax_code, amount | Impuestos |
| order_status_history | order_id, old_status, new_status | Historial |
| reservations | tenant_id, location_id, customer_id, scheduled_at | Reservas |
| waitlist | tenant_id, location_id, customer_id, position | Lista de espera |
| table_sessions | tenant_id, table_id, opened_at, closed_at | Ocupacion |
| cash_sessions | tenant_id, register_id, opened_by, closed_by | Turnos de caja |
| cash_movements | tenant_id, cash_session_id, movement_type, amount | Movimientos |
| receipts | tenant_id, order_id, receipt_number | Comprobantes |

Las sesiones de cobro, metodos, transacciones y reembolsos pertenecen a PAYMENTS. SALES conserva pedidos, cuentas y su estado comercial, y referencia los pagos mediante contratos.

### Separacion de conceptos comerciales

- Un pedido no necesariamente equivale a una factura.
- Un pago no necesariamente equivale a una venta fiscalmente emitida.
- Un pedido puede estar parcialmente pagado.
- Un pago puede aplicarse a uno o varios documentos operativos segun configuracion.
- Una venta fiscal puede agrupar o segmentar pedidos.
- Los comprobantes fiscales deben mantener concepto propio.
- Las notas credito deben relacionarse con la venta fiscal original.
- Las notas de ajuste deben conservar su documento de origen.
- Los reembolsos deben relacionarse con pago y documento fiscal aplicable.

Estos conceptos deben conservar trazabilidad independiente sin mezclar sus estados.

### Diccionario de inventario y abastecimiento

| Tabla | Campos principales | Descripcion |
|---|---|---|
| inventory_items | tenant_id, product_id, tracking_type | Elementos inventariables |
| stock_balances | warehouse_id, product_id, quantity | Existencias actuales |
| stock_movements | tenant_id, movement_type, occurred_at | Libro de movimientos |
| stock_movement_items | movement_id, product_id, quantity_delta | Detalle del movimiento |
| stock_lots | tenant_id, product_id, lot_number, expiry_date | Lotes |
| stock_counts | tenant_id, warehouse_id, count_date | Conteos |
| stock_count_items | count_id, product_id, counted_quantity | Resultados |
| stock_transfers | tenant_id, source_warehouse, destination_warehouse | Transferencias |
| stock_transfer_items | transfer_id, product_id, quantity | Productos transferidos |
| waste_records | tenant_id, product_id, quantity, reason | Mermas |
| inventory_reservations | tenant_id, product_id, quantity, reference | Reservas de existencias |
| suppliers | tenant_id, name, tax_id, status | Proveedores |
| supplier_products | supplier_id, product_id, price | Catalogo del proveedor |
| purchase_requests | tenant_id, location_id, requested_by | Solicitudes |
| purchase_orders | tenant_id, supplier_id, status, total | Ordenes |
| purchase_order_items | purchase_order_id, product_id, quantity | Detalles |
| goods_receipts | tenant_id, purchase_order_id, received_at | Recepciones |
| supplier_invoices | tenant_id, supplier_id, invoice_number | Facturas recibidas |

### Reglas de inventario

- Las existencias actuales deben ser una proyeccion derivada.
- Los movimientos deben ser inmutables una vez confirmados.
- Los ajustes deben registrar motivo y responsable.
- Los conteos deben conciliarse con stock_balances.
- Los lotes deben conservar numero y vencimiento.
- Las transferencias deben identificar origen y destino.
- Las reservas deben liberar existencias segun su ciclo.
- Las recepciones deben generar movimientos de entrada.
- La confirmacion de venta debe originar una solicitud de consumo segun receta.
- INVENTORY resuelve con PRODUCTION la receta efectiva mediante contratos
  publicos y registra los movimientos unicamente en su propio ledger.

Las diferencias deben corregirse mediante ajustes trazables, no mediante edicion directa del saldo.

### Diccionario financiero, fiscal y analitico

| Tabla | Campos principales | Descripcion |
|---|---|---|
| expenses | tenant_id, location_id, category_id, amount | Gastos |
| expense_categories | tenant_id, name, accounting_code | Categorias |
| chart_of_accounts | tenant_id, account_code, name | Plan de cuentas |
| accounting_periods | tenant_id, starts_at, ends_at, status | Periodos |
| journal_entries | tenant_id, entry_number, date, status | Asientos |
| journal_entry_lines | entry_id, account_id, debit, credit | Partidas contables |
| receivables | tenant_id, customer_id, balance | Cuentas por cobrar |
| payables | tenant_id, supplier_id, balance | Cuentas por pagar |
| bank_accounts | tenant_id, account_name, currency | Cuentas bancarias |
| bank_transactions | tenant_id, reference, amount | Movimientos bancarios |
| reconciliations | tenant_id, period, status | Conciliaciones |
| fiscal_documents | tenant_id, document_type, status | Documentos fiscales |
| fiscal_document_events | tenant_id, document_id, event_type | Historial fiscal |
| customers | tenant_id, name, email, phone | Clientes |
| loyalty_accounts | tenant_id, customer_id, points_balance | Fidelizacion |
| loyalty_transactions | tenant_id, account_id, points | Movimientos de puntos |
| employees | tenant_id, employee_number, status | Empleados |
| employee_shifts | tenant_id, employee_id, starts_at, ends_at | Turnos |
| attendance_records | tenant_id, employee_id, clock_in, clock_out | Asistencia |
| forecasts | tenant_id, metric, forecast_date, value | Predicciones |
| ai_insights | tenant_id, insight_type, confidence, payload | Hallazgos analíticos derivados de IA, bajo ownership de ANALYTICS |

### Reglas financieras

- Los importes deben usar NUMERIC.
- Los periodos contables deben bloquear modificaciones historicas.
- Los asientos deben balancear debito y credito.
- Las conciliaciones deben conservar diferencias y resolucion.
- Los documentos fiscales deben mantener estados independientes.
- Los eventos fiscales deben conservar respuesta, fecha y proveedor.
- Las predicciones deben conservar periodo y datos utilizados.
- Los hallazgos de IA deben conservar confianza y contexto.

## Relaciones, claves y restricciones

### Claves primarias

Las entidades principales deben utilizar UUID.

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

Ventajas:

- Identificadores distribuidos.
- Sincronizacion entre dispositivos.
- Menor dependencia de secuencias centrales.
- Compatibilidad con bases dedicadas.

Las tablas de auditoria o eventos de altísimo volumen pueden evaluarse con identificadores ordenables o particionamiento.

### Claves foraneas multi-tenant

No es suficiente referenciar solo product_id.

Las relaciones dentro del mismo módulo deben validar tenant_id.

```sql
UNIQUE (tenant_id, id)

-- Ejemplo únicamente intra-módulo:
FOREIGN KEY (tenant_id, related_id)
REFERENCES <schema_del_mismo_modulo>.<tabla_propietaria> (tenant_id, id)
```

Una referencia a un producto de CATALOG desde otro módulo no crea una FK hacia `catalog`: conserva el ID lógico y valida tenant/estado mediante el contrato de CATALOG. Las claves foráneas compuestas impiden relaciones cruzadas solo dentro del límite de propiedad del módulo.

### Restricciones por dominio

| Dominio | Restriccion |
|---|---|
| Productos | SKU unico dentro del tenant |
| Sucursales | Codigo unico dentro del tenant |
| Precios | Nunca negativos |
| Cantidades | Mayores que cero en ventas |
| Pagos | Montos positivos |
| Descuentos | No superar el valor permitido |
| Inventario | No aceptar cantidades negativas si la politica lo prohibe |
| Recetas | Rendimiento mayor que cero |
| Transferencias | Origen y destino diferentes |
| Suscripciones | Periodos coherentes |
| Caja | No cerrar dos veces |
| Facturacion | Numeracion segun reglas fiscales |
| Contabilidad | Debe igual a Haber por asiento |
| Lotes | Fecha de vencimiento valida |
| Reservas | Fecha futura segun politica |
| Membresias | Usuario perteneciente al tenant |

### Reglas concurrentes

Algunos casos no pueden resolverse solo con CHECK:

- Precios con periodos superpuestos.
- Saldos negativos bajo concurrencia.
- Numeracion fiscal consecutiva.
- Transferencias simultaneas.
- Dos cierres de caja simultaneos.
- Reservas de inventario sobre el mismo stock.

Estos casos requieren transacciones, bloqueos, reglas deterministas o indices de exclusion.

## Indices recomendados

Los indices deben crearse segun consultas reales y no indiscriminadamente.

| Tabla | Indice | Beneficio |
|---|---|---|
| orders | tenant_id, location_id, created_at | Consultas de ventas |
| orders | tenant_id, status | Pedidos pendientes |
| order_items | tenant_id, order_id | Detalles |
| products | tenant_id, name | Busqueda de productos |
| products | tenant_id, sku | Consulta por codigo |
| stock_balances | tenant_id, warehouse_id, product_id | Inventario |
| stock_movements | tenant_id, product_id, occurred_at | Kardex |
| payment_sessions | tenant_id, sales_order_id | Sesiones de cobro vinculadas a pedidos |
| customers | tenant_id, phone | Buscar clientes |
| audit_logs | tenant_id, occurred_at | Auditoria |
| subscriptions | tenant_id, status | Estado comercial |
| usage_records | tenant_id, metric_code, occurred_at | Facturacion por consumo |

### Optimizaciones adicionales

- Utilizar indices GIN con pg_trgm para busquedas de texto.
- Evaluar pg_trgm para nombres de productos y clientes.
- Medir consultas antes de agregar indices especiales.
- Considerar particionamiento por fecha en tablas de alto volumen.
- Priorizar particionamiento para ventas, movimientos, auditoria y eventos.
- Revisar costo de escritura y almacenamiento de cada indice.
- Mantener indices alineados con el contexto tenant_id.

## Integridad financiera e inventarios

### Contabilidad

- Cada asiento debe tener varias líneas.
- La suma de debitos debe ser igual a la suma de créditos.
- Un asiento contabilizado no debe editarse directamente.
- Las correcciones deben registrar un asiento de reversión.
- Después de revertir, puede registrarse un nuevo asiento autorizado.
- Los periodos cerrados deben impedir modificaciones.
- Las correcciones deben mantener referencias al asiento original.

### Inventario

- Cada movimiento publicado debe generar variaciones de stock.
- Los movimientos originales no deben modificarse directamente.
- Las diferencias deben registrarse mediante movimientos adicionales.
- Las existencias deben poder reconstruirse desde el libro de movimientos.

Ejemplo de transferencia:

| Movimiento | Bodega A | Bodega B |
|---|---:|---:|
| Transferencia de 20 kg | -20 kg | +20 kg |

Estados de transferencia:

- Borrador.
- Solicitada.
- Aprobada.
- En transito.
- Recibida.
- Cerrada.
- Cancelada.

Si mercancía se pierde en tránsito:

- Debe registrarse una diferencia.
- Debe conservarse el movimiento original.
- Debe crearse un ajuste autorizado.
- Debe identificarse responsable y motivo.
- Debe quedar trazable en ambas bodegas.

## Infraestructura compartida y dedicada

### Modalidad 1 - Shared Cloud

Ideal para restaurantes independientes y pequenas cadenas.

- Aplicacion compartida.
- Base de datos compartida.
- Aislamiento por tenant.
- Recursos administrados centralmente.

### Modalidad 2 - Dedicated Database

Ideal para cadenas medianas y necesidades especiales.

- Aplicacion compartida.
- Base de datos independiente.
- Credenciales independientes.
- Backups independientes.
- Mismas migraciones y versiones de esquema.

### Modalidad 3 - Dedicated Environment

Ideal para grandes cadenas y clientes Enterprise.

- Aplicacion dedicada.
- Base de datos dedicada.
- Recursos aislados.
- Opciones de red privada.
- Políticas especiales de respaldo.
- Objetivos especiales de disponibilidad.

### Tabla de control

Tabla recomendada:

- Esquema: platform
- Tabla: tenant_deployments

| Campo | Tipo | Funcion |
|---|---|---|
| id | UUID | Identificador |
| tenant_id | UUID | Cliente |
| deployment_type | VARCHAR | shared, dedicated_db, dedicated_full |
| region | VARCHAR | Region geografica |
| database_cluster_ref | VARCHAR | Referencia al cluster |
| database_name_ref | VARCHAR | Referencia segura |
| secret_reference | VARCHAR | Referencia al gestor de secretos |
| deployment_status | VARCHAR | Estado |
| schema_version | VARCHAR | Version de esquema |
| created_at | TIMESTAMPTZ | Creacion |

Nunca guardar contrasenas de base de datos en esta tabla.

- Utilizar un gestor de secretos.
- Guardar solo referencias.
- Rotar credenciales.
- Auditar acceso a secretos.
- Permitir migracion de tenant entre modalidades.

### Migracion entre infraestructuras

El sistema debe permitir migrar un tenant de Shared Cloud a Dedicated Database o Dedicated Environment sin reconstruir sus datos.

Datos que deben preservar:

- Usuarios.
- Empresas.
- Sucursales.
- Productos.
- Recetas.
- Pedidos.
- Inventarios.
- Documentos.
- Auditoria.
- Suscripciones.
- Configuracion.

### Fases de migracion

1. Verificar compatibilidad de esquema.
2. Preparar infraestructura destino.
3. Ejecutar migraciones comunes.
4. Realizar sincronizacion inicial.
5. Ejecutar sincronizacion incremental.
6. Definir ventana controlada de cambio.
7. Detener nuevas operaciones o limitar escrituras.
8. Sincronizar cambios finales.
9. Verificar integridad.
10. Cambiar el despliegue activo.
11. Ejecutar pruebas posteriores.
12. Mantener reversión controlada.

### Verificacion de integridad

- Comparar conteos de entidades.
- Comparar totales financieros.
- Comparar existencias.
- Comparar pedidos y pagos.
- Comparar documentos fiscales.
- Comparar registros de auditoria.
- Comparar suscripciones y configuracion.
- Reportar diferencias antes de habilitar destino.

Todas las instalaciones deben utilizar el mismo modelo de dominios y el mismo sistema de migraciones por módulo. Cada módulo conserva su propio historial SQLx; no se comparte la tabla `_sqlx_migrations` entre módulos.

## Preparacion de base de datos para produccion

Antes de habilitar el entorno productivo deben configurarse:

- Un usuario exclusivo para migraciones.
- Un usuario de aplicacion sin privilegios de propietario.
- Politicas RLS para cada tabla nueva.
- Contexto de tenant por transaccion.
- Secretos fuera de la base de datos.
- Backups probados.
- Restauraciones probadas.

### Usuarios de PostgreSQL

- Las migraciones deben ejecutarse con un usuario exclusivo.
- El usuario de aplicacion no debe ser propietario de las tablas.
- El usuario de aplicacion no debe tener BYPASSRLS.
- Los privilegios deben seguir el principio de minimo privilegio.
- Los usuarios administrativos deben separarse del usuario operativo.

### Row-Level Security

- Cada tabla multi-tenant debe tener una politica RLS.
- Las politicas deben validar tenant_id.
- El contexto de tenant debe establecerse despues de autenticar.
- El contexto debe establecerse despues de autorizar al usuario.
- El contexto debe estar limitado a una transaccion.
- El usuario de aplicacion no debe confiar solo en filtros de API.
- Las consultas sin contexto deben ser rechazadas o no acceder a datos.

### Secretos y respaldos

- No almacenar contrasenas en tablas de configuracion.
- Utilizar gestor de secretos.
- Rotar credenciales.
- Auditar accesos a secretos.
- Ejecutar backups periodicos.
- Ejecutar restauraciones de prueba.
- Medir tiempo de recuperacion.
- Verificar integridad despues de restaurar.

## Reglas oficiales de diseño

1. Ninguna operación empresarial puede existir sin tenant.
2. Ningún pedido puede utilizar productos de otro tenant.
3. Ninguna sucursal puede acceder a inventarios no autorizados.
4. Ningún pago confirmado puede eliminarse físicamente.
5. Ningún movimiento de inventario publicado puede modificarse silenciosamente.
6. Ningún asiento contable confirmado puede editarse sin reversión.
7. Los precios deben conservar historial.
8. Las recetas deben estar versionadas.
9. Las operaciones offline deben tener identificadores idempotentes.
10. Toda operación crítica debe tener trazabilidad.
11. Las facturas fiscales y las facturas SaaS deben mantenerse separadas.
12. Los planes comerciales deben evolucionar sin modificar registros históricos.
13. Todos los clientes deben utilizar el mismo contrato de datos independientemente de infraestructura.
14. Las acciones de IA deben respetar los mismos permisos que las acciones humanas.

## Arquitectura técnica definitiva

La siguiente tabla conserva los dominios y sus responsabilidades y aplica la distribución aprobada en ADR-0008. PLATFORM pertenece a Admin Platform Backend; todos los demás dominios de negocio pertenecen a Public Backend. Los BFF no son propietarios de estos módulos.

### Dominios con propietario único

| Dominio canonico | Responsabilidad | Ubicacion fisica |
|---|---|---|
| PLATFORM | SaaS, tenants, planes, suscripciones, limites e infraestructura | `backend/admin-platform-backend/modules/platform/` |
| IDENTITY | Usuarios, membresias, RBAC, ABAC y sesiones | `backend/public-backend/modules/identity/` |
| ORGANIZATION | Empresas legales, grupos, marcas, sucursales y recursos fisicos | `backend/public-backend/modules/organization/` |
| CATALOG | Productos, variantes, precios y agrupaciones comerciales genericas | `backend/public-backend/modules/catalog/` |
| SALES | Pedidos, cuentas y ciclo comercial generico | `backend/public-backend/modules/sales/` |
| PAYMENTS | Metodos, cobros, autorizaciones, capturas, reembolsos y liquidaciones | `backend/public-backend/modules/payments/` |
| CASH | Cajas, turnos, arqueos y movimientos fisicos de efectivo | `backend/public-backend/modules/cash/` |
| KITCHEN | Estaciones operativas, comandas, KDS y preparacion gastronomica | `backend/public-backend/modules/kitchen/` |
| INVENTORY | Existencias, lotes fisicos, bodegas, movimientos y transferencias | `backend/public-backend/modules/inventory/` |
| PROCUREMENT | Proveedores, cotizaciones, compras y recepciones | `backend/public-backend/modules/procurement/` |
| PRODUCTION | Recetas versionadas, BOM, rendimientos, ordenes y lotes gastronomicos | `backend/public-backend/modules/production/` |
| BILLING | Facturacion fiscal, documentos electronicos y numeracion | `backend/public-backend/modules/billing/` |
| FINANCE | Tesoreria, cuentas por cobrar/pagar y contabilidad | `backend/public-backend/modules/finance/` |
| WORKFORCE | Empleados, turnos, asistencia y compensaciones | `backend/public-backend/modules/workforce/` |
| CUSTOMERS | CRM, fidelizacion, consentimiento y segmentacion | `backend/public-backend/modules/customers/` |
| INTEGRATIONS | API, webhooks, conectores, credenciales y hardware | `backend/public-backend/modules/integrations/` |
| AUTOMATION | Flujos, disparadores, campanas, condiciones y acciones | `backend/public-backend/modules/automation/` |
| ANALYTICS | KPI, tendencias, datos semanticos y dashboards | `backend/public-backend/modules/analytics/` |
| AUDIT | Auditoria transversal e historial de acciones | `backend/public-backend/modules/audit/` |
| REPORTING | Plantillas, generacion, exportacion y distribucion de informes | `backend/public-backend/modules/reporting/` |

Estos nombres son las identidades técnicas canónicas; no se les asignan números
de módulo. KITCHEN y PRODUCTION conservan su identidad y propiedad lógica por
sus responsabilidades gastronómicas. No se duplican ni se convierten en
subcarpetas de un crate compartido: cada uno vive bajo el backend que sea su
propietario.

### Topología de los cuatro backends

Restaurant OS se compone de cuatro procesos/binarios independientes:

1. Admin Platform Backend: contiene PLATFORM.
2. Admin BFF: proceso de composición para las interfaces administrativas; no posee módulos de negocio.
3. Public BFF: proceso de composición para las interfaces públicas y operativas; no posee módulos de negocio.
4. Public Backend: contiene todos los demás módulos de negocio canónicos.

Los BFF son procesos separados de sus respectivos backends; no existe un único `api-server` que aloje todos los módulos ni un único BFF compartido. Las operaciones administrativas sobre dominios empresariales se dirigen mediante contratos al módulo propietario en Public Backend; el frontend que inicia la operación no cambia el ownership. Entre procesos se utiliza gRPC para solicitudes/respuestas, NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda. Dentro de cada backend, los módulos que comparten proceso usan los contratos públicos y puertos/traits locales descritos en el estándar modular; los hechos durables se gestionan mediante Outbox/Inbox. Docker Compose debe representar cuatro servicios independientes. Es una topología objetivo, no evidencia de que ya esté implementada.

`AI` es una capacidad transversal, no un dominio propietario ni un módulo con schema propio en esta etapa. Se accede mediante un puerto/capacidad y utiliza herramientas autorizadas de los módulos. Cada módulo conserva los datos que necesita para su propio proceso; no se asigna a AI la propiedad de conversaciones, configuración o consumo. Esta regla está registrada en [ADR-0006](docs/adr/0006-ai-cross-cutting-capability-no-owned-schema.md). Si una necesidad futura exige persistencia centralizada o un módulo AI, deberá aprobarse mediante un ADR nuevo. La librería `tenancy`, si se conserva como soporte compartido, no es un dominio propietario: PLATFORM mantiene la propiedad del ciclo de vida de tenants.

Algunos comentarios de las migraciones y datos iniciales en Audit/Reporting aun
conservan el nombre historico `purchasing`. Es un alias heredado de PROCUREMENT,
no un dominio ni crate separado. No editar migraciones que pudieran estar
aplicadas; si se requiere normalizar valores persistidos, hacerlo mediante una
migracion posterior compatible.

### Clasificación funcional

- Los grupos A-L son vistas comerciales o funcionales de alto nivel.
- Las numeraciones funcionales historicas describen lotes o capacidades, no
  dominios tecnicos, crates ni versiones de migracion.
- Los dominios tecnicos canonicos son los nombres de la tabla anterior.
- Las funcionalidades detalladas deben mantenerse una sola vez bajo su dominio responsable.
- Los conectores externos pertenecen a INTEGRATIONS aun cuando sean usados por SALES, BILLING o PROCUREMENT.
- Los domicilios son pedidos de SALES y cumplimiento operativo; las plataformas externas son INTEGRATIONS.

### Propiedad de recursos físicos

| Recurso | Propietario |
|---|---|
| Areas fisicas | ORGANIZATION |
| Mesas fisicas | ORGANIZATION |
| Estaciones fisicas | ORGANIZATION |
| Sesiones de venta y cuentas | SALES |
| Asignacion de mesas, ocupacion, reservas y lista de espera | Restaurant vertical |
| Configuracion operativa de cocina | KITCHEN (Restaurant vertical) |
| Comandas y preparacion | KITCHEN |

El Restaurant vertical puede configurar una mesa como recurso de servicio, pero
ORGANIZATION conserva la identidad y propiedad del recurso fisico. KITCHEN debe
referenciar estaciones de ORGANIZATION y no crear entidades fisicas duplicadas.

### Responsabilidades compartidas

- CATALOG define productos, variantes, precios y oferta comercial base.
  Restaurant vertical compone menus gastronomicos usando referencias a CATALOG.
- Restaurant vertical posee reglas de servicio de restaurante: menus por
  horario, cursos, modificadores gastronomicos, mesas, reservas y asignacion de
  comandas a cocina.
- PRODUCTION, ubicado en Restaurant vertical, define recetas, versiones,
  componentes, rendimientos y ordenes/lotes gastronomicos. No es propietario
  del catalogo base ni del libro de existencias.
- INVENTORY es propietario de existencias, lotes fisicos y movimientos. Registra
  el consumo solicitado mediante contratos; Restaurant vertical no escribe en
  su ledger ni duplica sus lotes fisicos.
- KITCHEN coordina la preparacion, comandas, estaciones y KDS; no duplica
  pedidos de SALES ni las ordenes/lotes de PRODUCTION.
- SALES administra pedidos, cuentas y estados comerciales genericos; PAYMENTS
  procesa y registra los cobros. Restaurant vertical relaciona el pedido con
  la mesa, los comensales y el flujo de servicio sin crear otra orden o cuenta.
- PAYMENTS administra metodos, proveedores, autorizaciones, capturas, reembolsos y liquidaciones.
- CASH registra el efectivo recibido/devuelto en la caja y sus arqueos; no duplica transacciones de PAYMENTS.
- BILLING emite documentos fiscales.
- FINANCE registra tesoreria, cuentas y contabilidad a partir de eventos de los dominios operativos.

### Coordinación entre dominios

- Cada dominio controla sus propias transacciones.
- Los eventos transaccionales deben registrarse mediante Outbox.
- Los consumidores deben ser idempotentes.
- Los procesos que cruzan dominios deben usar coordinacion tipo Saga.
- Las compensaciones y reconciliaciones deben registrar motivos y estados.
- Las pasarelas externas no participan en una transaccion SQL.
- Una operación externa debe crear un registro pendiente y actualizarlo con el resultado de consulta al proveedor.

## Módulo CATALOG

### Fuente maestra y herencia

El escenario principal sera un catálogo compartido con excepciones locales.

- La marca tendrá una fuente maestra de catalogo.
- Las sucursales asignadas heredaran productos y configuraciones.
- Las excepciones se almacenaran aparte del maestro.
- Una sucursal puede mantener un catalogo independiente.
- Los cambios se publicaran por versiones.

### Reglas de funcionamiento

| Elemento | Comportamiento |
|---|---|
| Productos y variantes | Administrados en el catalogo maestro |
| Categorias | Heredadas desde la marca |
| Precio | Valor general y posible valor por sucursal |
| Disponibilidad | Activacion o pausa por sucursal |
| Modificadores | Herencia con excepciones locales |
| Receta aplicable | Referencia a la version efectiva administrada por PRODUCTION |
| Catalogo independiente | La sucursal puede dejar de heredar |
| Publicacion | Cambios publicados por versiones |
| Ventas historicas | Conservan fotografia comercial al vender |

### Separacion de dominios

- CATALOG define productos, variantes, precios y agrupaciones comerciales
  genericas. Restaurant vertical compone menus gastronomicos con esas
  referencias y posee sus horarios, cursos y reglas de servicio.
- PRODUCTION define las recetas, formulas, rendimientos y ordenes/lotes de
  produccion aplicables a esos productos.
- INVENTORY administra existencias, movimientos y bodegas.
- PROCUREMENT administra compras y proveedores.
- Las recetas versionadas de PRODUCTION definen el consumo esperado.
- INVENTORY registra el consumo y las salidas reales mediante sus movimientos.

### Areas de arquitectura

1. Catalogos comerciales genericos, asignaciones y herencia.
2. Categorias, productos y variantes.
3. Agrupaciones comerciales genericas y canales.
4. Listas de precios e historial.
5. Opciones y agrupaciones genericas de productos.
7. Disponibilidad y horarios.
8. Impuestos y reglas comerciales.
9. Publicacion, excepciones y sincronizacion.

Las recetas y sus versiones se definen en PRODUCTION; CATALOG conserva la
referencia logica a la version efectiva que utiliza el producto. Las reglas de
menu gastronomico, cursos, modificadores culinarios y disponibilidad por
servicio pertenecen a Restaurant vertical.

### Entidades iniciales

- catalog_catalogs
- catalog_assignments
- catalog_categories
- catalog_products
- catalog_product_variants
- catalog_prices
- catalog_menus
- catalog_menu_items
- catalog_modifiers
- catalog_modifier_groups
- catalog_location_overrides
- catalog_publications

Las recetas no se almacenan en CATALOG. Los productos comerciales deben
referenciar la receta efectiva de PRODUCTION mediante un contrato o
identificador logico. Las entidades deben incluir tenant_id y un contexto de
marca o sucursal segun su alcance.

`catalog_menus` y `catalog_modifiers` en CATALOG representan agrupaciones y
opciones comerciales genericas. No almacenan cursos gastronomicos, flujo de
servicio, recetas ni reglas de preparacion; esas extensiones pertenecen a
Restaurant vertical.

### Reglas de publicación

- El catalogo maestro se publica mediante versiones.
- Una publicacion debe ser atomica.
- Una sucursal debe resolver una version efectiva.
- Las excepciones locales no deben modificar el maestro.
- Las ventas historicas deben conservar precio, impuestos y descripcion efectiva.
- La disponibilidad debe calcularse sobre heredado mas excepciones.
- Una sucursal independiente debe dejar de recibir publicaciones del maestro.

Las migraciones pueden asumir que existen platform.tenants, organization.brands y organization.locations.

## Regla fundamental de contexto multi-tenant

- Un usuario puede pertenecer a varios tenants.
- Cada operación debe ejecutarse en el contexto de un solo tenant.
- La sesion debe identificar el tenant activo.
- Los permisos determinan el alcance dentro del tenant activo.
- El alcance puede incluir toda la organización o partes como empresas, marcas, sucursales, areas o cajas.
- Un usuario no puede mezclar datos de varios tenants en una sola operación.
- Cambiar de tenant debe requerir una membresia autorizada.
- El tenant activo debe propagarse a API, servicios y transacciones.

### Defensa en profundidad

La aplicacion no sera la unica barrera de aislamiento.

- PostgreSQL aplicara Row-Level Security.
- Las consultas deben validar tenant_id.
- Las claves foráneas compuestas deben impedir relaciones cruzadas dentro del mismo módulo; no se crean FKs entre schemas propietarios distintos.
- Las politicas RLS deben rechazarse o no devolver filas ajenas.
- Los permisos de aplicacion no reemplazan las restricciones de base de datos.
- Las restricciones de base de datos no reemplazan la auditoria y autorizacion de aplicacion.

La IA, los usuarios humanos y las automatizaciones deben respetar el mismo contexto de tenant y permisos.

## Orden de construcción de la base de datos

| Orden | Dominio | Resultado |
|---:|---|---|
| 1 | platform | Clientes y estructura SaaS |
| 2 | identity | Usuarios y seguridad |
| 3 | organization | Empresas y sucursales |
| 4 | catalog | Productos y agrupaciones comerciales genericas; los menus gastronomicos se extienden en Restaurant vertical |
| 5 | sales | Pedidos, cuentas y estado comercial |
| 6 | payments | Metodos, cobros, capturas y reembolsos |
| 7 | cash | Turnos, arqueos y movimientos de efectivo |
| 8 | kitchen | Comandas |
| 9 | inventory | Existencias y movimientos |
| 10 | procurement | Compras y proveedores |
| 11 | production | Recetas, planificacion y ordenes/lotes de produccion |
| 12 | billing | Facturación fiscal |
| 13 | finance | Cuentas, tesorería y contabilidad |
| 14 | workforce | Personal |
| 15 | customers | CRM |
| 16 | integrations | API, webhooks, conectores y hardware |
| 17 | automation | Automatizaciones |
| 18 | analytics | KPI, tendencias, modelos semanticos y dashboards |
| 19 | audit | Auditoría transversal |
| 20 | reporting | Generación, exportación y distribución de informes |

El numero de esta tabla es solo el orden recomendado de construccion, no el ID
del dominio. Los prefijos `modulo_N` de migraciones existentes son una
secuencia historica independiente; `modulo_9_procurement_operaciones` extiende
PROCUREMENT y no crea un dominio adicional. No renumerar migraciones que ya
hayan sido aplicadas.

No se deben desarrollar todas las pantallas hasta tener definidas las relaciones y reglas de negocio de cada dominio.

## Orden recomendado de desarrollo funcional

Este orden describe el flujo de construccion orientado al producto. Puede solaparse con las migraciones técnicas cuando se identifiquen dependencias.

| Lote | Grupo funcional | Qué debe construir |
|---:|---|---|
| 0 | Administracion de plataforma | Tenants, planes, suscripciones y configuracion global |
| 1 | Empresa y multisucursal | Empresas, sucursales, establecimientos y configuracion general |
| 2 | Usuarios y seguridad | Usuarios, roles, permisos y acceso por sucursal |
| 3 | Catalogo de productos | Categorias, productos, variantes, unidades, impuestos y precios |
| 4 | Inventario | Bodegas, existencias, movimientos, ajustes, conteos y transferencias |
| 5 | Proveedores y compras | Proveedores, ordenes de compra, recepcion de mercancia y compras |
| 6 | Menu, recetas y produccion | Restaurant vertical compone menus y posee PRODUCTION/KITCHEN; CATALOG aporta productos base e INVENTORY el ledger |
| 7 | POS y ventas | Ordenes, pedidos, ventas, detalles, descuentos y anulaciones |
| 8 | Pagos | Metodos, cobros, capturas, reembolsos y liquidaciones |
| 9 | Caja | Apertura y cierre, turnos, arqueos y movimientos de efectivo |
| 10 | Clientes y fidelizacion | Clientes, historial, puntos, promociones y beneficios |
| 11 | Reportes y auditoria | Informes, exportaciones, analitica y trazabilidad |

Los lotes 1-11 corresponden a los once flujos funcionales del
[prompt de trabajo](./promt.md); el lote 0 de PLATFORM es una fundacion previa.
Estos numeros indican orden de trabajo, no dominios tecnicos, crates ni
migraciones.
Este recorrido habilita primero el nucleo de datos y operacion antes de agregar
canales digitales, automatizaciones e IA.

### Relación con dominios técnicos

- Empresa y multisucursal pertenecen principalmente a ORGANIZATION.
- Usuarios y seguridad pertenecen a IDENTITY.
- CATALOG posee productos, variantes, precios y agrupaciones comerciales
  genericas; menus gastronomicos, cursos y reglas de servicio pertenecen a
  Restaurant vertical.
- Inventario pertenece a INVENTORY.
- Compras pertenece a PROCUREMENT.
- SALES posee pedidos, cuentas y ciclo comercial generico; el servicio de mesas
  y la ocupacion pertenecen a Restaurant vertical.
- PRODUCTION y KITCHEN conservan la propiedad de sus dominios gastronómicos y se implementan bajo el backend propietario; INVENTORY posee el ledger físico y aplica los consumos solicitados por contrato.
- POS, pedidos y cuentas pertenecen a SALES; el procesamiento de pagos pertenece a PAYMENTS.
- Caja y efectivo pertenecen a CASH; FINANCE consolida tesoreria, cuentas y contabilidad.
- INTEGRATIONS conecta con los proveedores de pago, mientras PAYMENTS conserva sus cuentas, operaciones y estados.
- Clientes y fidelizacion pertenecen a CUSTOMERS.
- REPORTING es propietario de plantillas, generacion, exportacion y
  distribucion; ANALYTICS de KPI, tendencias y dashboards; AUDIT de la
  trazabilidad de acciones.

### Modelo entidad-relacion - Organizacion empresarial

Entidades principales:

- tenants
- business_groups
- legal_entities
- brands
- locations
- areas
- tables
- warehouses
- registers
- terminals
- printers

Relaciones principales:

- Un tenant contiene grupos empresariales.
- Un tenant contiene empresas legales.
- Un grupo empresarial puede relacionar varias empresas legales.
- Una empresa legal opera una o varias marcas.
- Una marca puede tener varias sucursales.
- Una sucursal pertenece a una marca y puede asociarse a una empresa legal.
- Una sucursal contiene areas.
- Un area contiene mesas.
- Una sucursal contiene bodegas, cajas y terminales.
- Una caja utiliza uno o varios terminales.
- Las impresoras se asignan a sucursales, cajas o terminales segun configuracion.

Las relaciones cruzadas deben validar tenant_id y las relaciones comerciales o fiscales aplicables.

### Modelo entidad-relacion - Productos, pedidos y cocina

Entidades principales:

- products
- product_variants
- product_prices
- production.recipes
- production.recipe_versions
- production.recipe_components
- locations
- orders
- order_items
- order_item_modifiers
- kitchen_tickets
- kitchen_ticket_items

Relaciones principales:

- Un producto puede tener variantes.
- Un producto puede tener precios vigentes por sucursal.
- Un producto referencia una version de receta propietaria de PRODUCTION.
- Una receta referencia insumos de INVENTORY por contrato, sin poseer sus
  saldos, lotes fisicos ni movimientos.
- Una sucursal crea pedidos.
- Un pedido contiene productos y modificadores.
- Un pedido puede tener varias sesiones de cobro en PAYMENTS, enlazadas mediante identificadores logicos.
- Un pedido puede generar uno o varias comandas de cocina.
- Una comanda contiene productos preparados por estaciones.

Las relaciones deben usar el tenant de la venta y validar que producto, precio,
version de receta y sucursal pertenezcan al mismo tenant.

### Modelo entidad-relacion - Pagos y caja

PAYMENTS es propietario de las sesiones, metodos, intents, transacciones, capturas, reembolsos, disputas y liquidaciones. CASH es propietario de cajas fisicas, turnos, arqueos y movimientos de efectivo. SALES conserva unicamente las referencias necesarias para mostrar el resultado comercial del cobro.

- Una sesion de cobro puede referenciar un pedido o una venta de SALES.
- Una sesion puede producir uno o varios intents, intentos y transacciones en PAYMENTS.
- Un movimiento de caja referencia la transaccion o el reembolso de PAYMENTS que origino el flujo de efectivo.
- Las referencias entre dominios son contratos logicos; no se crean claves foraneas cruzadas.

### Modelo entidad-relacion - Inventario y compras

Entidades principales:

- warehouses
- inventory_items
- stock_balances
- stock_movements
- stock_movement_items
- suppliers
- purchase_orders
- purchase_order_items
- goods_receipts
- products

Relaciones principales:

- Una bodega pertenece a una sucursal.
- Una bodega mantiene existencias por producto o insumo.
- Los movimientos registran entradas y salidas.
- Cada movimiento tiene items detallados.
- Los movimientos son el libro inmutable de inventario.
- Los saldos son una proyeccion de los movimientos.
- Los saldos deben poder reconstruirse y verificarse.
- Un proveedor puede suministrar productos.
- Una orden de compra pertenece a una sucursal o compra central.
- Una orden contiene items y puede generar recepciones.
- Una recepcion actualiza movimientos de inventario.

El inventario no debe depender exclusivamente de stock_balances. Debe existir trazabilidad completa mediante stock_movements y stock_movement_items.

## Reglas fundamentales de base de datos

1. Identificacion universal mediante UUID para entidades principales.
2. Aislamiento multiempresa mediante tenant_id.
3. Alcance de sucursal mediante location_id cuando aplique.
4. Valores monetarios con NUMERIC y precision definida, nunca FLOAT.
5. Trazabilidad de inventario, pagos y registros contables.
6. Eliminacion logica y estados para datos que deben conservarse.
7. Retencion segun politicas configuradas.
8. Versionamiento de recetas, precios, menus y configuraciones.
9. Vigencias con fechas de inicio y fin.
10. Transacciones locales por módulo; coordinación entre SALES, PAYMENTS e INVENTORY mediante contratos, Outbox/Inbox, idempotencia y Saga.
11. Idempotencia mediante clave unica por operacion POS.
12. Row-Level Security de PostgreSQL para reforzar aislamiento.
13. Validacion de permisos en la aplicacion y en el acceso a datos.

### Transacciones

- La venta y la solicitud de cobro deben coordinarse mediante registros idempotentes y eventos; la llamada al proveedor ocurre fuera de la transaccion SQL.
- El resultado del cobro debe actualizar SALES mediante eventos de PAYMENTS, sin duplicar la transaccion financiera.
- Los movimientos de inventario deben coordinarse con la venta.
- Un error revierte la transacción local del módulo afectado. Los efectos ya confirmados en otros módulos se resuelven mediante compensaciones y reconciliaciones de la Saga; no se presupone rollback SQL global.
- Los reintentos deben conservar la clave idempotente.
- Los documentos fiscales deben vincularse al registro validado.

### Seguridad de datos

- Las consultas deben establecer el contexto de tenant.
- RLS debe impedir acceso cruzado aun ante errores de filtros.
- Los privilegios de servicio deben limitarse.
- Las acciones administrativas deben quedar auditadas.

## Sistema RBAC + ABAC

El control de acceso debe combinar roles con atributos contextuales.

### RBAC

- Roles base por cargo.
- Permisos por accion.
- Permisos por modulo.
- Permisos heredados.
- Permisos individualmente otorgados.
- Permisos individualmente denegados.

### ABAC

Los permisos deben poder condicionarse por:

- Tenant.
- Empresa.
- Grupo empresarial.
- Marca.
- Sucursal.
- Area.
- Caja.
- Terminal.
- Propiedad del recurso.
- Horario.
- Importe.
- Estado.
- Rol.
- Usuario.
- Contexto de sesion.

### Jerarquia de usuarios

- Superadministrador SaaS.
- Propietario o administrador del tenant.
- Gerente general.
- Administrador de sucursal.
- Supervisor.
- Contador.
- Jefe de cocina.
- Cajero.
- Mesero.
- Cocinero.
- Inventarista.

Los roles deben ser configurables y combinarse con restricciones contextuales.

## Permisos especificos

Cada permiso debe representar una accion concreta.

| Modulo | Permiso |
|---|---|
| Ventas | sales.view |
| Ventas | sales.create |
| Ventas | sales.cancel |
| Ventas | sales.discount |
| Caja | cash.sessions.open |
| Caja | cash.sessions.close |
| Caja | cash.movements.create |
| Caja | cash.expenses.approve |
| Caja | cash.counts.approve |
| Inventario | inventory.view |
| Inventario | inventory.adjust |
| Compras | purchases.create |
| Compras | purchases.approve |
| Personal | employees.view |
| Finanzas | finance.view |
| Reportes | reports.export |
| Configuracion | settings.update |

### Alcance de permisos

Una asignacion de rol puede limitarse a:

- Toda la plataforma.
- Todo el tenant.
- Grupo empresarial.
- Empresa legal.
- Marca.
- Sucursal.
- Area.
- Caja.
- Estacion de trabajo.

Ejemplo:

- Un gerente puede acceder a tres sucursales.
- Un cajero puede trabajar solamente en su sucursal asignada.
- Un cocinero puede operar solo estaciones permitidas.

### Restricciones especiales

Las acciones sensibles pueden tener limites y aprobaciones.

| Accion | Restriccion |
|---|---|
| Descuento | Hasta 10 por ciento |
| Anulacion | Requiere autorizacion |
| Retiro de caja | Hasta cierto monto |
| Ajuste de inventario | Hasta cierta cantidad |
| Cambio de precio | Solo administrador |
| Reembolso | Requiere supervisor |
| Compra | Hasta cierto presupuesto |

Las restricciones deben ser configurables por tenant y por sucursal.

### Doble aprobacion

- Permitir aprobaciones por dos responsables.
- Requerir aprobador distinto del solicitante.
- Definir montos que activan aprobacion adicional.
- Registrar solicitud y aprobacion.
- Rechazar operaciones vencidas o modificadas despues de solicitar aprobacion.

### Acceso de soporte SaaS

- El superadministrador SaaS no debe tener acceso automatico al contenido privado.
- El soporte debe solicitar acceso temporal.
- El acceso debe tener motivo registrado.
- El acceso debe tener duracion limitada.
- El acceso debe requerir autorizacion del tenant cuando aplique.
- Todas las acciones deben quedar auditadas.
- Revocar el acceso al finalizar el caso.

### Administracion de tenants

- Crear tenants.
- Activar o desactivar tenants.
- Registrar plan contratado.
- Administrar modulos habilitados.
- Administrar limites de uso.
- Registrar facturacion del servicio SaaS.
- Registrar vigencia y estado de suscripcion.
- Permitir administracion interna solo a roles autorizados.
- Mantener auditoria de cambios del tenant.

### Requisitos tecnicos SaaS

- Utilizar tenant_id en entidades y operaciones multitenant.
- Aplicar aislamiento en API, base de datos y almacenamiento.
- Validar tenant y sucursal en cada solicitud.
- Evitar consultas que omitan el alcance del tenant.
- Mantener permisos independientes por tenant.
- Mantener configuraciones fiscales e integraciones separadas.
- Permitir personalizacion sin compartir datos.
- Exigir pruebas de aislamiento entre tenants.

## Prioridades centrales del producto

El sistema debe poner especial atencion en estas cinco prioridades:

1. Multi-sucursal real: administracion centralizada, inventarios independientes y reportes consolidados.
2. Inventario conectado a recetas: cada venta actualiza automaticamente el consumo de materias primas y sus costos.
3. Automatizacion visual: el administrador debe poder crear procesos propios sin necesitar programar.
4. IA empresarial: las consultas deben responder con datos reales del negocio y respetar permisos.
5. Prediccion y prevencion: anticipar agotamientos, exceso de compras, caidas de ventas y problemas operativos.

El criterio general del producto es ayudar a aumentar las ganancias y disminuir las perdidas, no limitarse a registrar ventas.

## Alcance inicial

El alcance inicial sera una plataforma con una administracion central y soporte real para varias sucursales, aunque al inicio se encuentre habilitada solamente una.

### Requisitos principales

- Una sola empresa puede administrar multiples sucursales.
- Cada sucursal puede operar de manera independiente.
- Los datos deben estar aislados correctamente por empresa y sucursal.
- Los empleados pueden tener permisos globales o limitados a una sucursal.
- La administracion central debe consultar informacion consolidada.
- Los reportes deben comparar sucursales y rangos de tiempo.
- Las ventas, cajas, inventarios y gastos deben pertenecer a una sucursal.
- Los productos pueden configurarse a nivel corporativo y ajustarse por sucursal.

### Correspondencia entre clasificaciones historicas

| Clasificacion anterior | Dominio técnico dueño |
|---|---|
| Módulo 0 - Administración central | PLATFORM |
| Grupo B + módulo 16 | ORGANIZATION |
| Grupo C + módulos 2, 3, 4 y 11 | SALES, KITCHEN e INTEGRATIONS según responsabilidad |
| Grupo D + módulo 5 + CATALOG | CATALOG |
| Grupo E + módulos 6 y 8 | INVENTORY |
| Grupo F + módulos 7 y 9 | PROCUREMENT |
| Lote funcional 6 - Menú, recetas y producción | CATALOG, PRODUCTION, INVENTORY y KITCHEN según responsabilidad |
| Grupo G + módulo 10 | CUSTOMERS |
| Grupo H + módulo 12 | WORKFORCE |
| Grupo I + módulos 13 y 14 | CASH y FINANCE |
| Grupo J + módulos 1 y 15 | REPORTING y ANALYTICS según responsabilidad |
| Grupo K + módulos 17 y 18 | AUTOMATION e AI transversal |
| Grupo L | INTEGRATIONS |
| Grupo A | PLATFORM |

Los grupos A-L y numeros de modulos anteriores se conservan solo como
clasificaciones comerciales o funcionales heredadas. No son IDs de dominios,
crates ni migraciones y no deben usarse para crear nuevos modulos. El lote 6
del prompt inicial es una agrupacion funcional; no contradice que PRODUCTION
sea el propietario tecnico de recetas y ordenes de produccion. Las numeraciones
de `promt.md`, del roadmap funcional y de las migraciones son secuencias
distintas; los nombres de dominio de la tabla canonica son la unica identidad
tecnica estable.

### Clasificación de capacidades verticales

| Capacidad | Clasificación | Uso |
|---|---|---|
| Tenant, usuarios, permisos y auditoría | Core | Base SaaS |
| Empresas, marcas, sucursales y recursos físicos | Core | Identidad organizacional reutilizable |
| Productos, variantes, precios y pedidos genéricos | Core | Catálogo base y ciclo comercial |
| Pagos, caja e inventario físico | Core | Registros y movimientos transaccionales |
| Compras, proveedores y transferencias | Core | Abastecimiento reutilizable |
| Clientes, personal, finanzas y facturación | Core | Capacidades empresariales comunes |
| Integraciones, automatización, analítica y reporting | Core | Servicios transversales |
| Menús gastronómicos, cursos y modificadores | Restaurant Pack | Presentación y configuración de la oferta del restaurante |
| Mesas, comensales, reservas y flujo de servicio | Restaurant Pack | Atención en salón |
| Comandas, estaciones, preparación y Kitchen Display | Restaurant Pack | Operación de cocina |
| Recetas, subrecetas, rendimientos y producción culinaria | Restaurant Pack | Fórmulas y preparación gastronómica |
| Barra y productos por ronda | Restaurant Pack | Operación de bares |
| Domicilios y repartidores | Restaurant Pack u Optional | Fulfillment especializado |
| Promociones gastronómicas | Optional | Activable según vertical |

El Restaurant vertical consume las capacidades de Core mediante contratos; no
duplica catálogo base, pedidos, pagos, identidades de mesas físicas ni
existencias. La clasificación determina ubicación y propiedad, no solo
activación comercial por tenant.

## Modulos funcionales (clasificacion heredada)

Los encabezados numerados del 1 al 18 son areas funcionales historicas, no
dominios tecnicos ni crates. Pueden abarcar varios dominios y no definen una
segunda identidad de modulo; para implementar funcionalidades se deben usar los
propietarios canonicos de la tabla anterior.

### Modulo 1 - Panel principal (Dashboard)

- Vista general del estado operativo y financiero de toda la empresa.
- Filtros por sucursal y por periodo.
- Vista consolidada de todas las sucursales.
- Vista individual de una sucursal.
- Ventas del dia, semana y mes.
- Comparacion de ventas entre sucursales.
- Comparacion de ventas contra periodos anteriores.
- Ganancias y margenes estimados.
- Numero de pedidos.
- Ticket promedio.
- Productos mas vendidos.
- Productos menos vendidos.
- Inventario critico.
- Alertas de perdidas.
- Empleados trabajando.
- Cajas abiertas.
- Pedidos pendientes.
- Gastos del dia.

#### Requisitos del dashboard

- El administrador debe poder ver todas las sucursales simultaneamente.
- El administrador debe poder seleccionar una sucursal para reducir toda la vista a esa operacion.
- Los resultados deben respetar los permisos por sucursal del usuario.
- Los totales consolidados deben usar exactamente el periodo y la moneda definidos por el filtro.
- Las ventas deben separarse por sucursal y tambien poder sumarse a nivel empresarial.
- Las ganancias y los margenes deben identificarse como estimados hasta contar con costo real del producto.
- Las alertas de inventario deben considerar el stock disponible y el minimo configurado para cada sucursal.
- Las alertas de perdidas deben indicar su origen, periodo y sucursal.
- Los indicadores deben mostrar su variacion frente al periodo anterior.
- Los datos deben indicar su hora de ultima actualizacion.
- Si una sucursal no reporta datos, el dashboard debe mostrar el estado sin inventar ceros ni ocultar el problema.
- Los cambios de sucursal o periodo deben actualizar todos los indicadores de forma coherente.

#### Indicadores iniciales

- Ventas netas.
- Ventas brutas.
- Ganancias estimadas.
- Margen estimado.
- Numero de pedidos.
- Ticket promedio.
- Gastos del dia.
- Productos vendidos.
- Inventario critico.
- Perdidas registradas.
- Empleados con turno activo.
- Cajas abiertas.
- Pedidos pendientes.

### Modulo 2 - Punto de venta (POS)

Modulo operativo utilizado por cajeros y meseros para registrar y administrar pedidos. El POS inicia y presenta los cobros, mientras PAYMENTS procesa y registra sus operaciones financieras.

#### Operacion de cuentas y pedidos

- Abrir y cerrar cuentas.
- Crear pedidos.
- Agregar productos.
- Agregar modificadores a los productos.
- Aplicar descuentos autorizados.
- Dividir cuentas.
- Unir cuentas.
- Cambiar pedidos de mesa.
- Transferir pedidos entre meseros.
- Manejar diferentes medios de pago.
- Registrar pagos mixtos.
- Registrar propinas.
- Procesar devoluciones.
- Procesar anulaciones.
- Reimprimir comprobantes.
- Emitir facturacion electronica.
- Registrar pedidos para llevar.
- Registrar pedidos a domicilio.
- Registrar pedidos para recoger.
- Identificar y manejar clientes frecuentes.

#### Operacion especializada de restaurantes

- Mostrar un mapa visual de mesas.
- Mostrar estados de las mesas.
- Mostrar el tiempo de ocupacion de cada mesa.
- Administrar mesas reservadas.
- Registrar el numero de personas por mesa.
- Mostrar las comandas asociadas a cada mesa.
- Dividir productos entre comensales.

#### Estados operativos

- Los pedidos deben tener estados claros desde su apertura hasta su cierre.
- Las cuentas deben indicar si estan abiertas, parcialmente pagadas, pagadas o anuladas.
- Las mesas deben indicar disponibilidad, ocupacion, reserva y estado de atencion.
- Las devoluciones y anulaciones deben conservar trazabilidad y motivo.
- Las transferencias de pedidos deben conservar el responsable anterior y el nuevo.

#### Requisitos de autorizacion

- Los descuentos deben usar permisos o niveles de autorizacion definidos.
- Las anulaciones y devoluciones deben requerir autorizacion segun su importe y el rol.
- Los cambios de mesa, mesero y cuenta deben quedar registrados en la auditoria.
- PAYMENTS debe exponer al POS los metodos de pago habilitados para la sucursal.
- Los comprobantes deben identificar la sucursal, caja, usuario y pedido.

#### Requisitos de cobro

- Una cuenta puede pagarse mediante uno o varios metodos de pago.
- El pago mixto debe conservar el importe aplicado a cada metodo.
- Las propinas deben registrarse por separado de los importes de venta.
- Las devoluciones deben vincularse al pago original cuando sea posible.
- El POS debe invocar PAYMENTS para iniciar cobros, consultar resultados y solicitar reembolsos autorizados.
- Las operaciones financieras deben ser idempotentes.
- La apertura y el cierre de caja deben relacionarse con los cobros realizados.

#### Requisitos por sucursal

- El POS debe operar dentro de una sucursal seleccionada.
- El usuario debe tener permisos para usar la sucursal y el punto de venta.
- Las mesas, pedidos y cuentas deben pertenecer a una sucursal.
- Los productos, precios y medios de pago pueden variar por sucursal.
- La facturacion electronica debe utilizar la configuracion fiscal de la sucursal.

### Modulo 3 - Mesas, reservas y atencion

Modulo para administrar la capacidad, distribucion y atencion dentro de cada sucursal.

#### Planos y mesas

- Crear planos de los salones.
- Crear zonas dentro de cada plano.
- Crear mesas y asignar su capacidad.
- Ubicar mesas visualmente dentro del plano.
- Mostrar el estado actual de cada mesa.
- Registrar el tiempo de ocupacion de cada mesa.
- Registrar el numero de personas atendidas.
- Asociar meseros a las mesas.
- Asociar pedidos y comandas a cada mesa.

#### Reservas y espera

- Crear reservaciones.
- Consultar disponibilidad por fecha, hora y capacidad.
- Registrar reservas recibidas por telefono.
- Registrar reservas recibidas por pagina web.
- Gestionar cambios y cancelaciones de reservas.
- Mantener una lista de espera.
- Estimar y registrar el tiempo de espera.
- Notificar a los clientes sobre reservas, cambios o confirmaciones.
- Enviar recordatorios de reservaciones.
- Controlar clientes que no se presentan.
- Mantener el historial de visitas del cliente.
- Vincular reservas confirmadas con su mesa y mesero.

#### Estados de atencion

- Disponible.
- Reservada.
- Ocupada.
- Requiere atencion.
- Limpieza o preparacion.
- Fuera de servicio.

Los estados deben reflejarse en el plano visual y actualizarse con las operaciones de reserva, pedido y cobro.

#### Automatizaciones

- Alertar al encargado cuando una mesa exceda el tiempo de ocupacion configurado.
- Alertar cuando un pedido exceda el tiempo esperado de preparacion o salida.
- Alertar cuando una reserva este por comenzar.
- Alertar cuando la reserva no haya sido confirmada.
- Alertar al responsable ante una acumulacion de clientes en lista de espera.
- Notificar a la sucursal cuando un cliente tenga historial de reservas no presentadas.

#### Requisitos por sucursal

- Los planos, zonas, mesas y reservas deben pertenecer a una sucursal.
- La asignacion de meseros debe respetar los turnos y permisos de la sucursal.
- Los tiempos limites pueden configurarse por sucursal.
- Los usuarios deben tener permisos para crear, modificar o cancelar reservas.
- Las notificaciones deben identificar la sucursal correspondiente.
- El historial de visitas puede consultarse de forma central solo dentro del alcance autorizado.

### Modulo 4 - Cocina - KDS (Kitchen Display System)

Modulo que conecta el POS con la cocina y coordina la preparacion de los pedidos por estaciones.

#### Recepcion y organizacion

- Recibir comandas automaticamente desde el POS.
- Mostrar pedidos nuevos, en preparacion y listos.
- Separar pedidos por estaciones.
- Configurar estaciones de cocina caliente.
- Configurar estaciones de cocina fria.
- Configurar estaciones de bebidas.
- Configurar estaciones de postres.
- Configurar estaciones especiales como pizzas, parrilla u otras.
- Asignar cada producto a una o varias estaciones segun su receta.
- Permitir prioridad normal, alta o urgente en los pedidos.
- Permitir reordenar visualmente los pedidos segun su prioridad.

#### Control de preparacion

- Mostrar un cronometro de preparacion por pedido y producto.
- Mantener el estado de cada producto.
- Identificar pedidos retrasados.
- Identificar productos retrasados dentro de un pedido.
- Permitir marcar productos como iniciados.
- Permitir marcar productos como preparados.
- Permitir marcar pedidos completos como listos.
- Permitir marcar pedidos entregados al mesero o recolector.
- Notificar al mesero cuando un pedido o producto este listo.
- Registrar cancelaciones o devoluciones realizadas durante la preparacion.
- Registrar el responsable de las acciones de cocina.

#### Tiempos e historial

- Registrar el tiempo de recepcion de cada comanda.
- Registrar el inicio y final de preparacion.
- Registrar el tiempo entre la salida de cocina y la entrega.
- Mantener el historial de tiempos de preparacion.
- Comparar tiempos reales contra tiempos estimados.
- Permitir configurar tiempos objetivo por producto y estacion.

#### Inteligencia operativa

- Analizar cuanto tarda cada plato en prepararse.
- Comparar tiempos entre sucursales.
- Detectar cuellos de botella por estacion.
- Detectar empleados o turnos con mayor demora.
- Detectar dias y horarios con mayor congestion.
- Calcular tiempos estimados de entrega.
- Ajustar las estimaciones usando tiempos historicos.
- Generar alertas para pedidos que tengan riesgo de retrasarse.
- Sugerir prioridad o redistribucion cuando exista congestion.

#### Requisitos por sucursal

- Las estaciones deben configurarse por sucursal.
- Los pedidos deben pertenecer a la sucursal que los emitio.
- La configuracion de tiempos puede variar por sucursal.
- Los permisos deben diferenciar monitoreo, preparacion y administracion.
- Los analisis historicos deben respetar el alcance por sucursal.

### Modulo funcional 5 - Productos, menu y recetas

Este lote funcional cruza propietarios: CATALOG y los productos base permanecen
en Core; el menu gastronomico y las recetas pertenecen a Restaurant vertical.
INVENTORY conserva el stock fisico y sus movimientos.

#### Catalogo base (CATALOG, Core)

- Crear categorias.
- Crear productos.
- Registrar descripciones comerciales.
- Administrar fotografias.
- Registrar precios.
- Crear variantes y tamanos.
- Configurar impuestos.
- Administrar el estado comercial de cada producto.
- Identificar productos agotados.
- Identificar productos temporalmente indisponibles.

#### Menu gastronomico (Restaurant vertical)

- Componer menus con referencias a productos de CATALOG.
- Definir horarios de servicio, cursos y orden de platos.
- Configurar modificadores, adiciones y extras propios de preparaciones.
- Crear combos gastronomicos y ofertas asociadas al servicio.
- Publicar disponibilidad del menu por sucursal y horario.
- Vincular cada producto preparado con la receta aplicable de PRODUCTION.

#### Recetas y produccion (PRODUCTION, Restaurant vertical)

- Definir recetas por producto.
- Relacionar recetas con ingredientes e insumos.
- Registrar cantidades y unidades de preparacion.
- Definir rendimientos de cada receta.
- Calcular el costo de preparacion.
- Calcular el costo unitario del producto.
- Calcular el margen de ganancia.
- Permitir variantes con consumos de insumos diferentes.
- Permitir actualizar costos cuando cambien los precios de los insumos.

#### Catalogo central y excepciones por sucursal

- Mantener un catalogo central de productos administrado por la empresa.
- Permitir publicar o retirar productos por sucursal.
- Permitir que una sucursal tenga precios diferentes a otras sucursales.
- Permitir que una sucursal tenga impuestos o promociones diferentes cuando la configuracion fiscal lo requiera.
- Permitir configuraciones particulares de disponibilidad por sucursal.
- Permitir excepciones locales de productos y variantes segun las reglas de CATALOG.
- Permitir excepciones de menu, cursos y modificadores por sucursal desde
  Restaurant vertical.
- Aplicar los cambios centrales a todas las sucursales salvo configuraciones locales especificas.
- Evitar modificar el precio corporativo al crear una excepcion para una sucursal.
- Mostrar el origen de cada precio: central o configuracion local.

#### Control comercial

- Definir horarios de venta por producto cuando sea necesario.
- Programar promociones.
- Definir restricciones de venta.
- Vincular productos con estaciones de cocina.
- Vincular productos con categorias de reportes.
- Vincular productos con cuentas contables cuando aplique.

#### Requisitos por sucursal

- Los productos pueden heredarse del catalogo central.
- Las excepciones deben pertenecer a una sucursal.
- Las ventas deben usar el precio vigente para la sucursal.
- Los productos agotados deben gestionarse por sucursal.
- Las recetas pueden tener bases centrales y ajustes locales controlados.
- Los usuarios deben tener permisos separados para administrar el catalogo central y las excepciones locales.
- Los cambios de precio deben quedar registrados con usuario, sucursal, fecha y motivo.

### Modulo 6 - Inventario inteligente

Modulo para controlar existencias, consumos, movimientos y trazabilidad por sucursal.

#### Existencias

- Administrar inventario por sucursal.
- Administrar inventario central.
- Registrar materias primas.
- Registrar productos terminados.
- Definir unidades de medida.
- Definir conversiones entre unidades.
- Registrar lotes.
- Registrar fechas de vencimiento.
- Registrar ubicaciones de almacenamiento.
- Mostrar disponibilidad util por sucursal.
- Diferenciar stock disponible y stock reservado.

#### Movimientos

- Registrar entradas de inventario.
- Registrar salidas de inventario.
- Registrar ajustes autorizados.
- Registrar conteos fisicos.
- Registrar inventarios parciales.
- Registrar mermas.
- Registrar desperdicios.
- Registrar devoluciones de insumos.
- Registrar transferencias entre sucursales.
- Mantener el kardex completo de cada articulo.
- Mantener trazabilidad por lote y sucursal.

#### Consumo por recetas

- Descontar automaticamente los ingredientes al confirmar una venta o preparar el pedido.
- Utilizar la receta vigente del producto vendido.
- Descontar variantes y modificadores segun sus ingredientes adicionales.
- Identificar ingredientes opcionales solo cuando el cliente los seleccione.
- Procesar combos con las recetas de sus componentes.
- Permitir revertir el consumo si el pedido se cancela o devuelve antes de terminar el proceso.
- Evitar consumos duplicados ante reintentos o sincronizaciones.
- Registrar el pedido y el movimiento que genero cada consumo.

Ejemplo: al vender una hamburguesa se deben descontar automaticamente pan, carne, queso, lechuga, tomate y salsas segun las cantidades de su receta.

#### Rendimientos y conversiones

- Registrar rendimiento de materias primas.
- Registrar porciones obtenidas de cada insumo.
- Diferenciar cantidad comprada, cantidad util y cantidad consumida.
- Aplicar factores de conversion entre unidades.
- Permitir conversiones como kilogramo a gramo o unidad a porcion.
- Registrar desperdicio y rendimiento durante preparaciones.
- Aplicar el factor de rendimiento al calcular costo y consumo.
- Permitir recibir un insumo en una unidad y descontarlo en otra unidad base.

#### Control de niveles

- Configurar stock minimo por sucursal.
- Configurar stock maximo por sucursal.
- Generar alertas de reposicion.
- Generar alertas de vencimiento.
- Detectar productos sin movimiento.
- Identificar diferencias entre conteo fisico y sistema.
- Bloquear o advertir ventas de productos sin inventario segun la configuracion de la sucursal.

#### Transferencias

- Crear solicitudes de transferencia entre sucursales.
- Aprobar o rechazar transferencias.
- Descontar inventario al enviar.
- Registrar recepcion parcial o completa.
- Mantener inventario en transito.
- Conciliar diferencias de cantidad al recibir.
- Mantener trazabilidad entre sucursal origen y sucursal destino.

#### Requisitos por sucursal

- Los saldos deben pertenecer a una sucursal.
- El inventario central debe representar existencias administrativas o puntos no operativos configurados.
- Las transferencias deben respetar permisos de origen y destino.
- Los ajustes deben requerir motivo y autorizacion segun el importe o categoria.
- Los conteos deben quedar asociados al usuario y al momento de ejecucion.
- Las alertas deben indicar sucursal, articulo y nivel critico.
- Los consumos deben ejecutarse en el contexto de la sucursal que vendio el pedido.

### Modulo 7 - Compras y abastecimiento

Modulo para gestionar solicitudes, cotizaciones, proveedores, recepciones y reposicion de todas las sucursales.

#### Solicitudes y aprobaciones

- Crear solicitudes de compra.
- Crear solicitudes desde una sucursal.
- Crear solicitudes centralizadas desde la empresa.
- Agregar articulos, cantidades y unidades.
- Aprobar solicitudes segun autorizacion y importe.
- Permitir aprobaciones por etapas con responsable, decision, motivo e idempotencia.
- Rechazar solicitudes con motivo.
- Modificar solicitudes antes de su aprobacion.
- Convertir solicitudes aprobadas en ordenes de compra.
- Consolidar varias solicitudes aprobadas de una empresa en una orden para un proveedor compatible con sus lineas.
- Mantener trazabilidad desde la necesidad hasta la recepcion.

#### Ordenes y cotizaciones

- Crear ordenes de compra.
- Registrar cotizaciones de proveedores.
- Comparar precios por proveedor.
- Comparar plazos de entrega.
- Comparar condiciones de pago.
- Comparar costos de transporte.
- Seleccionar el proveedor recomendado o aprobado.
- Registrar compras recurrentes.
- Programar periodos de recompra.
- Programar entregas parciales de una orden por fecha, sucursal y bodega.
- Mantener el historial de precios por proveedor y articulo.

#### Recepcion de mercancia

- Registrar recepcion parcial.
- Registrar recepcion completa.
- Registrar productos rechazados.
- Registrar diferencias de cantidad.
- Inspeccionar cantidad, calidad, temperatura, empaque y documentos recibidos.
- Registrar discrepancias, evidencias y su resolucion.
- Vincular recepciones con la orden de compra.
- Vincular recepciones con lotes y vencimientos.
- Registrar costos adicionales como transporte.
- Registrar facturas de proveedores.
- Conciliar cantidades recibidas con facturas.
- Enviar las recepciones a Inventory mediante eventos idempotentes; Procurement no modifica existencias directamente.

#### Devoluciones y documentos

- Solicitar devoluciones a proveedores por dano, articulo incorrecto, calidad, vencimiento, exceso o retiro.
- Aprobar, despachar y cerrar devoluciones con trazabilidad de responsables y estados.
- Vincular cada linea devuelta con la linea de orden o recepcion correspondiente.
- Registrar el movimiento de salida con Inventory antes de completar la devolucion.
- Asociar documentos externos a solicitudes, ordenes, recepciones, facturas y devoluciones.
- Configurar por tenant las aprobaciones requeridas, inspecciones, tolerancias y recepciones por exceso.

#### Compras centralizadas y locales

- Permitir compras centralizadas administradas por la empresa.
- Permitir compras directas por sucursal dentro de sus autorizaciones.
- Distribuir una compra central entre varias sucursales.
- Registrar la sucursal beneficiaria de cada articulo.
- Permitir proveedores exclusivos o preferidos por sucursal.
- Permitir precios y contratos corporativos compartidos.
- Mantener un historial consolidado de compras.

#### Propuestas automaticas de compra

- Identificar articulos con inventario por debajo del minimo.
- Calcular una cantidad sugerida de reposicion.
- Considerar el stock maximo configurado.
- Considerar el consumo historico.
- Considerar pedidos pendientes o pronosticos disponibles.
- Considerar inventario en transito.
- Generar propuestas por sucursal.
- Permitir aprobacion, ajuste o rechazo de la propuesta.
- Evitar generar propuestas duplicadas mientras una solicitud o orden este activa.

#### Requisitos por sucursal

- Las solicitudes deben pertenecer a una sucursal o quedar como compras centrales.
- Las compras directas deben respetar limites de autorizacion.
- Las recepciones deben ingresar al inventario de la sucursal correspondiente.
- Los costos deben asignarse a la sucursal que recibe los bienes.
- Los proveedores pueden configurarse como globales o locales.
- Los reportes deben comparar compras por sucursal y proveedor.

### Modulo 8 - Transferencias entre sucursales

Modulo independiente para solicitar, aprobar, enviar, recibir y conciliar mercancia entre sucursales.

#### Solicitudes

- Solicitar mercancia a otra sucursal.
- Seleccionar sucursal origen y sucursal destino.
- Agregar productos, cantidades y unidad de medida.
- Registrar motivo de la solicitud.
- Aprobar solicitudes segun permisos y disponibilidad.
- Rechazar solicitudes con motivo.
- Modificar solicitudes antes del envio.
- Consultar transferencias pendientes.
- Priorizar transferencias urgentes.

#### Envio

- Registrar responsable del envio.
- Preparar la mercancia.
- Seleccionar lotes y fechas de vencimiento.
- Registrar cantidades efectivamente enviadas.
- Registrar costo de transporte cuando aplique.
- Registrar costo de transferencia.
- Confirmar salida del inventario de la sucursal origen.
- Mantener productos enviados como inventario en transito.
- Emitir un comprobante o remision de transferencia.

#### Recepcion

- Confirmar recepcion de la mercancia.
- Registrar recepcion parcial.
- Registrar recepcion completa.
- Registrar diferencias de cantidad.
- Registrar diferencias de estado o lote.
- Registrar responsable de la recepcion.
- Registrar costos adicionales asumidos por la sucursal destino.
- Registrar novedades o incidencias.

#### Conciliacion

- Actualizar inventario de la sucursal origen al enviar.
- Mantener en transito la mercancia mientras no sea recibida.
- Actualizar inventario de la sucursal destino al confirmar recepcion.
- Registrar movimientos en ambas sucursales.
- Mantener trazabilidad por lote.
- Ajustar diferencias solo con autorizacion.
- Evitar movimientos duplicados ante reintentos.
- Mantener el historial completo de estados y responsables.

#### Ejemplo operativo

La sucursal 1 puede tener exceso de pollo y la sucursal 2 puede estar agotada. El sistema permite solicitar la transferencia, aprobarla, enviarla, registrar su recepcion y actualizar ambos inventarios sin requerir una compra adicional.

#### Estados

- Solicitada.
- Aprobada.
- Rechazada.
- En preparacion.
- Enviada.
- En transito.
- Recibida parcialmente.
- Recibida.
- Conciliada.
- Cancelada.

#### Requisitos por sucursal

- Solo usuarios autorizados pueden solicitar transferencias hacia otras sucursales.
- Solo usuarios autorizados pueden aprobar la salida o recepcion.
- La sucursal origen debe tener disponibilidad suficiente.
- Los movimientos deben identificar sucursal origen y sucursal destino.
- Los reportes deben mostrar pendientes, costos y diferencias por sucursal.
- Las transferencias deben ser auditables de principio a fin.

### Modulo 9 - Proveedores

Modulo independiente para administrar proveedores, condiciones comerciales, facturas, documentos y cuentas por pagar.

#### Registro general

- Registrar proveedores.
- Registrar datos fiscales.
- Registrar razon social y identificacion fiscal.
- Registrar contactos.
- Registrar telefonos y correos.
- Registrar direcciones.
- Registrar productos que suministran.
- Registrar sucursales habilitadas para comprar al proveedor.
- Registrar categorias de proveedores.
- Activar o desactivar proveedores.

#### Condiciones comerciales

- Registrar precios historicos.
- Registrar listas de precios.
- Registrar descuentos.
- Registrar condiciones de pago.
- Registrar plazos de credito.
- Registrar monedas aceptadas.
- Registrar tiempos de entrega.
- Registrar minimos de pedido.
- Registrar costos de transporte acordados.
- Registrar proveedores preferidos por producto o sucursal.

#### Facturas y cuentas por pagar

- Registrar facturas de proveedores.
- Relacionar facturas con ordenes de compra.
- Relacionar facturas con recepciones.
- Registrar impuestos, descuentos y costos adicionales.
- Calcular el saldo pendiente.
- Registrar fechas de vencimiento.
- Registrar pagos parciales.
- Registrar pagos completos.
- Mantener el historial de cuentas por pagar.
- Conciliar diferencias entre factura, compra y recepcion.

#### Evaluacion e historial

- Mantener el historial de compras.
- Calificar proveedores.
- Registrar criterios de calidad.
- Registrar cumplimiento de entrega.
- Registrar diferencias de cantidad o precio.
- Registrar incidencias y reclamos.
- Comparar proveedores por costo, calidad y plazo.

#### Documentos

- Registrar contratos.
- Registrar anexos y actas.
- Registrar certificados.
- Registrar documentos fiscales.
- Registrar fechas de vigencia.
- Relacionar documentos con proveedores y sucursales.

#### Lectura inteligente de facturas

- Permitir cargar facturas en formato PDF o imagen.
- Extraer automaticamente proveedor.
- Extraer fecha y numero de factura.
- Extraer productos o descripcion.
- Extraer cantidades.
- Extraer impuestos.
- Extraer precios unitarios.
- Extraer descuentos y costos adicionales.
- Extraer totales y fecha de vencimiento.
- Permitir revision humana antes de registrar la factura.
- Comparar datos extraidos con la orden de compra y recepcion.
- Marcar diferencias para revision.
- Mantener trazabilidad de los datos originales y los datos confirmados.

#### Requisitos por sucursal

- Las cuentas por pagar pueden corresponder a la empresa o a una sucursal.
- Los proveedores pueden ser globales o habilitados por sucursal.
- Los usuarios deben tener permisos separados para administrar proveedores y pagar facturas.
- Las facturas deben indicar sucursal, comprador y recepcion relacionada cuando aplique.
- Los reportes deben consolidar proveedores por empresa y compararlos por sucursal.

### Modulo 10 - Clientes - CRM y fidelizacion

Modulo para conocer a los clientes, conservar su historial, premiar su fidelidad, gestionar consentimientos y construir segmentos. AUTOMATION define y ejecuta campañas; INTEGRATIONS entrega mensajes y registra resultados de proveedores.

#### Registro y perfil

- Registrar clientes.
- Registrar datos de contacto.
- Registrar preferencias.
- Registrar alergias o restricciones solo cuando exista una autorizacion del cliente.
- Registrar historial de compras.
- Registrar sucursales visitadas.
- Registrar frecuencia de visitas.
- Calcular ticket promedio.
- Registrar cumpleaños.
- Mantener notas comerciales autorizadas.
- Registrar clientes recurrentes y clientes nuevos.

#### Fidelizacion

- Configurar programas de puntos.
- Otorgar puntos por compra.
- Permitir canje de puntos.
- Registrar cupones.
- Registrar descuentos.
- Registrar tarjetas de regalo.
- Consultar saldo de puntos.
- Consultar saldo de tarjetas de regalo.
- Definir vigencia de beneficios.
- Vincular promociones con segmentos de clientes.

#### Segmentacion

- Crear segmentos por frecuencia de visitas.
- Crear segmentos por ticket promedio.
- Crear segmentos por productos preferidos.
- Crear segmentos por sucursal.
- Crear segmentos por fecha de ultimo consumo.
- Crear segmentos por cumpleaños.
- Crear segmentos por nivel de fidelidad.
- Permitir segmentacion manual.
- Permitir segmentacion automatica.

#### Marketing y comunicaciones

- Proveer segmentos y preferencias autorizadas a AUTOMATION para sus campañas.
- Validar que la audiencia respete consentimientos vigentes antes de compartirla.
- Permitir a INTEGRATIONS consultar el consentimiento necesario para entregar mensajes.
- Registrar referencias de consentimiento y segmento usadas por una campaña, sin mantener un registro paralelo de envios.
- Las campañas, su calendario, aprobacion y ejecucion pertenecen a AUTOMATION; la entrega y los resultados del canal pertenecen a INTEGRATIONS.
- Registrar encuestas de satisfaccion.
- Mantener el resultado de encuestas por sucursal y periodo.

#### Consentimientos y privacidad

- Registrar consentimientos otorgados por el cliente.
- Identificar finalidad de cada consentimiento.
- Registrar fecha y medio de consentimiento.
- Permitir revocacion de consentimientos.
- Restringir comunicaciones sin consentimiento valido.
- Permitir eliminacion o anonimización de datos segun las reglas aplicables.
- Mantener trazabilidad de cambios de consentimiento.

#### Inteligencia de recuperacion

- Detectar clientes que dejaron de visitar el restaurante.
- Comparar la frecuencia anterior con la frecuencia actual.
- Calcular el riesgo de abandono.
- Sugerir campañas de recuperacion.
- Definir incentivos segun el valor historico del cliente.
- Permitir excluir clientes de promociones segun sus preferencias.
- Mostrar motivos de clientes de alto riesgo.
- Permitir a AUTOMATION ejecutar campañas de recuperacion solo con autorizacion y consentimiento.

#### Requisitos por sucursal

- Los clientes pueden ser compartidos por la empresa.
- El historial comercial puede consolidarse por sucursal.
- Las campañas de AUTOMATION pueden ser centrales o locales y usar segmentos autorizados de CUSTOMERS.
- Las promociones deben indicar sucursales habilitadas.
- Los usuarios deben tener permisos por informacion del cliente y sucursal.
- Los informes de clientes deben respetar las reglas de privacidad.

### Modulo 11 - Domicilios y pedidos digitales

Modulo centralizado para recibir pedidos desde todos los canales digitales y gestionar su preparacion y entrega.

#### Canales de pedido

- Recibir pedidos por pagina web.
- Recibir pedidos por aplicacion propia.
- Recibir pedidos por WhatsApp mediante integracion.
- Recibir pedidos desde plataformas externas.
- Integrar marketplaces y servicios de delivery.
- Normalizar todos los canales en el mismo modelo de pedido.
- Identificar canal, sucursal y cliente en cada pedido.
- Evitar pedidos duplicados ante reintentos o integraciones.

#### Domicilios

- Gestionar repartidores.
- Registrar repartidores internos.
- Registrar repartidores externos o de terceros.
- Asignar domicilios a repartidores.
- Permitir asignacion manual.
- Permitir asignacion automatica segun disponibilidad y zona.
- Crear zonas de cobertura.
- Configurar tarifas de domicilio.
- Permitir tarifas diferentes por sucursal y zona.
- Calcular el importe estimado de entrega.
- Registrar direccion y puntos de referencia.
- Registrar notas de entrega.
- Mantener el historial de domicilios.

#### Seguimiento y estados

- Mostrar el estado actual de cada pedido.
- Registrar pedido recibido.
- Registrar pedido confirmado.
- Registrar pedido en preparacion.
- Registrar pedido listo.
- Registrar pedido asignado.
- Registrar pedido recogido.
- Registrar pedido en camino.
- Registrar pedido entregado.
- Registrar pedido cancelado o rechazado.
- Permitir seguimiento por el cliente.
- Registrar incidencias de entrega.

#### Tiempos de entrega

- Registrar hora de recepcion.
- Registrar hora de confirmacion.
- Registrar hora de salida de cocina.
- Registrar hora de asignacion.
- Registrar hora de salida del repartidor.
- Registrar hora de entrega.
- Calcular tiempos de preparacion.
- Calcular tiempos de recorrido.
- Calcular tiempos totales de entrega.
- Generar alertas por pedidos retrasados.

#### Integracion externa

- Sincronizar productos disponibles.
- Sincronizar precios segun sucursal.
- Sincronizar promociones autorizadas.
- Recibir pedidos externos con estado original del canal.
- Reenviar cambios de estado a plataformas externas.
- Registrar fallos de integracion.
- Permitir reintentos controlados.
- Mantener trazabilidad de integraciones.

#### Requisitos por sucursal

- Las zonas y tarifas deben configurarse por sucursal.
- Un pedido debe asignarse automaticamente a una sucursal segun zona o seleccion del cliente.
- Los repartidores deben operar dentro de sucursales autorizadas.
- Los pedidos deben respetar catalogo, precios e inventario de la sucursal.
- Los usuarios deben tener permisos para asignar, modificar o cancelar domicilios.
- Los reportes deben comparar canales, tiempos y entregas por sucursal.

### Modulo 12 - Empleados y recursos humanos

Modulo para administrar personas, cargos, horarios, asistencia, compensaciones y rendimiento por sucursal.

#### Registro laboral

- Registrar empleados.
- Registrar cargos.
- Registrar departamentos.
- Registrar datos laborales.
- Registrar contratos.
- Vincular empleados con una sucursal principal.
- Permitir asignaciones temporales a otras sucursales.
- Registrar estado activo o inactivo.
- Registrar responsabilidades laborales; los permisos de acceso pertenecen a Identity.

#### Horarios y turnos

- Crear horarios.
- Crear turnos.
- Asignar empleados a turnos.
- Configurar horarios por sucursal.
- Permitir turnos parciales y jornadas completas.
- Detectar conflictos de horario.
- Controlar cambios de turno.
- Mantener el historial de asignaciones.

#### Asistencia

- Registrar entrada.
- Registrar salida.
- Registrar inicio y fin de descansos.
- Controlar retrasos.
- Controlar horas extra.
- Registrar ausencias.
- Registrar permisos.
- Registrar vacaciones.
- Permitir correcciones autorizadas.
- Mantener el historial de asistencia.
- Vincular asistencia con nomina y rendimiento cuando aplique.

#### Compensaciones y nomina

- Workforce registra las condiciones contractuales de remuneracion y proporciona datos de turnos y asistencia.
- Finance/Payroll debe calcular y pagar nomina, propinas, comisiones y bonificaciones, con reglas de distribucion y trazabilidad.
- La integracion con nomina y el calculo/distribucion de compensaciones variables siguen pendientes de implementacion.

#### Rendimiento

- Medir ventas por empleado.
- Medir pedidos atendidos.
- Medir ticket promedio generado.
- Medir propinas obtenidas mediante datos proporcionados por Finance/Payroll.
- Medir puntualidad.
- Medir horas trabajadas.
- Medir productividad por turno.
- Mantener historial de actividad.
- Comparar rendimiento dentro de limites autorizados.

#### Inteligencia de personal

- Predecir la demanda de personal por sucursal.
- Relacionar ventas esperadas con cargas operativas.
- Estimar empleados necesarios por turno.
- Considerar productos, pedidos y reservaciones.
- Considerar ausencias y vacaciones previstas.
- Alertar por exceso de personal programado.
- Alertar por falta de personal programado.
- Permitir revisar y ajustar las recomendaciones humanas.
- Mantener el historial de predicciones y resultados reales.

#### Requisitos por sucursal

- Los empleados deben asignarse a una sucursal o a un conjunto autorizado.
- Los turnos deben pertenecer a una sucursal.
- Los horarios deben respetar configuraciones laborales locales.
- Los usuarios deben tener permisos separados para registrar, corregir y consultar asistencia.
- Los reportes deben separar o consolidar empleados por sucursal.
- El sistema debe proteger datos laborales y personales.

### Modulo 13 - Caja y operaciones de efectivo

Modulo para controlar cajas fisicas, turnos, arqueos y movimientos de efectivo por sucursal. PAYMENTS conserva el ciclo de vida de los cobros; FINANCE conserva tesoreria y contabilidad.

#### Operacion de caja

- Abrir caja.
- Registrar la base inicial.
- Registrar caja por sucursal.
- Registrar caja por punto de venta.
- Registrar usuario responsable.
- Registrar fecha y hora de apertura.
- Registrar fecha y hora de cierre.
- Permitir arqueos parciales.
- Permitir arqueo final.
- Calcular diferencias de caja.
- Registrar causas de diferencias.
- Aprobar cierres segun permisos.
- Mantener historial de aperturas y cierres.

#### Movimientos

- Registrar entradas de efectivo.
- Registrar salidas de efectivo.
- Registrar salidas de efectivo asociadas a gastos autorizados.
- Registrar retiros.
- Registrar pagos a proveedores desde caja cuando este permitido.
- Registrar consignaciones.
- Registrar devoluciones en efectivo asociadas al reembolso de PAYMENTS.
- Registrar responsable de cada movimiento.
- Registrar fecha y hora exacta.
- Registrar motivo y documento asociado.
- Mantener el historial completo de movimientos.

#### Integracion con PAYMENTS

- Asociar la operacion de caja con las transacciones de PAYMENTS mediante referencias idempotentes.
- Registrar en el arqueo unicamente la porcion en efectivo de pagos mixtos.
- Registrar una salida de efectivo cuando un reembolso aprobado por PAYMENTS se devuelva en efectivo.
- No guardar metodos, autorizaciones, referencias de proveedor ni estados de transaccion como propiedad de CASH.
- Detectar eventos repetidos sin duplicar movimientos de efectivo.

#### Arqueo y conciliacion de efectivo

- Comparar efectivo esperado con efectivo contado.
- Verificar que las porciones en efectivo reportadas por PAYMENTS coincidan con movimientos de caja.
- Identificar movimientos de efectivo pendientes de conciliacion.
- Registrar arqueos parciales y finales.
- Mantener diferencias y su resolucion.
- Permitir reversiones autorizadas.

La conciliacion de pasarelas y liquidaciones corresponde a PAYMENTS; la conciliacion bancaria y tesoreria corresponden a FINANCE.

#### Salidas de efectivo por gastos

- Registrar gastos menores pagados desde caja, con categoria, beneficiario, soportes y aprobaciones.
- Vincular el gasto y su movimiento de efectivo dentro de CASH.
- Permitir que FINANCE asigne cuentas y centros de costo, y consolide los gastos de todos los medios de pago.
- Incluir el movimiento de efectivo en el arqueo y reportes de caja.

#### Trazabilidad de responsables

- Identificar quien abre la caja.
- Identificar quien recibe dinero.
- Identificar quien registra entradas.
- Identificar quien registra retiros.
- Identificar quien entrega efectivo.
- Identificar quien realiza el conteo.
- Identificar quien aprueba el cierre.
- Identificar quien realiza el arqueo y resuelve diferencias de efectivo.
- Conservar fecha y hora de cada accion.
- Evitar retirar responsabilidades mediante ediciones sin auditoria.

#### Requisitos por sucursal

- Cada caja debe pertenecer a una sucursal.
- Una caja puede tener turnos y usuarios responsables.
- Solo usuarios autorizados pueden abrir, cerrar o retirar efectivo.
- Las diferencias deben permanecer asociadas a sucursal y caja.
- Las transacciones de PAYMENTS deben conservar la referencia a la sucursal correspondiente.
- Los reportes deben permitir consolidar tesoreria por empresa.

### Modulo 14 - Finanzas y contabilidad

Modulo para conocer la situacion financiera real de cada sucursal y consolidarla a nivel empresarial.

#### Operaciones financieras

- Registrar ingresos.
- Registrar egresos.
- Administrar cuentas por pagar.
- Administrar cuentas por cobrar.
- Calcular flujo de caja.
- Presentar estado de resultados.
- Presentar balance general.
- Registrar centros de costos.
- Registrar costos operativos.
- Calcular impuestos.
- Conciliar cuentas bancarias.
- Ejecutar cierres de periodos.
- Exportar informacion contable.
- Calcular rentabilidad por sucursal.

#### Estados financieros

- Mostrar ingresos por sucursal.
- Mostrar egresos por sucursal.
- Mostrar utilidad por sucursal.
- Mostrar margen por sucursal.
- Mostrar costos fijos y variables.
- Mostrar resultados consolidados.
- Comparar una sucursal contra el total empresarial.
- Permitir periodos diarios, mensuales y anuales.
- Permitir periodos fiscales configurados.
- Mostrar datos individuales y consolidados.

#### Costos y centros

- Crear plan contable.
- Crear centros de costos.
- Asociar gastos con centros.
- Asociar ingresos con sucursales.
- Registrar costos indirectos.
- Distribuir gastos corporativos entre sucursales.
- Permitir reglas de prorrateo.
- Mantener trazabilidad de cada asignacion.

#### Conciliacion y cierres

- Importar movimientos bancarios.
- Conciliar bancos con caja y tesoreria.
- Identificar movimientos pendientes.
- Registrar ajustes contables autorizados.
- Bloquear periodos cerrados.
- Permitir reapertura controlada.
- Mantener historial de cierres.
- Evitar modificar operaciones ya cerradas.

#### Exportacion e integracion

- Exportar asientos contables.
- Exportar reportes financieros.
- Configurar formatos contables.
- Integrar con sistemas contables externos.
- Mantener identificadores externos de cuentas y transacciones.
- Registrar fallos de exportacion.

#### Requisitos por sucursal

- Las operaciones deben pertenecer a una sucursal o a la empresa central.
- El estado individual debe incluir solo la sucursal seleccionada.
- El estado consolidado debe incluir las sucursales autorizadas.
- Los resultados deben respetar moneda e impuestos configurados.
- Los ajustes deben quedar asociados a usuario, motivo y periodo.
- La contabilidad corporativa debe reconciliarse con todos los movimientos operativos.

### Modulo 15 - Analitica empresarial (Analytics)

Analytics calcula KPI, tendencias y datasets semanticos. Reporting convierte los datos
autorizados en documentos y los distribuye; Audit registra solicitudes, accesos,
generaciones y descargas. Ninguno consulta las tablas
privadas de los otros dominios.

#### Reportes de ventas

- Ventas por dia.
- Ventas por hora.
- Ventas por producto.
- Ventas por sucursal.
- Ventas por empleado.
- Ventas por categoria.
- Ventas por canal.
- Ventas brutas y netas.
- Comparacion contra periodos anteriores.

#### Reportes de productos

- Productos mas vendidos.
- Productos menos vendidos.
- Variantes mas vendidas.
- Combos mas vendidos.
- Productos con mayor margen.
- Productos con menor margen.
- Productos sin movimiento.
- Descuentos por producto.

#### Reportes de rentabilidad

- Margen por producto.
- Margen por categoria.
- Rentabilidad por sucursal.
- Rentabilidad por canal.
- Contribucion por empleado.
- Costo real frente a precio de venta.
- Tendencias de margen.

#### Reportes de inventario

- Rotacion de inventario.
- Perdidas.
- Desperdicios.
- Productos vencidos.
- Productos por vencer.
- Stock minimo.
- Diferencias de conteo.
- Consumo por recetas.
- Transferencias entre sucursales.

#### Reportes de personal

- Ventas por empleado.
- Pedidos atendidos.
- Ticket promedio generado.
- Horas trabajadas.
- Puntualidad.
- Horas extra.
- Propinas y comisiones.
- Productividad por turno.

#### Reportes de caja

- Aperturas y cierres.
- Diferencias de caja.
- Entradas y salidas.
- Gastos operativos.
- Retiros.
- Movimientos por empleado.
- Estado de conciliacion de PAYMENTS y arqueos de efectivo de CASH.

#### Reportes de clientes

- Frecuencia de visitas.
- Consumo por cliente.
- Ticket promedio.
- Clientes nuevos.
- Clientes recurrentes.
- Clientes sin actividad.
- Resultados de encuestas.
- Uso de puntos y cupones.

#### Reportes de compras

- Compras por proveedor.
- Compras por sucursal.
- Historial de precios.
- Variacion de precios.
- Costos de transporte.
- Recepciones parciales.
- Cumplimiento de proveedores.
- Gastos por periodo.

#### Reportes de cocina

- Tiempos de preparacion.
- Tiempos por plato.
- Tiempos por estacion.
- Pedidos retrasados.
- Cuellos de botella.
- Preparacion por empleado o turno.
- Comparacion de tiempos entre sucursales.

#### Reportes comparativos

- Comparacion entre sucursales.
- Rankings de sucursales.
- Ranking de productos.
- Ranking de empleados.
- Variacion mensual.
- Variacion anual.
- Metas frente a resultados.

#### Filtros y exportacion

- Filtrar por fecha.
- Filtrar por rango de tiempo.
- Filtrar por sucursal.
- Filtrar por empleado.
- Filtrar por categoria.
- Filtrar por producto.
- Filtrar por canal.
- Filtrar por estado de pedido.
- Exportar resultados.
- Programar reportes recurrentes.
- Mantener la hora de ultima actualizacion.

#### Requisitos por sucursal

- Los reportes pueden mostrar una sucursal individual.
- Los reportes pueden mostrar todas las sucursales autorizadas.
- Los totales consolidados deben ser coherentes con los filtros aplicados.
- Los usuarios deben ver solo reportes dentro de su alcance.
- Los reportes deben indicar moneda y zona horaria.
- Los resultados deben poder exportarse sin exponer datos fuera del permiso.

#### Responsabilidad de Reporting

- Generar informes PDF, Excel (XLSX) y CSV, además de formatos estructurados autorizados.
- Administrar plantillas y versiones publicadas e inmutables.
- Permitir informes configurables por usuario, empresa y sucursal.
- Programar informes diarios, semanales, mensuales o trimestrales con zona horaria.
- Distribuirlos por canales autorizados; Integrations conserva conexiones y realiza el transporte externo.
- Mantener historial de solicitudes, ejecuciones, artefactos y entregas sin guardar los archivos binarios en PostgreSQL.
- Exigir permisos y aprobaciones para informes financieros o confidenciales.
- Registrar eventos de consulta, generación, exportación y descarga en Audit; no crear un libro de auditoría paralelo.

### Modulo 16 - Administracion de sucursales

Modulo central para crear, configurar, comparar y administrar todas las sucursales de una empresa.

#### Gestion de sucursales

- Crear sucursales.
- Registrar datos generales del establecimiento.
- Registrar direccion y ubicacion.
- Registrar telefono y datos de contacto.
- Registrar configuracion fiscal.
- Definir moneda.
- Definir zona horaria.
- Activar sucursales.
- Desactivar sucursales.
- Suspender temporalmente operaciones.
- Mantener historial de cambios de estado.

#### Configuracion operativa

- Asignar administradores.
- Asignar empleados.
- Configurar cajas.
- Configurar bodegas.
- Configurar cocinas.
- Configurar estaciones de cocina.
- Configurar mesas y planos.
- Configurar zonas de reserva.
- Configurar impresoras.
- Configurar metodos de pago.
- Configurar canales digitales.
- Configurar zonas de domicilio.
- Definir horarios de operacion.
- Definir precios locales.
- Definir impuestos locales.
- Establecer objetivos de ventas.

#### Configuracion central

- Aplicar cambios a todas las sucursales.
- Aplicar cambios a una lista seleccionada de sucursales.
- Aplicar cambios solo a sucursales que heredan el valor central.
- Permitir excepciones por sucursal.
- Mostrar el origen de cada configuracion.
- Previsualizar cambios antes de aplicarlos.
- Programar cambios futuros.
- Mantener historial de configuraciones.
- Permitir reversion de configuraciones autorizadas.

#### Permisos y responsables

- Controlar permisos por sucursal.
- Asignar usuarios administradores.
- Asignar roles operativos.
- Restringir cambios fuera de la sucursal.
- Permitir permisos globales solo a roles autorizados.
- Registrar aprobaciones y responsables.

#### Comparacion y control

- Comparar resultados entre sucursales.
- Comparar ventas.
- Comparar rentabilidad.
- Comparar costos.
- Comparar cumplimiento de objetivos.
- Comparar rendimiento de personal.
- Comparar inventario y desperdicios.
- Identificar sucursales inactivas o con retrasos operativos.
- Mostrar datos consolidados a nivel empresa.

#### Requisitos por sucursal

- Cada sucursal debe tener un identificador unico dentro de la empresa.
- Cada sucursal debe tener un contexto operativo propio.
- Las operaciones deben impedir mezclar datos de sucursales no autorizadas.
- Las configuraciones locales deben conservar trazabilidad.
- Los cambios centralizados deben respetar las excepciones locales.
- La desactivacion debe impedir nuevas operaciones sin eliminar historicos.

### Modulo 17 - Automatizaciones de procesos

Modulo con un motor visual para crear reglas empresariales sin desarrollar integraciones o programas especiales.

#### Constructor de automatizaciones

- Crear reglas visuales.
- Definir disparadores.
- Definir condiciones.
- Definir acciones.
- Definir secuencias de pasos.
- Programar retrasos.
- Programar fechas y horas.
- Definir aprobaciones.
- Configurar notificaciones.
- Activar o desactivar reglas.
- Versionar reglas automatizadas.
- Mantener el historial de ejecuciones.

#### Estructura de una automatizacion

Una automatizacion debe contener disparador, condiciones opcionales, una o varias acciones y manejo de errores.

- El disparador inicia la ejecucion.
- Las condiciones determinan si deben ejecutarse las acciones.
- Las acciones realizan cambios o integraciones.
- Los retrasos permiten esperar antes de continuar.
- Las aprobaciones permiten detener la automatizacion hasta recibir una decision.
- Las notificaciones informan a usuarios o equipos.
- Los reintentos permiten recuperar fallos temporales.
- Los errores deben registrarse y notificar a responsables.

#### Automatizacion de inventario

Ejemplo:

1. El inventario de pollo baja del minimo.
2. El sistema detecta la situacion.
3. Genera una solicitud de compra.
4. Notifica al administrador.
5. Si se aprueba, genera la orden de compra al proveedor.

La propuesta debe considerar sucursal, stock disponible, consumo y configuracion de proveedores.

#### Automatizacion de cierre de caja

Ejemplo:

1. El empleado solicita cerrar caja.
2. El sistema calcula el dinero esperado.
3. Compara el efectivo real.
4. Detecta diferencias.
5. Solicita aprobacion si supera el limite configurado.
6. Genera el informe de cierre.

Las aprobaciones deben respetar rol, importe y sucursal.

#### Automatizacion de cocina

Ejemplo:

1. Un pedido supera el tiempo establecido.
2. El sistema detecta el retraso.
3. Notifica al encargado.
4. Eleva la prioridad del pedido.
5. Registra el incidente para analisis.

Los tiempos pueden calcularse por sucursal, plato, estacion y turno.

#### Automatizacion de sucursales

Ejemplo:

1. Una sucursal presenta una caida de ventas.
2. El sistema compara los resultados con periodos historicos.
3. Detecta una anomalia.
4. Genera una alerta a la administracion central.

Las reglas deben distinguir caidas normales, estacionales y anomalas.

#### Ejecucion y control

- Registrar inicio y fin de cada ejecucion.
- Registrar disparador que inicio la regla.
- Registrar datos utilizados por las condiciones.
- Registrar acciones ejecutadas.
- Registrar aprobaciones recibidas.
- Registrar reintentos.
- Registrar errores y causa.
- Permitir ejecucion manual de una regla.
- Permitir ejecucion de prueba.
- Evitar ejecuciones duplicadas.
- Permitir limites de frecuencia.
- Permitir notificaciones por canal configurado.

#### Reintentos y errores

- Reintentar acciones temporales.
- Configurar cantidad de reintentos.
- Configurar intervalos de reintento.
- Detener la ejecucion ante errores permanentes.
- Registrar cada intento.
- Escalar errores segun prioridad.
- Permitir correccion y reanudacion.

#### Requisitos por sucursal

- Las reglas pueden ser globales.
- Las reglas pueden aplicarse a sucursales seleccionadas.
- Las reglas pueden tener condiciones locales.
- Las aprobaciones deben respetar el alcance de la sucursal.
- Los usuarios deben tener permisos separados para crear, aprobar y auditar reglas.
- Las ejecuciones deben mostrar sucursal, usuario y contexto.

### Capacidad transversal de inteligencia artificial - AI Manager

Capacidad de asistencia empresarial que consulta datos reales del restaurante mediante contratos y herramientas autorizadas, y ayuda a analizar, predecir y proponer acciones. No constituye un dominio propietario ni tiene schema PostgreSQL propio en esta etapa. Cada módulo conserva los datos de su proceso; cualquier persistencia compartida futura requiere un ADR nuevo.

#### Analista financiero

La IA debe poder responder preguntas como:

- ¿Cuanto ganamos hoy?
- ¿Que sucursal es mas rentable?
- ¿Cuales son nuestros mayores gastos?
- ¿Por que bajaron las ganancias?
- ¿Que productos tienen menor margen?

Las respuestas deben mostrar origen, periodo, sucursal y nivel de confianza cuando aplique.

#### Analista de inventario

- Identificar productos proximos a agotarse.
- Identificar ingredientes desperdiciados.
- Recomendar compras para el siguiente periodo.
- Identificar exceso de inventario por sucursal.
- Comparar consumo real contra consumo esperado.
- Detectar variaciones de vencimiento y merma.
- Proponer transferencias entre sucursales.

#### Analista de ventas

- Recomendar productos para promociones.
- Identificar dias con menor venta.
- Identificar horarios de mayor demanda.
- Identificar sucursales con mayor crecimiento.
- Comparar categorias y productos.
- Explicar cambios relevantes en ventas.

#### Predicciones

- Predecir ventas del dia siguiente.
- Predecir demanda por producto.
- Predecir demanda por sucursal.
- Predecir consumo de ingredientes.
- Predecir personal necesario.
- Predecir compras futuras.
- Mostrar el periodo y los datos utilizados.
- Indicar incertidumbre o nivel de confianza.
- Comparar predicciones con resultados reales.

#### Anomalias

- Detectar descuentos inusuales.
- Detectar anulaciones excesivas.
- Detectar diferencias de inventario.
- Detectar consumos fuera de lo normal.
- Detectar cambios extraños en las ventas.
- Detectar gastos inesperados.
- Generar alertas con evidencia y contexto.
- Permitir confirmar o descartar anomalías.

#### Asistente administrativo

El asistente debe interpretar instrucciones y consultar datos reales.

Ejemplos:

- "Muéstrame las ventas de las tres sucursales de esta semana".
- "Prepara una solicitud de compra de los productos que están por agotarse".
- "Compara la rentabilidad de las hamburguesas entre sucursales".

El asistente puede preparar acciones, solicitudes o informes, pero no debe ejecutarlas si requieren autorizacion.

#### Acciones asistidas

- Generar solicitudes de compra.
- Preparar informes.
- Comparar sucursales.
- Preparar promociones.
- Preparar ajustes de inventario.
- Preparar cambios de precio.
- Preparar alertas y resúmenes.
- Mantener borradores pendientes de aprobacion.

#### Permisos y autorizacion

- Limitar el acceso a datos segun usuario y sucursal.
- Permitir consulta sin modificar datos.
- Solicitar autorizacion para pagos.
- Solicitar autorizacion para anulaciones.
- Solicitar autorizacion para cambios de precio.
- Solicitar autorizacion para movimientos de inventario.
- Solicitar aprobacion segun las politicas de la empresa.
- Registrar usuario, fecha y accion solicitada.
- Registrar resultado de cada aprobacion.

#### Auditoria y confianza

- Mostrar la fuente de los datos usados.
- Mostrar periodos y filtros aplicados.
- Evitar inventar datos cuando no existan resultados.
- Indicar cuando una conclusion sea una estimacion.
- Permitir validar predicciones contra resultados posteriores.
- Mantener historial de preguntas y respuestas autorizadas.
- Permitir desactivar funciones de IA por sucursal.
- Permitir desactivar acciones automaticas mientras se conserva la consulta.

#### Requisitos por sucursal

- Las consultas deben respetar el alcance por sucursal.
- Las predicciones pueden calcularse individualmente o en conjunto.
- Las recomendaciones deben indicar sucursal y contexto.
- Las acciones deben crear borradores dentro de la sucursal correspondiente.
- Los usuarios deben tener permisos separados para consultar, proponer y aprobar.

## Capacidad transversal A - Usuarios, roles y permisos

La plataforma debe permitir asignar acceso granulado segun usuario, cargo, empresa y sucursal.

### Usuarios

- Registrar usuarios.
- Registrar identificacion y contacto.
- Permitir invitaciones.
- Activar o desactivar usuarios.
- Mantener sesiones.
- Registrar inicio y cierre de sesion.
- Permitir autenticacion segura.
- Permitir autenticacion multifactor cuando aplique.
- Vincular usuarios con empresas y sucursales.
- Registrar cambio de sucursal activa.

### Roles funcionales

- Superadministrador: administracion global de la plataforma, sin acceso automatico al contenido privado de tenants.
- Propietario: acceso a todas las sucursales.
- Gerente general: administracion global dentro de las sucursales autorizadas.
- Administrador de sucursal: administracion completa de su sucursal.
- Supervisor: operacion y supervision.
- Cajero: ventas y caja.
- Mesero: pedidos y mesas.
- Cocinero: comandas.
- Inventarista: inventarios.
- Contador: finanzas y reportes.

Los roles pueden combinarse y personalizarse segun las necesidades del cliente.

### Permisos granulares

- Permisos por accion.
- Permisos por modulo.
- Permisos por entidad.
- Permisos por sucursal.
- Permisos por empresa.
- Permisos globales.
- Permisos condicionales segun importe.
- Permisos condicionales segun estado.
- Permisos limitados por ubicacion.
- Permisos temporales.

Ejemplos:

- Puede aplicar descuentos hasta el 10%.
- No puede anular facturas.
- Puede visualizar ventas, pero no costos.
- Puede consultar inventario, pero no modificarlo.
- Puede cerrar caja, pero no modificar movimientos anteriores.

### Separacion de funciones

- Separar consulta de modificacion.
- Separar preparacion de aprobacion.
- Separar apertura de caja de cierre.
- Separar conteo de aprobacion de diferencias.
- Separar compra de pago.
- Separar recepcion de aprobacion contable.
- Permitir doble aprobacion en operaciones sensibles.

### Auditoria

- Registrar todas las operaciones sensibles.
- Registrar usuario responsable.
- Registrar sucursal y sesion.
- Registrar fecha y hora.
- Registrar accion realizada.
- Registrar datos anteriores y nuevos cuando aplique.
- Registrar motivo y aprobacion.
- Registrar consultas sensibles.
- Registrar cambios de permisos.
- Evitar eliminar registros de auditoria.
- Permitir exportacion y revision por usuarios autorizados.

Los permisos y la auditoria deben aplicarse a los modulos operativos y a las acciones realizadas por automatizaciones o IA.

## Capacidad transversal B - Configuracion general

Debe existir un centro central de configuracion para administrar los parametros corporativos y locales.

### Configuracion empresarial

- Registrar informacion de la empresa.
- Registrar datos tributarios.
- Configurar moneda principal.
- Configurar monedas adicionales cuando aplique.
- Configurar zona horaria.
- Configurar impuestos.
- Configurar numeraciones de documentos.
- Configurar sucursales.
- Configurar impresoras.
- Registrar dispositivos.
- Configurar metodos de pago.
- Configurar plantillas de documentos.
- Configurar idiomas.
- Configurar notificaciones.
- Configurar parametros generales.
- Configurar integraciones habilitadas.

### Configuracion por sucursal

- Permitir configuracion individual por sucursal.
- Configurar moneda local si esta permitido.
- Configurar zona horaria local.
- Configurar impuestos locales.
- Configurar numeracion local.
- Configurar impresoras locales.
- Configurar dispositivos locales.
- Configurar metodos de pago disponibles.
- Configurar horarios de operacion.
- Configurar plantillas de comprobantes.
- Configurar idioma y formatos locales.
- Configurar notificaciones locales.
- Configurar parametros operativos locales.

### Plantillas y documentos

- Crear plantillas de facturas.
- Crear plantillas de tickets.
- Crear plantillas de pedidos.
- Crear plantillas de cotizaciones.
- Crear plantillas de recepciones.
- Permitir variables dinamicas.
- Permitir encabezados y pies personalizados.
- Permitir logos e informacion tributaria.
- Mantener version historica de plantillas.

### Configuracion central selectiva

- Aplicar cambios a toda la empresa.
- Aplicar cambios a una lista de sucursales.
- Permitir sucursales que heredan configuracion central.
- Permitir excepciones locales.
- Mostrar origen de cada valor.
- Previsualizar cambios.
- Programar activacion futura.
- Permitir reversion autorizada.
- Registrar auditoria de cambios.

### Dispositivos e impresoras

- Registrar dispositivos por sucursal.
- Identificar impresora, caja y POS.
- Validar compatibilidad.
- Mostrar estado de conexion.
- Generar alertas de desconexion.
- Permitir configuracion por tipo de documento.

### Requisitos generales

- Las configuraciones deben estar disponibles segun permisos.
- Las configuraciones criticas deben requerir autorizacion.
- Los cambios deben quedar asociados a usuario y sucursal.
- Los valores invalidos deben bloquearse antes de guardar.
- Cada modulo debe utilizar la configuracion vigente.
- La configuracion debe permitir restauracion controlada.

## Capacidad transversal C - Integraciones externas

El sistema debe estar preparado para conectarse con servicios externos y ofrecer una API propia.

### Centro de integraciones

- Mostrar integraciones disponibles.
- Configurar integraciones por empresa.
- Configurar integraciones por sucursal.
- Activar o desactivar integraciones.
- Gestionar credenciales.
- Registrar estado de conexion.
- Registrar errores de integracion.
- Permitir reintentos.
- Mantener historial de sincronizacion.
- Registrar webhooks recibidos y enviados.

### WhatsApp Business

- Recibir pedidos.
- Confirmar pedidos.
- Enviar notificaciones.
- Enviar estados de domicilio.
- Permitir atencion al cliente.
- Asociar conversaciones con clientes y pedidos.
- Respetar consentimientos.

### Google Maps

- Validar direcciones.
- Calcular distancias.
- Estimar tiempos de viaje.
- Definir zonas de cobertura.
- Calcular tarifas segun distancia o zona.
- Mostrar ubicacion de domicilios.

### DIAN y facturacion electronica

- Integrar facturacion y documentos electronicos.
- Validar datos tributarios.
- Enviar documentos a la autoridad fiscal.
- Consultar estado de documentos.
- Guardar respuestas y acuses.
- Permitir reenvios controlados.

### Conectores de pasarela de pago

INTEGRATIONS implementa la comunicacion tecnica con proveedores externos; PAYMENTS conserva las cuentas, metodos y operaciones financieras.

- Enviar a proveedores las solicitudes autorizadas por PAYMENTS.
- Recibir, validar y normalizar webhooks para PAYMENTS.
- Mantener credenciales en un gestor de secretos y exponer solo referencias seguras.
- Permitir a PAYMENTS consultar el estado de transacciones, gestionar reembolsos y conciliar liquidaciones.
- Propagar eventos con idempotencia para evitar cobros o reembolsos duplicados.
- No crear en INTEGRATIONS un libro paralelo de transacciones o reembolsos.

### Analitica externa

- Medir canales digitales.
- Enviar eventos comerciales.
- Respetar consentimientos de medicion.
- Evitar informacion sensible innecesaria.
- Comparar conversiones por canal.

### Automatizacion externa

- Integrar plataformas como Zapier u otras herramientas.
- Ejecutar acciones mediante eventos.
- Permitir flujos hacia sistemas externos.
- Recibir acciones desde sistemas externos.
- Documentar cada evento disponible.

### API propia

- Exponer una API documentada.
- Permitir integraciones de terceros autorizados.
- Utilizar autenticacion por claves o tokens.
- Aplicar permisos por cliente de API.
- Definir limites de uso.
- Registrar llamadas y errores.
- Permitir webhooks de salida.
- Mantener versionado de la API.

### Seguridad e integridad

- Cifrar credenciales.
- Aplicar permisos minimos.
- Registrar usuario y sucursal que configura una integracion.
- Permitir revocacion inmediata.
- Reintentar operaciones idempotentes sin duplicar datos.
- Mantener trazabilidad entre pedido, cobro y documento externo.

### Requisitos por sucursal

- Las integraciones pueden ser globales o locales.
- Los canales deben utilizar credenciales autorizadas por sucursal.
- Las facturas deben enviarse con datos fiscales de la sucursal.
- Los eventos de pago deben conservar la sucursal para que PAYMENTS realice la conciliacion correspondiente.
- Los permisos deben limitar configuraciones de integracion.

## Requisito transversal - Operacion offline-first

La venta y la caja deben poder continuar sin conectividad para las operaciones
habilitadas. Los cimientos se definen en Fase 0 y el flujo offline minimo se
entrega junto con el primer POS operativo; la resiliencia avanzada no se aplaza
a la Fase 10.

### Datos locales

- Conservar datos operativos necesarios en el dispositivo.
- Conservar catalogo disponible.
- Conservar precios vigentes.
- Conservar productos y excepciones por sucursal.
- Conservar inventario util conocido.
- Conservar metodos de pago disponibles.
- Conservar numeracion local autorizada.
- Conservar configuraciones fiscales necesarias.
- Proteger los datos locales contra perdida o acceso no autorizado.

### Operacion sin conexion

- Permitir registrar pedidos sin conexion.
- Permitir registrar ventas sin conexion.
- Permitir cobrar solo mediante metodos expresamente habilitados para uso
  offline, con limites y reglas de conciliacion definidos.
- Permitir abrir y cerrar caja segun las reglas locales.
- Permitir crear clientes basicos cuando este autorizado.
- Permitir imprimir comprobantes locales.
- Permitir operaciones de devolucion segun permisos y datos disponibles.

### Cola de sincronizacion

- Guardar las operaciones pendientes de sincronizacion.
- Mantener estado de cada operacion.
- Procesar operaciones pendientes al recuperar conexion.
- Sincronizar automaticamente.
- Permitir sincronizacion manual.
- Registrar fecha de creacion y fecha de sincronizacion.
- Registrar reintentos y errores.
- Mantener bloqueo local durante operaciones criticas.

### Identificacion e idempotencia

- El POS debe generar un identificador unico y una clave de idempotencia en el
  dispositivo antes
  del primer envio de cada operacion; no depender de una respuesta del servidor
  para asignar la identidad local.
- Mantener el mismo identificador y la misma clave durante todos los reintentos
  y sincronizaciones.
- El servidor debe deduplicar operaciones dentro del tenant y dispositivo
  registrados, sin confiar en el identificador de dispositivo enviado por el
  cliente como prueba de identidad o autorizacion.
- El servidor debe rechazar o ignorar operaciones duplicadas.
- Las ventas no deben contabilizarse dos veces.
- Los movimientos de inventario no deben aplicarse dos veces.
- Los pagos no deben asentarse dos veces.
- Los cierres no deben procesarse dos veces.

### Numeracion fiscal

- Asignar a cada sucursal y punto de venta rangos autorizados y no solapados
  para los dispositivos o cajas que deban operar desconectados, conforme a la
  validacion fiscal aplicable.
- No habilitar emision fiscal offline si el dispositivo no tiene un rango
  valido y vigente.
- Evitar duplicados y conservar la trazabilidad de la reserva, asignacion y
  consumo de cada consecutivo.
- Mantener numeros fiscales validos durante desconexion.
- Registrar conflictos de numeracion.
- Bloquear comprobantes si no hay numeracion valida.
- Sincronizar registros fiscales sin alterar consecutivos.

### Resolucion de conflictos

- Detectar operaciones modificadas fuera de orden.
- Detectar cambios simultaneos entre dispositivos.
- Mantener versiones de operaciones.
- Aplicar reglas deterministas de conflicto.
- No sobrescribir registros financieros sin trazabilidad.
- Marcar conflictos que requieren revision humana.
- Permitir conciliacion posterior.
- Informar al usuario cuando una operacion no pudo sincronizarse.

### Fiabilidad

- No perder pedidos si el navegador se recarga.
- Persistir datos en almacenamiento local seguro.
- Confirmar que una operacion quedo registrada antes de continuar.
- Evitar depender solo de memoria o almacenamiento temporal.
- Recuperar operaciones pendientes despues de reiniciar.
- Mantener auditoria de sincronizaciones y conflictos.

### Requisitos por sucursal

- Cada dispositivo debe identificarse dentro de una sucursal.
- El dispositivo debe estar registrado y provisionado antes de operar offline;
  su identidad local no sustituye autenticacion al sincronizar.
- Los datos locales deben estar separados por sucursal.
- Los permisos offline deben coincidir con los permisos vigentes.
- La sincronizacion debe indicar sucursal, caja y usuario.
- Los reportes deben distinguir operaciones pendientes y operaciones confirmadas.

## Requisitos particulares - Operacion en Colombia

El sistema debe contemplar desde el diseño las obligaciones tributarias y comerciales aplicables en Colombia.

### Facturacion electronica

- Integrarse con la DIAN.
- Emitir facturas electronicas de venta.
- Emitir documentos equivalentes electronicos tipo POS cuando corresponda.
- Emitir notas credito.
- Emitir notas de ajuste.
- Registrar documentos anulados.
- Registrar respuestas de validacion y aceptacion.
- Mantener trazabilidad completa de documentos fiscales.
- Utilizar numeracion autorizada y configurada.
- Identificar correctamente empresa, sucursal y punto de venta.

### Impuestos

- Identificar la responsabilidad tributaria de la empresa.
- Registrar NIT y datos fiscales.
- Configurar impuestos por producto y servicio.
- Gestionar IVA.
- Gestionar impuesto nacional al consumo cuando corresponda.
- Permitir combinaciones fiscales segun el producto.
- Aplicar impuestos segun sucursal y normativa vigente.
- Mantener reglas fiscales versionadas.
- Evitar asumir que todos los alimentos o servicios tienen el mismo tratamiento tributario.

### Numeracion y autorizaciones

- Registrar resoluciones y rangos autorizados.
- Asociar numeracion con sucursal y punto de venta.
- Reservar rangos sin crear documentos duplicados.
- Alertar por proximidad al agotamiento de numeracion.
- Bloquear emisiones que excedan rangos autorizados.
- Mantener numeros emitidos, anulados y pendientes.
- Registrar fecha de habilitacion y vencimiento de resoluciones.

### Reportes fiscales

- Generar reportes contables y tributarios.
- Separar ventas gravadas, excluidas y exentas.
- Separar IVA e impuesto nacional al consumo.
- Reportar notas credito y ajustes.
- Consolidar documentos por sucursal.
- Exportar informacion para procesos contables y tributarios.
- Conservar documentos originales y respuestas fiscales.

### Proteccion de datos

- Registrar y proteger datos personales.
- Solicitar consentimientos cuando sean aplicables.
- Restringir acceso segun rol y sucursal.
- Registrar consultas y cambios de datos personales.
- Permitir rectificacion y eliminacion segun las reglas aplicables.
- Mantener registros fiscales sin vulnerar derechos de datos.

### Componente independiente de facturacion

La facturacion debe ser un componente independiente del POS.

- Debe comunicarse con el POS mediante interfaces o eventos.
- Debe permitir actualizar reglas normativas sin modificar la operacion principal.
- Debe recibir ventas validadas del POS.
- Debe registrar estados de transmision y respuesta.
- Debe permitir reenvios controlados.
- Debe conservar trazabilidad del documento original.
- Debe soportar distintos proveedores fiscales sin acoplarlos al modulo de ventas.

### Requisito fiscal offline

- Permitir operaciones locales segun la modalidad habilitada.
- Reservar y asignar previamente numeracion autorizada, vigente y no solapada
  para el dispositivo y punto de venta.
- No emitir documentos fiscales sin identificacion valida.
- Marcar documentos pendientes de transmision.
- Sincronizar documentos fiscales al recuperar conexion.
- Evitar duplicar documentos fiscales al sincronizar.
- Resolver diferencias de numeracion mediante conciliacion autorizada.

### Reglas normativas

- No asumir que un recibo impreso satisface una obligacion fiscal electronica.
- Validar la aplicacion normativa vigente antes de emitir documentos.
- Mantener actualizaciones legales trazables.
- Solicitar revision profesional o normativa ante cambios tributarios.

### Plataforma

- Configuracion global.
- Entornos empresariales.
- Auditoria.
- Integraciones.
- Observabilidad.

### Identidad y organizaciones

- Usuarios.
- Empresas u organizaciones.
- Sucursales.
- Invitaciones.
- Roles.
- Permisos.
- Sesiones.

### Catalogo

- Categorias.
- Productos.
- Variantes.
- Modificadores.
- Combos.
- Precios.
- Impuestos.
- Disponibilidad por sucursal.

### Ventas y pedidos

- Punto de venta.
- Pedidos de mostrador.
- Pedidos en mesa.
- Pedidos de delivery.
- Descuentos.
- Propinas.
- Pagos.
- Facturacion.

### Mesas

- Zonas.
- Mesas.
- Estado de ocupacion.
- Apertura y division de cuenta.
- Transferencia de mesas.

### Cocina

- Comandas.
- Estados de preparacion.
- KDS.
- Tiempos de servicio.
- Alertas de retraso.

### Inventario y recetas

- Insumos.
- Recetas.
- Costeo.
- Merma.
- Ajustes.
- Conteos.
- Transferencias.
- Stock minimo.
- Kardex.

### Compras

- Proveedores.
- Solicitudes.
- Ordenes de compra.
- Recepcion.
- Precios historicos.
- Sugerencia de compra.

### Personal

- Empleados.
- Roles.
- Horarios.
- Turnos.
- Asistencia.
- Comisiones.
- Rendimiento.

### Clientes

- Clientes.
- Contactos.
- Historial.
- Fidelizacion.
- Segmentacion.
- CRM.

### Finanzas y facturacion

- Caja.
- Apertura y cierre.
- Arqueo.
- Gastos.
- Cuentas por pagar.
- Cuentas por cobrar.
- Facturacion electronica.
- Integracion contable.
- Reportes financieros.

### Analytics e inteligencia

- Ventas.
- Costos.
- Margenes.
- Rentabilidad.
- Desempeno por sucursal.
- Deteccion de anomalias.
- Pronostico de demanda.
- Recomendaciones de compra.
- Alertas operativas.
- Consultas asistidas por IA.

### Automatizacion e integraciones

- Reglas basadas en eventos.
- Pagos.
- Sistemas fiscales.
- Delivery.
- Reservas.
- WhatsApp.
- Webhooks.
- Integraciones contables.

## Requisitos tecnicos

- Utilizar un monolito modular bien organizado en la primera etapa.
- Organizar el backend por modulos de dominio con limites claros.
- Evitar una arquitectura de microservicios prematura.
- Utilizar PostgreSQL como base de datos principal.
- Exponer funcionalidades mediante APIs internas y publicas.
- Utilizar colas de eventos para procesos asincronos.
- Utilizar almacenamiento local para operaciones offline.
- Sincronizar operaciones locales mediante APIs y colas seguras.
- Permitir evolucionar hacia servicios separados cuando el volumen lo justifique.
- Separar componentes solo por necesidad tecnica o de escala demostrada.
- Mantener interfaces estables entre modulos.
- Evitar duplicar modelos y reglas de negocio al extraer servicios.
- Utilizar una base de datos central mientras las reglas operativas lo permitan.
- Preparar modulos para que puedan evolucionar hacia servicios independientes.
- Mantener observabilidad y trazabilidad entre modulos y colas.
- Arquitectura modular preparada para crecer.
- API segura y documentada.
- Base de datos central con aislamiento por organizacion y sucursal.
- Operaciones financieras idempotentes.
- Auditoria de cambios sensibles.
- Manejo explicito de moneda, impuestos y zonas horarias.
- Observabilidad central.

## Stack tecnologico inicial

| Componente | Tecnología |
|---|---|
| Frontend administrativo | Next.js + React + TypeScript |
| Interfaz POS | React + TypeScript + PWA |
| Aplicacion de escritorio | Tauri |
| Aplicacion móvil futura | React Native |
| Backend | Rust + Axum |
| Monorepo Rust | Cargo workspace |
| Persistencia Rust | PostgreSQL + SQLx |
| API hacia frontends | HTTP + OpenAPI expuesta por Admin BFF y Public BFF |
| Comunicación entre procesos | gRPC + Tonic + Protobuf versionado para solicitudes/respuestas; NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda. Los módulos dentro de un mismo backend usan puertos/traits locales |
| Tiempo real | WebSockets |
| Base de datos | PostgreSQL |
| Caché | Redis |
| Mensajería | NATS Core (señales efímeras) y NATS JetStream (eventos durables) |
| Archivos | Almacenamiento compatible con S3 |
| Analítica inicial | PostgreSQL |
| Analítica a escala | ClickHouse cuando el volumen lo justifique |
| IA | Modelos mediante API y servicios propios |
| Automatizacion | Motor de workflows propio |
| Monitoreo | OpenTelemetry + Grafana |
| Infraestructura | Docker + servicios cloud |

No es necesario implementar todas las tecnologias desde el primer dia.

### Criterios de seleccion

- Rust permite compilar cada proceso como un binario independiente: los backends de dominio contienen sus módulos propietarios y los BFF contienen composición y transporte.
- Cargo workspace permite separar módulos en crates y enlazarlos en el binario del backend propietario.
- SQLx permite persistencia tipada y transacciones controladas sobre PostgreSQL.
- Hexagonal + DDD mantienen reglas de negocio independientes de transporte y persistencia.
- Axum sirve las superficies HTTP de Admin BFF y Public BFF; Admin Platform Backend y Public Backend exponen sus contratos de backend.
- Tonic proporciona gRPC y HTTP/2 en las fronteras entre los cuatro procesos desde el inicio y permite futuras extracciones de módulos.
- PostgreSQL ofrece transacciones y relaciones sólidas.
- Redis puede utilizarse para caché, sesiones y coordinación.
- WebSockets permiten actualizar pedidos y pantallas de cocina.
- PWA permite instalar el POS y conservar capacidades locales.
- Tauri puede integrarse con impresoras y dispositivos de escritorio.
- Las interfaces deben usar una biblioteca de componentes y sistema de diseño propio.
- S3 permite almacenar archivos y documentos con proveedores compatibles.
- ClickHouse puede introducirse cuando PostgreSQL ya no sea suficiente para analítica.
- OpenTelemetry permite trazabilidad técnica de punta a punta.

## Arquitectura Rust modular

Restaurant OS utilizara un monolito modular implementado en Rust.

- El repositorio sera un Cargo workspace.
- Los modulos se implementaran como crates de biblioteca.
- Admin Platform Backend sera un binario/proceso independiente.
- Admin BFF sera un binario/proceso independiente que expone HTTP/OpenAPI a los frontends administrativos.
- Public BFF sera un binario/proceso independiente que expone HTTP/OpenAPI a los frontends públicos.
- Public Backend sera un binario/proceso independiente.
- Admin Platform Backend y Public Backend tendrán sus módulos propietarios y puntos de composición. Admin BFF y Public BFF tendrán puntos de composición propios, sin módulos propietarios de negocio.
- Los modulos no deben estar acoplados a clases o tablas privadas de otros modulos.
- Los modulos deben exponer contratos publicos, puertos y fachadas.
- La arquitectura debe facilitar extraer modulos sin reescribir sus reglas de negocio.

### Estructura inicial del repositorio

```text
restaurant-os/
├── apps/
│   ├── admin-platform-backend/
│   │   └── src/
│   ├── admin-bff/
│   │   └── src/
│   ├── public-bff/
│   │   └── src/
│   ├── public-backend/
│   │   └── src/
│   ├── admin-web/
│   ├── customer-portal/
│   ├── kitchen-display/
│   └── pos/
│
├── backend/
│   ├── admin-platform-backend/
│   │   └── modules/
│   ├── admin-bff/
│   │   └── modules/
│   ├── public-bff/
│   │   └── modules/
│   └── public-backend/
│       └── modules/
│
├── contracts/
│   └── protobuf/
│       └── <backend>/<modulo>/v1/*.proto
│
├── crates/
│   ├── shared/
│   ├── contracts/
│   │   └── events/
│   └── adapters/
│       ├── grpc/
│       ├── messaging/
│       └── local/
│
├── packages/
│   ├── permissions/
│   ├── shared-types/
│   ├── ui/
│   ├── utilities/
│   └── validation/
│
├── infrastructure/
│   ├── docker/
│   │   ├── admin-platform-backend/
│   │   ├── admin-bff/
│   │   ├── public-bff/
│   │   └── public-backend/
│   ├── deployment/
│   │   ├── development/
│   │   ├── staging/
│   │   └── production/
│   ├── database/
│   │   ├── postgres/
│   │   └── scripts/
│   ├── nats/
│   ├── redis/
│   └── monitoring/
│       ├── opentelemetry/
│       └── dashboards/
│
├── docs/
├── scripts/
├── migrations/  # ubicación histórica; no agregar migraciones nuevas aquí
└── rules/
```

### Responsabilidad de cada carpeta

| Carpeta | Responsabilidad |
|---|---|
| `apps/admin-platform-backend/` | Punto de entrada del proceso independiente de administración SaaS. |
| `apps/admin-bff/` | Punto de entrada del BFF administrativo; expone HTTP/OpenAPI y coordina contratos hacia backends. |
| `apps/public-bff/` | Punto de entrada del BFF público; expone HTTP/OpenAPI y coordina contratos hacia backends. |
| `apps/public-backend/` | Punto de entrada del backend público independiente. |
| `apps/admin-web/` | Frontend de administración de plataforma. |
| `apps/customer-portal/` | Aplicación de portal para clientes/usuarios públicos. |
| `apps/kitchen-display/` | Interfaz de pantallas de cocina. |
| `apps/pos/` | Aplicación de punto de venta. |
| `backend/<backend>/modules/` | Módulos/crates que pertenecen exclusivamente al backend indicado. |
| `crates/shared/` | Bibliotecas técnicas neutrales reutilizables; no debe apropiarse de dominios ni tablas. |
| `contracts/protobuf/` | Fuentes Protobuf versionadas para contratos gRPC. |
| `crates/contracts/events/` | Esquemas versionados de eventos compartidos. |
| `crates/adapters/local/` | Adaptadores para llamadas entre módulos que comparten proceso. |
| `crates/adapters/grpc/` | Adaptadores gRPC para fronteras entre procesos. |
| `crates/adapters/messaging/` | Adaptadores de NATS Core y NATS JetStream. |
| `packages/permissions/` | Tipos y utilidades compartidas de presentación de permisos; la autorización efectiva pertenece al backend. |
| `packages/shared-types/` | Tipos compartidos no autoritativos, preferiblemente derivados de contratos. |
| `packages/ui/` | Componentes y sistema visual compartido de frontend. |
| `packages/utilities/` | Utilidades técnicas compartidas de frontend. |
| `packages/validation/` | Validaciones de presentación; no reemplazan las validaciones del dominio. |
| `infrastructure/docker/` | Definiciones de contenedores para los cuatro procesos. |
| `infrastructure/deployment/` | Configuración objetivo por entorno: desarrollo, staging y producción. |
| `infrastructure/database/` | Configuración y scripts operativos de PostgreSQL; no es propietaria de migraciones de módulos. |
| `infrastructure/nats/` | Configuración de NATS Core y JetStream. |
| `infrastructure/redis/` | Configuración de Redis cuando corresponda. |
| `infrastructure/monitoring/` | Configuración de OpenTelemetry y dashboards. |
| `docs/` | Documentación de arquitectura, decisiones, ingeniería y operación. |
| `scripts/` | Automatización reproducible de desarrollo, validación y operaciones locales. |
| `migrations/` | Archivos históricos existentes; se conserva sin mover ni editar en esta reorganización. |
| `rules/` | Reglas de trabajo y controles documentales del repositorio. |

### Reglas obligatorias de estructura

1. Los cuatro backends son procesos/binarios independientes; cada uno tiene su
   propio punto de entrada y su propia composición de dependencias.
2. Cada módulo aparece una sola vez, bajo `backend/<backend-propietario>/modules/`.
   La responsabilidad del dominio se conserva aunque cambie la ubicación física.
3. Cada módulo mantiene su crate, capas `domain/`, `application/`,
   `infrastructure/` y `contracts/`, según corresponda.
4. Cada módulo es propietario exclusivo de su schema, rol, tablas, migraciones
   e historial SQLx. No existe historial compartido entre módulos.
5. Ningún módulo puede leer o escribir directamente tablas de otro módulo; no
   se permiten FKs, joins, vistas ni consultas entre schemas propietarios.
6. Los módulos del mismo proceso se comunican mediante contratos públicos y
   puertos/traits locales para solicitudes síncronas. Los hechos se expresan
   mediante eventos.
7. Entre procesos, las solicitudes/respuestas usan gRPC + Protobuf versionado.
   NATS Core se reserva para señales efímeras y JetStream para eventos durables.
8. Outbox/Inbox e idempotencia protegen la entrega durable. `FOR UPDATE SKIP
   LOCKED` solo reclama filas de trabajo; no es un protocolo de comunicación.
9. `crates/` y `packages/` no pueden convertirse en depósitos de lógica de
   negocio ni persistencia propietaria.
10. Los BFF no duplican reglas de dominio ni se integran dentro de los backends.
11. No crear carpetas de módulos vacías para asignar dominios por inferencia.
    La asignación debe respetar la matriz de responsabilidades y decisiones
    arquitectónicas aprobadas.
12. La estructura es objetivo documental; su presencia no demuestra que los
    binarios, servicios Docker, NATS, generadores o despliegues estén activos.

### Estructura interna de un modulo

```text
backend/
└── <backend-propietario>/
    └── modules/
        └── <modulo>/
            ├── Cargo.toml
            ├── migrations/
            ├── contracts/
            └── src/
                ├── domain/
                │   ├── entities/
                │   ├── value_objects/
                │   └── rules/
                ├── application/
                │   ├── commands/
                │   ├── queries/
                │   └── ports/
                ├── infrastructure/
                │   └── persistence/
                └── lib.rs
```

Las capas deben seguir arquitectura hexagonal:

- Domain contiene entidades, objetos de valor y reglas.
- Application contiene casos de uso y puertos.
- Infrastructure implementa persistencia, mensajeria y transporte.
- API o adapters presentan los casos de uso al exterior.

DDD debe definir agregados, entidades, casos de uso y límites por dominio.

### Inversion de dependencias

Las reglas de negocio de ventas no deben conocer tablas ni servicios privados de inventario.

Ventas debe depender de un puerto:

```rust
#[async_trait::async_trait]
pub trait StockGateway: Send + Sync {
    async fn reserve_stock(
        &self,
        command: ReserveStock,
    ) -> Result<StockReservation, StockError>;
}
```

El puerto debe tener adaptadores intercambiables:

- LocalInventoryAdapter para comunicacion dentro del mismo proceso.
- GrpcInventoryAdapter para comunicacion con un microservicio separado.

Las interfaces asincronas dinamicas deben utilizar async-trait.

### Comunicacion

Mecanismos iniciales:

- Contratos locales para operaciones inmediatas dentro del mismo proceso.
- gRPC con Tonic y Protocol Buffers para solicitudes/respuestas entre los cuatro procesos independientes desde el inicio.
- NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda.
- Eventos asíncronos para hechos publicados por otros módulos; Outbox/Inbox mantiene la entrega durable e idempotente.

gRPC no debe utilizarse para absolutamente toda comunicacion.

### Contratos gRPC

Los contratos gRPC versionados deben definir operaciones como:

```proto
syntax = "proto3";

package inventory.v1;

service InventoryService {
  rpc ReserveStock(ReserveStockRequest)
      returns (ReserveStockResponse);

  rpc ReleaseReservation(ReleaseReservationRequest)
      returns (ReleaseReservationResponse);
}
```

Los contratos deben versionarse, validar tenant y sucursal y conservar identificadores idempotentes.

### Eventos de dominio

- Los comandos solicitan que ocurra una accion.
- Los eventos representan hechos que ya ocurrieron.
- Los eventos deben contener tenant, sucursal, correlacion y identificador de evento.
- Las operaciones deben registrar eventos en Outbox dentro de la misma transaccion.
- Un publicador debe entregar los eventos al broker.
- Los consumidores deben evitar procesar dos veces.
- Los eventos deben utilizar esquemas versionados.

Ejemplo:

- ReserveStock es un comando.
- StockReserved es un evento.
- ReleaseReservation es un comando.
- ReservationReleased es un evento.

### Propiedad de PostgreSQL

- La base inicial sera compartida.
- Cada modulo tendra propiedad exclusiva de sus esquemas y tablas.
- Ventas no debe modificar tablas de inventario.
- Inventario no debe modificar tablas de ventas.
- Los modulos tendran repositorios y migraciones propios.
- Las relaciones cruzadas se identificaran por UUID.
- Los modulos no compartirán transacciones SQLx.
- Cada modulo controlara sus propias transacciones.

Al extraer inventario:

- Inventario adquirira su propia base de datos.
- Ventas adquirira su propia base o conservara solo su dominio.
- Pagos adquirira su propia persistencia.
- Los adapters cambiaran de local a gRPC.
- Las reglas de negocio no deberan reescribirse.

### Saga de venta

Una venta no debe resolverse mediante una transaccion SQL compartida entre modulos.

Ejemplo:

1. POS envia la solicitud y la clave de idempotencia.
2. SALES crea una venta pendiente.
3. INVENTORY recibe reserve_stock y verifica disponibilidad.
4. PAYMENTS autoriza o registra el pago.
5. SALES confirma la venta si todas las condiciones se cumplen.
6. Los eventos se publican para caja, clientes, reportes y auditoria.

Si el pago falla:

- INVENTORY debe liberar la reserva.
- SALES debe cancelar o revertir el estado pendiente.

Si el pago se autoriza y la venta falla:

- Debe existir una compensacion para cancelar o revertir la autorizacion.
- El estado debe permitir recuperacion y reconciliacion.

Los procesos que cruzan modulos deben usar Saga, compensaciones y estados persistentes.

### Extraccion futura de microservicios

El procedimiento sera:

1. Extraer el crate del modulo a un ejecutable independiente.
2. Implementar servidor gRPC con Tonic.
3. Migrar datos y dar al modulo su propia base.
4. Sustituir el adaptador local por el adaptador gRPC.
5. Conservar los casos de uso y puertos existentes.
6. Configurar autenticacion mutua, timeouts y reintentos.
7. Mantener idempotencia y circuit breakers.

Al pasar por la red aparecen latencia y fallos que no existen en llamadas locales. Las reglas no deben reescribirse, pero los adaptadores y el manejo de disponibilidad sí deben soportar esos fallos.

## Arquitectura de modulos

Cada modulo debe mantener sus propias reglas de negocio, servicios, validaciones y acceso a datos.

### Separacion de responsabilidad

- Ventas no debe modificar directamente tablas internas de inventario.
- Inventario debe exponer interfaces para solicitar movimientos.
- Cocina debe exponer interfaces para estados y tiempos.
- Compras debe exponer interfaces para recepciones.
- Finanzas debe exponer interfaces para asientos y conciliacion.
- Los modulos deben validar sus propios permisos y datos.
- Los modulos deben publicar eventos de dominio transaccionales.

### Comunicacion entre modulos

- Utilizar interfaces internas definidas.
- Utilizar servicios de aplicacion.
- Utilizar eventos transaccionales.
- Utilizar colas para procesos asincronos.
- Evitar dependencias circulares.
- Evitar acceso directo a tablas que pertenecen a otro modulo.
- Mantener contratos versionados.
- Registrar correlacion entre operaciones y eventos.

### Ejemplo de venta e inventario

1. SALES valida el pedido y coordina el pago mediante el contrato de PAYMENTS.
2. SALES solicita a INVENTORY aplicar el consumo mediante su contrato publico.
3. INVENTORY obtiene de PRODUCTION la receta efectiva y versionada para la
   sucursal mediante su contrato publico.
4. INVENTORY valida sucursal y existencias y escribe en su propio ledger.
5. En el monolito, el caso de uso coordina una transaccion local de PostgreSQL
   que abarca las escrituras necesarias, sin acceso directo a tablas ajenas.
6. Si una validacion falla, la transaccion se revierte; no hay confirmaciones
   manuales entre modulos.
7. Tras el commit, se publica el evento transaccional de venta completada y
   otros modulos reaccionan mediante sus contratos.

Esta separacion evita codigo desorganizado y permite extraer servicios con menor riesgo cuando crezca el sistema.

## Reglas obligatorias de los modulos

| Regla | Cumplimiento |
|---|---|
| Independencia | Cada modulo posee su dominio y sus casos de uso |
| Sin dependencias circulares | Ningun modulo puede crear ciclos de dependencias |
| Contratos publicos | Solo se interactua con interfaces publicas |
| Inversion de dependencias | Los modulos no dependen de implementaciones ajenas |
| Persistencia independiente | Cada modulo posee sus tablas; la atomicidad de cada caso de uso se coordina explicitamente |
| Comunicacion intercambiable | Adaptadores locales y gRPC implementan los mismos puertos |
| Eventos | Los acontecimientos usan contratos versionados |
| Idempotencia | Los comandos importantes no se ejecutan dos veces |
| Seguridad multiempresa | Toda operacion respeta tenant, empresa, sucursal y permisos |
| Pruebas | Cada modulo puede probarse con implementaciones simuladas |

Independencia no significa que una venta pueda confirmarse sin comprobar inventario cuando las existencias son necesarias.

- Ventas conserva sus reglas y casos de uso.
- Ventas consume el puerto publico de inventario.
- El adaptador local o remoto decide la comunicacion.
- Si un servicio externo no esta disponible, se aplica una politica explicita: rechazo controlado, espera, reintento o compensacion.

## Arquitectura tecnológica definitiva

| Componente | Tecnologia |
|---|---|
| Producto | POS SaaS multisucursal |
| Backend inicial | Rust |
| Framework | Axum |
| Organizacion | Cargo Workspace |
| Arquitectura | Hexagonal + DDD |
| Persistencia | PostgreSQL + SQLx |
| Comunicación entre procesos | gRPC + Tonic + Protobuf para solicitudes/respuestas; NATS Core para señales efímeras y NATS JetStream para eventos durables |
| Eventos | Outbox + broker |
| Caché | Redis |
| Frontend | React + TypeScript |
| Despliegue objetivo inicial | Cuatro procesos/servicios independientes: Admin Platform Backend, Admin BFF, Public BFF y Public Backend, coordinados con Docker Compose |

Cada uno de los cuatro procesos contiene sus propios módulos organizados como monolito modular. Los módulos que comparten backend/proceso usan contratos y puertos locales; no se convierten automáticamente en microservicios. Los cuatro procesos se comunican mediante gRPC y NATS Core/JetStream según el tipo de interacción.

- Construir los cuatro backends como binarios/procesos independientes.
- Desplegar Admin Platform Backend, Admin BFF, Public BFF y Public Backend como cuatro servicios de aplicación.
- Usar Tonic/gRPC y Protobuf versionado en las fronteras entre procesos desde el inicio.
- Usar NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda.
- Mantener puertos/traits locales entre módulos que comparten el mismo backend/proceso.
- No declarar esta topología implementada hasta verificar los manifiestos de despliegue.

## Capacidad transversal del AI Manager

La capacidad de IA se integra con los módulos empresariales mediante puertos, contratos, herramientas autorizadas y contexto multi-tenant. No posee schema ni almacenamiento propio aprobado actualmente; cada módulo conserva sus propios datos. Cualquier persistencia centralizada futura requiere un ADR nuevo.

### Agentes especializados

| Agente | Responsabilidad |
|---|---|
| AI Sales | Analizar ventas y demanda |
| AI Inventory | Inventarios y abastecimiento |
| AI Finance | Costos, gastos y rentabilidad |
| AI Operations | Cocina y tiempos de servicio |
| AI Marketing | Clientes y promociones |
| AI Manager | Coordinacion y consultas generales |

Los agentes pueden compartir modelos y herramientas, sin requerir seis modelos independientes.

### Herramientas y datos

- Consultar ventas.
- Consultar costos.
- Consultar gastos.
- Consultar inventarios.
- Consultar mermas.
- Consultar margenes.
- Consultar personal.
- Consultar pedidos.
- Consultar reportes.
- Preparar acciones sujetas a aprobacion.

Toda herramienta debe aplicar permisos, tenant, sucursal y auditoria.

### Ejemplo de analisis

Pregunta:

"¿Por qué la sucursal de Medellín está ganando menos que la de Bogotá?"

Proceso:

1. Consultar ventas.
2. Consultar costos de productos.
3. Consultar gastos.
4. Comparar inventarios y mermas.
5. Analizar margenes.
6. Presentar causas probables.
7. Sugerir acciones.

La respuesta debe indicar:

- Datos utilizados.
- Periodo consultado.
- Sucursales comparadas.
- Nivel de confianza.
- Supuestos realizados.
- Posibles acciones.
- Enlaces o referencias internas a reportes.

### Coordinacion

- AI Manager clasifica la consulta.
- Delega a agentes especializados.
- Combina resultados.
- Evita contradicciones entre modulos.
- Solicita datos adicionales si son insuficientes.
- Presenta respuestas verificables.
- Registra la consulta y los datos utilizados.

### Seguridad

- Consultar solo datos autorizados.
- No acceder a tenants ajenos.
- No ejecutar cambios sensibles sin aprobacion.
- No inventar resultados cuando no existan datos.
- Mantener trazabilidad de las herramientas utilizadas.

## Motor de eventos y automatizaciones

Las automatizaciones deben ejecutarse sobre eventos de dominio desacoplados.

### Modelo de flujo

1. Disparador: define que ocurrio.
2. Condicion: determina si la regla aplica.
3. Accion: ejecuta la operacion o solicitud.
4. Aprobacion: requiere autorizacion cuando sea necesaria.
5. Auditoria: registra decisiones y resultados.

Ejemplo de inventario:

- La carne baja de 10 kg.
- El sistema verifica si existe suficiente inventario en otra bodega.
- Si existe, puede generar una solicitud de transferencia.
- Si no existe, puede generar una solicitud de compra.
- La accion requiere aprobacion segun los limites configurados.
- El flujo y sus decisiones quedan auditados.

### Eventos iniciales

- order.created
- order.paid
- order.cancelled
- inventory.low_stock
- inventory.adjusted
- purchase.requested
- purchase.approved
- cash.opened
- cash.closed
- reservation.created
- employee.clocked_in
- kitchen.order.delayed

Los eventos deben incluir tenant, sucursal, entidad afectada, usuario cuando aplique y identificador de correlacion.

### Automatizaciones comerciales

| Situacion | Automatizacion |
|---|---|
| Inventario bajo | Crear solicitud de compra |
| Producto agotado | Ocultarlo del menu digital |
| Pedido retrasado | Alertar a cocina |
| Caja con diferencias | Solicitar revision |
| Cliente inactivo | Crear campaña de recuperacion |
| Venta anormal | Generar alerta |
| Cierre del dia | Enviar reporte |
| Compra pendiente | Recordar aprobacion |

### Control

- Las reglas criticas deben ser deterministas.
- Las reglas deben validar permisos y limites.
- La IA puede sugerir nuevas automatizaciones.
- Las automatizaciones sugeridas deben pasar revision humana.
- Las ejecuciones deben conservar reintentos e idempotencia.
- Los errores deben registrarse y notificarse.

- Pruebas unitarias, integracion y extremo a extremo.
- Contenedores Docker.
- Respaldo y recuperacion.
- Escalabilidad horizontal.
- POS disponible sin conexion y con sincronizacion posterior.
- Proteccion de datos personales.

## Requisitos de permisos

- Permisos por accion.
- Alcance global.
- Alcance por empresa.
- Alcance por sucursal.
- Alcance por lista o recurso.
- Separacion entre funciones administrativas y operativas.
- Registro de acciones sensibles.

## Criterios de calidad

- Cada sucursal puede operar aunque haya problemas de conectividad.
- Ningun usuario puede acceder a datos fuera de su alcance autorizado.
- Los resultados financieros deben ser reproducibles.
- Los reportes deben permitir filtros por sucursal y periodo.
- Las operaciones críticas deben ser auditables.
- Los servicios deben publicar eventos para automatizaciones.
- Las configuraciones deben ser versionables.

## Criterios de validacion antes del lanzamiento

- Validar aislamiento entre empresas y tenants.
- Validar aislamiento entre sucursales y usuarios.
- Validar venta y sincronizacion offline sin duplicados.
- Validar consumo de inventario por recetas.
- Validar costeo de recetas y margen.
- Validar apertura y cierre de cajas.
- Validar trazabilidad de pagos y devoluciones.
- Validar facturacion fiscal.
- Validar cierre de periodos sin modificar historicos.
- Validar concurrencia de varias terminales.
- Validar restauracion de respaldos.
- Ejecutar pruebas de carga, seguridad, recuperacion y concurrencia.
- Validar cambio seguro de tenant por usuario con varias membresias.
- Validar RLS ante consultas directas y manipulacion de API.

## Criterios de aceptacion por dominio

| Dominio | Criterio verificable |
|---|---|
| PLATFORM | Crear, suspender y reactivar tenants sin exponer datos privados; aplicar límites y módulos contratados |
| PLATFORM | Aplicar limites efectivos y rechazar exceso segun plan y override |
| IDENTITY | Cambiar tenant sin heredar permisos, roles o sucursales incorrectas |
| ORGANIZATION | Rechazar relaciones fiscales o comerciales entre tenants y resolver empresa legal efectiva |
| CATALOG | Verificar que un override local nunca modifica el catalogo maestro |
| SALES | Demostrar estados y reversos separados para pedido, pago y documento fiscal |
| KITCHEN | Repetir el mismo evento y verificar que no duplica comandas |
| INVENTORY | Reconstruir saldos desde movimientos y detectar diferencias |
| PROCUREMENT | Conciliar orden, recepcion y factura de tres vias sin facturas duplicadas |
| BILLING | Reservar numeracion valida y reintentar rechazos sin duplicar documentos |
| FINANCE | Rechazar asientos desbalanceados y auditar reversos |
| WORKFORCE | Auditoria de correcciones y calculo verificable de compensaciones |
| CUSTOMERS | Bloquear comunicaciones inmediatamente despues de revocar consentimiento |
| INTEGRATIONS | Verificar credenciales, reintentos y ausencia de efectos duplicados |
| AUTOMATION | Repetir ejecuciones y verificar idempotencia sin efectos duplicados |
| ANALYTICS | Reproducir metricas con periodo, moneda y alcance definidos |
| AUDIT | Demostrar actor, accion, entidad, tenant y timestamp de operaciones criticas |
| AI | Ejecutar herramientas solo con los mismos permisos, alcance y aprobaciones humanos |
| OFFLINE | Reiniciar, reintentar y resolver conflictos sin duplicar operaciones |
| INFRASTRUCTURE | Verificar integridad total antes de habilitar un tenant migrado |

## Decisiones innegociables

| Numero | Decision | Motivo |
|---:|---|---|
| 1 | Multi-tenant nativo | Separar los clientes |
| 2 | Multiempresa y multimarca | Administrar cadenas complejas |
| 3 | Multi-sucursal | Crecer sin reconstruir |
| 4 | Permisos granulares | Seguridad empresarial |
| 5 | Offline-first | No detener las ventas |
| 6 | Arquitectura modular | Facilitar mantenimiento |
| 7 | API propia | Integrar aplicaciones |
| 8 | Motor de eventos | Automatizar procesos |
| 9 | IA conectada a datos reales | Inteligencia empresarial |
| 10 | Auditoria completa | Trazabilidad y control |

### Practicas obligatorias

- Versionar la API desde el inicio.
- Utilizar migraciones versionadas de base de datos.
- Mantener migraciones reversibles cuando sea posible.
- Ejecutar migraciones en entornos controlados.
- Mantener pruebas unitarias.
- Mantener pruebas de integracion.
- Mantener pruebas extremo a extremo.
- Mantener pruebas de seguridad y aislamiento.
- Mantener entornos separados de desarrollo.
- Mantener entorno de pruebas.
- Mantener entorno de produccion.
- Ejecutar despliegues reproducibles.
- Mantener configuraciones separadas por entorno.
- Mantener secretos fuera del codigo fuente.

## Recomendacion final - Ecosistema integrado

Restaurant OS no debe diseñarse como un conjunto aislado de pantallas. Debe construirse como un ecosistema de modulos relacionados, con reglas de negocio y contratos definidos.

### Flujo transaccional principal

Una venta debe conectar:

1. POS.
2. Pedido.
3. Cocina.
4. Pago.
5. Facturacion.
6. Inventario.
7. Finanzas.
8. Analitica.

Una sola operacion debe actualizar todos los procesos correspondientes y conservar trazabilidad entre ellos.

### Efectos esperados

- El pedido debe quedar identificado.
- La cocina debe recibir la comanda.
- El pago debe registrarse sin duplicados.
- El documento fiscal debe generarse segun corresponde.
- El inventario debe consumir la receta efectiva.
- Las finanzas deben registrar ingresos o asientos correspondientes.
- La analitica debe recibir el evento y actualizar indicadores.
- Los errores deben permitir reconciliacion sin perder informacion.

### Escala funcional

La misma arquitectura debe funcionar para:

- Una cafeteria con una caja.
- Un restaurante independiente.
- Una cadena con multiples sucursales.
- Una empresa con varias marcas.
- Varias empresas legales bajo un mismo propietario.

El sistema no debe requerir implementaciones distintas para clientes pequeños y grandes. Debe activar capacidades segun modalidad, plan y configuracion.

La principal medida de calidad sera que una operacion completa sea consistente, trazable y reproducible en todos los niveles del sistema.