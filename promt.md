Vamos a desarrollar la base de datos de nuestro POS multisucursal por lotes
funcionales. Los numeros siguientes indican orden de trabajo, no IDs de
dominios tecnicos, crates ni migraciones. La propiedad y los limites canonicos
se definen en [requisitos.md](./requisitos.md).
Los encabezados funcionales historicos 1-18 de requisitos.md y los prefijos
`modulo_N` de las migraciones son referencias distintas; ninguno identifica un
dominio. Para nuevas implementaciones, usar los nombres canonicos de la tabla
siguiente.

## Responsabilidad de este archivo

- [requisitos.md](./requisitos.md) es la fuente de verdad para requisitos,
  propietarios de dominio y ubicacion entre Core y verticales.
- [ROADMAP.md](./ROADMAP.md) define fases y entregables.
- Este prompt define el orden de trabajo y las instrucciones para cada lote; no
  debe cambiar propietarios ni mover responsabilidades entre carpetas.

Quiero que trabajemos en el siguiente orden:

1. Empresa y estructura multisucursal.
2. Usuarios, roles y permisos.
3. Catálogo de productos.
4. Inventario y transferencias.
5. Proveedores y compras.
6. Menú, recetas y producción.
7. POS, pedidos y ventas.
8. Pagos.
9. Caja y operaciones de efectivo.
10. Clientes y fidelización.
11. Reportes y auditoría.

Los lotes funcionales pueden involucrar varios dominios, pero no pueden crear
propiedad duplicada:

| Lote funcional | Propietarios tecnicos |
|---|---|
| Empresa y estructura multisucursal | ORGANIZATION |
| Usuarios, roles y permisos | IDENTITY |
| Catálogo de productos | CATALOG |
| Inventario y transferencias | INVENTORY |
| Proveedores y compras | PROCUREMENT |
| Menú, recetas y producción | Restaurant vertical (PRODUCTION y KITCHEN); CATALOG aporta productos base e INVENTORY el ledger |
| POS, pedidos y ventas | SALES |
| Pagos | PAYMENTS |
| Caja y operaciones de efectivo | CASH |
| Clientes y fidelización | CUSTOMERS |
| Reportes y auditoría | REPORTING, ANALYTICS y AUDIT |

`PROCUREMENT` es el nombre canonico para proveedores y compras. No existe un
dominio separado `PURCHASING`. Las recetas y ordenes de produccion pertenecen a
`PRODUCTION`; `CATALOG` conserva los productos comerciales, `INVENTORY` el
inventario fisico y `KITCHEN` las comandas y preparacion de pedidos de clientes.

## Topología backend y BFF

`api-server` aloja el monolito modular de backend y expone gRPC. El BFF es un proceso independiente que consume gRPC y expone HTTP/OpenAPI a los frontends. En Docker Compose son dos servicios de aplicación. Esta separación no convierte los módulos internos en microservicios.

## Responsabilidad de Core y Restaurant vertical

- `crates/core/` contiene los dominios reutilizables: PLATFORM, IDENTITY,
  ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, INVENTORY, PROCUREMENT,
  BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS,
  AUDIT y REPORTING. `tenancy/` es soporte compartido, no un dominio propietario.
- `crates/verticals/restaurant/` contiene `KITCHEN` y `PRODUCTION`, ademas de
  flujos gastronomicos como mesas y reservas, servicio en salon, menu por
  horario, cursos, modificadores y preparacion.
- `KITCHEN` y `PRODUCTION` conservan sus nombres y propiedad logica, aunque sus
  crates se ubiquen bajo el vertical. No crear duplicados en `crates/core/`.
- El vertical referencia productos de CATALOG, pedidos de SALES, recursos
  fisicos de ORGANIZATION y stock/movimientos de INVENTORY mediante contratos;
  no vuelve a crear ni escribir las entidades propietarias.
- El código de los módulos se ubica según estas reglas. Las migraciones históricas permanecen en su ubicación actual; las nuevas migraciones se guardan en `backend/<backend>/modules/<modulo>/migrations/`. Cada módulo tiene su propio schema PostgreSQL, rol de migración y tabla de historial SQLx schema-qualified (por ejemplo, `identity._sqlx_migrations`). Nunca se comparte la tabla de historial entre módulos; las versiones son independientes por historial.

**Instrucciones importantes:**

- Antes de crear tablas, revisa la arquitectura completa para evitar duplicaciones.
- Cada funcionalidad debe pertenecer a un único módulo principal.
- Antes de implementar un lote, identifica su dominio propietario y su ruta
  `crates/core/` o `crates/verticals/restaurant/` usando `requisitos.md`.
- Las claves foráneas y relaciones SQL solo se permiten dentro del límite de propiedad del mismo módulo. No crear FKs, joins, vistas ni consultas directas entre schemas propietarios distintos; las referencias entre módulos usan IDs estables y contratos públicos.
- Todo debe contemplar múltiples sucursales.
- Las existencias, ventas, compras y movimientos deben quedar identificados por sucursal.
- Diseña una estructura escalable y preparada para futuras funcionalidades.
- Incluye claves primarias, claves foráneas, índices, restricciones y campos de auditoría.
- No dupliques tablas ni funcionalidades que ya existan en otros módulos.
- Entrega el SQL completo de cada módulo, sus relaciones y las instrucciones para ejecutarlo.
- Revisa la compatibilidad con los módulos anteriores antes de avanzar.

**Vamos a empezar únicamente por el MÓDULO 1: EMPRESA Y ESTRUCTURA MULTISUCURSAL.**

No avances al siguiente módulo hasta que hayamos revisado y aprobado el SQL del actual.

8. Las reglas que le impondría a tu agente
Estas serían obligatorias desde el primer día:
Regla	Qué debe cumplir
Independencia	Cada módulo posee su dominio y sus casos de uso.
Sin dependencias circulares	Ningún módulo puede generar ciclos de dependencias.
Contratos públicos	Solo se puede interactuar con las interfaces públicas.
Inversión de dependencias	Los módulos nunca dependen de implementaciones ajenas.
Persistencia independiente	Cada módulo administra sus tablas, schema PostgreSQL, rol, migraciones, historial SQLx y transacciones.
Comunicación intercambiable	Los módulos internos usan puertos locales; `api-server` y el BFF se comunican por gRPC desde el inicio.
Eventos	Los acontecimientos se publican mediante contratos versionados.
Idempotencia	Los comandos importantes no deben ejecutarse dos veces accidentalmente.
Seguridad multiempresa	Toda operación debe respetar el contexto y los permisos de empresa y sucursal.
Pruebas	Cada módulo debe poder probarse con implementaciones simuladas de sus dependencias.

Un matiz fundamental: independencia no significa que ventas pueda confirmar una venta sin inventario cuando necesita comprobar existencias. Significa que ventas puede desarrollarse, probarse y mantener sus propias operaciones sin conocer la implementación de inventario. Si un servicio externo no está disponible, cada proceso deberá tener una política explícita de recuperación o rechazo.

## Arquitectura normativa

Antes de cualquier cambio, leer [Estándar general](docs/architecture/engineering-standard.md), [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md), [Reglas de implementación](docs/engineering/implementation-rules.md) y [ADRs aceptados](docs/adr/README.md). La jerarquía y precedencia de esos documentos es obligatoria.
