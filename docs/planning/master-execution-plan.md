# Plan maestro de ejecución detallado — Restaurant OS

**Estado:** planificación documental  
**Versión:** 1.0  
**Fecha:** 2026-11-25  
**Ámbito:** fases funcionales 0–10 y fase final de privacidad, cumplimiento legal y lanzamiento  
**Fuente funcional:** [ROADMAP.md](../../ROADMAP.md)  
**Propiedad de dominios:** [requisitos.md](../../requisitos.md)  
**Orden de lotes funcionales:** [promt.md](../../promt.md)

---

## 1. Propósito y autoridad del documento

Este documento descompone el roadmap existente en subfases ejecutables. Para cada subfase define tareas, dependencias, documentación y ADR relacionados, entregables, pruebas, criterios verificables y una puerta de avance.

No crea fases funcionales nuevas ni sustituye las tres vistas que ya existen en ROADMAP.md:

1. Fases funcionales del producto: Fase 0 a Fase 10.
2. Lotes funcionales: lote 0 a lote 11.
3. Plan maestro de desarrollo: secuencia orientativa de ingeniería, infraestructura y entrega.

Las tres vistas se relacionan, pero no son numeraciones intercambiables. Los lotes indican orden funcional recomendado; no son IDs de módulos, crates, schemas ni migraciones.

### 1.1 Jerarquía documental obligatoria

- [requisitos.md](../../requisitos.md) es la fuente de verdad de requisitos, ownership y ubicación física de módulos.
- [ROADMAP.md](../../ROADMAP.md) conserva la visión, fases funcionales, lotes y plan maestro.
- [promt.md](../../promt.md) define el orden de trabajo por lotes.
- Los ADR Accepted son decisiones arquitectónicas obligatorias.
- Las especificaciones técnicas desarrollan esas decisiones sin modificarlas.
- Este plan ordena el trabajo y convierte las decisiones en entregables y pruebas; no puede cambiar ownership, contratos ni decisiones aceptadas.
- Si un ejemplo o regla histórica de requisitos.md contradice un ADR Accepted, prevalece el ADR; el plan debe identificar la parte supersedida para que no se implemente como requisito vigente.
- Cualquier desviación arquitectónica requiere ADR aceptado antes de implementarse.

### 1.2 Topología y ownership que todas las fases deben respetar

1. Admin Platform Backend: propietario exclusivo de PLATFORM.
2. Admin BFF: proceso independiente de composición y exposición HTTP/OpenAPI; no posee dominios ni persistencia de negocio.
3. Public BFF: proceso independiente de composición y exposición HTTP/OpenAPI; no posee dominios ni persistencia de negocio.
4. Public Backend: propietario de todos los demás módulos canónicos.

Los módulos conservan su ownership, schema, rol, migraciones e historial SQLx independientes. No hay tablas de historial compartidas. No se permiten FKs, joins ni consultas directas entre schemas de módulos distintos. Cada módulo utiliza sus contratos públicos y adaptadores permitidos; los BFF no consultan PostgreSQL de negocio.

La comunicación entre procesos utiliza gRPC/Protobuf para solicitudes y respuestas, NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda. Dentro de un backend, los módulos usan contratos públicos y puertos/traits locales. Outbox/Inbox e idempotencia protegen los efectos durables.

### 1.3 Estados de decisión

- ADR-0001 a ADR-0018: Accepted.
- ADR-0019: Accepted por aprobación expresa del propietario del producto. La validación de entradas y contratos de datos se considera requisito transversal.
- ADR-0020 a ADR-0027: Accepted.
- La aceptación de un ADR no significa que su implementación, infraestructura, pruebas o controles ya existan.
- La situación de PRs y ramas es independiente del estado de decisión arquitectónica. Este documento no autoriza por sí solo fusionar PRs.

### 1.4 Reglas de planificación

- No se inicia implementación de una subfase sin satisfacer sus dependencias y contar con los documentos de diseño necesarios.
- No se considera entregable una tarea que solo tenga una pantalla si el backend propietario, autorización, persistencia, auditoría y pruebas correspondientes faltan.
- No se cierra una subfase con pruebas exclusivamente unitarias cuando el riesgo exige integración, seguridad o E2E.
- No se declaran controles de seguridad activos por el mero hecho de que exista un ADR, una especificación, un workflow o un archivo CODEOWNERS.
- No se modifican archivos SQL ni migraciones fuera del proceso de implementación y revisión correspondiente.
- Las pruebas deben ejecutarse contra las fronteras reales cuando el objetivo sea validar integración, aislamiento, autorización, mensajería o persistencia.
- Los límites numéricos, capacidad, SLO, RPO/RTO y dimensionamiento se determinan mediante análisis y pruebas operativas; no se inventan valores universales en este plan.

---

## 2. Modelo de puertas de avance

Cada subfase tiene una puerta de avance. Se considera superada únicamente cuando:

1. Los entregables enumerados existen y están revisados.
2. Las pruebas aplicables están automatizadas, ejecutadas y con evidencia.
3. No quedan defectos críticos o altos sin tratamiento aprobado.
4. Los controles de seguridad y privacidad aplicables han sido verificados.
5. La documentación, contratos y ownership están sincronizados.
6. Se conocen los riesgos residuales y tienen responsable y tratamiento.
7. La revisión de producto/arquitectura correspondiente está registrada.

Una dependencia no satisfecha bloquea el inicio de la subfase dependiente. Un fallo de seguridad crítico, una fuga entre tenants, una pérdida de datos, una duplicación financiera o una violación de ownership bloquea el avance aunque el resto de pruebas pase.

### 2.1 Tipos de prueba exigidos

- **Unitarias:** reglas puras, invariantes, transiciones, cálculos, validadores y políticas.
- **Integración:** interacción real entre módulo, schema propio, transacciones, contratos, PostgreSQL, Redis, NATS, almacenamiento y proveedores simulados/controlados.
- **Seguridad:** autorización, aislamiento multi-tenant, abuso, entradas maliciosas, secretos, criptografía, archivos, sesiones, dependencias y configuración.
- **Contrato:** compatibilidad OpenAPI/Protobuf, eventos versionados y consumidores.
- **E2E:** recorridos de usuario y procesos completos a través de los cuatro procesos cuando corresponda.
- **Carga/resiliencia:** concurrencia, límites, backpressure, failover, recuperación, latencia y degradación controlada.
- **Operativas:** backup/restore, despliegue, rollback/roll-forward, incidentes, runbooks y verificación de evidencias.

No todas las subfases necesitan todos los tipos; cada una identifica expresamente los aplicables.

---

## PARTE I — FUNDACIONES Y PRODUCTO

## 3. Fase 0 — Fundaciones

**Objetivo:** dejar preparada la arquitectura, gobernanza, seguridad base, entornos y capacidades transversales antes de construir los flujos funcionales.

**Dependencias:** decisiones arquitectónicas aceptadas; matriz de dominios en requisitos.md; topología y contratos documentados.  
**Lotes relacionados:** lote 0 de PLATFORM como fundación SaaS y preparación de los lotes funcionales posteriores.

### 0.1 — Cierre de arquitectura, ownership y contratos

#### Tareas

- Consolidar el mapa de los cuatro procesos y sus límites de responsabilidad.
- Verificar la matriz de los módulos canónicos y sus ubicaciones físicas.
- Registrar por módulo propietario, schema, rol, migraciones e historial SQLx independientes.
- Documentar los contratos públicos y dirección permitida de dependencias.
- Establecer OpenAPI como fuente HTTP y Protobuf como fuente gRPC.
- Establecer versionado y ownership de eventos por módulo.
- Documentar adaptadores local, gRPC y messaging según las decisiones vigentes.
- Identificar dependencias funcionales entre módulos sin inventar un grafo: cada dependencia futura debe justificarse por caso de uso y contrato.
- Definir el proceso de revisión de cambios de arquitectura y desviaciones.

**Dependencias técnicas/funcionales:** ADR-0001, ADR-0002, ADR-0005, ADR-0007, ADR-0008 y ADR-0009; requisitos.md y promt.md. ADR-0005 conserva las reglas de contratos gRPC que siguen vigentes; la topología de cuatro procesos y la comunicación actual se rigen por ADR-0007.  
**Documentos/ADR:** ADR-0001, 0002, 0005, 0007, 0008 y 0009; engineering-standard.md; restaurant-os-architecture.md; crate-architecture.md.  

#### Entregables

- Matriz de ownership validada.
- Mapa de procesos y fronteras.
- Catálogo inicial de contratos y eventos con propietarios.
- Matriz de dependencias justificadas y dependencias prohibidas.
- Checklist de revisión arquitectónica.

#### Pruebas

- Unitarias: no aplican a la documentación de arquitectura.
- Integración/contrato: validación automatizada de estructura, enlaces y referencias entre documentos.
- Seguridad: revisión de límites de confianza, ownership y ausencia de acceso cruzado.
- E2E: no aplica todavía.

#### Criterios verificables

- Cada módulo canónico tiene un único propietario.
- PLATFORM es el único módulo de Admin Platform Backend.
- Los BFF no poseen dominios ni persistencia de negocio.
- Cada módulo mantiene su propio historial SQLx.
- No existe decisión documental que habilite consultas o FKs entre schemas de módulos distintos.

**Puerta:** arquitectura y ownership consistentes en todos los documentos normativos; no hay contradicciones abiertas.

### 0.2 — Gobernanza documental y desarrollo seguro

#### Tareas

- Definir convenciones de ramas, PR, revisión, versionado y changelog.
- Configurar Rulesets/branch protection reales para main y ramas críticas.
- Exigir checks adecuados y revisión humana para cambios sensibles.
- Separar permisos de lectura, escritura, administración y despliegue.
- Definir reglas de CODEOWNERS junto con enforcement de GitHub.
- Definir política de dependencias, actualización y vulnerabilidades.
- Definir permisos mínimos por workflow y separación de validación no privilegiada y despliegues privilegiados.
- Definir cómo se documentan excepciones, bypasses y cambios de emergencia.
- Mantener secretos fuera de repositorio, logs, imágenes y artefactos.

**Dependencias:** 0.1.  
**Documentos/ADR:** ADR-0020, ADR-0024; documentation-quality-and-security-standard.md; implementation-rules.md.  

#### Entregables

- Política de contribución y revisión.
- Rulesets configurados y evidencia de enforcement.
- Matriz de permisos de repositorio y CI.
- Política de dependencias y vulnerabilidades.
- Checklist de PR seguro.

#### Pruebas

- Integración: PR de prueba para comprobar checks y protecciones.
- Seguridad: intento controlado de push directo, force-push, workflow con permisos excesivos y exposición de secretos.
- Operativas: evidencia de recuperación ante fallo de CI.

#### Criterios

- main no acepta cambios fuera del flujo protegido.
- Los workflows tienen permisos mínimos y no exponen secretos a código no confiable.
- CODEOWNERS no se presenta como enforcement si no hay reglas que exijan la revisión.

**Puerta:** reglas verificadas en GitHub y evidencia conservada; no basta con documentación.

### 0.3 — Modelo de amenazas y requisitos de seguridad

#### Tareas

- Inventariar activos, actores, superficies y fronteras de confianza.
- Modelar amenazas para cuatro procesos, módulos, navegador, APIs, workers, mensajería, almacenamiento, proveedores y operación.
- Evaluar suplantación, robo de sesión, BOLA/IDOR, escalada, inyección, SSRF, XSS, CSRF, abuso, scraping, DDoS, exfiltración, malware, supply chain y pérdida de disponibilidad.
- Definir controles preventivos, detectivos, correctivos y evidencias.
- Asignar controles a fases y subfases de este plan.
- Mantener riesgos residuales con propietario y tratamiento.

**Dependencias:** 0.1.  
**Documentos/ADR:** ADR-0020 a ADR-0027; ADR-0011, 0015, 0018 y 0019.  

#### Entregables

- Modelo de amenazas versionado.
- Matriz amenaza/control/fase/prueba/evidencia.
- Registro de riesgos residuales.
- Baseline de seguridad por proceso.

**Pruebas:** revisión de amenazas y tabletop de escenarios; no sustituye pruebas técnicas posteriores.  
**Criterios:** todas las superficies críticas tienen amenazas y controles asignados; no hay amenazas altas sin tratamiento o aceptación formal.  
**Puerta:** modelo revisado y enlazado a tareas concretas del plan.

### 0.4 — Identidad, autorización y aislamiento como fundamentos

#### Tareas

- Diseñar identidad de usuario y de servicio diferenciadas.
- Definir contexto autenticado confiable y propagación entre procesos.
- Definir RBAC + ABAC y alcance por tenant, grupo, empresa, marca, sucursal, recurso y operación.
- Definir reglas de separación entre privilegios SaaS de PLATFORM y administración de tenant.
- Diseñar aislamiento PostgreSQL/RLS por transacción y permisos mínimos.
- Definir revocación, sesiones, elevación de privilegios y acceso excepcional de soporte.
- Definir autorización en el backend propietario, incluyendo workers y consumidores.

**Dependencias:** 0.1 y 0.3.  
**Documentos/ADR:** ADR-0008, 0011, 0020, 0021; ADR-0010 y 0012.  

#### Entregables

- Modelo de identidad y autorización.
- Matriz rol/atributo/acción/ámbito.
- Contrato de contexto autenticado.
- Diseño de aislamiento por módulo y proceso.
- Casos negativos de autorización.

**Pruebas:** unitarias de políticas; integración con contexto/RLS; seguridad BOLA/IDOR, tenant cruzado, escalada horizontal/vertical y worker con contexto inválido.  
**Criterios:** ningún ID o tenant enviado por cliente constituye autoridad; cada módulo propietario toma la decisión final.  
**Puerta:** modelo aprobado y pruebas negativas definidas antes de construir operaciones protegidas.

### 0.5 — Política transversal de validación de entradas

#### Tareas

- Aplicar validación en frontend, BFF, frontera backend/gRPC, aplicación, dominio y persistencia.
- Definir contratos por campo: tipo, requerido, null, rango, formato, precisión, cardinalidad y profundidad.
- Definir DTO específicos por operación y rechazo de campos desconocidos por defecto en escrituras HTTP.
- Evitar mass assignment de tenant, actor, permisos, estado interno y campos calculados.
- Definir normalización explícita por tipo de dato.
- Definir validación de filtros, ordenamiento, paginación y cursores.
- Definir controles para archivos, URLs, SSRF, importaciones y respuestas de proveedores.
- Definir errores HTTP/gRPC estables y seguros.
- Definir validación de eventos, workers, Outbox/Inbox e idempotencia.
- Mantener autorización y validación de estado como controles separados.

**Dependencias:** 0.1, 0.3 y 0.4.  
**Documentos/ADR:** ADR-0019 Accepted; ADR-0002, 0009, 0011, 0012, 0015, 0018, 0020, 0021, 0022, 0025 y 0027; ../architecture/input-validation-and-data-contracts.md.  

#### Entregables

- Catálogo de reglas y formatos.
- Plantilla de contrato de entrada por operación.
- Catálogo de errores públicos.
- Checklist de revisión de validación.
- Matriz de pruebas negativas y fuzzing.

**Pruebas:** unitarias de formatos/límites; contrato OpenAPI/Protobuf; seguridad mass assignment, inyección, SSRF, traversal, tenant cruzado y abuso; fuzz/property tests para parsers.  
**Criterios:** todas las fronteras y tipos de entrada tienen política definida; el frontend nunca es la única validación.  
**Puerta:** política y checklist disponibles antes de implementar el primer endpoint o consumidor.

### 0.6 — Fundamentos de datos, PostgreSQL y consistencia

#### Tareas

- Definir PostgreSQL objetivo y estrategia HA con primario y réplicas de lectura.
- Definir pools por módulo/runtime, límites globales, separación de lectura/escritura y routing por consistencia.
- Definir UUIDv7 global y estrategia futura para identificadores existentes, sin modificar SQL en esta fase.
- Definir transacciones locales por módulo, Outbox/Inbox, idempotencia y Saga.
- Identificar expresamente y no aplicar el ejemplo histórico de requisitos.md que propone una transacción local única con escrituras de varios módulos: ADR-0013 Accepted prevalece; incluso dentro del mismo proceso, cada módulo confirma sus propias transacciones y los flujos multi-módulo se coordinan mediante contratos/Saga/Outbox/Inbox, sin XA/2PC ni transacciones PostgreSQL compartidas.
- Definir roles separados de migración, runtime, backup y monitoreo.
- Definir política RLS y contexto de tenant.
- Definir backups, WAL, PITR y pruebas de restauración.
- Definir retención de datos técnicos y de negocio según ownership.

**Dependencias:** 0.1 y 0.4.  
**Documentos/ADR:** ADR-0001, 0003, 0010, 0012, 0013, 0014; identifier-strategy.md; postgresql-ha-and-read-replicas.md; distributed-transaction-consistency.md; transactional-outbox-inbox-operations.md.  

#### Entregables

- Diseño de PostgreSQL HA y réplicas.
- Presupuesto de conexiones por proceso/módulo/réplica.
- Estrategia UUIDv7 y transición futura.
- Diseño Outbox/Inbox/Saga.
- Plan backup/restore/PITR.

**Pruebas:** integración transaccional; aislamiento RLS; concurrencia; idempotencia; restore completo y PITR en entorno aislado.  
**Criterios:** un módulo no accede a tablas ajenas; las lecturas críticas no se enrutan a réplicas sin garantía de consistencia; la réplica no se considera backup.  
**Puerta:** diseños revisados y pruebas operativas planificadas; sin cambios SQL anticipados.

### 0.7 — Infraestructura, red, secretos y criptografía

#### Tareas

- Diseñar redes separadas por entorno y función.
- Definir exposición pública mínima y aislamiento de PostgreSQL, Redis, NATS, métricas y administración.
- Definir egress restringido por proceso.
- Diseñar contenedores no privilegiados, filesystem y capacidades mínimas.
- Definir gestor de secretos, identidades separadas y ciclo de rotación/revocación.
- Definir TLS entre clientes, procesos, bases, caché, mensajería y administración.
- Definir cifrado, gestión de claves y respaldos.
- Definir hardening y configuración segura por entorno.

**Dependencias:** 0.3, 0.4 y 0.6.  
**Documentos/ADR:** ADR-0020, 0023; ADR-0012, 0015, 0016 y 0017.  
**Entregables:** modelo de red, matriz de flujos permitidos, política de secretos, baseline de contenedores, política TLS/criptográfica y runbooks de rotación.  
**Pruebas:** escaneo de configuración e imágenes; pruebas de certificados, expiración y rotación; validación de puertos expuestos y egress; restauración de secretos.  
**Criterios:** no hay secretos compartidos entre los cuatro procesos ni servicios de datos expuestos públicamente sin justificación.  
**Puerta:** arquitectura de infraestructura y controles verificables listos para despliegue controlado.

### 0.8 — Observabilidad, auditoría y respuesta a incidentes

#### Tareas

- Definir OpenTelemetry y propagación W3C Trace Context.
- Definir métricas RED/USE, logs estructurados y trazas sin datos sensibles.
- Separar telemetría operativa, auditoría de negocio y evidencia de seguridad.
- Definir ownership de eventos de auditoría por módulo.
- Definir detecciones, severidades, alertas, escalamiento y runbooks.
- Definir retención, integridad y acceso a evidencias.
- Definir proceso de respuesta: detección, triage, contención, erradicación, recuperación y lecciones.
- Definir ejercicios de incidentes y comunicación con tenants.

**Dependencias:** 0.3, 0.4, 0.6 y 0.7.  
**Documentos/ADR:** ADR-0004, 0015, 0020, 0026; ADR-0018.  
**Entregables:** estrategia de observabilidad; catálogo de eventos auditables; matriz de alertas; runbooks; plan de respuesta y ejercicios.  
**Pruebas:** integración de propagación de trazas; verificación de redacción; alertas sintéticas; tabletop y simulación de incidente.  
**Criterios:** cada evento sensible tiene evidencia mínima y propietario; logs no sustituyen auditoría.  
**Puerta:** señales críticas, runbooks y responsabilidades definidos antes de operar servicios.

### 0.9 — Plataforma de mensajería, caché y almacenamiento

#### Tareas

- Diseñar NATS Core y JetStream HA, cuentas, subjects, streams, retención, ACK y DLQ.
- Diseñar Redis Cluster TLS/ACL y política cache-aside e invalidación durable.
- Diseñar almacenamiento de objetos con aislamiento por entorno/finalidad, ownership de metadata por módulo y acceso temporal autorizado.
- Definir cuarentena y procesamiento aislado de archivos.
- Definir límites de tamaño, tipos, análisis, descargas y ciclo de vida.
- Definir fallback seguro cuando Redis o proveedores no estén disponibles.

**Dependencias:** 0.6, 0.7 y 0.8.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0016, 0017, 0023, 0025, 0027; redis-cache-operations.md; nats-core-jetstream-cluster.md.  
**Entregables:** diseño de NATS, Redis y object storage; contratos de eventos; política de caché; flujo seguro de archivos.  
**Pruebas:** failover, replay, duplicados, invalidación, cache stampede, TLS/ACL, archivos maliciosos, traversal y acceso entre tenants.  
**Criterios:** Redis no es fuente de verdad ni broker durable; JetStream no promete exactly-once; metadata y autorización de archivos permanecen en módulos propietarios.  
**Puerta:** contratos y pruebas de resiliencia definidos antes de conectar los dominios.

### 0.10 — Fundamentos offline-first del POS

#### Tareas

- Definir identificadores generados en dispositivo y persistencia local durable.
- Definir el conjunto mínimo de datos locales: catálogo disponible, precios vigentes, variantes/excepciones de sucursal, inventario conocido, métodos de pago permitidos, configuración fiscal y rangos de numeración autorizados.
- Definir cola de operaciones, orden, reintentos, sincronización e idempotencia.
- Definir estados de sincronización y recuperación tras reinicio.
- Definir resolución de conflictos con reglas explícitas y revisión humana donde no haya resolución determinista.
- Definir límites offline de pagos y numeración fiscal.
- Definir protección de datos locales, cifrado, sesión, revocación y limpieza al cambiar tenant/usuario.
- Definir telemetría de sincronización sin registrar payloads sensibles.

**Dependencias:** 0.4, 0.5, 0.6 y 0.8.  
**Documentos/ADR:** ADR-0003, 0011, 0012, 0013, 0015, 0018, 0019, 0021, 0022, 0025.  
**Entregables:** especificación offline-first, máquina de estados de sincronización, política de conflictos, matriz de operaciones permitidas offline.  
**Pruebas:** unitarias de idempotencia/estados; integración de reconexión; seguridad de almacenamiento local y cambio de tenant; E2E de venta offline, reinicio y sincronización sin duplicados.  
**Criterios:** operaciones no autorizadas offline se bloquean; ningún reintento duplica venta, pago o movimiento; el dispositivo no emite documentos fiscales sin numeración vigente asignada.  
**Puerta:** contrato offline y casos de aceptación definidos antes de implementar el POS.

**Salida de Fase 0:** arquitectura, contratos, seguridad, datos, infraestructura, observabilidad y estrategia offline documentados y revisados. No implica que el software o la infraestructura estén desplegados.

---

## 4. Fase 1 — Plataforma e identidad

**Objetivo:** habilitar ciclo de vida SaaS, organizaciones, sucursales, usuarios, autenticación, autorización y configuración base.

**Dependencias:** Fase 0; subfases 0.1–0.10.  
**Lotes relacionados:** lote 0 PLATFORM, lote 1 ORGANIZATION y lote 2 IDENTITY.

### 1.1 — PLATFORM y ciclo de vida SaaS

#### Tareas

- Modelar tenants, planes, suscripciones, capacidades, límites y overrides bajo PLATFORM.
- Activar capacidades Core, Restaurant Pack y Optional según tenant, marca o sucursal, sin convertir capacidades verticales en dependencias obligatorias de Core.
- Implementar altas, suspensión, reactivación y baja del tenant con proceso durable.
- Separar privilegios SaaS de administración del tenant.
- Definir medición de consumo y límites sin permitir bypass ante fallos.
- Implementar soporte excepcional temporal, justificado, auditado y revocable.
- Aplicar conservación de datos de clientes al eliminar tenant conforme ADR-0014.
- No permitir que PLATFORM borre directamente schemas de otros módulos.

**Dependencias:** 0.4, 0.5, 0.6, 0.8.  
**Documentos/ADR:** ADR-0008, 0014, 0020, 0021, 0025, 0026.  
**Entregables:** PLATFORM operativo; ciclo de vida tenant; planes/capacidades; procedimiento de baja; auditoría de administración SaaS.  
**Pruebas:** unitarias de estados y límites; integración de baja por lotes/reanudación; seguridad de aislamiento y soporte temporal; E2E alta/suspensión/reactivación.  
**Criterios:** PLATFORM no posee datos de negocio; la baja no elimina automáticamente perfiles ni facturas de clientes; operaciones son idempotentes y auditables.  
**Puerta:** ciclo de vida tenant probado sin acceso cruzado ni borrado fuera de ownership.

### 1.2 — ORGANIZATION: estructura empresarial

#### Tareas

- Crear, actualizar, activar, desactivar y suspender sucursales; conservar datos de ubicación/contacto y el historial de cambios de estado.
- Gestionar grupos empresariales, empresas legales, marcas y sucursales.
- Gestionar áreas, estaciones, bodegas, cajas y terminales según ownership.
- Definir zona horaria, moneda, región, idioma y datos fiscales por ámbito.
- Definir herencia central y excepciones locales sin sobrescribir el maestro.
- Mantener límites de relaciones entre tenants y empresas legales.

**Dependencias:** 1.1 y 0.4.  
**Documentos/ADR:** ADR-0001, 0008, 0019, 0020, 0021.  
**Entregables:** estructura empresarial y sucursales; configuración regional; matriz de herencia/excepciones.  
**Pruebas:** unitarias de jerarquía y reglas; integración de unicidad y relaciones; seguridad tenant/sucursal cruzada; E2E crear empresa y sucursales.  
**Criterios:** una sucursal pertenece a su ámbito empresarial correcto; no se permiten relaciones cruzadas entre tenants; la zona horaria es explícita; suspender/desactivar bloquea nuevas operaciones según estado sin eliminar históricos.  
**Puerta:** jerarquía y aislamiento verificados.

### 1.3 — IDENTITY: usuarios, autenticación y sesiones

#### Tareas

- Implementar identidad global de usuario y membresías por tenant sin duplicación.
- Implementar registro, invitaciones, activación y recuperación de cuenta.
- Aplicar exclusivamente Argon2id para nuevas contraseñas locales, con salt aleatorio único generado por la biblioteca, formato PHC y parámetros mínimos aprobados en ADR-0011.
- Definir actualización de parámetros de hash y migración gradual al autenticar cuando un hash requiera rehash; no crear algoritmos alternativos.
- Excluir contraseñas, hashes, salts y secretos de logs, eventos, trazas y contratos públicos.
- Implementar MFA donde corresponda, sesiones, rotación, expiración y revocación.
- Gestionar dispositivos y sesiones activas.
- Aplicar cookies seguras, CSRF, protección XSS, CSP, CORS y cabeceras.
- No almacenar tokens de larga duración en localStorage/sessionStorage.
- Limpiar estado local y cachés privadas al cerrar sesión o cambiar tenant.

**Dependencias:** 1.1, 1.2, 0.4 y 0.5.  
**Documentos/ADR:** ADR-0011, 0019, 0020, 0021, 0022, 0024, 0026.  
**Entregables:** flujos de identidad y sesión; política de cookies; recuperación de cuenta; revocación y auditoría.  
**Pruebas:** unitarias de políticas; integración de login/refresh/logout/revocación; seguridad CSRF, XSS, fijación/robo de sesión y enumeración; E2E autenticación y cambio de tenant.  
**Criterios:** cambio de tenant vuelve a validar membresía y permisos; sesión revocada no puede reutilizarse; cookies tienen atributos seguros; errores no filtran existencia sensible.  
**Puerta:** pruebas de sesión y autorización superadas.

### 1.4 — Autorización RBAC/ABAC y contexto confiable

#### Tareas

- Implementar roles y permisos por acción, módulo, tenant y ámbito.
- Aplicar atributos de sucursal, empresa, importe, recurso y estado.
- Construir contexto confiable de actor y servicio.
- Aplicar autorización en módulo propietario y en workers.
- Proteger acciones de alto impacto con separación de funciones y aprobaciones.
- Implementar acceso excepcional de soporte temporal y auditable.
- Definir revocación y coherencia de cachés de autorización.

**Dependencias:** 1.2 y 1.3.  
**Documentos/ADR:** ADR-0020, 0021, 0022, 0025, 0026; ADR-0016.  
**Entregables:** motor/políticas RBAC/ABAC por módulo; matriz de permisos; pruebas negativas automatizadas; runbook de revocación.  
**Pruebas:** unitarias de política; integración con backend propietario; seguridad BOLA/IDOR, escalada y tenant cruzado; E2E con roles distintos.  
**Criterios:** ocultar botones no cuenta como autorización; IDs válidos de otro tenant se rechazan; workers revalidan identidad/contexto; administradores SaaS no obtienen acceso operativo automático.  
**Puerta:** cobertura negativa de permisos y aislamiento aprobada.

### 1.5 — Configuración operativa inicial

#### Tareas

- Configurar datos fiscales y numeraciones por entidad/sucursal.
- Configurar moneda, impuestos, idioma y zona horaria.
- Configurar cajas, bodegas, cocinas, mesas, impresoras y terminales.
- Configurar métodos de pago, horarios, canales, notificaciones, idiomas y formatos por empresa y sucursal.
- Administrar plantillas versionadas de facturas, tickets, pedidos, cotizaciones y recepciones, con variables dinámicas, encabezados/pies, logotipos y datos fiscales.
- Aplicar cambios centrales a toda la empresa o a sucursales seleccionadas, mostrando origen, excepciones locales, previsualización, activación programada y reversión autorizada.
- Registrar dispositivos POS, impresoras, lectores, cajones, pantallas de cocina y terminales de pago; mantener estado, sucursal y caja asociados.
- Asignar rangos fiscales autorizados y no solapados a sucursal, punto de venta y dispositivo cuando corresponda.

**Dependencias:** 1.2 y 1.4; los módulos propietarios correspondientes deben exponer sus contratos.  
**Documentos/ADR:** ADR-0008, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** configuración inicial por sucursal; inventario de dispositivos; asignación fiscal controlada.  
**Pruebas:** unitarias de herencia; integración de rangos no solapados; seguridad de modificación privilegiada; E2E activar sucursal y terminal.  
**Criterios:** cada configuración tiene propietario y ámbito; no se asignan rangos fiscales duplicados; los cambios sensibles quedan auditados.  
**Puerta:** una sucursal puede quedar configurada sin alterar otras.

**Salida de Fase 1:** PLATFORM, estructura empresarial, identidad, permisos y configuración inicial disponibles y verificadas.

---

## 5. Fase 2 — Catálogo y ventas básicas

**Objetivo:** entregar el primer flujo de venta y cobro en una sucursal, con POS y operación offline limitada.

**Dependencias:** Fase 1; contratos de CATALOG, SALES, PAYMENTS y CASH; base offline de 0.10.  
**Lotes relacionados:** lotes 3, 7, 8 y 9; el lote gastronómico se coordina con Fase 3.

### 2.1 — CATALOG: productos comerciales

#### Tareas

- Gestionar categorías, productos, variantes, presentaciones y agrupaciones comerciales.
- Gestionar precios, impuestos y disponibilidad por sucursal.
- Definir catálogo maestro y excepciones locales sin alterar el maestro.
- Gestionar imágenes y documentos mediante ADR-0027.
- Versionar publicaciones y cambios comerciales.
- No trasladar recetas o menús gastronómicos al ownership de CATALOG.

**Dependencias:** 1.2, 1.4 y 1.5.  
**Documentos/ADR:** ADR-0008, 0009, 0019, 0020, 0021, 0027.  
**Entregables:** catálogo comercial; precios por sucursal; gestión de medios; historial/versiones.  
**Pruebas:** unitarias de precios/variantes; integración de persistencia propietaria; seguridad mass assignment y acceso a imágenes; E2E alta/edición/publicación.  
**Criterios:** una excepción local no modifica el catálogo maestro; productos y agrupaciones genéricas son propiedad de CATALOG.  
**Puerta:** catálogo publicado y aislado por tenant/sucursal.

### 2.2 — SALES: pedidos y cuentas

#### Tareas

- Crear pedidos y líneas con estados explícitos.
- Soportar mesa, mostrador, para llevar y delivery cuando el flujo correspondiente esté habilitado.
- Gestionar descuentos, anulaciones y cambios autorizados.
- Separar estado de pedido, pago y documento fiscal.
- Implementar división/unión de cuentas, transferencia de mesa y asignación de mesero cuando corresponda.
- Aplicar idempotencia a comandos POS.
- Conservar secuencia/versionado del agregado para concurrencia y eventos.

**Dependencias:** 2.1 y 1.4; recursos de ORGANIZATION.  
**Documentos/ADR:** ADR-0003, 0013, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** ciclo de pedido/cuenta; comandos versionados; historial del módulo; contratos OpenAPI/Protobuf aplicables.  
**Pruebas:** unitarias de máquina de estados; integración de transacciones y concurrencia; seguridad de manipulación de precios/tenant; E2E pedido completo.  
**Criterios:** un pedido no duplica efectos ante reintentos; descuentos/anulaciones requieren permiso; pago y fiscalización no se confunden con estado del pedido.  
**Puerta:** flujo de pedido consistente con eventos e idempotencia.

### 2.3 — PAYMENTS: cobros y devoluciones

#### Tareas

- Modelar intentos, autorizaciones, capturas, fallos, devoluciones y conciliación.
- Soportar métodos y pagos mixtos según contratos habilitados.
- Validar callbacks/webhooks y firmas de proveedores.
- Gestionar idempotencia y estados inciertos sin asumir que timeout significa fallo.
- Separar credenciales de proveedores por entorno y finalidad.
- Evitar registrar datos de tarjeta o secretos.

**Dependencias:** 2.2, 1.4 y 0.8.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0019, 0020, 0021, 0023, 0025, 0026.  
**Entregables:** ciclo de pago; integración de proveedor bajo contrato; conciliación y trazabilidad; política de reintentos.  
**Pruebas:** unitarias de estados; integración de callbacks duplicados/fuera de orden; seguridad de firma, replay y credenciales; E2E cobro, fallo, timeout y devolución.  
**Criterios:** ninguna repetición produce doble cobro; resultado incierto se reconcilia antes de repetir; datos sensibles no aparecen en logs.  
**Puerta:** pagos y devoluciones idempotentes y auditables.

### 2.4 — CASH: apertura, movimientos y cierre

#### Tareas

- Implementar apertura y cierre de caja por sucursal/terminal.
- Registrar fondo inicial, entradas, retiros, gastos y arqueos.
- Vincular movimientos con actor, motivo y operación.
- Aplicar permisos, límites y doble aprobación cuando corresponda.
- Evitar edición destructiva de movimientos; corregir mediante operaciones trazables.

**Dependencias:** 1.4 y 2.2; integración con PAYMENTS.  
**Documentos/ADR:** ADR-0013, 0015, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** ciclo de caja; arqueo; diferencias; auditoría.  
**Pruebas:** unitarias de saldo y cierre; integración de concurrencia; seguridad de segregación de funciones; E2E apertura-venta-cierre.  
**Criterios:** saldo reconstruible desde movimientos; diferencias no se ocultan; caja de una sucursal no se consulta desde otra sin permiso.  
**Puerta:** caja concilia en recorridos normales y concurrentes.

### 2.5 — POS web/PWA y seguridad de borde

#### Tareas

- Construir interfaz de venta y operación.
- Aplicar validación UX sin depender de ella como barrera de seguridad.
- Implementar sesiones seguras, CSRF, CSP, CORS restrictivo y cabeceras.
- Aplicar rate limits, cuotas y límites de body/consulta por operación.
- Proteger impresión, WebSockets y recursos estáticos.
- Aislar cachés y datos locales por usuario/tenant.
- Evitar secretos en bundles y almacenamiento web inseguro.

**Dependencias:** 1.3, 1.4, 2.1–2.4.  
**Documentos/ADR:** ADR-0019, 0020, 0021, 0022, 0025; ADR-0024 para supply chain.  
**Entregables:** POS funcional; configuración segura de BFF; catálogo de errores; pruebas E2E.  
**Pruebas:** unitarias de componentes críticos; integración HTTP/WebSocket; seguridad XSS/CSRF/CORS/sesión/rate limit; E2E por rol y sucursal.  
**Criterios:** las operaciones se autorizan en backend propietario; no hay secretos en frontend; controles de borde no reemplazan controles internos.  
**Puerta:** recorridos POS y pruebas de navegador superados.

### 2.6 — Offline-first: venta y caja habilitadas

#### Tareas

- Persistir localmente operaciones autorizadas antes de sincronizar.
- Generar identificadores en dispositivo.
- Mostrar estados pendientes, sincronizados, fallidos y en conflicto.
- Reintentar con idempotencia tras reconexión y reinicio.
- Limitar métodos de pago y operaciones fiscales offline a los autorizados.
- Bloquear emisión fiscal si el dispositivo carece de rango vigente asignado.
- Permitir abrir y cerrar caja offline conforme a las reglas locales y permisos vigentes disponibles.
- Permitir crear clientes básicos offline cuando la política de operación lo autorice.
- Permitir devoluciones offline únicamente bajo reglas, permisos y datos locales disponibles; dejar constancia de su estado pendiente cuando requiera conciliación.
- Permitir impresión local de comprobantes no fiscales y documentos fiscales solo cuando exista numeración válida y vigente asignada.
- Mantener sincronización automática y manual, cola durable local, errores visibles, bloqueo local en operaciones críticas y recuperación tras recarga/reinicio.
- Resolver conflictos mediante reglas deterministas y revisión humana cuando afecten datos financieros.
- Limpiar datos privados ante logout, revocación o cambio de tenant.

**Dependencias:** 0.10, 2.2, 2.3, 2.4 y 2.5.  
**Documentos/ADR:** ADR-0003, 0012, 0013, 0018, 0019, 0021, 0022, 0025.  
**Entregables:** sincronización local; recuperación tras reinicio; política offline por operación.  
**Pruebas:** unitarias de deduplicación/estados; integración de recarga, reinicio, cola durable, impresión y reconexión; seguridad de almacenamiento local y aislamiento por sucursal/tenant; E2E de venta, caja, cliente básico, devolución autorizada, dos terminales, conflicto y sincronización manual/automática.  
**Criterios:** cero duplicados en ventas/pagos/movimientos/devoluciones durante pruebas; recuperación completa de cola; ninguna operación offline no autorizada; no se emiten documentos fiscales sin numeración válida.  
**Puerta:** pruebas de desconexión prolongada y reconexión sin pérdida ni duplicación.

**Salida de Fase 2:** una sucursal puede registrar pedidos, cobrar, operar caja y recuperar operaciones offline autorizadas.

---

## 6. Fase 3 — Operación de mesas y cocina

**Objetivo:** conectar servicio, mesas, reservas, comandas y preparación sin alterar ownership de dominios.

**Dependencias:** Fase 2; ORGANIZATION, SALES y contratos de Restaurant vertical.  
**Lotes relacionados:** lote 6 (menú/recetas/producción) coordinado con Fase 4; capacidades de servicio de Restaurant vertical.

### 3.1 — Recursos de servicio y mesas

#### Tareas

- Modelar zonas, mesas, capacidad y estados.
- Construir mapa visual del salón.
- Asignar meseros y controlar ocupación.
- Gestionar reservas, lista de espera, no presentados y notificaciones.
- Mantener relación entre recurso físico, pedido y cuenta sin duplicar ownership.

**Dependencias:** 1.2, 1.4 y 2.2.  
**Documentos/ADR:** requisitos.md; ADR-0008, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** mapa de mesas; estados; reservas y lista de espera; auditoría de cambios.  
**Pruebas:** unitarias de estados/capacidad; integración de concurrencia; seguridad de acceso por sucursal; E2E reserva-asignación-cuenta.  
**Criterios:** no se asigna una mesa simultáneamente a cuentas incompatibles; transferencias quedan trazadas.  
**Puerta:** escenarios concurrentes de reserva y asignación superados.

### 3.2 — Menús gastronómicos y modificadores

#### Tareas

- Modelar menús por horario, sucursal y modalidad de servicio bajo Restaurant vertical.
- Componer menús con productos base de CATALOG.
- Gestionar modificadores culinarios, extras y disponibilidad.
- Versionar cambios y conservar la configuración efectiva al crear pedido.
- Validar compatibilidad entre menú, producto, sucursal e inventario sin consultas cruzadas a schemas.

**Dependencias:** 2.1, 3.1 y contratos de CATALOG.  
**Documentos/ADR:** requisitos.md; ADR-0008, 0009, 0013, 0019, 0020, 0021.  
**Entregables:** menús gastronómicos; reglas de disponibilidad; versiones aplicadas a pedidos.  
**Pruebas:** unitarias de reglas; integración por contratos; seguridad de edición por tenant/sucursal; E2E publicación y pedido.  
**Criterios:** CATALOG conserva productos/agrupaciones genéricas; menús y reglas gastronómicas permanecen en el dominio vertical propietario.  
**Puerta:** pedido reproduce la versión de menú y modificadores que aceptó el cliente.

### 3.3 — KITCHEN: comandas y estaciones

#### Tareas

- Crear comandas a partir de pedidos mediante contrato/evento.
- Separar líneas por estaciones y prioridades.
- Gestionar estados de preparación por producto.
- Implementar KDS, cronómetros y alertas de demora.
- Notificar al servicio cuando productos estén listos.
- Manejar duplicados, eventos fuera de orden y recuperación.
- Mantener historial propio del módulo.

**Dependencias:** 2.2, 3.1 y 3.2.  
**Documentos/ADR:** ADR-0003, 0004, 0013, 0015, 0017, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** KDS; estaciones; ciclo de comanda; alertas y métricas de preparación.  
**Pruebas:** unitarias de estados; integración JetStream/Outbox/Inbox; seguridad de mensajes no autorizados; E2E pedido-comanda-preparación-entrega.  
**Criterios:** reentrega de evento no duplica comanda; secuencia por agregado detecta huecos; el estado de cocina no modifica directamente el schema de SALES.  
**Puerta:** recuperación y duplicados probados sin perder comandas.

### 3.4 — Tiempos, notificaciones y operación en tiempo real

#### Tareas

- Medir tiempos de preparación y servicio.
- Emitir alertas de retrasos y cuellos de botella.
- Implementar notificaciones con límites y preferencias.
- Proteger WebSockets, canales y mensajes por tenant/sucursal.
- Definir degradación ante desconexión de clientes KDS.

**Dependencias:** 3.3 y 0.8.  
**Documentos/ADR:** ADR-0015, 0017, 0018, 0020–0026.  
**Entregables:** métricas de servicio; notificaciones; panel de demoras; runbook de desconexión.  
**Pruebas:** integración de eventos; seguridad de autorización de canales; carga de conexiones; E2E de alerta y recuperación.  
**Criterios:** ningún usuario recibe eventos de otra sucursal/tenant; notificaciones no alteran estado de negocio.  
**Puerta:** tiempos y alertas medibles con aislamiento probado.

**Salida de Fase 3:** operación coordinada entre servicio, mesas y cocina con trazabilidad e idempotencia.

---

## 7. Fase 4 — Inventario, recetas y producción

**Objetivo:** controlar existencias, movimientos, recetas, costos, lotes, producción y mermas.

**Dependencias:** Fases 1–3; CATALOG y SALES; interfaces de INVENTORY y PRODUCTION.  
**Lotes relacionados:** lote 4 INVENTORY y lote 6 PRODUCTION/KITCHEN.

### 4.1 — INVENTORY: ledger y existencias

#### Tareas

- Definir productos inventariables, unidades y conversiones.
- Registrar entradas, salidas, reservas, ajustes y conteos.
- Implementar ledger inmutable y reconstrucción de saldo.
- Gestionar bodegas, lotes, vencimientos y existencias por sucursal.
- Aplicar concurrencia y consistencia al reservar/consumir.
- Mantener inventario en tránsito y transferencias con estados.
- Aplicar permisos y doble aprobación a ajustes sensibles.

**Dependencias:** 1.2, 1.4 y CATALOG.  
**Documentos/ADR:** ADR-0001, 0010, 0012, 0013, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** ledger; saldo proyectado; lotes/vencimientos; conteos; transferencias.  
**Pruebas:** unitarias de saldo; integración de transacciones/concurrencia; seguridad de manipulación y tenant cruzado; E2E recepción-consumo-ajuste.  
**Criterios:** saldo reconstruible desde movimientos; no hay edición destructiva; cada movimiento conserva actor, causa y contexto.  
**Puerta:** conciliación de ledger y concurrencia superadas.

### 4.2 — PRODUCTION: recetas y subrecetas versionadas

#### Tareas

- Modelar recetas, subrecetas, ingredientes, rendimientos y porciones.
- Versionar recetas y vigencia por sucursal cuando corresponda.
- Calcular consumo esperado y costo con precisión decimal.
- Mantener fichas técnicas y reglas de sustitución explícitas.
- No asignar recetas a CATALOG ni almacenar movimientos físicos fuera de INVENTORY.

**Dependencias:** 2.1, 3.2 y 4.1.  
**Documentos/ADR:** requisitos.md; ADR-0008, 0009, 0012, 0019, 0020, 0021.  
**Entregables:** recetas versionadas; costos y rendimientos; reglas de vigencia.  
**Pruebas:** unitarias de conversiones/costos; integración con contratos INVENTORY; seguridad de edición por ámbito; E2E receta-publicación-consumo.  
**Criterios:** cada pedido usa versión efectiva; costo y cantidades reproducibles; PRODUCTION no escribe directamente en schema INVENTORY.  
**Puerta:** cálculo de receta validado con casos de borde y precisión decimal.

### 4.3 — Producción, lotes y consumo de inventario

#### Tareas

- Gestionar órdenes y lotes de producción.
- Registrar insumos consumidos y productos resultantes mediante contratos de INVENTORY.
- Controlar rendimiento, merma y diferencias.
- Implementar operaciones idempotentes y recuperables.
- Coordinar pasos multi-módulo con Saga cuando corresponda.

**Dependencias:** 4.1 y 4.2.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** órdenes de producción; lotes; trazabilidad de consumo/salida; proceso de reconciliación.  
**Pruebas:** unitarias de estado; integración de Saga/Outbox/Inbox; seguridad de permisos; E2E producción con fallo parcial y recuperación.  
**Criterios:** una repetición no duplica consumos ni salidas; las compensaciones son operaciones de negocio explícitas.  
**Puerta:** recuperación ante fallos parciales demostrada.

### 4.4 — Mermas, vencimientos y costeo

#### Tareas

- Registrar mermas y desperdicios con motivo y responsable.
- Alertar sobre vencimientos y stock mínimo/máximo.
- Calcular costo real y variación contra costo esperado.
- Medir rotación y diferencias de inventario.
- Proteger exportaciones y reportes de inventario.

**Dependencias:** 4.1–4.3.  
**Documentos/ADR:** ADR-0015, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** reportes de merma; alertas; costos; trazabilidad por sucursal.  
**Pruebas:** unitarias de cálculo; integración de alertas; seguridad de exportaciones; E2E de vencimiento/merma/ajuste.  
**Criterios:** métricas reproducibles desde movimientos y versiones de receta.  
**Puerta:** conciliación de costos y mermas aprobada.

**Salida de Fase 4:** inventario y producción trazables, con costos y consumos verificables.

---

## 8. Fase 5 — Compras y proveedores

**Objetivo:** automatizar abastecimiento, compras, recepciones, facturas y transferencias.

**Dependencias:** Fase 4 y proveedores de pago/facturación cuando aplique.  
**Lotes relacionados:** lote 5 PROCUREMENT.

### 5.1 — PROCUREMENT: proveedores y catálogo de abastecimiento

#### Tareas

- Gestionar proveedores, datos comerciales/fiscales y contactos.
- Gestionar productos suministrados, listas y precios históricos.
- Evaluar desempeño de proveedores, cumplimiento, calidad, tiempos de entrega y variaciones de precio con historial.
- Registrar condiciones de pago, contratos y documentos.
- Permitir extracción asistida de datos de facturas de proveedor desde documentos mediante OCR/IA, con validación contra proveedor/orden/recepción y revisión humana antes de crear o contabilizar operaciones.
- Aplicar verificación de identidad y autorización en cambios sensibles.
- Gestionar archivos mediante el flujo seguro de ADR-0027.

**Dependencias:** 1.2, 1.4 y 4.1.  
**Documentos/ADR:** ADR-0008, 0019, 0020, 0021, 0026, 0027.  
**Entregables:** ficha de proveedor; historial de precios; documentos y condiciones.  
**Pruebas:** unitarias de validación; integración de archivos; seguridad de acceso y datos entre tenants; E2E alta/actualización proveedor.  
**Criterios:** proveedor y documentos pertenecen al módulo/tenant correcto; no se confía en archivos ni respuestas externas.  
**Puerta:** alta y consulta segura de proveedores verificadas.

### 5.2 — Solicitudes, cotizaciones y órdenes de compra

#### Tareas

- Crear solicitudes de compra y cotizaciones.
- Comparar proveedores y precios.
- Crear órdenes con estados y versiones.
- Aplicar umbrales y aprobaciones por rol/importe.
- Soportar compras centralizadas y por sucursal.
- Evitar que una orden aprobada cambie silenciosamente.

**Dependencias:** 5.1, 4.1 y 1.4.  
**Documentos/ADR:** ADR-0013, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** flujo de solicitud/cotización/orden; reglas de aprobación; auditoría.  
**Pruebas:** unitarias de aprobación; integración de concurrencia/versionado; seguridad de segregación de funciones; E2E solicitud-aprobación-orden.  
**Criterios:** autor no aprueba su propia operación cuando la política exige separación; cambios quedan versionados.  
**Puerta:** flujo de aprobación y autorización superado.

### 5.3 — Recepción, conciliación y cuentas por pagar

#### Tareas

- Registrar recepción parcial/completa y diferencias.
- Conciliar orden, recepción y factura de proveedor.
- Gestionar documentos, costos de transporte y cuentas por pagar según ownership.
- Prevenir facturas y recepciones duplicadas.
- Integrar movimientos con INVENTORY mediante contratos.
- Aplicar Saga para operaciones multi-módulo durables.

**Dependencias:** 5.2, 4.1, FINANCE y BILLING según sus contratos.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0019, 0020, 0021, 0025, 0026, 0027.  
**Entregables:** recepción; conciliación de tres vías; cuentas por pagar; evidencia documental.  
**Pruebas:** unitarias de conciliación; integración de contratos y Saga; seguridad de documentos; E2E orden-recepción-factura-pago.  
**Criterios:** diferencias quedan registradas; no hay doble recepción ni factura duplicada; cada módulo escribe únicamente sus datos.  
**Puerta:** conciliación y recuperación ante fallo parcial demostradas.

### 5.4 — Transferencias entre sucursales

#### Tareas

- Solicitar y aprobar transferencias.
- Registrar despacho, inventario en tránsito y recepción.
- Gestionar diferencias, daños y ajustes.
- Conservar responsables y evidencia.
- Coordinar INVENTORY sin compartir tablas.

**Dependencias:** 4.1 y 5.2.  
**Documentos/ADR:** ADR-0013, 0019, 0020, 0021, 0025, 0026, 0027.  
**Entregables:** ciclo de transferencia; trazabilidad; conciliación de diferencias.  
**Pruebas:** unitarias de estados; integración de movimientos; seguridad entre sucursales; E2E despacho-recepción con diferencia.  
**Criterios:** una transferencia no crea ni elimina stock sin movimiento trazable; diferencias no se ocultan.  
**Puerta:** escenarios normales, duplicados y fallos parciales superados.

**Salida de Fase 5:** abastecimiento y recepción integrados con inventario y aprobación auditable.

---

## 9. Fase 6 — Personal y clientes

**Objetivo:** gestionar workforce y relaciones con clientes con controles de privacidad y consentimiento.

**Dependencias:** Fases 1–5; ORGANIZATION, IDENTITY, CUSTOMERS y WORKFORCE.  
**Lotes relacionados:** lote 10 CUSTOMERS; WORKFORCE como capacidad empresarial.

### 6.1 — WORKFORCE: empleados, cargos y contratos

#### Tareas

- Gestionar empleados, cargos, departamentos y relaciones laborales.
- Gestionar contratos, documentos y vigencias.
- Aplicar permisos por sucursal y rol.
- Proteger datos personales y limitar acceso.
- Gestionar solicitudes y ciclo de vida documental.

**Dependencias:** 1.2, 1.3 y 1.4.  
**Documentos/ADR:** ADR-0018, 0019, 0020, 0021, 0026, 0027.  
**Entregables:** fichas de empleados; contratos; permisos; inventario de datos tratados.  
**Pruebas:** unitarias de reglas; integración de documentos; seguridad de acceso mínimo y tenant; E2E alta/cambio/baja.  
**Criterios:** los datos laborales no se exponen a roles no autorizados; accesos y cambios sensibles quedan auditados.  
**Puerta:** ciclo de empleado y protección de documentos validados.

### 6.2 — Turnos, asistencia, ausencias y compensaciones

#### Tareas

- Gestionar horarios, turnos, asignaciones y asistencia.
- Gestionar horas extra, descansos, ausencias, permisos y vacaciones.
- Registrar las condiciones contractuales de remuneración y entregar a FINANCE los datos autorizados de turnos, asistencia, ausencias y variables laborales.
- Gestionar propinas y comisiones como datos de origen y métricas laborales, sin calcular ni pagar nómina desde WORKFORCE.
- Mantener FINANCE como propietario del cálculo y pago de nómina, propinas, comisiones y bonificaciones; no crear un módulo PAYROLL independiente.
- Registrar correcciones con motivo, actor y evidencia.
- Definir reportes con datos mínimos necesarios.

**Dependencias:** 6.1, CASH y SALES cuando corresponda.  
**Documentos/ADR:** ADR-0013, 0015, 0018, 0019, 0020, 0021, 0026.  
**Entregables:** calendario laboral; asistencia; reglas de cálculo; historial de correcciones.  
**Pruebas:** unitarias de cálculos; integración de concurrencia; seguridad de privilegios; E2E turnos/asistencia/corrección.  
**Criterios:** cálculos reproducibles y cambios auditados; acceso limitado por responsabilidad.  
**Puerta:** pruebas de cálculo y autorización superadas.

### 6.3 — CUSTOMERS: perfiles e historial

#### Tareas

- Gestionar perfiles, contactos y preferencias.
- Registrar encuestas, opiniones y retroalimentación de clientes con finalidad y permisos definidos.
- Conservar historial de compras según ownership y reglas de retención.
- Permitir acceso a perfil sin perderlo automáticamente al eliminar un tenant, conforme ADR-0014.
- Definir separación entre perfil, relación comercial y datos propios del tenant.
- Implementar derechos y solicitudes con enrutamiento al módulo responsable.

**Dependencias:** 1.3, 1.4, 2.2 y 0.8.  
**Documentos/ADR:** ADR-0014, 0018, 0019, 0020, 0021, 0026.  
**Entregables:** perfil cliente; historial; flujo de derechos; registro de solicitudes.  
**Pruebas:** unitarias de reglas de perfil; integración de ownership; seguridad de acceso y eliminación; E2E solicitud de acceso/rectificación/eliminación.  
**Criterios:** baja de tenant no destruye datos de cliente que deben conservarse; eliminación individual se distingue de baja de tenant; legal hold y retención se respetan.  
**Puerta:** flujos de derechos y conservación validados.

### 6.4 — Fidelización, campañas y consentimientos

#### Tareas

- Gestionar puntos, cupones, promociones, campañas de recuperación y tarjetas regalo.
- Gestionar segmentación y preferencias; definir campañas para clientes inactivos sin inferir consentimiento comercial.
- Registrar resultados de campañas, encuestas y respuestas dentro del alcance autorizado.
- Separar consentimientos por finalidad y canal.
- Permitir revocación y opt-out de comunicaciones comerciales.
- No condicionar el servicio a marketing.
- Registrar versión del aviso, elección, timestamp y contexto mínimo.
- Aplicar límites de campañas para evitar abuso y exposición masiva.

**Dependencias:** 6.3, 0.5 y 0.8.  
**Documentos/ADR:** ADR-0018, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** fidelización; centro de preferencias; evidencia de consentimiento; flujo de baja de comunicaciones.  
**Pruebas:** unitarias de acumulación y reglas; integración de revocación; seguridad de exportación/segmentación; E2E revocar y verificar bloqueo de campaña.  
**Criterios:** revocación efectiva antes de nuevas comunicaciones; consentimiento de marketing no se mezcla con términos o cookies.  
**Puerta:** evidencia de elección y revocación reproducible.

**Salida de Fase 6:** empleados y clientes gestionados con autorización, privacidad y trazabilidad.

---

## 10. Fase 7 — Contabilidad, facturación y finanzas

**Objetivo:** convertir operaciones en registros financieros y fiscales consistentes y auditables.

**Dependencias:** Fases 2, 4, 5 y 6; SALES, PAYMENTS, CASH, BILLING y FINANCE.  
**Lotes relacionados:** capacidades financieras y fiscales vinculadas a los lotes 7–9.

### 7.1 — BILLING: documentos fiscales y numeración

#### Tareas

- Separar documento fiscal de pedido y pago.
- Gestionar numeración y autorización por empresa legal/sucursal/punto de venta.
- Integrar proveedor/autoridad fiscal según jurisdicción.
- Gestionar facturas, documentos equivalentes, notas y respuestas.
- Preservar integridad, autenticidad y trazabilidad documental.
- Gestionar operación fiscal offline solo con numeración previamente autorizada.
- Validar firmas, callbacks y respuestas externas.

**Dependencias:** 1.2, 1.5, 2.2 y 2.3.  
**Documentos/ADR:** ADR-0003, 0013, 0014, 0018, 0019, 0020, 0021, 0023, 0025, 0026, 0027.  
**Entregables:** ciclo fiscal; numeración; documentos y acuses; reconciliación de estados.  
**Pruebas:** unitarias de cálculo y estados; integración de proveedor; seguridad de firma/replay/archivos; E2E emisión, rechazo, nota y contingencia.  
**Criterios:** no se confunde pago con factura; numeración no se solapa; documento retenido conserva evidencia; errores externos se reconcilian.  
**Puerta:** pruebas fiscales y de contingencia aprobadas para jurisdicción habilitada.

### 7.2 — FINANCE: libro, asientos y periodos

#### Tareas

- Definir plan contable, centros de costo y reglas de contabilización.
- Registrar asientos balanceados y reversos.
- Gestionar ingresos, egresos, cuentas por pagar, cuentas por cobrar, flujo de caja, costos operativos, impuestos y rentabilidad por sucursal/empresa legal.
- Gestionar plan contable, centros de costo, gastos directos/indirectos, prorrateos corporativos y trazabilidad de asignaciones.
- Calcular y pagar nómina, propinas, comisiones y bonificaciones a partir de las condiciones contractuales y datos laborales proporcionados por WORKFORCE; FINANCE conserva el ownership de los cálculos y pagos.
- Gestionar periodos diarios, mensuales, anuales y fiscales configurados; bloquear cierres y permitir reapertura únicamente mediante proceso autorizado, justificado y auditado.
- Importar movimientos bancarios, conciliar bancos, caja, tesorería y liquidaciones de PAYMENTS; identificar pendientes y ajustes autorizados.
- Separar operación financiera de documentos fiscales.
- Mantener referencias de origen y trazabilidad.
- No modificar históricos cerrados mediante edición destructiva.

**Dependencias:** 2.3, 2.4, 4.1, 5.3, 6.1, 6.2 y 7.1.  
**Documentos/ADR:** ADR-0001, 0013, 0015, 0018, 0019, 0020, 0021, 0026.  
**Entregables:** libro contable; plan de cuentas; centros de costo; cierres y reversos.  
**Pruebas:** unitarias de balance; integración de transacciones; seguridad de aprobación/cierre; E2E asiento desde venta y reverso.  
**Criterios:** asientos balanceados; reversos trazables; periodos cerrados no se alteran silenciosamente; nómina y compensaciones son reproducibles y conciliables; reaperturas y prorrateos conservan motivo, aprobación y evidencia.  
**Puerta:** conciliación y cierre reproducibles.

### 7.3 — CASH y tesorería: conciliaciones

#### Tareas

- Consolidar arqueos, entradas, retiros y diferencias.
- Conciliar bancos y pasarelas.
- Gestionar cuentas por cobrar/pagar en su módulo propietario.
- Registrar gastos y soportes.
- Mantener trazabilidad de actor, sucursal y medio de pago.
- Aplicar aprobaciones y separación de funciones.

**Dependencias:** 2.3, 2.4, 5.3, 7.1 y 7.2.  
**Documentos/ADR:** ADR-0013, 0015, 0019, 0020, 0021, 0025, 0026, 0027.  
**Entregables:** conciliaciones; reportes de tesorería; gastos; diferencias auditadas.  
**Pruebas:** unitarias de conciliación; integración de extractos/proveedores; seguridad de acciones de alto impacto; E2E conciliar caja/pasarela/banco.  
**Criterios:** diferencias se explican y no se borran; no se duplica contabilización; evidencias están protegidas.  
**Puerta:** conciliaciones de muestra cerradas con evidencia.

### 7.4 — Reportes financieros y fiscales

#### Tareas

- Construir estado de resultados, balance y flujo de caja.
- Reportar por sucursal, marca y empresa legal con filtros autorizados.
- Aplicar reglas de moneda, periodo y zona horaria.
- Proteger exportaciones y documentos.
- Definir retención y acceso de informes.

**Dependencias:** 7.1–7.3 y 0.8.  
**Documentos/ADR:** ADR-0015, 0018, 0019, 0020, 0021, 0025, 0026, 0027.  
**Entregables:** reportes financieros; reportes fiscales; exportaciones controladas.  
**Pruebas:** unitarias de agregación; integración de consistencia; seguridad de exportación masiva; E2E reportes por rol y entidad legal.  
**Criterios:** cifras reproducibles desde datos fuente; el usuario no consulta ámbitos fuera de permiso; exportaciones quedan auditadas.  
**Puerta:** conciliación entre reportes y fuentes contables aprobada.

### 7.5 — Cumplimiento fiscal colombiano y DIAN

#### Tareas

- Implementar en BILLING el ciclo de documentos fiscales exigidos para Colombia: factura electrónica de venta, documento equivalente electrónico tipo POS cuando corresponda, notas crédito, notas de ajuste y registro de documentos anulados.
- Registrar respuestas de validación, aceptación/rechazo, transmisión, reenvíos controlados y acuses de la DIAN/proveedor autorizado, conservando documento original y trazabilidad.
- Gestionar NIT, responsabilidades tributarias y configuración fiscal de empresa legal, sucursal y punto de venta.
- Aplicar impuestos por producto/servicio y reglas versionadas para IVA e impuesto nacional al consumo cuando corresponda; no asumir tratamiento fiscal uniforme para todos los productos.
- Gestionar resoluciones, rangos autorizados, vigencia, alertas de agotamiento, numeración emitida/anulada/pendiente y bloqueo al exceder o carecer de autorización.
- Separar el componente fiscal del POS: SALES entrega ventas validadas; BILLING es propietario del documento y su estado; INTEGRATIONS transporta mensajes con DIAN/proveedores sin crear un libro fiscal paralelo.
- Generar reportes fiscales por sucursal y empresa legal, separando ventas gravadas/excluidas/exentas, IVA, impuesto nacional al consumo, notas y ajustes; exportar datos contables/tributarios.
- Aplicar contingencia offline únicamente con rangos previamente asignados, válidos, vigentes y no solapados; marcar pendientes de transmisión y conciliar sin duplicar ni alterar consecutivos.
- Mantener revisión normativa/profesional por jurisdicción antes de habilitar emisión productiva.

**Dependencias:** 1.2, 1.5, 2.2, 2.3, 2.6, 7.1, 7.2 y 9.2.  
**Documentos/ADR:** requisitos.md (Requisitos particulares — Operación en Colombia); ADR-0003, 0013, 0018, 0019, 0020, 0021, 0023, 0025, 0026 y 0027.  
**Entregables:** matriz fiscal colombiana versionada; integración DIAN/proveedor; ciclo documental completo; control de resoluciones y rangos; reportes fiscales; procedimiento de contingencia.  
**Pruebas:** unitarias de impuestos/numeración/estados; integración con sandbox y respuestas aceptadas/rechazadas; seguridad de firma, replay, credenciales y archivos; E2E factura/documento POS/nota crédito/nota de ajuste/anulación, rechazo, reenvío y operación offline con sincronización; conciliación de reportes.  
**Criterios:** no se emite sin numeración y autorización vigentes; los estados DIAN son trazables; los reintentos no duplican documentos; los reportes reconcilian con documentos fuente; el recibo impreso no se considera sustituto de una obligación fiscal electrónica.  
**Puerta:** validación normativa y pruebas fiscales completas aprobadas para Colombia antes de habilitar el mercado.

**Salida de Fase 7:** ciclo financiero y fiscal trazable, conciliable y protegido.

---

## 11. Fase 8 — Analytics e inteligencia

**Objetivo:** generar indicadores y análisis confiables sin convertir analítica o IA en una vía de acceso privilegiado a datos.

**Dependencias:** datos operativos estables de Fases 2–7; contratos/eventos; observabilidad.  
**Lotes relacionados:** lote 11 REPORTING, ANALYTICS y AUDIT.

### 8.1 — Datos analíticos y ownership

#### Tareas

- Definir eventos y métricas de negocio con propietarios.
- Separar datos operativos de proyecciones analíticas.
- Definir consistencia, retraso y linaje de indicadores.
- Aplicar minimización y permisos al consumo analítico.
- Evitar consultas directas a schemas ajenos; usar contratos/eventos o mecanismos aprobados.
- Definir moneda, periodo, zona horaria y alcance para cada métrica.

**Dependencias:** 0.6, 0.8 y eventos de módulos productores.  
**Documentos/ADR:** ADR-0001, 0003, 0004, 0013, 0015, 0018, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** catálogo de métricas; linaje; contrato de eventos analíticos; reglas de acceso.  
**Pruebas:** contrato de eventos; integración de retraso/duplicados; seguridad de ámbito; E2E reproducibilidad de indicador.  
**Criterios:** cada métrica tiene definición, unidad, periodo, moneda, propietario y origen.  
**Puerta:** indicadores reproducibles y aislados.

### 8.2 — Dashboards operativos y ejecutivos

#### Tareas

- Construir vistas por sucursal, marca, empresa y consolidado autorizado.
- Mostrar ventas por día/hora/producto/categoría/canal/empleado, ticket promedio, descuentos, márgenes, rentabilidad, inventario/rotación/vencimientos/mermas, compras/proveedores, clientes/fidelización/encuestas, personal/horas/propinas, caja, cocina, domicilios, reservas y ejecuciones de automatización.
- Comparar sucursales, marcas y empresas legales; mostrar metas frente a resultados y distinguir datos reales, estimados y su frescura.
- Definir filtros por fecha/rango, sucursal, empleado, categoría, producto, canal y estado de pedido, con campos seleccionables, agrupaciones, paginación y límites de exportación.
- Mostrar frescura de datos y retraso de actualización.
- Proteger exportaciones y evitar exfiltración masiva.

**Dependencias:** 8.1 y módulos productores.  
**Documentos/ADR:** ADR-0015, 0018, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** dashboards por rol; catálogo de KPIs; reportes descargables controlados.  
**Pruebas:** unitarias de agregaciones; integración de filtros; seguridad BOLA/exportación; E2E de dashboard por rol.  
**Criterios:** cifras tienen definición y frescura visibles; acceso respeta tenant/sucursal; exportaciones tienen límites y auditoría.  
**Puerta:** conciliación de indicadores y controles de exportación aprobados.

### 8.3 — Detección de anomalías y predicciones

#### Tareas

- Definir datos y ventanas de entrenamiento/consulta permitidas.
- Construir detección de anomalías en ventas, caja, descuentos, inventario, compras, tiempos de cocina y demanda.
- Pronosticar demanda de personal por sucursal/turno usando ventas esperadas, pedidos, reservas, productos, ausencias y vacaciones previstas.
- Estimar necesidades de personal; alertar por exceso o falta de cobertura y permitir revisión/ajuste humano.
- Mantener historial de predicciones, supuestos y resultados reales para evaluar calidad.
- Permitir análisis asistido de facturas de proveedor y otros documentos autorizados, con extracción propuesta, validación contra datos de PROCUREMENT y revisión humana; nunca contabilizar automáticamente datos no verificados.
- Medir calidad, falsos positivos y sesgos operativos.
- Mostrar incertidumbre, periodo, fuente y supuestos.
- Mantener decisión humana para acciones de impacto financiero u operativo.

**Dependencias:** 8.1 y 8.2.  
**Documentos/ADR:** ADR-0006, 0015, 0018, 0020, 0021, 0025, 0026.  
**Entregables:** modelos/reglas analíticas; evaluación; explicaciones; controles de acceso.  
**Pruebas:** unitarias de reglas; integración de pipelines; seguridad de aislamiento y exfiltración; E2E de alerta y revisión humana.  
**Criterios:** resultado rastreable; datos no se reutilizan para otra finalidad sin fundamento; predicción no ejecuta acciones privilegiadas.  
**Puerta:** calidad y riesgo residual aceptados por producto.

### 8.4 — Capacidades de IA asistida

#### Tareas

- Definir agentes especializados (ventas, inventario, finanzas, operaciones/cocina, marketing y coordinación AI Manager) como capacidades lógicas, no como seis módulos propietarios ni seis modelos obligatoriamente independientes.
- Definir herramientas autorizadas para consultar ventas, costos, gastos, inventarios, mermas, márgenes, personal, pedidos y reportes mediante contratos de los módulos propietarios.
- Hacer que AI Manager clasifique consultas, delegue, combine resultados, detecte contradicciones y solicite datos cuando sean insuficientes.
- Presentar periodo, sucursales/ámbito, fuentes, datos utilizados, confianza, supuestos y acciones sugeridas.
- No crear schema, tablas ni migraciones propias de AI; cualquier persistencia necesaria pertenece al módulo dueño del proceso y requiere respetar ADR-0006.
- Aplicar autorización del backend propietario en cada acción.
- Limitar contexto, datos y llamadas a proveedores.
- Prevenir prompt injection, exfiltración y uso de herramientas no autorizadas.
- Registrar fuentes, decisiones, aprobaciones y resultados sin guardar secretos.
- Exigir aprobación humana para acciones sensibles.
- Medir costos y aplicar límites para evitar Denial of Wallet.

**Dependencias:** 8.1–8.3, identidad y autorización.  
**Documentos/ADR:** ADR-0006, 0015, 0018, 0019, 0020, 0021, 0023, 0025, 0026.  
**Entregables:** catálogo de herramientas; políticas; trazabilidad; evaluación de seguridad y calidad.  
**Pruebas:** unitarias de autorización; integración de herramientas; seguridad prompt injection/exfiltración; E2E de acción propuesta y aprobación.  
**Criterios:** IA no elude permisos, no obtiene acceso global por ser interna, no posee schema propio y no ejecuta acciones de alto impacto sin aprobación; sus resultados son trazables y no inventan datos ausentes.  
**Puerta:** revisión de seguridad y pruebas adversariales aprobadas.

### 8.5 — REPORTING: informes, plantillas y distribución

#### Tareas

- Implementar REPORTING como propietario de solicitudes, definiciones de informes, plantillas, versiones publicadas inmutables, ejecuciones, artefactos y entregas.
- Generar PDF, XLSX y CSV, además de formatos estructurados autorizados.
- Permitir informes configurables por usuario, empresa y sucursal, con filtros, campos, agrupaciones y comparaciones.
- Programar informes diarios, semanales, mensuales y trimestrales respetando zona horaria y permisos vigentes al ejecutar y entregar.
- Distribuir informes por canales autorizados mediante INTEGRATIONS; REPORTING no almacena credenciales externas.
- Mantener historial de solicitudes, ejecuciones, artefactos y entregas; no guardar archivos binarios en PostgreSQL.
- Exigir permisos y aprobaciones para informes financieros/confidenciales; aplicar límites de tamaño, filas, frecuencia y exportación.
- Registrar en AUDIT solicitudes, accesos, generaciones, exportaciones y descargas; conservar referencias y metadatos sin duplicar el historial propio de REPORTING.

**Dependencias:** 8.1, 8.2, 0.4, 0.8, 9.2 y almacenamiento de objetos de 0.9.  
**Documentos/ADR:** requisitos.md (Grupo J y responsabilidad de Reporting); ADR-0001, 0003, 0015, 0018, 0019, 0020, 0021, 0025, 0026 y 0027.  
**Entregables:** servicio REPORTING; catálogo y plantillas versionadas; programador; artefactos y entregas; matriz de permisos y aprobaciones.  
**Pruebas:** unitarias de plantillas/filtros; integración de generación y almacenamiento; seguridad de exportación, aislamiento y descargas; E2E de programación, entrega, revocación y descarga auditada.  
**Criterios:** artefactos reproducibles, protegidos y versionados; el usuario solo recibe informes dentro de su alcance; las entregas respetan consentimiento y canal autorizado; las descargas quedan auditadas.  
**Puerta:** generación, autorización, retención y distribución demostradas de extremo a extremo.

### 8.6 — AUDIT: auditoría de accesos y evidencias

#### Tareas

- Implementar AUDIT como propietario de los registros de auditoría de seguridad y de los eventos de acceso/consulta/generación/exportación/descarga que le correspondan por contrato.
- Mantener separados auditoría, logs operativos, métricas/trazas e historial de negocio.
- Recibir eventos mediante contratos versionados y entrega durable/idempotente; no consultar directamente schemas ajenos.
- Conservar actor/identidad de servicio, acción, recurso, tenant/sucursal cuando aplique, resultado, instante, motivo y correlación mínima necesaria.
- Proteger integridad, acceso, búsqueda, retención y exportación de evidencias.
- Mantener el historial de cada módulo bajo su propio ownership; AUDIT no crea una tabla compartida que sustituya los historiales de los módulos ni permite escrituras directas ajenas.
- Correlacionar eventos con W3C Trace Context sin confundir trace_id con actor, evidencia o causalidad.

**Dependencias:** 0.4, 0.8, Outbox/Inbox, 8.5 y contratos de todos los módulos productores.  
**Documentos/ADR:** requisitos.md (AUDIT y Grupo J); ADR-0001, 0003, 0004, 0014, 0015, 0018, 0020, 0021 y 0026.  
**Entregables:** contratos de auditoría; registro de eventos de seguridad y accesos; políticas de integridad/retención; consultas y exportación controlada; runbooks de investigación.  
**Pruebas:** unitarias de clasificación/redacción; integración de entrega durable, deduplicación e integridad; seguridad de acceso y manipulación; E2E reconstrucción de una acción sensible y descarga de evidencia.  
**Criterios:** cada acción sensible puede reconstruirse; no se almacenan secretos ni payloads sensibles innecesarios; AUDIT no sustituye el historial propio de cada módulo.  
**Puerta:** trazabilidad y consulta restringida verificadas sin crear persistencia compartida.

**Salida de Fase 8:** dashboards y análisis reproducibles, con IA limitada por permisos y supervisión.

---

## 12. Fase 9 — Automatización e integraciones

**Objetivo:** automatizar procesos y conectar proveedores/canales externos con aislamiento, límites y trazabilidad.

**Dependencias:** eventos estables, Fases 2–8, contratos y autorización.  
**Lotes relacionados:** capacidades de AUTOMATION e INTEGRATIONS; canales externos.

### 9.1 — AUTOMATION: motor de reglas y flujos

#### Tareas

- Definir disparadores, condiciones, acciones, versiones y estados.
- Gestionar aprobaciones y límites de ejecución.
- Aplicar idempotencia, reintentos, backoff y DLQ.
- Asegurar que las automatizaciones ejecuten comandos mediante contratos de módulos propietarios.
- Evitar acceso directo a bases de datos o secretos de otros módulos.
- Permitir pausa, cancelación y auditoría de flujos.

**Dependencias:** 0.6, 0.8 y eventos de Fases 2–8.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** motor de automatización; catálogo de disparadores; historial de ejecuciones; controles de aprobación.  
**Pruebas:** unitarias de reglas; integración de eventos; seguridad de permisos/abuso; E2E con fallo, reintento y cancelación.  
**Criterios:** duplicados no repiten efectos; cada acción pasa por autorización del módulo propietario; ejecuciones limitadas por tenant y recursos.  
**Puerta:** recuperación y límites probados.

### 9.2 — INTEGRATIONS: credenciales y conectores

#### Tareas

- Gestionar credenciales por tenant/proveedor/entorno.
- Implementar ciclo de emisión, rotación, expiración y revocación.
- Validar firmas, callbacks, esquemas y versiones externas.
- Aplicar anti-SSRF y egress restringido para destinos controlables.
- Aislar datos de cada integración y limitar scopes.
- Gestionar fallos, rate limits y reintentos de proveedores.

**Dependencias:** 0.5, 0.7, 0.8 y módulos consumidores.  
**Documentos/ADR:** ADR-0019, 0020, 0021, 0023, 0024, 0025, 0026.  
**Entregables:** framework de conectores; almacén de secretos; inventario de proveedores; runbooks.  
**Pruebas:** contrato con sandbox/proveedor; integración de rotación; seguridad SSRF/replay/credenciales; E2E revocación y fallo de proveedor.  
**Criterios:** ningún secreto aparece en logs/frontend; cada conector tiene scope mínimo y propietario; respuestas externas se consideran no confiables.  
**Puerta:** evaluación de seguridad por proveedor superada.

### 9.3 — API pública, webhooks y canales digitales

#### Tareas

- Publicar APIs versionadas y documentación.
- Definir autenticación, scopes, cuotas y límites por cliente.
- Firmar y proteger webhooks, reintentos y replay.
- Recibir pedidos desde web, aplicación propia, WhatsApp Business y plataformas/marketplaces externos; normalizar canal, sucursal y cliente en el contrato de SALES y deduplicar reintentos.
- Gestionar domicilios: repartidores internos/externos, asignación manual y automática por disponibilidad/zona, cobertura, tarifas por sucursal/zona, direcciones, referencias y notas.
- Mantener estados e historial de entrega: recibido, confirmado, preparación, listo, asignado, recogido, en camino, entregado, cancelado/rechazado e incidencias.
- Registrar marcas de tiempo de recepción, confirmación, salida de cocina, asignación, salida del repartidor y entrega; calcular tiempos y alertas de retraso.
- Respetar disponibilidad, precios, promociones e inventario de la sucursal; asignar la sucursal por zona o selección autorizada.
- Proteger exportación de datos y endpoints de alto costo.
- Aplicar controles anti-bot y DDoS en el borde y límites internos.

**Dependencias:** 2.2, 2.5, 3.1, 6.3, 9.2.  
**Documentos/ADR:** ADR-0002, 0019, 0020, 0021, 0022, 0024, 0025, 0026.  
**Entregables:** API pública; portal de desarrolladores si corresponde; webhooks; catálogo de límites.  
**Pruebas:** contrato y compatibilidad; integración de firma/replay; seguridad BOLA, rate limit, scraping y exportación; E2E de canal externo.  
**Criterios:** no se publican endpoints sin autorización, cuotas y contrato; webhook duplicado no duplica efectos.  
**Puerta:** pruebas de abuso y compatibilidad aprobadas.

### 9.4 — Pagos, fiscalidad, mensajería y proveedores externos

#### Tareas

- Implementar conectores concretos habilitados por mercado y contrato: pasarelas de pago, DIAN/proveedores de facturación, WhatsApp Business, correo, SMS, Google Maps, plataformas/marketplaces de delivery, reservas, sistemas contables, analítica externa y automatizadores externos.
- Para WhatsApp, cubrir recepción/confirmación de pedidos, notificaciones, estados de domicilio y atención al cliente, respetando consentimiento y asociación autorizada con cliente/pedido.
- Para mapas, cubrir validación de direcciones, distancias, tiempos estimados, zonas de cobertura, tarifas y ubicación de domicilios.
- Para plataformas externas, sincronizar catálogo/precios/promociones autorizados, normalizar pedidos, devolver estados y conservar estado original del canal.
- Mantener la separación de ownership: PAYMENTS posee operaciones financieras; BILLING posee documentos fiscales y su ciclo de vida; INTEGRATIONS implementa transporte, credenciales, callbacks y normalización externa; SALES conserva pedidos y su estado comercial.
- Revisar contrato, finalidad, datos, ubicación, retención y subencargados.
- Definir fallback y reconciliación por proveedor.
- Limitar consumo/costos y proteger credenciales.
- Mantener inventario de dependencias y proveedores.

**Dependencias:** 7.1, 9.2 y 9.3.  
**Documentos/ADR:** ADR-0015, 0018, 0019, 0020, 0023, 0025, 0026, 0027.  
**Entregables:** integraciones productivas aprobadas; fichas de proveedor; procedimientos de contingencia.  
**Pruebas:** integración/sandbox; seguridad de callbacks y archivos; carga y límites; E2E de contingencia.  
**Criterios:** no se habilita proveedor sin evaluación de seguridad/privacidad/contrato; fallos no provocan duplicación o pérdida silenciosa; cada integración tiene propietario funcional, credenciales y alcance por tenant/sucursal, consentimiento cuando aplique y reconciliación verificable.  
**Puerta:** aprobación por proveedor y evidencia de pruebas.

### 9.5 — Hardware, dispositivos y periféricos operativos

#### Tareas

- Integrar dispositivos POS, impresoras de tickets/documentos, impresoras de cocina, lectores de códigos, cajones de dinero, pantallas KDS y terminales de pago.
- Registrar y provisionar cada dispositivo por tenant, sucursal, caja y función antes de habilitar operación offline; permitir activación, desactivación, revocación y reasignación autorizada.
- Validar la identidad del dispositivo mediante credenciales/provisión confiables al sincronizar; el identificador enviado por el navegador no constituye prueba de identidad ni autorización.
- Mantener estado de conexión, compatibilidad, salud, última comunicación y alertas de desconexión.
- Configurar impresoras por tipo de documento/estación y mantener plantillas/versiones de impresión.
- Coordinar terminales de pago con PAYMENTS e INTEGRATIONS sin almacenar datos sensibles de tarjeta ni convertir el hardware en fuente de verdad financiera.
- Permitir impresión local offline conforme a la política de 0.10/2.6 y distinguir comprobantes locales de documentos fiscales válidos.
- Aislar comandos y control de dispositivos por sucursal, usuario y permiso; no exponer interfaces de administración de hardware públicamente.

**Dependencias:** 1.2, 1.5, 2.5, 2.6, 3.3, 7.1, 9.2 y 0.7.  
**Documentos/ADR:** requisitos.md (Grupo L — Hardware y configuración de dispositivos); ADR-0008, 0019, 0020, 0021, 0022, 0023, 0025, 0026 y 0027 cuando procese documentos.  
**Entregables:** inventario/provisionamiento de dispositivos; adaptadores de periféricos; configuración de impresión; estado y alertas; procedimientos de reemplazo/revocación.  
**Pruebas:** unitarias de estados y permisos; integración con simuladores y hardware representativo; seguridad de emparejamiento, comandos y aislamiento; E2E impresión de ticket/comanda, lectura de código, apertura autorizada de cajón y operación degradada.  
**Criterios:** un dispositivo no puede operar en otra sucursal sin autorización; desconexiones son visibles; los comandos no duplican cobros ni operaciones; la impresión no altera el estado fiscal.  
**Puerta:** periféricos críticos probados en escenarios normales, desconexión y recuperación.

**Salida de Fase 9:** automatizaciones e integraciones operan con límites, permisos, idempotencia y trazabilidad.

---

## 13. Fase 10 — Escala, resiliencia y portal cliente

**Objetivo:** preparar operación de mayor volumen, continuidad, alta disponibilidad y portal de autoservicio.

**Dependencias:** Fases 0–9; infraestructura, observabilidad, seguridad y procesos de recuperación.  
**Nota:** esta fase amplía resiliencia; no posterga fundamentos offline-first ni controles de seguridad que deben existir desde fases anteriores.

### 10.1 — Portal de clientes y autoservicio

#### Tareas

- Habilitar consulta de perfil, historial, reservas, pedidos y seguimiento.
- Gestionar preferencias y consentimiento.
- Asegurar separación entre clientes y tenants.
- Aplicar autenticación, sesiones, rate limits y protección antiabuso.
- Limitar información mostrada según relación y finalidad.

**Dependencias:** 1.3, 1.4, 6.3, 6.4, 9.3.  
**Documentos/ADR:** ADR-0018, 0019, 0020, 0021, 0022, 0025, 0026.  
**Entregables:** portal; gestión de preferencias; flujos de pedidos/reservas.  
**Pruebas:** unitarias; integración de perfil; seguridad BOLA/IDOR y sesiones; E2E cliente autenticado/no autenticado.  
**Criterios:** cliente solo ve sus datos y operaciones autorizadas; revocación y derechos están disponibles.  
**Puerta:** seguridad de cuenta y aislamiento validados.

### 10.2 — Escala de sincronización offline

#### Tareas

- Probar múltiples terminales, desconexiones prolongadas y grandes colas.
- Definir límites, backpressure y prioridades de sincronización.
- Gestionar conflictos con reglas deterministas y revisión humana.
- Evitar duplicados y pérdida de operaciones ante fallos.
- Medir latencia, retraso, tamaño de cola y tasa de conflictos.
- Mostrar por dispositivo/sucursal las operaciones pendientes, sincronizadas, confirmadas, fallidas y en conflicto, sin presentar pendientes como operaciones confirmadas.

**Dependencias:** 2.6 y 0.10.  
**Documentos/ADR:** ADR-0003, 0013, 0015, 0019, 0020, 0021, 0025, 0026.  
**Entregables:** política de sincronización a escala; panel de salud; herramientas de conciliación.  
**Pruebas:** carga, resiliencia, integración y E2E multi-dispositivo; seguridad de contexto y almacenamiento local.  
**Criterios:** cola recuperable; conflictos visibles; no se pierden ni duplican efectos confirmados.  
**Puerta:** pruebas prolongadas y de carga superadas.

### 10.3 — Alta disponibilidad y recuperación ante desastres

#### Tareas

- Desplegar y verificar PostgreSQL HA, Redis Cluster y NATS HA según ADR.
- Probar failover, fencing, quorum y recuperación.
- Verificar backups, WAL, PITR y restauración.
- Probar recuperación de objetos y metadatos.
- Definir runbooks, responsables y comunicaciones.
- Validar RPO/RTO acordados para cada servicio y flujo crítico.

**Dependencias:** 0.6–0.9; infraestructura desplegable y observabilidad.  
**Documentos/ADR:** ADR-0010, 0012, 0015, 0016, 0017, 0023, 0026, 0027.  
**Entregables:** clústeres HA; backups probados; runbooks; informe de recuperación.  
**Pruebas:** failover, restore, PITR, pérdida de nodo/zona, expiración de certificado y recuperación de streams/objetos.  
**Criterios:** no hay split-brain; recuperación cumple objetivos aprobados; réplica no sustituye backup; evidencias disponibles.  
**Puerta:** ejercicio de desastre aprobado.

### 10.4 — Rendimiento, límites y optimización

#### Tareas

- Medir perfiles de carga por servicio/módulo y rutas críticas.
- Dimensionar pools, workers, conexiones, shards, streams, caché y almacenamiento.
- Afinar índices según consultas reales y métricas.
- Aplicar particionamiento solo cuando volumen y evidencia lo justifiquen.
- Optimizar consultas, paginación, exportaciones y fan-out.
- Verificar cuotas por tenant, usuario, proceso y proveedor.
- Controlar Denial of Wallet y degradación.

**Dependencias:** fases funcionales completas y telemetría fiable.  
**Documentos/ADR:** ADR-0010, 0015, 0016, 0017, 0020, 0023, 0025.  
**Entregables:** pruebas de carga; presupuesto de recursos; perfil de capacidad; plan de optimización.  
**Pruebas:** carga, estrés, soak, concurrencia, degradación y seguridad de agotamiento de recursos.  
**Criterios:** SLO y límites medidos; no hay agotamiento ilimitado ni degradación en cascada; optimizaciones justificadas por datos.  
**Puerta:** capacidad aprobada para el volumen objetivo.

### 10.5 — Seguridad avanzada y pruebas adversariales

#### Tareas

- Ejecutar pentest de aplicaciones, APIs, sesiones, infraestructura y multi-tenancy.
- Ejecutar pruebas de abuso, DDoS controlado, scraping y exfiltración.
- Revisar supply chain, SBOM, procedencia, firmas y artefactos.
- Revisar configuración de red, secretos, contenedores y almacenamiento.
- Revisar auditoría, alertas y respuesta a incidentes.
- Corregir hallazgos y repetir pruebas.

**Dependencias:** controles de fases anteriores; entorno de preproducción representativo.  
**Documentos/ADR:** ADR-0020 a ADR-0027; ADR-0015, 0018 y 0019.  
**Entregables:** informe de seguridad; SBOM/procedencia; registro de hallazgos; evidencia de remediación; aprobación de riesgo residual.  
**Pruebas:** SAST, DAST, SCA, secret scanning, fuzzing, pentest, pruebas de aislamiento y simulación de incidentes.  
**Criterios:** cero hallazgos críticos/altos sin remediar o aceptación formal; ninguna fuga cross-tenant; artefacto probado idéntico al promovido.  
**Puerta:** seguridad autoriza la transición a preparación final de lanzamiento.

### 10.6 — Auditoría, continuidad y operación

#### Tareas

- Verificar cobertura de eventos auditables.
- Ejecutar ejercicios de respuesta a incidentes y recuperación.
- Validar rotación/revocación de secretos.
- Verificar alertas, guardias, runbooks y escalamiento.
- Revisar retención de logs, métricas, trazas y auditoría.
- Validar continuidad de proveedores y restauración de integraciones.

**Dependencias:** 0.8 y 10.3–10.5.  
**Documentos/ADR:** ADR-0015, 0018, 0023, 0026, 0027.  
**Entregables:** informe operativo; runbooks aprobados; evidencias de ejercicios; plan de continuidad.  
**Pruebas:** tabletop, simulación, restore, alerta sintética y auditoría de accesos.  
**Criterios:** incidentes críticos tienen responsable, canal, procedimiento y evidencia; auditoría íntegra y accesible solo a roles autorizados.  
**Puerta:** operación y continuidad aprobadas.

**Salida de Fase 10:** plataforma escalable, recuperable, medida y sometida a pruebas de seguridad avanzadas.

---

### 10.7 — Modalidades de infraestructura y migración de tenants

#### Tareas

- Habilitar el modelo de despliegue por tenant definido en requisitos.md: Shared Cloud (aplicación y base compartidas con aislamiento tenant), Dedicated Database (aplicación compartida y base independiente) y Dedicated Environment (aplicación, base y recursos dedicados).
- Mantener en PLATFORM únicamente el control de modalidad, región, estado y referencias seguras de infraestructura; no almacenar contraseñas ni secretos, solo referencias al gestor de secretos.
- Definir el ciclo de aprovisionamiento, validación, suspensión, cambio de modalidad y retiro de cada despliegue.
- Diseñar migración de tenant entre modalidades sin reconstruir sus datos: compatibilidad de esquema, preparación de destino, migración por módulo propietario, sincronización inicial e incremental, ventana de corte, sincronización final, cambio de destino y reversión controlada.
- Preservar usuarios, empresas, sucursales, catálogo, recetas, pedidos, inventario, documentos, auditoría, suscripciones y configuración, conforme a sus respectivos módulos propietarios.
- Verificar conteos, totales financieros, existencias, pedidos, pagos, documentos fiscales, archivos/metadatos, auditoría, suscripciones y configuración antes de habilitar destino.
- Mantener las mismas versiones/modelos de dominio y migraciones por módulo; cada módulo conserva schema, rol e historial SQLx independiente también en bases dedicadas.
- No compartir `_sqlx_migrations`, no mover ownership a PLATFORM y no ejecutar consultas/escrituras cruzadas entre schemas como atajo de migración.
- Definir estrategia de rollback, reconciliación y tratamiento de operaciones concurrentes durante el corte.

**Dependencias:** 0.1, 0.6, 0.7, 0.8, 1.1 y módulos propietarios; requiere que los flujos de datos y backups estén operativos.  
**Documentos/ADR:** requisitos.md (Infraestructura compartida y dedicada); ADR-0001, 0007, 0008, 0010, 0012, 0014, 0015, 0023, 0024, 0026 y 0027.  
**Entregables:** catálogo de modalidades; control de despliegues; runbook de migración; herramienta/procedimiento por módulo; matriz de integridad; procedimiento de rollback y evidencias.  
**Pruebas:** integración de aprovisionamiento; ensayo completo de migración entre las tres modalidades; comparación de datos y totales; seguridad de credenciales/red/archivos; carga y concurrencia durante corte; E2E tenant migrado y verificación de acceso/operación.  
**Criterios:** no se activa destino con diferencias sin resolver; ninguna credencial queda en datos de control; ownership y aislamiento se mantienen; rollback es ejecutable y probado.  
**Puerta:** migración ensayada y conciliada antes de ofrecer modalidades dedicadas a clientes.

## 14. Fase final — Privacidad, cumplimiento legal y lanzamiento a producción

**Objetivo:** cerrar documentación legal, configuración de consentimiento, validación jurídica por mercado y Go/No-Go. Esta fase es la última antes de habilitar producción y comercialización por jurisdicción.

**Dependencias:** fases funcionales y técnicas anteriores; inventario real de datos, proveedores, superficies y mercados.  
**No sustituye:** los controles de privacidad, minimización, aislamiento, seguridad, auditoría, retención y eliminación que se diseñan y construyen desde fases anteriores.

### F.1 — Inventario final de tratamientos y mercados

#### Tareas

- Confirmar jurisdicciones, mercados, tipos de cliente y superficies.
- Completar inventario por módulo de datos, finalidad, sensibilidad, base/justificación, destinatarios y retención.
- Identificar roles de Restaurant OS y tenant por actividad.
- Inventariar proveedores, subencargados, transferencias, cookies y SDKs.
- Verificar que el comportamiento real coincide con el inventario.

**Dependencias:** fases 1–10 y ADR-0018.  
**Documentos/ADR:** ADR-0014, 0015, 0018, 0020, 0023, 0026, 0027.  
**Entregables:** inventario aprobado; mapa de tratamientos; matriz de proveedores y transferencias.  
**Pruebas:** revisión de evidencia y muestreo de flujos; verificación de configuración real.  
**Criterios:** cada tratamiento y proveedor tiene finalidad, rol, datos y responsable identificados.  
**Puerta:** inventario completo y validado.

### F.2 — Matriz de retención y eliminación

#### Tareas

- Definir plazos/criterios por categoría, finalidad, módulo y jurisdicción con revisión legal.
- Definir triggers, acciones, excepciones y legal hold.
- Definir tratamiento de respaldos y restauraciones.
- Verificar baja de tenant conforme ADR-0014 y eliminación individual separada.
- Definir evidencias y acceso restringido.

**Dependencias:** F.1; ownership por módulo.  
**Documentos/ADR:** ADR-0014, 0018, 0020, 0026, 0027.  
**Entregables:** matriz de retención; procedimientos de eliminación; flujo de legal hold.  
**Pruebas:** integración de ciclo de vida; seguridad de acceso; E2E solicitud y evidencia de eliminación/retención.  
**Criterios:** no hay retención indefinida por defecto ni eliminación de documentos legalmente retenibles; restauración no revive datos ya eliminados sin reconciliación.  
**Puerta:** matriz y procesos aprobados por legal y producto.

### F.3 — Documentos y contratos legales

#### Tareas

- Redactar política de privacidad.
- Redactar política de retención y eliminación.
- Redactar términos SaaS y términos de usuarios finales cuando aplique.
- Preparar DPA/anexo de tratamiento cuando corresponda.
- Redactar política de cookies y tecnologías similares.
- Preparar avisos contextuales por formulario, registro, pagos, marketing, soporte e integraciones.
- Versionar documentos y conservar historial de publicación.

**Dependencias:** F.1 y F.2.  
**Documentos/ADR:** ADR-0018; ADR-0014, 0020, 0023, 0026.  
**Entregables:** paquete legal definitivo por mercado/servicio; versiones y fechas de vigencia.  
**Pruebas:** revisión jurídica, consistencia entre contrato y comportamiento, enlaces y accesibilidad.  
**Criterios:** documentos no prometen controles inexistentes; roles y finalidades coinciden con tratamiento real.  
**Puerta:** aprobación jurídica por jurisdicción y aprobación de negocio.

### F.4 — Banner, preferencias y consentimiento

#### Tareas

- Configurar banner y centro de preferencias según jurisdicción y superficie.
- Clasificar tecnologías necesarias, preferencias, analítica y marketing.
- Aplicar consentimiento previo donde corresponda.
- Ofrecer aceptación y rechazo con facilidad comparable y elección granular cuando aplique.
- Habilitar revocación accesible.
- Registrar versión del aviso, elección, timestamp y contexto mínimo.
- Verificar SDKs, cookies, tags y terceros realmente cargados.
- No agrupar aceptación de términos, privacidad y cookies.

**Dependencias:** F.3 y frontend de Fases 1–9.  
**Documentos/ADR:** ADR-0018, 0019, 0020, 0022, 0024, 0026.  
**Entregables:** banner y centro de preferencias configurados; inventario técnico de tecnologías; evidencia de consentimiento.  
**Pruebas:** E2E aceptar/rechazar/revocar; seguridad de manipulación de consentimiento; accesibilidad y dispositivos; verificación de no carga previa de tecnologías no esenciales cuando aplique.  
**Criterios:** elección se respeta; revocación detiene usos futuros no esenciales; no se infiere consentimiento del silencio.  
**Puerta:** pruebas y revisión legal completadas.

### F.5 — Derechos, incidentes y proveedores

#### Tareas

- Verificar canales y procedimientos de acceso, rectificación, oposición, portabilidad, limitación, retiro y eliminación según jurisdicción.
- Verificar identidad y routing al módulo propietario.
- Probar respuesta a incidentes y plazos de notificación aplicables.
- Revisar contratos y subencargados.
- Confirmar medidas de seguridad y eliminación al terminar servicios de proveedores.

**Dependencias:** F.1–F.4 y 10.6.  
**Documentos/ADR:** ADR-0014, 0015, 0018, 0020, 0023, 0026, 0027.  
**Entregables:** procedimientos; responsables; acuerdos; inventario de subencargados; ejercicios y evidencias.  
**Pruebas:** E2E de derechos; tabletop de incidente; pruebas de baja de proveedor y revocación de credenciales.  
**Criterios:** cada solicitud/incidente tiene dueño, plazo, canal y evidencia; datos preservados se limitan a finalidad legal.  
**Puerta:** responsables y procedimientos operativos confirmados.

### F.6 — Go/No-Go por jurisdicción

#### Tareas

- Revisar todas las puertas anteriores.
- Confirmar que los artefactos desplegados corresponden al commit y build probados.
- Confirmar backups, restauración, observabilidad, seguridad, guardias y runbooks.
- Confirmar ausencia de hallazgos críticos/altos no resueltos o aceptados formalmente.
- Obtener aprobación de producto, ingeniería, seguridad, operaciones y asesoría jurídica.
- Conservar acta de Go/No-Go y evidencias.

**Dependencias:** F.1–F.5 y Fase 10.  
**Documentos/ADR:** ADR-0018 y ADR-0020 a ADR-0027; todos los ADR aplicables a la superficie lanzada.  
**Entregables:** checklist Go/No-Go; aprobaciones; evidencias; plan de rollback y comunicación.  
**Pruebas:** regresión completa; integración; seguridad; E2E; carga; restore; smoke tests del release.  
**Criterios:** no se lanza mercado/superficie con requisitos legales, controles o aprobaciones pendientes; el artefacto publicado es el probado; existe rollback y soporte operativo.  
**Puerta final:** autorización explícita de lanzamiento por mercado. La aprobación de un mercado no autoriza automáticamente otros.

---

## PARTE II — SEGURIDAD INTEGRADA EN TODAS LAS FASES

## 15. Matriz de integración de ADR de seguridad

Los ADR siguientes no se ejecutan como un proyecto aislado al final. Sus controles se introducen en Fase 0 y se implementan/proban en cada fase que incorpora la superficie correspondiente.

| ADR | Decisión aceptada | Fases/subfases donde se materializa | Evidencia de salida |
|---|---|---|---|
| ADR-0020 | Marco integral y defensa en profundidad | 0.3–0.9; todas las fases; 10.5; F.6 | Modelo de amenazas, controles por frontera, riesgos y pruebas |
| ADR-0021 | RBAC/ABAC y aislamiento multi-tenant | 0.4; 1.2–1.5; todas las operaciones; 10.5 | Matriz de permisos, pruebas BOLA/IDOR y tenant cruzado |
| ADR-0022 | Frontend, navegador, sesiones y APIs de borde | 1.3; 2.5–2.6; 6.4; 9.3; 10.1; F.4 | Pruebas CSRF/XSS/CSP/CORS/sesiones y consentimiento |
| ADR-0023 | Infraestructura, redes, secretos y criptografía | 0.7; 0.9; despliegues de todas las fases; 10.3–10.5; 10.7 | Flujos de red, TLS, rotación, hardening, backup cifrado |
| ADR-0024 | Desarrollo seguro, CI/CD y supply chain | 0.2; todos los PR/build/release; 10.5; F.6 | Rulesets, CI, SCA, SBOM, procedencia y artefactos verificados |
| ADR-0025 | Abuso de APIs, bots, DDoS y exfiltración | 0.5; 1.4; 2.5; todas las APIs; 8.2–8.6; 9.1–9.5; 10.4–10.7 | Rate limits, cuotas, backpressure, límites de exportación y pruebas |
| ADR-0026 | Auditoría, detección y respuesta a incidentes | 0.8; operaciones sensibles en todas las fases; 8.6; 10.6–10.7; F.5–F.6 | Eventos de auditoría, alertas, runbooks, ejercicios y evidencias |
| ADR-0027 | Archivos, documentos y object storage | 0.9; 2.1; 5.1; 6.1; 7.1; 8.5; 9.4; 10.3; 10.7; F.1–F.5 | Validación, cuarentena, autorización, integridad, retención y descarga segura |

### 15.1 Controles que nunca se aplazan

- Autorización en backend propietario y aislamiento multi-tenant.
- Validación de entradas en cada frontera y en el módulo consumidor.
- DTO específicos y protección contra mass assignment.
- Gestión segura de sesiones, cookies y secretos.
- TLS y mínimo privilegio en toda comunicación desplegada.
- Idempotencia y manejo de duplicados en operaciones durables.
- Auditoría de acciones sensibles.
- Logs y trazas sin secretos ni payloads personales sensibles.
- Límites de recursos y protección antiabuso.
- Protección de archivos desde la primera función que los acepte.
- Backups y recuperación probados antes de depender de datos productivos.
- Privacidad por diseño, minimización y ownership de datos desde su primera captura.

### 15.2 Pruebas de seguridad transversales obligatorias

Cada fase debe seleccionar y ejecutar las pruebas que correspondan a su superficie:

- Autenticación, sesión, revocación y elevación.
- RBAC/ABAC, BOLA/IDOR y acceso entre tenants/sucursales.
- Mass assignment, campos desconocidos, tipos y límites.
- SQL/command injection, XSS, CSRF, SSRF y traversal.
- CORS, CSP, WebSockets y cookies.
- Rate limiting, cuotas, scraping, concurrencia y agotamiento de recursos.
- Replay, duplicados, eventos falsificados y fuera de orden.
- Secretos, TLS, certificados, permisos de red y contenedores.
- Dependencias vulnerables, workflows, SBOM, procedencia y artefactos.
- Archivos maliciosos, bombas de descompresión, acceso y descarga.
- Exportación masiva, exfiltración y abuso de herramientas de IA.
- Auditoría, alertas, respuesta a incidentes y restauración.

---

## 16. Matriz de dependencias funcionales y técnicas

| Capacidad | Depende de | No puede avanzar si falta |
|---|---|---|
| PLATFORM | identidad de servicios, límites, auditoría, persistencia propia | ownership PLATFORM, autorización, baja segura |
| ORGANIZATION | PLATFORM, identidad, contexto tenant | jerarquía y aislamiento |
| IDENTITY | contexto confiable, seguridad web, auditoría | autenticación y revocación seguras |
| CATALOG | ORGANIZATION, autorización, validación, archivos si aplica | ownership y contratos |
| SALES | CATALOG, ORGANIZATION, IDENTITY, CASH/PAYMENTS según flujo | idempotencia, estados y permisos |
| PAYMENTS | SALES, proveedor, secretos, reconciliación | idempotencia y manejo de resultado incierto |
| CASH | identidad, SALES/PAYMENTS | ledger de caja y autorización |
| KITCHEN | SALES, recursos, eventos | contrato y deduplicación |
| PRODUCTION | CATALOG e INVENTORY por contratos | versión de receta y ledger |
| INVENTORY | ORGANIZATION, CATALOG, concurrencia | movimientos trazables |
| PROCUREMENT | proveedores, INVENTORY, aprobaciones | segregación y conciliación |
| WORKFORCE | ORGANIZATION e IDENTITY | privacidad y alcance por sucursal |
| CUSTOMERS | IDENTITY, SALES y privacidad | ownership y derechos |
| BILLING | SALES/PAYMENTS, datos fiscales, jurisdicción | numeración y trazabilidad |
| FINANCE | fuentes financieras, BILLING/CASH/PROCUREMENT | asientos y reversos |
| ANALYTICS | eventos y datos de módulos propietarios | definición/linaje y permisos |
| REPORTING | métricas, autorización y límites de exportación | consistencia y seguridad de datos; 8.5 define plantillas, artefactos, programación y distribución |
| AUDIT | eventos de acceso/seguridad y evidencia propia | ownership, integridad, retención y consulta restringida; 0.8 y 8.6 |
| AUTOMATION | eventos, contratos, autorización e idempotencia | límites y recuperación |
| INTEGRATIONS | secretos, contratos externos, anti-SSRF y conectividad de hardware | evaluación de proveedor y dispositivos por sucursal |
| AUDIT | ownership de eventos, integridad y acceso restringido | evidencia y retención |

Esta tabla indica dependencias de capacidad, no autoriza a inventar dependencias crate-a-crate ni consultas directas. Toda dependencia de implementación se justifica por caso de uso y contrato.

---

## 17. Criterios globales de aceptación del producto

Antes de considerar el producto listo para lanzamiento deben verificarse, como mínimo:

1. Dos tenants no pueden acceder a datos del otro mediante APIs, UI, workers, eventos, archivos, cachés, exportaciones o consultas.
2. Un usuario solo opera en tenants, empresas, marcas y sucursales autorizados.
3. Los cuatro procesos mantienen límites e identidades separados.
4. Cada módulo conserva ownership de datos, schema, rol, migraciones e historial SQLx.
5. Los BFF no consultan directamente PostgreSQL de negocio.
6. Las operaciones financieras son idempotentes y conciliables.
7. Una venta actualiza los módulos participantes mediante contratos y consistencia distribuida; los fallos parciales se recuperan.
8. El inventario se reconstruye desde movimientos y las recetas están versionadas.
9. Caja, pagos, devoluciones, facturas y asientos mantienen estados y trazabilidad separados.
10. Los eventos duplicados o fuera de orden no duplican efectos.
11. El flujo offline recupera operaciones tras reinicio y reconexión sin pérdida ni duplicación.
12. Los respaldos pueden restaurarse y se ha probado recuperación ante desastre.
13. Los controles de seguridad ADR-0020 a ADR-0027 tienen evidencia verificable.
14. La validación de entradas conforme ADR-0019 se aplica a HTTP, gRPC, workers, mensajería e integraciones.
15. Auditoría permite reconstruir acciones sensibles sin almacenar secretos ni datos innecesarios.
16. Los archivos y documentos tienen autorización, integridad, retención y ciclo de vida.
17. Los reportes y exportaciones respetan permisos, límites y privacidad.
18. Los procedimientos de incidentes, derechos y retención están probados.
19. El paquete legal y de consentimiento está aprobado por mercado.
20. El artefacto lanzado es el mismo artefacto probado y cuenta con rollback.
21. La facturación colombiana cubre documentos DIAN/POS aplicables, notas, anulaciones, impuestos, rangos autorizados, respuestas y contingencia offline.
22. Los pedidos digitales y domicilios conservan canal, sucursal, repartidor, zonas/tarifas, estados, tiempos, incidencias y deduplicación.
23. Nómina y compensaciones son calculadas/pagadas por FINANCE a partir de datos laborales de WORKFORCE, sin crear un módulo PAYROLL adicional.
24. REPORTING genera, programa, distribuye y protege PDF/XLSX/CSV; AUDIT registra accesos, solicitudes, generaciones y descargas sin sustituir historiales propios.
25. Los periféricos POS y las tres modalidades de infraestructura están provisionados, aislados y probados; migraciones dedicadas se concilian y tienen rollback.

---

## 18. Evidencia y cierre de cada subfase

Cada subfase debe cerrar con un registro de evidencia que contenga:

- Identificador de fase/subfase.
- Objetivo y alcance implementado.
- Módulos y procesos afectados.
- ADR y documentos aplicados.
- PRs y commits correspondientes.
- Entregables y versiones de contratos.
- Pruebas ejecutadas, resultado y enlaces a ejecuciones.
- Hallazgos, severidad, correcciones y riesgos residuales.
- Evidencia de seguridad y privacidad.
- Decisión de aceptación y responsable.
- Dependencias habilitadas para la siguiente subfase.

No se acepta como evidencia una lista de pruebas planeadas, un workflow sin ejecución o un ADR sin implementación. Se debe diferenciar claramente diseño, implementación, despliegue y operación verificada.

---

## 19. Exclusiones y límites

Este documento es un plan de trabajo; no constituye autorización para:

- Implementar código, crates, endpoints, workflows o infraestructura ahora.
- Crear o modificar archivos SQL, migraciones, schemas, roles o datos.
- Cambiar ownership o mover módulos.
- Fusionar PRs.
- Seleccionar bibliotecas o proveedores que los ADR dejan abiertos.
- Inventar límites numéricos, SLO, RPO/RTO o plazos legales.
- Considerar implementado un control por existir documentación.
- Posponer controles de seguridad a la última fase.
- Convertir los BFF en propietarios de negocio.
- Crear tablas compartidas de historial, auditoría o persistencia para reemplazar ownership de módulos.

Las estimaciones temporales del ROADMAP.md son orientativas y deben recalcularse cuando existan equipo, alcance, capacidad y dependencias reales. La fase legal final depende además de mercados y asesoría jurídica.

---

## 20. Documentos de referencia

- [ROADMAP.md](../../ROADMAP.md)
- [requisitos.md](../../requisitos.md)
- [promt.md](../../promt.md)
- [Índice de ADR](../adr/README.md)
- [Índice de arquitectura](../architecture/README.md)
- [Estándar general de ingeniería](../architecture/engineering-standard.md)
- [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md)
- [Diseño de crates y dependencias](../architecture/crate-architecture.md)
- [Reglas de implementación](../engineering/implementation-rules.md)
- [Calidad y seguridad documental](../engineering/documentation-quality-and-security-standard.md)
- [Validación de entradas y contratos de datos](../architecture/../architecture/input-validation-and-data-contracts.md)
- [Operación Outbox/Inbox](../architecture/transactional-outbox-inbox-operations.md)
- [Consistencia distribuida y Sagas](../architecture/distributed-transaction-consistency.md)
- [PostgreSQL HA y réplicas](../architecture/postgresql-ha-and-read-replicas.md)
- [Estrategia UUIDv7](../architecture/identifier-strategy.md)
- [Observabilidad](../architecture/observability-strategy.md)
- [Redis Cluster y caché](../architecture/redis-cache-operations.md)
- [NATS Core y JetStream](../architecture/nats-core-jetstream-cluster.md)

---

## 21. Matriz de trazabilidad de requisitos de requisitos.md

Esta matriz relaciona los apartados normativos de `requisitos.md` con las subfases que los convierten en tareas, entregables y pruebas. No reemplaza el texto funcional fuente ni autoriza a reducir sus requisitos. Cuando una capacidad aparezca en más de un apartado, se conserva la cobertura en todos los contextos aplicables.

| Apartado de `requisitos.md` | Cobertura en el plan | Evidencia mínima exigida |
|---|---|---|
| Visión del producto y modelo SaaS multiempresa | 0.1; 1.1–1.5; 10.7 | tenant, multiempresa, multimarca, sucursales y capacidades opcionales probadas |
| Arquitectura vertical configurable (Core/Restaurant Pack/Optional) | 0.1; 2.1; 3.1–3.3; 4.2–4.4 | pruebas de activación por ámbito y ausencia de dependencias gastronómicas obligatorias en Core |
| Arquitectura empresarial y jerarquía (tenant, grupo, empresa legal, marca, sucursal, área, estación, bodega, caja, terminal) | 1.2; 1.5; 0.4 | invariantes jerárquicos, relaciones válidas, aislamiento y configuración heredada/excepciones |
| Grupo A — Administración SaaS / PLATFORM | 1.1; 0.4; 0.8; 10.7 | ciclo de vida, planes, suscripciones, capacidades, límites, uso, soporte temporal y baja segura |
| Grupo B — Administración empresarial | 1.2; 1.4; 1.5; 8.2 | configuración central/local, responsables, permisos, comparación y consolidación por entidades autorizadas |
| Grupo C — Operación del restaurante | 2.2–2.6; 3.1–3.4; 9.3; 9.5 | venta, servicio, cocina, delivery, canales y periféricos en flujos E2E |
| Grupo D — Productos, menú y producción | 2.1; 3.2; 4.2–4.4 | catálogo comercial separado de menú gastronómico y recetas versionadas |
| Grupo E — Inventario y logística | 4.1; 4.3–4.4; 5.4 | ledger reconstruible, lotes, vencimientos, consumo, mermas, conteos y transferencias |
| Grupo F — Compras y proveedores | 5.1–5.4; 7.3 | proveedor, cotización, orden, recepción parcial, conciliación, cuentas por pagar y documentos |
| Grupo G — Clientes, fidelización y marketing | 6.3–6.4; 10.1; F.1–F.5 | perfil/historial, segmentación, puntos, campañas, preferencias y revocación |
| Grupo H — Personal y recursos humanos | 6.1–6.2; 7.2; 8.2 | empleados, contratos, turnos, asistencia, ausencias, compensaciones, nómina y rendimiento |
| Grupo I — Finanzas y contabilidad | 2.3–2.4; 5.3; 7.1–7.5 | caja, tesorería, cuentas por pagar/cobrar, bancos, plan contable, asientos, periodos, impuestos y conciliación |
| Grupo J — Reportes y Business Intelligence | 7.4; 8.1–8.5; 8.6 | dashboards, KPI, reportes por ámbito, filtros, exportaciones, programación, trazabilidad y auditoría |
| Grupo K — Automatización e inteligencia artificial | 8.3–8.4; 9.1 | predicciones, agentes, constructor visual, disparadores, condiciones, acciones, aprobaciones, límites y recuperación |
| Grupo L — Integraciones y tecnología | 0.7; 0.9; 9.2–9.5; 10.3 | credenciales, conectores, webhooks, hardware, seguridad, reintentos, sincronización y recuperación |
| Diseño de base de datos, relaciones, integridad, precisión y concurrencia | 0.1; 0.4; 0.6; 4.1–4.4; 7.1–7.3 | schema/rol/migración/historial por módulo, invariantes, precisión decimal, transacciones locales, concurrencia y restauración |
| Infraestructura compartida y dedicada; migración entre modalidades | 0.6–0.7; 10.3; 10.7 | Shared Cloud, Dedicated Database y Dedicated Environment; ensayo de migración, conciliación y rollback |
| Preparación de PostgreSQL, roles, RLS, secretos y respaldos | 0.6–0.7; 10.3 | pruebas RLS, mínimo privilegio, backups, WAL, PITR y restore |
| Arquitectura técnica, cuatro procesos, crates, contratos y comunicación | 0.1; 0.2; 0.6; 0.9; 10.3 | cuatro binarios independientes, BFF separados, contratos, adaptadores local/gRPC/messaging y CI de contratos |
| Transacciones, Outbox/Inbox, Saga, eventos y coordinación | 0.6; 0.8–0.9; 1.1; 2.2–2.6; 3.3; 5.3–5.4; 9.1; 10.2 | ADR-0013 prevalece sobre el ejemplo histórico de transacción multi-módulo en requisitos.md; atomicidad por módulo, entrega durable, idempotencia, compensación, reconciliación y pruebas de fallos parciales |
| Sistema RBAC + ABAC, permisos específicos y doble aprobación | 0.4; 1.3–1.4; todas las subfases operativas; 10.5 | pruebas por tenant/empresa/marca/sucursal/área/caja/terminal, importe, horario, estado y separación de funciones |
| Módulos funcionales heredados 1–17 | 1.1–1.5; 2.1–2.6; 3.1–3.4; 4.1–4.4; 5.1–5.4; 6.1–6.4; 7.1–7.5; 8.1–8.6; 9.1–9.5; 10.1–10.7 | trazabilidad por dominio y flujos E2E entre módulos propietarios |
| Capacidades transversales A — Usuarios, roles y permisos | 0.4; 1.3–1.4 | autenticación, membresías, permisos y pruebas negativas |
| Capacidades transversales B — Configuración general | 1.2; 1.5 | configuración empresarial/sucursal, plantillas, dispositivos, herencia, previsualización, programación y reversión |
| Capacidades transversales C — Integraciones externas | 9.2–9.5 | API, webhooks, WhatsApp, mapas, DIAN, pagos, contabilidad, delivery y hardware |
| Operación offline-first | 0.10; 2.6; 10.2; 7.5 | almacenamiento local seguro, cola durable, numeración, impresión, cobros autorizados, conflictos, reintentos y cero duplicados |
| Requisitos particulares de Colombia | 1.5; 2.6; 7.1; 7.5; 9.2; 9.4 | DIAN, documentos POS, notas, IVA/INC, resoluciones, reportes y contingencia fiscal |
| Stack, Rust modular, contratos, persistencia y extracción futura | 0.1; 0.6; 0.9; 10.3 | cumplimiento de arquitectura aceptada, sin implementar dependencias antes de la fase autorizada |
| AI Manager y agentes especializados | 8.1–8.4 | herramientas autorizadas, fuentes, periodo, supuestos, confianza, aprobación humana y ausencia de schema propio |
| Motor de eventos y automatizaciones | 0.6; 0.8–0.9; 9.1 | reglas versionadas, ejecuciones, aprobaciones, reintentos, límites, auditoría y recuperación |
| Criterios de calidad, validación antes de lanzamiento y aceptación por dominio | 2.1–2.6; 3.1–3.4; 4.1–4.4; 5.1–5.4; 6.1–6.4; 7.1–7.5; 8.1–8.6; 9.1–9.5; 10.1–10.7; F.1–F.6 | evidencia verificable para cada criterio y Go/No-Go por mercado |

### 21.1 Trazabilidad explícita de los 20 módulos canónicos

| Módulo | Proceso propietario | Subfases principales | Límite que debe probarse |
|---|---|---|---|
| PLATFORM | Admin Platform Backend | 1.1; 10.7 | solo ciclo de vida SaaS y referencias de despliegue; no borra ni posee datos de negocio |
| IDENTITY | Public Backend | 1.3–1.4 | identidad global única; credenciales y membresías bajo su ownership |
| ORGANIZATION | Public Backend | 1.2; 1.5 | jerarquía empresarial y recursos organizacionales |
| CATALOG | Public Backend | 2.1 | productos y agrupaciones comerciales genéricas; no es dueño de menús gastronómicos |
| SALES | Public Backend | 2.2; 9.3 | pedidos/cuentas/canales y estados comerciales |
| PAYMENTS | Public Backend | 2.3; 7.3 | operaciones financieras, cobros, devoluciones y conciliación de liquidaciones |
| CASH | Public Backend | 2.4; 7.3 | caja física, arqueos, movimientos y cierres |
| KITCHEN | Public Backend | 3.3–3.4 | comandas, estaciones y preparación; no órdenes/lotes de producción |
| INVENTORY | Public Backend | 4.1; 4.3–4.4; 5.4 | ledger, existencias, lotes, movimientos y transferencias |
| PROCUREMENT | Public Backend | 5.1–5.4 | proveedores, abastecimiento, órdenes, recepciones y conciliación |
| PRODUCTION | Public Backend | 4.2–4.4 | recetas, subrecetas, rendimientos y órdenes/lotes de producción |
| BILLING | Public Backend | 7.1; 7.5 | documentos fiscales, numeración, respuestas y trazabilidad |
| FINANCE | Public Backend | 7.2–7.4 | contabilidad, tesorería, nómina y compensaciones; sin módulo PAYROLL adicional |
| WORKFORCE | Public Backend | 6.1–6.2 | datos laborales, contratos, horarios, turnos y asistencia; no autoriza usuarios |
| CUSTOMERS | Public Backend | 6.3–6.4; 10.1 | perfiles, historial, fidelización, preferencias y derechos |
| INTEGRATIONS | Public Backend | 9.2; 9.4–9.5 | transporte técnico externo, credenciales, callbacks y hardware; no duplica libros de PAYMENTS/BILLING |
| AUTOMATION | Public Backend | 9.1 | reglas y flujos; ejecuta mediante contratos de módulos propietarios |
| ANALYTICS | Public Backend | 8.1–8.3 | KPI, tendencias, anomalías y datasets semánticos |
| AUDIT | Public Backend | 0.8; 8.6 | auditoría de seguridad/accesos bajo su ownership; no reemplaza historiales de cada módulo |
| REPORTING | Public Backend | 8.5 | generación, plantillas, programación, artefactos y distribución de informes |

Los BFF no son propietarios de estos módulos ni de sus schemas. La matriz no crea módulos nuevos ni altera la distribución aprobada por ADR-0008.

## 22. Matriz integral de trazabilidad de ADR aceptados

Cada ADR debe reflejarse en diseño, implementación, pruebas y evidencia de las subfases indicadas. Las menciones de esta tabla no significan que el control esté implementado; funcionan como criterios obligatorios de planificación y cierre.

| ADR | Decisión aceptada | Subfases donde se materializa | Evidencia exigida |
|---|---|---|---|
| ADR-0001 | Ownership PostgreSQL y migraciones por módulo | 0.1; 0.6; todas las subfases con persistencia; 10.7 | schema, rol, migraciones e historial SQLx independientes; no acceso cruzado |
| ADR-0002 | OpenAPI, Protobuf y código generado | 0.1; 0.5; todas las APIs HTTP/gRPC | contratos fuente, generación reproducible, lint y compatibilidad |
| ADR-0003 | Stateless, Outbox/Inbox y coordinación de jobs | 0.6; 0.9; todos los flujos durables; 9.1; 10.2 | entrega at-least-once, deduplicación, leases, checkpoints e idempotencia |
| ADR-0004 | W3C Trace Context | 0.8; 0.9; todos los contratos y workers | propagación HTTP/gRPC/eventos, continuidad y redacción |
| ADR-0005 | Contratos Protobuf/gRPC desde el inicio | 0.1; 0.9; comunicación entre procesos | contratos versionados; su topología histórica se interpreta junto con ADR-0007 |
| ADR-0006 | AI transversal sin schema propio | 8.1–8.4 | herramientas por contrato, datos bajo ownership de módulos y ausencia de schema/tablas AI |
| ADR-0007 | Cuatro procesos independientes y comunicación | 0.1; 0.2; 0.9; despliegue y pruebas de todas las fronteras | cuatro binarios/procesos, dos BFF separados, gRPC y NATS según semántica |
| ADR-0008 | Distribución de módulos entre procesos | 0.1; todas las fases funcionales; 10.7 | PLATFORM único en Admin Platform; los otros 19 en Public Backend; BFF sin ownership |
| ADR-0009 | Límites de crates y dependencias | 0.1; 0.2; 0.5; 0.9; todos los módulos | crates de contratos, implementación, adaptadores local/gRPC/messaging y dependencias permitidas |
| ADR-0010 | Pooling y gestión de conexiones PostgreSQL | 0.6; 10.3–10.4; cada módulo con persistencia | pools por módulo/runtime, presupuesto global, límites, routing read/write y backpressure |
| ADR-0011 | Hash de contraseñas y autenticación | 1.3; 10.5 | Argon2id, salt único, formato PHC, parámetros aprobados, rehash y pruebas de credenciales |
| ADR-0012 | UUIDv7 global y PostgreSQL HA/read replicas | 0.6; 4.1–4.4; 7.1; 10.3–10.4; 10.7 | UUIDv7 y transición futura, primario/standbys, failover, consistencia de lectura, backups/PITR |
| ADR-0013 | Consistencia distribuida y Sagas | 0.6; 1.1; 2.2–2.4; 3.3; 4.3; 5.3–5.4; 7.1–7.3; 9.1 | transacciones locales, propietario de Saga, compensaciones, reintentos y reconciliación |
| ADR-0014 | Baja de tenants y conservación de datos de clientes | 1.1; 6.3; F.2; 10.7 | baja por módulo, preservación de perfiles/historial/facturas, aislamiento y eliminación individual separada |
| ADR-0015 | Observabilidad integral | 0.8; 0.9; todas las fases; 10.3–10.6 | métricas, logs, trazas, alertas, dashboards, redacción y runbooks |
| ADR-0016 | Redis Cluster, TLS y caché distribuida | 0.9; consultas elegibles; 10.3–10.4 | Cluster, TLS/ACL, cache-aside, invalidación durable, fallback y ausencia de dependencia de corrección |
| ADR-0017 | NATS Core y JetStream HA | 0.9; todos los flujos de eventos; 10.3–10.4 | clúster, quorum, Core efímero, JetStream durable, ACK, replicación, DLQ y recuperación |
| ADR-0018 | Privacidad, retención, términos y cookies | 0.3; 0.5; 6.4; 8.4–8.6; F.1–F.6 | minimización desde diseño y paquete legal/consentimiento final por jurisdicción |
| ADR-0019 | Validación de entradas y contratos de datos | 0.5; todas las fronteras, módulos, workers e integraciones | validación por campo/frontera, pruebas negativas, fuzzing y errores seguros |
| ADR-0020 | Defensa en profundidad | 0.3–0.9; todas las fases; 10.5; F.6 | modelo de amenazas, controles por frontera y riesgos residuales |
| ADR-0021 | RBAC/ABAC y aislamiento multi-tenant | 0.4; 1.2–1.5; todas las operaciones; 10.5 | matriz de permisos, BOLA/IDOR y pruebas tenant/sucursal cruzados |
| ADR-0022 | Seguridad frontend, navegador, sesiones y APIs de borde | 1.3; 2.5–2.6; 6.4; 9.3; 9.5; 10.1; F.4 | CSRF/XSS/CSP/CORS, cookies, sesiones, caché local y dispositivos |
| ADR-0023 | Infraestructura, redes, secretos y criptografía | 0.7; 0.9; despliegues de todas las fases; 10.3–10.7 | red, TLS, secretos, rotación, hardening y backup cifrado |
| ADR-0024 | Desarrollo seguro, CI/CD y supply chain | 0.2; cada PR/build/release; 10.5; F.6 | Rulesets, CI, SCA, SBOM, procedencia y artefactos verificados |
| ADR-0025 | Abuso de APIs, bots, DDoS y exfiltración | 0.5; 1.4; 2.5; todas las APIs; 8.2–8.6; 9.1–9.5; 10.4–10.5 | rate limits, cuotas, backpressure, exportación limitada y pruebas |
| ADR-0026 | Auditoría, detección y respuesta a incidentes | 0.8; operaciones sensibles en todas las fases; 8.6; 10.6–10.7; F.5–F.6 | eventos, alertas, runbooks, ejercicios, integridad y evidencias |
| ADR-0027 | Archivos, documentos y object storage | 0.9; 2.1; 5.1; 6.1; 7.1; 8.5; 9.4; 10.3; 10.7; F.1–F.5 | validación, cuarentena, autorización, integridad, retención y descarga segura |

**Regla de cierre:** ninguna subfase se considera completa hasta que cada requisito funcional aplicable y cada decisión ADR relacionada tenga una referencia verificable a su implementación, pruebas ejecutadas y evidencia. Una fila de esta matriz no sustituye los criterios específicos de aceptación de la subfase.

**Estado final:** plan detallado propuesto como documento de ejecución. Las decisiones arquitectónicas citadas permanecen en sus estados ADR vigentes. La existencia de este plan no significa que las subfases estén implementadas ni que una fase haya sido aceptada como terminada.
