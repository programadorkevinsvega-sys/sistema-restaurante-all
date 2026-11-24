# Diseño de crates y dependencias

**Estado:** propuesta técnica para revisión. La decisión normativa permanece pendiente en [ADR-0009](../adr/0009-crate-boundaries-and-dependencies.md).  
**Base arquitectónica:** ADR-0001 a ADR-0008, en especial ADR-0007 y ADR-0008.

Este documento concreta el layout y las reglas de dependencias que deberán aplicarse al crear el workspace Rust. No declara implementados los crates, los binarios ni las herramientas.

## 1. Resultado de diseño

La solución se compone de cuatro binarios independientes, módulos de negocio con implementación privada y contratos públicos separados, y crates técnicos neutrales. Los crates de transporte se mantienen separados de los contratos de aplicación y del dominio.

- Cada módulo es una unidad de ownership con un crate de implementación.
- Cada módulo expone un crate `<modulo>-contracts` cuando otros módulos/procesos necesitan consumir su API.
- Cada binario tiene un único composition root.
- Un consumidor nunca depende del crate de implementación de otro módulo.
- Los BFF dependen de clientes de transporte, no de implementaciones de negocio.
- Los adaptadores PostgreSQL permanecen dentro del módulo dueño de las tablas.

## 2. Layout propuesto

```text
apps/
  admin-platform-backend/       # binario Admin Platform Backend
  admin-bff/                    # binario Admin BFF
  public-bff/                   # binario Public BFF
  public-backend/               # binario Public Backend

backend/
  admin-platform-backend/
    modules/
      platform/
        contracts/              # platform-contracts
        implementation/         # platform
        migrations/             # migraciones e historial exclusivo PLATFORM
  public-backend/
    modules/
      identity/
        contracts/              # identity-contracts
        implementation/         # identity
        migrations/             # migraciones e historial exclusivo IDENTITY
      organization/
        contracts/
        implementation/
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

crates/
  shared/                        # capacidades técnicas neutrales
  contracts/
    proto/
      admin-platform-backend/platform/v1/*.proto
      public-backend/identity/v1/*.proto
      public-backend/<module>/v1/*.proto
    events/
      <owner-module>/v1/*         # esquemas versionados, si se mantienen como archivos
  adapters/
    grpc/                        # infraestructura genérica gRPC/Tonic
    messaging/                   # NATS Core y JetStream
    local/                       # utilidades genéricas locales, si son necesarias
```

El árbol es un layout objetivo, no una instrucción para crear todas las carpetas ahora. La ruta canónica de migraciones sigue siendo `backend/<backend>/modules/<modulo>/migrations/` (ADR-0001). El ejemplo muestra los 20 módulos sin cambiar sus responsabilidades ni su propiedad.

## 3. Inventario por proceso

| Binario | Crates de implementación propios | Dependencias de transporte permitidas |
|---|---|---|
| Admin Platform Backend | `platform` | Cliente gRPC de `identity` en Public Backend cuando lo requiera; servidor gRPC de PLATFORM |
| Public Backend | `identity`, `organization`, `catalog`, `sales`, `payments`, `cash`, `kitchen`, `inventory`, `procurement`, `production`, `billing`, `finance`, `workforce`, `customers`, `integrations`, `automation`, `analytics`, `audit`, `reporting` | Servidores gRPC para los contratos publicados por este proceso; clientes gRPC externos solo cuando exista caso de uso aprobado |
| Admin BFF | Ninguno de negocio | Clientes gRPC de PLATFORM y de módulos públicos que alimenten sus endpoints; HTTP/OpenAPI |
| Public BFF | Ninguno de negocio | Clientes gRPC de módulos públicos que alimenten sus endpoints; HTTP/OpenAPI |

Admin BFF puede consultar ambos backends; Public BFF consume Public Backend. Ningún BFF abre conexiones PostgreSQL a schemas de negocio. Admin Platform Backend no incorpora `identity` como implementación: consume el contrato remoto del único propietario IDENTITY en Public Backend.

## 4. Anatomía de un módulo

Cada módulo tiene un crate de implementación privado y un crate público de contratos cuando exista un consumidor real.

```text
modules/<module>/
  contracts/                     # <module>-contracts
    src/
      lib.rs
      ports/                     # traits públicos
      dto/                       # requests/responses públicos
      events/                    # eventos publicados y sus tipos
      errors.rs                  # errores estables de contrato
  implementation/                # <module>
    src/
      domain/
      application/
        ports/
        use_cases/
      adapters/
        inbound/
        outbound/
      infrastructure/
        persistence/
        messaging/
      lib.rs
  migrations/
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
| `crates/adapters/local` | Utilidades genéricas para wiring/invocación local si se demuestra necesidad | Un crate por cada pareja de módulos o un bus local global que oculte dependencias |

La persistencia SQLx es específica de cada módulo y permanece en su implementación. La tabla Outbox/Inbox, cuando exista, es propiedad del módulo/consumidor correspondiente; el adaptador de mensajería no la convierte en tabla compartida.

## 7. Mapa de contratos Protobuf

Los archivos fuente se ubican por proceso propietario y módulo:

- `crates/contracts/proto/admin-platform-backend/platform/v1/`
- `crates/contracts/proto/public-backend/identity/v1/`
- `crates/contracts/proto/public-backend/<module>/v1/`

Los tipos generados se publican en crates de transporte separados por servicio/módulo, por ejemplo `platform-proto` e `identity-proto`. Los nombres finales de paquetes se fijarán al crear el workspace. No se crea un crate único que exporte implementaciones de todos los módulos.

OpenAPI se mantiene en las superficies HTTP de cada BFF. Los artefactos generados HTTP tampoco se mezclan con los DTO de dominio.

## 8. Qué dependencias de dominio no se fijan todavía

No se declara un grafo completo entre IDENTITY, ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, KITCHEN, INVENTORY, PROCUREMENT, PRODUCTION, BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS, AUDIT y REPORTING. Deducirlo solo por nombres o por el flujo general del producto sería inventar relaciones.

Antes de añadir cada dependencia se documentará: módulo consumidor, módulo proveedor, capacidad/puerto, caso de uso, dirección, modo de interacción (local/gRPC/evento), datos de contexto y motivo. Las dependencias de módulos se limitan a los contratos explícitos resultantes.

## 9. Versiones externas y workspace

No fijar versiones de Tokio, SQLx, Tonic, Prost, NATS, OpenTelemetry ni generadores en este diseño. Primero se debe inventariar el toolchain, establecer MSRV y verificar compatibilidad. Al implementar:

- usar workspace Cargo con versiones centralizadas;
- versionar `Cargo.lock` para binarios;
- fijar generadores y herramientas de CI;
- controlar features y duplicados;
- validar licencias, advisories, MSRV y builds reproducibles.

## 10. Orden de implementación posterior

1. Confirmar/aceptar ADR-0009 y el layout.
2. Definir toolchain, workspace y convenciones de nombres.
3. Crear crates de composición de los cuatro procesos y crates técnicos mínimos.
4. Crear primero los contratos públicos y la implementación del primer módulo vertical seleccionado, sin inventar dependencias.
5. Integrar módulos del mismo backend por puertos locales.
6. Añadir contratos Protobuf y adaptadores gRPC para las fronteras entre procesos.
7. Añadir adaptadores NATS cuando existan eventos que lo requieran.
8. Activar controles de CI de fronteras de crates, generación y compatibilidad.

El orden funcional de dominios continúa siendo el de `ROADMAP.md` y `requisitos.md`; este diseño no lo reemplaza.

## 11. Límites de este cambio

Esta propuesta no crea crates, `Cargo.toml`, `Cargo.lock`, dependencias, código Rust, archivos `.proto`, esquemas de eventos, workflows ni infraestructura. No modifica SQL ni migraciones, no ejecuta migraciones y no cambia la propiedad ni las responsabilidades de ningún módulo.
