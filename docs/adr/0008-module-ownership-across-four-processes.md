# ADR-0008: Distribución de módulos entre los cuatro procesos

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.
- Complementa: ADR-0007.

## Contexto

ADR-0007 establece cuatro procesos independientes, pero deja pendiente la asignación concreta de los dominios a cada proceso. Es necesario fijar esa distribución antes de crear los crates y definir sus dependencias.

## Decisión

La distribución aprobada es deliberadamente concentrada:

1. **Admin Platform Backend** es propietario únicamente del módulo `PLATFORM`, responsable del ciclo de vida SaaS: tenants, planes, suscripciones, límites y capacidades propias de administración de la plataforma.
2. **Public Backend** es propietario de todos los demás módulos de negocio enumerados en la matriz canónica de `requisitos.md`.
3. **Admin BFF** y **Public BFF** son procesos independientes de composición y exposición HTTP/OpenAPI. No son propietarios de dominios de negocio, schemas PostgreSQL ni tablas de negocio; tampoco duplican módulos de los backends.

### Matriz de propiedad

| Proceso | Módulos propietarios |
|---|---|
| Admin Platform Backend | PLATFORM |
| Public Backend | IDENTITY, ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, KITCHEN, INVENTORY, PROCUREMENT, PRODUCTION, BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS, AUDIT, REPORTING |
| Admin BFF | Ninguno. Composición de APIs para las interfaces administrativas. |
| Public BFF | Ninguno. Composición de APIs para las interfaces públicas y operativas. |

La asignación de `IDENTITY` a Public Backend significa que existe un único propietario de usuarios, membresías, autenticación, autorización y sesiones. Admin Platform Backend consume los contratos de identidad que necesite; no crea tablas, copias autoritativas ni un segundo módulo IDENTITY. Las credenciales y permisos específicos de la administración SaaS se modelan dentro de los límites de PLATFORM cuando sean propios del ciclo de vida de la plataforma, sin duplicar la propiedad de identidad.

Las capacidades de menús gastronómicos y servicio de restaurante permanecen en Public Backend junto a los dominios gastronómicos responsables. Esta distribución física no cambia las responsabilidades: CATALOG conserva productos y agrupaciones comerciales genéricas; KITCHEN conserva estaciones, comandas y preparación; PRODUCTION conserva recetas, fórmulas y órdenes de producción; INVENTORY conserva existencias y movimientos. No se crea un dominio adicional ni se fusionan esas responsabilidades por esta decisión.

AI continúa siendo una capacidad transversal sin módulo ni schema propietario, conforme a ADR-0006.

## Reglas de implementación derivadas

- Los módulos propietarios viven una sola vez en `backend/<backend-propietario>/modules/<modulo>/`.
- La ruta de PLATFORM es `backend/admin-platform-backend/modules/platform/`.
- Los demás módulos canónicos viven bajo `backend/public-backend/modules/<modulo>/`.
- Los BFF pueden tener módulos internos de transporte, presentación, autenticación de borde o composición, pero no se convierten en propietarios de dominios ni de persistencia de negocio.
- Una operación administrativa sobre datos empresariales no convierte al Admin BFF ni a PLATFORM en propietarios de esos datos: la operación se dirige al contrato del módulo dueño en Public Backend.
- La comunicación entre procesos conserva los mecanismos de ADR-0007: gRPC + Protobuf versionado para solicitud/respuesta, NATS Core para señales efímeras y NATS JetStream para eventos durables.
- Cada módulo mantiene schema, rol, migraciones y tabla de historial SQLx exclusivos. No hay tablas compartidas entre módulos ni tablas de historial compartidas.
- Esta distribución no autoriza a crear crates, manifests, dependencias, código ejecutable, tablas o migraciones. Esos trabajos se planifican después de revisar esta matriz.

## Consecuencias

- Public Backend contiene la mayor parte de los dominios de negocio y sus puntos de composición.
- Admin Platform Backend mantiene un límite pequeño y explícito alrededor de la gestión SaaS.
- Ambos BFF siguen siendo procesos separados, sin persistencia propietaria de negocio.
- Los consumidores administrativos acceden a dominios empresariales mediante sus contratos, sin saltarse el ownership.
- Cualquier futura redistribución requiere un ADR nuevo aceptado; no se mueve un módulo por conveniencia de carpetas.

## Alternativas consideradas

- Distribuir dominios empresariales entre un backend administrativo y uno público según el frontend que los consulta: rechazado, porque confunde superficie de presentación con propiedad del dominio.
- Convertir los BFF en propietarios de módulos o persistencia: rechazado.
- Duplicar IDENTITY para separar administradores de plataforma y usuarios de tenants: rechazado, porque crearía dos fuentes autoritativas para identidad.

## Estado de implementación

La distribución está aprobada documentalmente. No implica que los crates, binarios, contratos gRPC, servicios Docker o infraestructura de mensajería estén implementados.
