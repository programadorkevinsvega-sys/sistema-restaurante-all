# Diseño de crates y dependencias

**Estado:** propuesta técnica para revisión. La decisión normativa permanece pendiente en [ADR-0009](../adr/0009-crate-boundaries-and-dependencies.md).  
**Base arquitectónica:** ADR-0001 a ADR-0008, en especial ADR-0007 y ADR-0008.

Este documento concreta el layout y las reglas de dependencias que deberán aplicarse al crear el workspace Rust. No declara implementados los crates, los binarios ni las herramientas.

## 1. Resultado de diseño

La solución se compone de cuatro binarios independientes, módulos de negocio con implementación privada y contratos públicos separados, y crates técnicos neutrales. Los crates de transporte se mantienen separados de los contratos de aplicación y del dominio.

- Cada módulo es una unidad de ownership con un crate de implementación.
- Cada uno de los 20 módulos tiene desde el inicio un crate público `<modulo>-contracts`, aunque su API inicial sea pequeña.
- Cada binario tiene un único composition root.
- Un consumidor nunca depende del crate de implementación de otro módulo.
- Los BFF dependen de clientes de transporte, no de implementaciones de negocio.
- Los adaptadores PostgreSQL permanecen dentro del módulo dueño de las tablas.

## 2. Layout propuesto

```text
Cargo.toml                      # único Cargo workspace raíz
Cargo.lock                      # lockfile compartido por los cuatro binarios

apps/
  admin-platform-backend/       # paquete/binario independiente
  admin-bff/                    # paquete/binario independiente
  public-bff/                   # paquete/binario independiente
  public-backend/               # paquete/binario independiente

backend/
  admin-platform-backend/
    modules/
      platform/
        Cargo.toml              # crate de implementación PLATFORM
        sqlx.toml               # configuración SQLx del módulo
        src/
          lib.rs
          domain/
          application/
          adapters/
          infrastructure/
        contracts/
          Cargo.toml            # crate platform-contracts
          src/
            lib.rs
        migrations/             # migraciones e historial exclusivo PLATFORM
  public-backend/
    modules/
      identity/
        Cargo.toml              # crate de implementación IDENTITY
        sqlx.toml               # configuración SQLx del módulo
        src/
          lib.rs
          domain/
          application/
          adapters/
          infrastructure/
        contracts/
          Cargo.toml            # crate identity-contracts
          src/
            lib.rs
        migrations/             # migraciones e historial exclusivo IDENTITY
      organization/
        Cargo.toml
        sqlx.toml
        src/{lib.rs,domain/,application/,adapters/,infrastructure/}
        contracts/{Cargo.toml,src/lib.rs}
        migrations/
      catalog/
        contracts/
        implementation/
        migrations/
      sales/
        contracts/
        implementation/
        migrations/
      payments/
        contracts/
        implementation/
        migrations/
      cash/
        contracts/
        implementation/
        migrations/
      kitchen/
        contracts/
        implementation/
        migrations/
      inventory/
        contracts/
        implementation/
        migrations/
      procurement/
        contracts/
        implementation/
        migrations/
      production/
        contracts/
        implementation/
        migrations/
      billing/
        contracts/
        implementation/
        migrations/
      finance/
        contracts/
        implementation/
        migrations/
      workforce/
        contracts/
        implementation/
        migrations/
      customers/
        contracts/
        implementation/
        migrations/
      integrations/
        contracts/
        implementation/
        migrations/
      automation/
        contracts/
        implementation/
        migrations/
      analytics/
        contracts/
        implementation/
        migrations/
      audit/
        contracts/
        implementation/
        migrations/
      reporting/
        contracts/
        implementation/
        migrations/

  admin-bff/                    # módulos técnicos de transporte/composición
  public-bff/                    # módulos técnicos de transporte/composición

contracts/
  protobuf/
    admin-platform-backend/platform/v1/*.proto
    public-backend/identity/v1/*.proto
    public-backend/<module>/v1/*.proto

crates/
  shared/                        # capacidades técnicas neutrales
  contracts/
    events/                      # esquemas de eventos versionados por módulo propietario
  adapters/
    local/                       # llamadas entre módulos que comparten proceso
    grpc/                        # infraestructura genérica gRPC/Tonic
    messaging/                   # NATS Core y JetStream
```

El árbol es un layout objetivo, no una instrucción para crear carpetas ahora. Existe un único workspace Cargo en la raíz, con cuatro paquetes binarios independientes y `Cargo.lock` compartido. La ruta canónica de migraciones sigue siendo `backend/<backend>/modules/<modulo>/migrations/` (ADR-0001). El ejemplo muestra los 20 módulos sin cambiar sus responsabilidades ni su propiedad.

## 3. Inventario por proceso

| Binario | Crates de implementación propios | Dependencias de transporte permitidas |
|---|---|---|
| Admin Platform Backend | `platform` | Cliente gRPC de `identity` en Public Backend cuando lo requiera; servidor gRPC de PLATFORM |
| Public Backend | `identity`, `organization`, `catalog`, `sales`, `payments`, `cash`, `kitchen`, `inventory`, `procurement`, `production`, `billing`, `finance`, `workforce`, `customers`, `integrations`, `automation`, `analytics`, `audit`, `reporting` | Servidores gRPC para los contratos publicados por este proceso; clientes gRPC externos solo cuando exista caso de uso aprobado |
| Admin BFF | Ninguno de negocio | Clientes gRPC de PLATFORM y de módulos públicos que alimenten sus endpoints; HTTP/OpenAPI |
| Public BFF | Ninguno de negocio | Clientes gRPC de módulos públicos que alimenten sus endpoints; HTTP/OpenAPI |

Admin BFF puede consultar ambos backends; Public BFF consume Public Backend. Ningún BFF abre conexiones PostgreSQL a schemas de negocio. Admin Platform Backend no incorpora `identity` como implementación: consume el contrato remoto del único propietario IDENTITY en Public Backend.

## 4. Anatomía de un módulo

Cada módulo tiene desde el inicio un crate de implementación privado y un crate público de contratos, aunque inicialmente el contrato tenga pocas operaciones.

```text
modules/<module>/
  Cargo.toml                     # crate de implementación privado
  sqlx.toml                      # configuración SQLx exclusiva del módulo
  src/
    lib.rs
    domain/
    application/
    adapters/
    infrastructure/
  contracts/
    Cargo.toml                   # crate público <module>-contracts
    src/
      lib.rs
  migrations/                    # migraciones e historial SQLx exclusivos
```

Las capas pueden organizarse en módulos Rust dentro del crate de implementación; no se convierten automáticamente en crates separados. Solo se separa una capa en otro crate si hay una razón concreta de aislamiento, compilación o reutilización y se conserva la regla de no exponer internos. El crate de contratos no contiene SQLx, modelos de persistencia, entidades de dominio ni dependencias de framework.

## 5. Reglas de dependencias

### 5.1 Dentro de un módulo

- `domain` no depende de capas externas ni de otros módulos.
- `application` depende de `domain` y declara puertos.
- Adaptadores dependen de `application`, `domain` y contratos externos estrictamente necesarios.
- La composición del binario conecta los adaptadores.
- Los contratos públicos son independientes de la implementación.

### 5.2 Entre módulos del mismo backend

- El consumidor depende exclusivamente de `<provider>-contracts`.
- Las consultas y comandos síncronos se invocan mediante traits/puertos locales.
- Los eventos se consumen mediante contratos versionados; los durables usan Outbox/Inbox e idempotencia.
- No se permite importar implementación, repositorios, modelos SQL ni migraciones del proveedor.
- No se accede directamente a tablas de otro módulo.

### 5.3 Entre procesos

- gRPC + Protobuf versionado para request/response síncronos.
- NATS Core para señales efímeras.
- NATS JetStream para eventos/mensajes durables.
- Los crates de transporte generados/adaptadores traducen entre Protobuf y DTO públicos.
- Nunca se importa un crate de implementación de otro proceso.
- No se reemplaza una frontera gRPC por acceso a base de datos compartida.

### 5.4 BFF

Los BFF contienen composición de endpoints, autenticación/autorización de borde según corresponda, validación de entrada de transporte, agregación de respuestas y traducción HTTP. La autorización efectiva y las reglas de negocio permanecen en los módulos propietarios. No contienen entidades de negocio, reglas duplicadas, repositorios SQL de negocio ni migraciones de módulos.

## 6. Catálogo de crates compartidos

| Ubicación | Contenido permitido | Contenido prohibido |
|---|---|---|
| `crates/shared` | Configuración base, contexto W3C, observabilidad, utilidades técnicas pequeñas y neutrales | Entidades, reglas, enums de negocio, repositorios, tablas o DTO específicos de dominios |
| `crates/contracts/proto` | Fuentes Protobuf versionadas por proceso/módulo | Código generado editado manualmente o contratos que mezclen dominios |
| `crates/contracts/events` | Esquemas de eventos versionados con owner explícito | Eventos sin propietario o modelos internos de persistencia |
| `crates/adapters/grpc` | Infraestructura genérica cliente/servidor, interceptores, propagación de contexto | Reglas de negocio o mapeos específicos de dominio |
| `crates/adapters/messaging` | Conexión NATS Core/JetStream, publicación/consumo genérico, manejo técnico de ACK | Tablas Outbox/Inbox ajenas, políticas de negocio o definición de ownership |
| `crates/adapters/local` | Adaptador local obligatorio desde el día uno para implementar los puertos públicos entre módulos que comparten proceso; usa los mismos puertos que implementa el adaptador gRPC y puede sustituirse al extraer un módulo | Un crate por pareja de módulos, un bus global que oculte dependencias o acceso a internos/tablas ajenas |

La persistencia SQLx es específica de cada módulo y permanece en su implementación. La tabla Outbox/Inbox, cuando exista, es propiedad del módulo/consumidor correspondiente; el adaptador de mensajería no la convierte en tabla compartida.

## 7. Mapa de contratos Protobuf

Los archivos fuente Protobuf se ubican en una única raíz `contracts/protobuf/`, por proceso propietario y módulo:

- `contracts/protobuf/admin-platform-backend/platform/v1/`
- `contracts/protobuf/public-backend/identity/v1/`
- `contracts/protobuf/public-backend/<module>/v1/`

Los tipos generados se publican en crates de transporte separados por servicio/módulo, por ejemplo `platform-proto` e `identity-proto`. Los nombres finales de paquetes se fijarán al crear el workspace. No se crea un crate único que exporte implementaciones de todos los módulos.

OpenAPI se mantiene en las superficies HTTP de cada BFF. Los artefactos generados HTTP tampoco se mezclan con los DTO de dominio.

## 8. Qué dependencias de dominio no se fijan todavía

No se declara un grafo completo entre IDENTITY, ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, KITCHEN, INVENTORY, PROCUREMENT, PRODUCTION, BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS, AUDIT y REPORTING. Deducirlo solo por nombres o por el flujo general del producto sería inventar relaciones.

Antes de añadir cada dependencia se documentará: módulo consumidor, módulo proveedor, capacidad/puerto, caso de uso, dirección, modo de interacción (local/gRPC/evento), datos de contexto y motivo. Las dependencias de módulos se limitan a los contratos explícitos resultantes.

## 9. Versiones externas y workspace

No fijar versiones de Tokio, SQLx, Tonic, Prost, NATS, OpenTelemetry ni generadores en este diseño. Primero se debe inventariar el toolchain, establecer MSRV y verificar compatibilidad. Al implementar:

- usar un único workspace Cargo en la raíz con cuatro paquetes binarios independientes;
- centralizar versiones compatibles en el workspace;
- versionar el único `Cargo.lock` raíz;
- fijar generadores y herramientas de CI;
- controlar features y duplicados;
- validar licencias, advisories, MSRV y builds reproducibles.

## 10. Orden de implementación posterior

1. Confirmar/aceptar ADR-0009 y el layout.
2. Definir toolchain, workspace y convenciones de nombres.
3. Crear los cuatro paquetes binarios independientes dentro del workspace raíz y los crates técnicos definidos, incluido `crates/adapters/local`.
4. Crear primero los contratos públicos y la implementación del primer módulo vertical seleccionado, sin inventar dependencias.
5. Integrar módulos del mismo backend por puertos locales.
6. Añadir/compilar los contratos Protobuf desde `contracts/protobuf/` y los adaptadores gRPC para las fronteras entre procesos; el adaptador local permanece para llamadas dentro del mismo proceso.
7. Añadir adaptadores NATS cuando existan eventos que lo requieran.
8. Activar controles de CI de fronteras de crates, generación y compatibilidad.

El orden funcional de dominios continúa siendo el de `ROADMAP.md` y `requisitos.md`; este diseño no lo reemplaza.

## 11. Límites de este cambio

Esta propuesta no crea crates, `Cargo.toml`, `Cargo.lock`, dependencias, código Rust, archivos `.proto`, esquemas de eventos, workflows ni infraestructura. No modifica SQL ni migraciones, no ejecuta migraciones y no cambia la propiedad ni las responsabilidades de ningún módulo.
