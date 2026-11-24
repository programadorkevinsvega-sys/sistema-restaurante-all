# ADR-0009: Límites de crates y dirección de dependencias

- Estado: **Proposed**
- Propuesto: 2026-11-24
- Complementa: ADR-0001, ADR-0002, ADR-0003, ADR-0005, ADR-0007 y ADR-0008.
- Aprobación: pendiente del propietario del producto.

## Contexto

ADR-0007 y ADR-0008 fijan cuatro procesos independientes y la propiedad de los módulos. El estándar exige módulos aislados, contratos públicos, composición en el borde del proceso y bibliotecas compartidas neutrales. Antes de crear manifiestos Rust es necesario concretar qué paquetes/crates representan esas responsabilidades y qué dependencias pueden cruzar cada frontera.

El repositorio todavía no tiene un workspace Cargo implementado. Esta propuesta define límites y direcciones, no versiones concretas de crates externos ni un grafo de dependencias entre todos los dominios.

## Decisión propuesta

### 1. Unidad de módulo

Cada módulo de negocio seguirá siendo una unidad de ownership y una implementación crate privada del backend propietario. Cuando otros módulos o procesos deban consumir su API, tendrá además un crate público `<modulo>-contracts` separado de su implementación:

- `<modulo>-contracts`: traits/puertos públicos, DTO de solicitud/respuesta, tipos de eventos y errores de contrato. No contiene entidades, repositorios, SQL ni reglas de negocio.
- `<modulo>` (implementación): domain, application, puertos internos, adaptadores y persistencia del módulo. No expone sus internos.
- Los dos crates pertenecen al mismo módulo y no dividen su ownership.

La separación del crate de contratos permite que un consumidor compile contra la API sin incorporar ni poder importar la implementación del propietario. Si un módulo todavía no tiene consumidores externos, el crate de contratos puede ser mínimo; no se crea una abstracción vacía por anticipado.

### 2. Layout físico objetivo

```text
apps/
  admin-platform-backend/       # binario/composición de PLATFORM
  admin-bff/                    # binario/composición HTTP administrativa
  public-bff/                   # binario/composición HTTP pública/operativa
  public-backend/               # binario/composición de módulos públicos

backend/
  admin-platform-backend/
    modules/platform/
      contracts/                 # crate platform-contracts
      implementation/            # crate platform
      migrations/                # propiedad exclusiva de PLATFORM
  public-backend/
    modules/<module>/
      contracts/                 # crate <module>-contracts
      implementation/            # crate <module>
      migrations/                # propiedad exclusiva del módulo
  admin-bff/                     # solo composición/transporte, no dominios
  public-bff/                    # solo composición/transporte, no dominios

crates/
  shared/                        # utilidades técnicas neutrales y pequeñas
  contracts/
    proto/
      <backend>/<module>/v1/*.proto
    events/
      <owner-module>/v1/*         # esquemas de eventos, si se versionan aquí
  adapters/
    grpc/                        # infraestructura genérica gRPC/Tonic
    messaging/                   # infraestructura NATS Core/JetStream
    local/                       # utilidades genéricas de invocación local, si hacen falta
```

Las rutas `contracts/` e `implementation/` son una propuesta de layout para el contenido de cada módulo; no crean todavía directorios ni manifiestos. La ruta de migraciones sigue siendo la canónica fijada por ADR-0001: `backend/<backend>/modules/<modulo>/migrations/`. En el layout futuro debe quedar como hermana de `contracts/` e `implementation/`, no dentro de un crate técnico compartido.

### 3. Crates de proceso y composición

Cada uno de los cuatro binarios tiene un único crate de entrada y composición bajo `apps/<proceso>/`. Ese crate:

- construye configuración, logging, telemetría, pools y clientes;
- instancia implementaciones propietarias del proceso;
- conecta puertos con adaptadores;
- registra servidores gRPC y/o rutas HTTP que correspondan;
- administra el ciclo de vida del proceso.

La composición no se reparte entre módulos y no se importa desde otro proceso. Un proceso no depende del crate de implementación de otro proceso.

### 4. Matriz de dependencias entre procesos

| Proceso/binario | Puede incorporar | No puede incorporar |
|---|---|---|
| Admin Platform Backend | implementación PLATFORM; contratos de PLATFORM; cliente Protobuf/gRPC de IDENTITY cuando lo requiera; crates técnicos neutrales | implementaciones de módulos de Public Backend; tablas o migraciones ajenas |
| Public Backend | implementaciones de los 19 módulos públicos; contratos de esos módulos; servidores Protobuf/gRPC; adaptadores técnicos | implementación PLATFORM; crates de los BFF |
| Admin BFF | clientes Protobuf/gRPC de PLATFORM y de los módulos de Public Backend que expongan sus endpoints; OpenAPI/HTTP y crates técnicos | crates de implementación de módulos; acceso directo a PostgreSQL de negocio |
| Public BFF | clientes Protobuf/gRPC de módulos de Public Backend que expongan sus endpoints; OpenAPI/HTTP y crates técnicos | crates de implementación de módulos; acceso directo a PostgreSQL de negocio |

La tabla indica límites permitidos por proceso, no obliga a que cada BFF consuma todos los contratos. Los endpoints concretos determinan qué clientes necesita cada BFF. Admin BFF puede hablar con ambos backends; Public BFF habla con Public Backend. Admin Platform Backend consume IDENTITY mediante el contrato de proceso de Public Backend cuando el caso de uso lo requiera. Ninguna de estas rutas autoriza acceso directo a datos ajenos.

### 5. Dirección de dependencias dentro de un módulo

```text
domain
  ↑ application
  ↑ adapters (inbound/outbound)
  ↑ module composition (solo en el binario propietario)
```

- `domain` no depende de frameworks, PostgreSQL, NATS, gRPC, HTTP ni otros módulos.
- `application` depende del dominio y define/consume puertos; no conoce adaptadores concretos.
- Los adaptadores implementan puertos y traducen protocolos/almacenamiento.
- La composición del proceso conecta implementaciones concretas.
- El crate `<modulo>-contracts` es independiente de las capas internas y solo contiene la API pública estable.
- La implementación de un módulo puede depender de los crates `*-contracts` de otros módulos permitidos; nunca de sus crates de implementación.

Las llamadas síncronas entre módulos del mismo backend se resuelven mediante puertos/traits locales y DTO del contrato. Las llamadas entre procesos usan clientes/servidores gRPC generados desde Protobuf versionado, según ADR-0005 y ADR-0007. No se debe envolver una llamada local en gRPC solo para simular una frontera de proceso.

### 6. Contratos de transporte y generación

- Protobuf fuente de verdad de gRPC; los archivos `.proto` se mantienen versionados por backend propietario y módulo.
- Los tipos/stubs generados se aíslan en crates de transporte `*-proto`/cliente-servidor por servicio o módulo; no se mezclan con entidades ni DTO internos.
- Los adaptadores gRPC convierten entre Protobuf y DTO del crate `*-contracts`.
- OpenAPI es fuente de verdad HTTP de cada BFF; los tipos/clientes generados se aíslan de la lógica de negocio.
- El código generado no se edita manualmente.
- Los esquemas de eventos se versionan por módulo propietario. El módulo productor conserva la autoridad sobre el evento; NATS Core y JetStream son transportes, no propietarios del contrato.
- Contexto W3C, tenant, actor e idempotency key se propagan conforme a ADR-0004 y ADR-0003.

No se propone un único crate gigante que mezcle todos los contratos de negocio. Los crates de Protobuf se mantienen por servicio/módulo para reducir acoplamiento y permitir evolución independiente.

### 7. Crates técnicos compartidos

`crates/shared` solo puede alojar capacidades técnicas genéricas sin semántica de dominio (por ejemplo, configuración base, propagación de contexto, utilidades de observabilidad o tipos realmente transversales y estables). Antes de agregar una utilidad se debe comprobar que no pertenece naturalmente a un módulo.

`crates/adapters` puede alojar infraestructura de transporte reutilizable (gRPC/Tonic, NATS Core/JetStream y mecanismos locales genéricos). La persistencia SQLx y los repositorios que conocen tablas/schema permanecen dentro del módulo propietario. Un crate de adaptador no puede consultar varios schemas ni convertirse en repositorio compartido de negocio.

No se crea un crate común para entidades, enums, DTO o reglas de negocio compartidas. Si dos módulos necesitan un concepto, se acuerda un contrato explícito o cada uno mantiene su modelo/proyección.

### 8. Dependencias externas y versiones

La selección de versiones de Rust, SQLx, Tonic, Prost, NATS, Tokio, serialización, OpenTelemetry y generadores queda pendiente de inventario técnico y compatibilidad. Esta propuesta no fija versiones ni añade dependencias. Cuando se implemente el workspace:

- centralizar versiones compatibles en el workspace Cargo;
- fijar `Cargo.lock` para binarios;
- evitar dependencias duplicadas con versiones incompatibles;
- justificar cada dependencia y limitar features;
- validar MSRV, licencias, advisories y reproducibilidad en CI.

### 9. Grafo entre módulos de negocio

Esta propuesta no inventa dependencias entre los 19 módulos de Public Backend. La propiedad física no implica que todos dependan entre sí. Antes de implementar cada integración se debe registrar consumidor, proveedor, capacidad/puerto, dirección, modalidad (local, gRPC o evento), contexto requerido y motivo funcional. Solo se añade una dependencia a `Cargo.toml` cuando existe un caso de uso y contrato aprobado.

## Consecuencias

- Los módulos mantienen implementación y datos bajo su backend propietario.
- Los consumidores dependen de contratos, nunca de implementaciones ajenas.
- Los BFF y binarios quedan como composition roots separados.
- La generación de transporte no contamina el dominio.
- Las bibliotecas compartidas no absorben ownership de negocio.
- Se mantiene la independencia de schema, rol, migraciones e historial SQLx por módulo.

## Alternativas consideradas

- Un crate de implementación por proceso con todos los dominios dentro: rechazado porque no impone fronteras de compilación entre módulos.
- Un crate compartido con todos los DTO, entidades y servicios: rechazado porque crea un dominio común artificial y acoplamiento.
- Un crate de implementación por módulo consumido directamente por otros procesos: rechazado porque filtra internos y permite saltarse gRPC.
- Un crate Protobuf monolítico para todos los servicios: no recomendado; dificulta evolución independiente.
- Un microservicio por módulo desde el inicio: rechazado; contradice la topología modular aprobada y no está justificado por métricas.

## Estado de implementación

Propuesta documental pendiente de aceptación. No se han creado directorios de crates, manifiestos Cargo, dependencias, código, contratos Protobuf ni adaptadores. No se han modificado archivos SQL ni migraciones y no se han ejecutado migraciones.
