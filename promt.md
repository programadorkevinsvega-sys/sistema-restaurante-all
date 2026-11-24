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
  propietarios de dominio y ubicación física de los módulos.
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

## Topología de los cuatro backends

Restaurant OS se compone de cuatro procesos/binarios independientes, cada uno con sus propios módulos:

1. Admin Platform Backend.
2. Admin BFF.
3. Public BFF.
4. Public Backend.

No existe un único `api-server` que aloje todos los módulos ni un único BFF compartido. Cada backend conserva su composición modular y sus responsabilidades. Los BFF son procesos independientes, no capas integradas dentro de los backends de plataforma/público.

Entre procesos se utiliza gRPC para solicitudes y respuestas; NATS Core para señales efímeras; y NATS JetStream para eventos durables, según corresponda. Dentro de cada backend, los módulos que comparten proceso utilizan los contratos públicos y puertos/traits locales descritos en el estándar modular; los eventos durables usan Outbox/Inbox. `FOR UPDATE SKIP LOCKED` reclama filas de trabajo del Outbox cuando corresponde, no sustituye los contratos de comunicación.

## Responsabilidad y ubicación de módulos

- Los cuatro procesos son independientes. PLATFORM vive en
  `backend/admin-platform-backend/modules/platform/`; todos los demás módulos
  canónicos viven en `backend/public-backend/modules/<modulo>/`.
- Admin BFF y Public BFF no poseen módulos de negocio, schemas ni tablas de
  negocio; sus módulos internos se limitan a transporte y composición.
- Cada módulo conserva su responsabilidad, contratos, schema, rol, migraciones
  e historial SQLx exclusivos.
- `crates/` se reserva para bibliotecas técnicas neutrales, contratos
  versionados y adaptadores local/gRPC/messaging.
- Las responsabilidades de CATALOG, KITCHEN, PRODUCTION y los demás dominios
  siguen siendo las definidas en `requisitos.md`; esta organización física no
  las fusiona ni las reasigna.
- No crear duplicados ni cambiar la asignación aprobada en
  [ADR-0008](docs/adr/0008-module-ownership-across-four-processes.md) sin un
  nuevo ADR aceptado.

## Arquitectura normativa

Antes de cualquier cambio, leer [Estándar general](docs/architecture/engineering-standard.md), [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md), [Reglas de implementación](docs/engineering/implementation-rules.md) y [ADRs aceptados](docs/adr/README.md). La jerarquía y precedencia de esos documentos es obligatoria.
