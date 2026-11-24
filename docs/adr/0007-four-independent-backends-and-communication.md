# ADR-0007: Topología de cuatro backends independientes y comunicación

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.
- Sustituye parcialmente: ADR-0005, únicamente en la topología de procesos y el despliegue de dos procesos.

## Contexto

La documentación anterior describía Restaurant OS como un único proceso `api-server` que alojaba los módulos de backend y un único BFF separado. Esa descripción no representa la topología aprobada del producto.

También es necesario distinguir dos fronteras diferentes: la comunicación entre módulos que comparten el mismo backend/proceso y la comunicación entre los backends independientes. El estándar modular adjunto define la primera y prepara cada módulo para una futura extracción como microservicio.

## Decisión

Restaurant OS se compone de cuatro backends/procesos totalmente independientes. Cada uno se compila y ejecuta como un binario separado y contiene sus propios módulos:

1. **Admin Platform Backend**.
2. **Admin BFF**.
3. **Public BFF**.
4. **Public Backend**.

No existe un único `api-server` que aloje los módulos de los cuatro procesos ni un único BFF compartido. Cada proceso conserva sus propios módulos, punto de composición y responsabilidades. Esta decisión no reasigna ni elimina la responsabilidad funcional de ningún módulo.

### Comunicación dentro de cada backend

Mientras dos módulos pertenecen al mismo backend y comparten proceso:

- Las consultas y comandos síncronos se realizan mediante contratos públicos y puertos/traits locales, con DTO propios.
- Los hechos ya ocurridos se expresan como eventos; los eventos durables se registran mediante Outbox/Inbox e idempotencia.
- Los módulos no importan implementaciones internas ni acceden directamente a las tablas de otros módulos.
- `FOR UPDATE SKIP LOCKED` se utiliza para reclamar filas de Outbox/trabajo entre workers cuando corresponde. Es un mecanismo de coordinación de procesamiento en PostgreSQL, no un protocolo de comunicación entre módulos.

Cada módulo conserva su schema, rol, migraciones y tabla de historial SQLx exclusivos. No se comparten tablas de historial ni tablas propietarias entre módulos.

### Comunicación entre los cuatro procesos

Las fronteras entre procesos utilizan el mecanismo adecuado al tipo de interacción:

- **gRPC + Protobuf versionado:** solicitudes y respuestas síncronas entre procesos.
- **NATS Core:** señales y mensajes efímeros que no requieren persistencia durable.
- **NATS JetStream:** eventos y mensajes que requieren persistencia, confirmación durable, reintentos o consumo recuperable.

Los eventos durables mantienen Outbox transaccional, consumidores idempotentes e Inbox/deduplicación según corresponda. No se sustituye la propiedad de datos de un módulo por acceso directo desde otro proceso.

## Consecuencias

- La documentación, los manifiestos y los inventarios de despliegue deben representar cuatro procesos independientes.
- Cada backend puede evolucionar y escalar como unidad, sin convertir automáticamente cada módulo interno en microservicio.
- Un módulo puede extraerse posteriormente como microservicio conservando sus contratos públicos y cambiando sus adaptadores locales por adaptadores de transporte.
- La comunicación entre procesos no se reduce a gRPC: NATS Core y JetStream cubren respectivamente los casos efímeros y durables.
- Esta decisión arquitectónica no constituye evidencia de que los cuatro binarios, servicios Docker, conexiones gRPC o infraestructura NATS ya estén implementados. Su estado debe verificarse por separado.
- Las responsabilidades y ownership funcionales definidos en `requisitos.md` permanecen vigentes.

## Alternativas consideradas

- Un único `api-server` y un único BFF: rechazado; no representa la topología aprobada.
- Integrar los BFF dentro de los backends de plataforma/público: rechazado; cada BFF es un proceso/binario independiente.
- Usar únicamente gRPC para toda comunicación: rechazado; no cubre adecuadamente los casos de mensajería efímera y durable.
- Usar NATS Core como sustituto de mensajería durable: rechazado; los eventos que requieren durabilidad usan JetStream.
- Convertir todos los módulos en microservicios desde el inicio: rechazado; cada backend mantiene su organización modular y la extracción futura requiere una razón medible.

## Relación con ADR anteriores

ADR-0005 mantiene vigente la decisión de definir Protobuf versionado desde el inicio y usar gRPC en las fronteras entre procesos. Sus referencias a un único `api-server`, un único BFF y dos servicios de aplicación quedan sustituidas por esta decisión. El patrón de comunicación local entre módulos que comparten proceso sigue vigente y se aplica dentro de cada uno de los cuatro backends.

ADR-0001 mantiene vigente el ownership de PostgreSQL y las migraciones/historial SQLx independientes por módulo. ADR-0003 mantiene vigente Outbox/Inbox, idempotencia y coordinación de jobs.

## Estado de implementación

Decisión arquitectónica aceptada. La existencia y configuración efectiva de los cuatro procesos, sus contratos, los servicios Docker y la infraestructura NATS deben verificarse mediante código y manifiestos; este ADR no declara esos elementos implementados.
