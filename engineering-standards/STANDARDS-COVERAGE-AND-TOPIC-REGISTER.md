# Inventario exhaustivo y matriz de cobertura de la biblioteca

**Versión:** 0.3.0 | **Estado:** Draft | **Fuente canónica:** catálogo maestro y árbol de `engineering-standards/`.

## 1. Propósito y regla de integridad

Este archivo es el manifiesto de descubrimiento versionado. Contiene identificadores estables para los estándares documentales y para cada tema de la taxonomía A–J del catálogo. El agente DEBE usarlo como lista de control, además de leer los documentos completos. No puede crear una selección reducida ni sustituirlo por memoria o inferencias.

Cada proyecto consumidor debe copiar este inventario a su registro y crear exactamente una fila de evaluación por cada `STD-*` y `TOP-*`. Las filas pueden agruparse en la conversación para preguntar al propietario, pero no se pueden omitir del registro. Si el manifiesto cambia, el proyecto registra la versión y revisa el delta.

**Importante:** la presencia de un enlace o una referencia en la columna de cobertura no implica conformidad, adopción ni implementación. `Parcial/transversal` nunca equivale a cobertura especializada suficiente. Cuando un tema aplicable no tenga controles específicos suficientes, se registra `Brecha de biblioteca`.

## 2. Estados: dos dimensiones independientes

No confundir aplicabilidad con decisión de adopción.

**Aplicabilidad (una por elemento):** `Aplica`, `Condicional` o `No aplica`. Para `Condicional`, registrar disparador, evidencia y resultado de evaluación. Para `No aplica`, registrar justificación y disparador de reevaluación.

**Estado de adopción (una por elemento):** `Adoptado`, `Adoptado con adaptación`, `Aplazado`, `No aplicable`, `Rechazado`, `Pendiente de decisión` o `Brecha de biblioteca`. `No aplicable` solo es válido cuando la aplicabilidad sea `No aplica`. Si aplica, pero se decide no adoptar, usar `Rechazado`, nunca `No aplicable`.

## 3. Inventario de estándares documentales

Identificadores `STD-001` en adelante. El ID se mantiene aunque cambie el título o ruta; una retirada conserva el ID y su trazabilidad. Las rutas son relativas a `engineering-standards/`.

| ID | Documento normativo | Ruta |
|---|---|---|
| STD-001 | architecture decision record standard | [00-governance/architecture-decision-record-standard.md](./00-governance/architecture-decision-record-standard.md) |
| STD-002 | documentation lifecycle and review | [00-governance/documentation-lifecycle-and-review.md](./00-governance/documentation-lifecycle-and-review.md) |
| STD-003 | standard exception and waiver process | [00-governance/standard-exception-and-waiver-process.md](./00-governance/standard-exception-and-waiver-process.md) |
| STD-004 | domain boundaries and ownership standard | [01-software-architecture/domain-boundaries-and-ownership-standard.md](./01-software-architecture/domain-boundaries-and-ownership-standard.md) |
| STD-005 | modular architecture standard | [01-software-architecture/modular-architecture-standard.md](./01-software-architecture/modular-architecture-standard.md) |
| STD-006 | service decomposition standard | [01-software-architecture/service-decomposition-standard.md](./01-software-architecture/service-decomposition-standard.md) |
| STD-007 | data ownership and access standard | [02-data-management/data-ownership-and-access-standard.md](./02-data-management/data-ownership-and-access-standard.md) |
| STD-008 | database schema and migration standard | [02-data-management/database-schema-and-migration-standard.md](./02-data-management/database-schema-and-migration-standard.md) |
| STD-009 | database security and access control standard | [02-data-management/database-security-and-access-control-standard.md](./02-data-management/database-security-and-access-control-standard.md) |
| STD-010 | identifier strategy standard | [02-data-management/identifier-strategy-standard.md](./02-data-management/identifier-strategy-standard.md) |
| STD-011 | multi tenant data isolation standard | [02-data-management/multi-tenant-data-isolation-standard.md](./02-data-management/multi-tenant-data-isolation-standard.md) |
| STD-012 | background jobs and leases standard | [03-distributed-systems/background-jobs-and-leases-standard.md](./03-distributed-systems/background-jobs-and-leases-standard.md) |
| STD-013 | idempotency standard | [03-distributed-systems/idempotency-standard.md](./03-distributed-systems/idempotency-standard.md) |
| STD-014 | messaging and event contracts standard | [03-distributed-systems/messaging-and-event-contracts-standard.md](./03-distributed-systems/messaging-and-event-contracts-standard.md) |
| STD-015 | saga and distributed consistency standard | [03-distributed-systems/saga-and-distributed-consistency-standard.md](./03-distributed-systems/saga-and-distributed-consistency-standard.md) |
| STD-016 | transactional inbox standard | [03-distributed-systems/transactional-inbox-standard.md](./03-distributed-systems/transactional-inbox-standard.md) |
| STD-017 | transactional outbox standard | [03-distributed-systems/transactional-outbox-standard.md](./03-distributed-systems/transactional-outbox-standard.md) |
| STD-018 | api contract design standard | [04-apis-and-contracts/api-contract-design-standard.md](./04-apis-and-contracts/api-contract-design-standard.md) |
| STD-019 | api error model standard | [04-apis-and-contracts/api-error-model-standard.md](./04-apis-and-contracts/api-error-model-standard.md) |
| STD-020 | api versioning and compatibility standard | [04-apis-and-contracts/api-versioning-and-compatibility-standard.md](./04-apis-and-contracts/api-versioning-and-compatibility-standard.md) |
| STD-021 | api abuse and rate protection standard | [05-application-security/api-abuse-and-rate-protection-standard.md](./05-application-security/api-abuse-and-rate-protection-standard.md) |
| STD-022 | application security baseline standard | [05-application-security/application-security-baseline-standard.md](./05-application-security/application-security-baseline-standard.md) |
| STD-023 | authentication and authorization standard | [05-application-security/authentication-and-authorization-standard.md](./05-application-security/authentication-and-authorization-standard.md) |
| STD-024 | file upload and content processing standard | [05-application-security/file-upload-and-content-processing-standard.md](./05-application-security/file-upload-and-content-processing-standard.md) |
| STD-025 | frontend web security standard | [05-application-security/frontend-web-security-standard.md](./05-application-security/frontend-web-security-standard.md) |
| STD-026 | input validation and data integrity standard | [05-application-security/input-validation-and-data-integrity-standard.md](./05-application-security/input-validation-and-data-integrity-standard.md) |
| STD-027 | secrets and credential management standard | [05-application-security/secrets-and-credential-management-standard.md](./05-application-security/secrets-and-credential-management-standard.md) |
| STD-028 | security audit and incident response standard | [05-application-security/security-audit-and-incident-response-standard.md](./05-application-security/security-audit-and-incident-response-standard.md) |
| STD-029 | container and runtime hardening standard | [06-infrastructure-security/container-and-runtime-hardening-standard.md](./06-infrastructure-security/container-and-runtime-hardening-standard.md) |
| STD-030 | data encryption and key management standard | [06-infrastructure-security/data-encryption-and-key-management-standard.md](./06-infrastructure-security/data-encryption-and-key-management-standard.md) |
| STD-031 | network segmentation and egress standard | [06-infrastructure-security/network-segmentation-and-egress-standard.md](./06-infrastructure-security/network-segmentation-and-egress-standard.md) |
| STD-032 | transport encryption and certificate standard | [06-infrastructure-security/transport-encryption-and-certificate-standard.md](./06-infrastructure-security/transport-encryption-and-certificate-standard.md) |
| STD-033 | backup disaster recovery and continuity standard | [07-resilience-and-recovery/backup-disaster-recovery-and-continuity-standard.md](./07-resilience-and-recovery/backup-disaster-recovery-and-continuity-standard.md) |
| STD-034 | high availability and failover standard | [07-resilience-and-recovery/high-availability-and-failover-standard.md](./07-resilience-and-recovery/high-availability-and-failover-standard.md) |
| STD-035 | timeouts retries and backpressure standard | [07-resilience-and-recovery/timeouts-retries-and-backpressure-standard.md](./07-resilience-and-recovery/timeouts-retries-and-backpressure-standard.md) |
| STD-036 | capacity planning and load testing standard | [08-performance-and-capacity/capacity-planning-and-load-testing-standard.md](./08-performance-and-capacity/capacity-planning-and-load-testing-standard.md) |
| STD-037 | connection pooling and resource budget standard | [08-performance-and-capacity/connection-pooling-and-resource-budget-standard.md](./08-performance-and-capacity/connection-pooling-and-resource-budget-standard.md) |
| STD-038 | distributed caching standard | [08-performance-and-capacity/distributed-caching-standard.md](./08-performance-and-capacity/distributed-caching-standard.md) |
| STD-039 | observability and telemetry standard | [09-observability/observability-and-telemetry-standard.md](./09-observability/observability-and-telemetry-standard.md) |
| STD-040 | privacy and personal data lifecycle standard | [10-privacy-and-data-protection/privacy-and-personal-data-lifecycle-standard.md](./10-privacy-and-data-protection/privacy-and-personal-data-lifecycle-standard.md) |
| STD-041 | testing strategy and quality gates standard | [11-testing-and-quality/testing-strategy-and-quality-gates-standard.md](./11-testing-and-quality/testing-strategy-and-quality-gates-standard.md) |
| STD-042 | ci cd and software supply chain standard | [12-devsecops/ci-cd-and-software-supply-chain-standard.md](./12-devsecops/ci-cd-and-software-supply-chain-standard.md) |
| STD-043 | secure software development lifecycle standard | [12-devsecops/secure-software-development-lifecycle-standard.md](./12-devsecops/secure-software-development-lifecycle-standard.md) |
| STD-044 | project adoption and conformance | [13-project-adaptation/project-adoption-and-conformance.md](./13-project-adaptation/project-adoption-and-conformance.md) |
| STD-045 | accessibility and inclusive design standard | [14-specialized-engineering/accessibility-and-inclusive-design-standard.md](./14-specialized-engineering/accessibility-and-inclusive-design-standard.md) |
| STD-046 | artificial intelligence and agent systems standard | [14-specialized-engineering/artificial-intelligence-and-agent-systems-standard.md](./14-specialized-engineering/artificial-intelligence-and-agent-systems-standard.md) |
| STD-047 | cloud architecture and provider governance standard | [14-specialized-engineering/cloud-architecture-and-provider-governance-standard.md](./14-specialized-engineering/cloud-architecture-and-provider-governance-standard.md) |
| STD-048 | feature flags and progressive delivery standard | [14-specialized-engineering/feature-flags-and-progressive-delivery-standard.md](./14-specialized-engineering/feature-flags-and-progressive-delivery-standard.md) |
| STD-049 | finops and technology cost management standard | [14-specialized-engineering/finops-and-technology-cost-management-standard.md](./14-specialized-engineering/finops-and-technology-cost-management-standard.md) |
| STD-050 | frontend application architecture standard | [14-specialized-engineering/frontend-application-architecture-standard.md](./14-specialized-engineering/frontend-application-architecture-standard.md) |
| STD-051 | infrastructure as code and platform automation standard | [14-specialized-engineering/infrastructure-as-code-and-platform-automation-standard.md](./14-specialized-engineering/infrastructure-as-code-and-platform-automation-standard.md) |
| STD-052 | internationalization and localization standard | [14-specialized-engineering/internationalization-and-localization-standard.md](./14-specialized-engineering/internationalization-and-localization-standard.md) |
| STD-053 | iot and device fleet standard | [14-specialized-engineering/iot-and-device-fleet-standard.md](./14-specialized-engineering/iot-and-device-fleet-standard.md) |
| STD-054 | kubernetes and container orchestration standard | [14-specialized-engineering/kubernetes-and-container-orchestration-standard.md](./14-specialized-engineering/kubernetes-and-container-orchestration-standard.md) |
| STD-055 | machine learning and mlops standard | [14-specialized-engineering/machine-learning-and-mlops-standard.md](./14-specialized-engineering/machine-learning-and-mlops-standard.md) |
| STD-056 | mobile application engineering standard | [14-specialized-engineering/mobile-application-engineering-standard.md](./14-specialized-engineering/mobile-application-engineering-standard.md) |
| STD-057 | object storage and media lifecycle standard | [14-specialized-engineering/object-storage-and-media-lifecycle-standard.md](./14-specialized-engineering/object-storage-and-media-lifecycle-standard.md) |
| STD-058 | offline first and client synchronization standard | [14-specialized-engineering/offline-first-and-client-synchronization-standard.md](./14-specialized-engineering/offline-first-and-client-synchronization-standard.md) |
| STD-059 | payment integration and financial controls standard | [14-specialized-engineering/payment-integration-and-financial-controls-standard.md](./14-specialized-engineering/payment-integration-and-financial-controls-standard.md) |
| STD-060 | real time and streaming systems standard | [14-specialized-engineering/real-time-and-streaming-systems-standard.md](./14-specialized-engineering/real-time-and-streaming-systems-standard.md) |
| STD-061 | search and information retrieval standard | [14-specialized-engineering/search-and-information-retrieval-standard.md](./14-specialized-engineering/search-and-information-retrieval-standard.md) |
| STD-062 | site reliability engineering and slo standard | [14-specialized-engineering/site-reliability-engineering-and-slo-standard.md](./14-specialized-engineering/site-reliability-engineering-and-slo-standard.md) |
| STD-063 | software license and open source compliance standard | [14-specialized-engineering/software-license-and-open-source-compliance-standard.md](./14-specialized-engineering/software-license-and-open-source-compliance-standard.md) |
| STD-064 | technical documentation and developer experience standard | [14-specialized-engineering/technical-documentation-and-developer-experience-standard.md](./14-specialized-engineering/technical-documentation-and-developer-experience-standard.md) |
| STD-065 | third party integration and webhook standard | [14-specialized-engineering/third-party-integration-and-webhook-standard.md](./14-specialized-engineering/third-party-integration-and-webhook-standard.md) |
| STD-066 | user experience and product usability standard | [14-specialized-engineering/user-experience-and-product-usability-standard.md](./14-specialized-engineering/user-experience-and-product-usability-standard.md) |

## 4. Inventario de temas de descubrimiento A–J

Cada fila requiere evaluación individual, incluso si se considera cubierta por uno o varios estándares. `Documento relacionado` es una pista inicial de navegación, no una conclusión automática de suficiencia. Cuando no haya un documento específico claramente dedicado, la cobertura queda como `Transversal/parcial — validar` y el agente debe decidir si constituye brecha.

| ID | Familia | Tema que debe evaluarse | Documento relacionado / cobertura inicial |
|---|---|---|---|
| TOP-A-001 | A | Gobierno de estándares, jerarquía documental, lenguaje normativo y versionado | 00-governance/documentation-lifecycle-and-review.md; VERSIONING.md; GOVERNANCE.md |
| TOP-A-002 | A | Descubrimiento de requisitos, historias, casos de uso y criterios de aceptación | 13-project-adaptation/project-adoption-and-conformance.md; brecha posible de requisitos/product discovery |
| TOP-A-003 | A | Gestión de alcance, cambios, riesgos, dependencias y trazabilidad | 00-governance/architecture-decision-record-standard.md; trazabilidad transversal |
| TOP-A-004 | A | ADR, RFC, revisiones técnicas, excepciones y obsolescencia | 00-governance/architecture-decision-record-standard.md; standard-exception-and-waiver-process.md |
| TOP-A-005 | A | Documentación de arquitectura, decisiones, operación y usuario | 14-specialized-engineering/technical-documentation-and-developer-experience-standard.md; observability-and-telemetry-standard.md |
| TOP-A-006 | A | Gestión de configuración, ambientes, feature flags y cambios de esquema | 14-specialized-engineering/feature-flags-and-progressive-delivery-standard.md; database-schema-and-migration-standard.md |
| TOP-A-007 | A | Gestión de releases, compatibilidad, rollback y comunicación de cambios | ci-cd-and-software-supply-chain-standard.md; API versioning standard; rollback coverage parcial |
| TOP-A-008 | A | Propiedad intelectual, licencias, atribución y uso de código/datos de terceros | software-license-and-open-source-compliance-standard.md |
| TOP-A-009 | A | Gestión de proveedores, contratos, SLA y salida/portabilidad | cloud-architecture-and-provider-governance-standard.md; third-party-integration-and-webhook-standard.md |
| TOP-B-001 | B | Monolito, monolito modular, microservicios, SOA, serverless y arquitecturas híbridas | domain-boundaries-and-ownership-standard.md; modular-architecture-standard.md; service-decomposition-standard.md |
| TOP-B-002 | B | Arquitectura hexagonal, clean architecture, capas, vertical slices y componentes | modular-architecture-standard.md; cobertura parcial de patrones |
| TOP-B-003 | B | DDD, bounded contexts, context mapping, agregados y eventos de dominio | domain-boundaries-and-ownership-standard.md; cobertura parcial DDD |
| TOP-B-004 | B | Separación de responsabilidades, acoplamiento, cohesión y dependencias | modular-architecture-standard.md; domain-boundaries-and-ownership-standard.md |
| TOP-B-005 | B | Arquitecturas orientadas a eventos, mensajes, streaming y workflows | messaging-and-event-contracts-standard.md; real-time-and-streaming-systems-standard.md |
| TOP-B-006 | B | Sistemas reactivos, tiempo real, edge, offline-first y event sourcing cuando proceda | offline-first-and-client-synchronization-standard.md; real-time-and-streaming-systems-standard.md; brecha posible event sourcing/edge |
| TOP-B-007 | B | Evolución, modularización, strangler pattern y retiro de sistemas legados | modular-architecture-standard.md; service-decomposition-standard.md; cobertura parcial de modernización legacy |
| TOP-B-008 | B | Diseño para testabilidad, extensibilidad, portabilidad y mantenibilidad | testing-strategy-and-quality-gates-standard.md; modular-architecture-standard.md |
| TOP-C-001 | C | Modelado conceptual, lógico y físico; normalización y desnormalización | database-schema-and-migration-standard.md; cobertura parcial |
| TOP-C-002 | C | SQL, NoSQL, documentos, clave-valor, grafos, series temporales y búsqueda | database-schema-and-migration-standard.md; brecha posible para motores especializados |
| TOP-C-003 | C | Ownership, límites de escritura, integridad, consistencia y transacciones | data-ownership-and-access-standard.md; saga-and-distributed-consistency-standard.md |
| TOP-C-004 | C | Migraciones, versionado de esquemas, compatibilidad y rollback/roll-forward | database-schema-and-migration-standard.md |
| TOP-C-005 | C | Identificadores, secuencias, claves naturales/sustitutas y generación distribuida | identifier-strategy-standard.md |
| TOP-C-006 | C | Multi-tenancy, aislamiento, residencia y segregación de datos | multi-tenant-data-isolation-standard.md |
| TOP-C-007 | C | Gobierno, catálogo, linaje, calidad, clasificación y retención | privacy-and-personal-data-lifecycle-standard.md; brecha de gobierno/calidad/linaje de datos |
| TOP-C-008 | C | Cifrado, masking, tokenización, anonimización y eliminación | data-encryption-and-key-management-standard.md; privacy-and-personal-data-lifecycle-standard.md |
| TOP-C-009 | C | Backups, restauración, PITR, archivado y portabilidad | backup-disaster-recovery-and-continuity-standard.md |
| TOP-C-010 | C | Object/blob storage, archivos, medios y ciclo de vida | object-storage-and-media-lifecycle-standard.md |
| TOP-C-011 | C | Replicación, particionado, sharding, búsqueda y analítica | database-schema-and-migration-standard.md; search-and-information-retrieval-standard.md; brecha de sharding/analítica |
| TOP-D-001 | D | RPC, HTTP, gRPC, GraphQL, WebSocket, SSE y protocolos binarios | api-contract-design-standard.md; cobertura parcial de protocolos |
| TOP-D-002 | D | Mensajería, brokers, colas, pub/sub, streaming y contratos de eventos | messaging-and-event-contracts-standard.md |
| TOP-D-003 | D | Outbox, Inbox, deduplicación, idempotencia, orden y replay | transactional-outbox-standard.md; transactional-inbox-standard.md; idempotency-standard.md |
| TOP-D-004 | D | Sagas, workflows, compensaciones y coordinación distribuida | saga-and-distributed-consistency-standard.md |
| TOP-D-005 | D | Reintentos, timeout, circuit breaker, bulkhead, backpressure y rate control | timeouts-retries-and-backpressure-standard.md; api-abuse-and-rate-protection-standard.md |
| TOP-D-006 | D | Webhooks, callbacks, polling, sincronización y conectores externos | third-party-integration-and-webhook-standard.md |
| TOP-D-007 | D | Consistencia eventual, reconciliación, entrega y semántica de procesamiento | saga-and-distributed-consistency-standard.md; messaging-and-event-contracts-standard.md |
| TOP-D-008 | D | Jobs, scheduler, leases, locks y ejecución distribuida | background-jobs-and-leases-standard.md |
| TOP-D-009 | D | Integraciones con pagos, correo, SMS, identidad, mapas y sistemas empresariales | payment-integration-and-financial-controls-standard.md; third-party-integration-and-webhook-standard.md; brecha para algunos conectores |
| TOP-E-001 | E | Diseño de APIs, contratos, versionado, compatibilidad y errores | api-contract-design-standard.md; api-versioning-and-compatibility-standard.md; api-error-model-standard.md |
| TOP-E-002 | E | Autenticación de clientes, autorización por recurso, scopes y cuotas | authentication-and-authorization-standard.md; api-abuse-and-rate-protection-standard.md |
| TOP-E-003 | E | BFF, gateway, composición y límites de confianza | api-contract-design-standard.md; cobertura parcial BFF/gateway |
| TOP-E-004 | E | Arquitectura frontend, estado, formularios, routing y componentes | frontend-application-architecture-standard.md |
| TOP-E-005 | E | Seguridad web, CSP, CORS, CSRF, XSS, cookies y sesiones | frontend-web-security-standard.md |
| TOP-E-006 | E | Accesibilidad, diseño inclusivo, UX, usabilidad y diseño responsivo | accessibility-and-inclusive-design-standard.md; user-experience-and-product-usability-standard.md |
| TOP-E-007 | E | Internacionalización, localización, zonas horarias, formatos y RTL | internationalization-and-localization-standard.md |
| TOP-E-008 | E | SEO, renderizado SSR/SSG/CSR, rendimiento web y Core Web Vitals | frontend-application-architecture-standard.md; brecha SEO y Core Web Vitals |
| TOP-E-009 | E | Compatibilidad de navegadores, degradación progresiva y privacidad analítica | frontend-application-architecture-standard.md; cobertura parcial |
| TOP-F-001 | F | Android/iOS, arquitectura cliente y ciclo de vida | mobile-application-engineering-standard.md |
| TOP-F-002 | F | Almacenamiento local, secretos, permisos y protección del dispositivo | mobile-application-engineering-standard.md; secrets-and-credential-management-standard.md |
| TOP-F-003 | F | Sincronización offline, conflictos, colas locales y conectividad intermitente | offline-first-and-client-synchronization-standard.md |
| TOP-F-004 | F | Notificaciones push, deep links, enlaces universales y distribución | brecha de biblioteca — push/deep links/distribución |
| TOP-F-005 | F | Actualizaciones, compatibilidad, telemetría y gestión de versiones | mobile-application-engineering-standard.md |
| TOP-F-006 | F | Accesibilidad móvil, pruebas en dispositivos y seguridad móvil | accessibility-and-inclusive-design-standard.md; mobile-application-engineering-standard.md |
| TOP-G-001 | G | Threat modeling, clasificación de activos, límites de confianza y abuso | application-security-baseline-standard.md; brecha de threat modeling dedicado |
| TOP-G-002 | G | Secure SDLC, OWASP y controles por tecnología | secure-software-development-lifecycle-standard.md; application-security-baseline-standard.md |
| TOP-G-003 | G | Identidad, autenticación, autorización, MFA, sesiones y ciclo de credenciales | authentication-and-authorization-standard.md |
| TOP-G-004 | G | Secretos, certificados, PKI, criptografía y gestión de claves | secrets-and-credential-management-standard.md; data-encryption-and-key-management-standard.md |
| TOP-G-005 | G | Validación, sanitización, serialización y deserialización segura | input-validation-and-data-integrity-standard.md |
| TOP-G-006 | G | SSRF, inyección, traversal, deserialización, XSS, CSRF y otros riesgos | application-security-baseline-standard.md; brecha de catálogo de amenazas detallado |
| TOP-G-007 | G | Seguridad de archivos, malware, contenido y cadena de procesamiento | file-upload-and-content-processing-standard.md |
| TOP-G-008 | G | Seguridad de red, egress, DNS, TLS, WAF y DDoS | network-segmentation-and-egress-standard.md; transport-encryption-and-certificate-standard.md |
| TOP-G-009 | G | Seguridad de contenedores, hosts, cloud, CI/CD y supply chain | container-and-runtime-hardening-standard.md; ci-cd-and-software-supply-chain-standard.md |
| TOP-G-010 | G | Auditoría, detección, respuesta a incidentes y forense | security-audit-and-incident-response-standard.md |
| TOP-G-011 | G | Privacidad por diseño, consentimiento, derechos y retención | privacy-and-personal-data-lifecycle-standard.md |
| TOP-G-012 | G | Seguridad de IA, datos de entrenamiento, prompt injection y fuga de información | artificial-intelligence-and-agent-systems-standard.md; machine-learning-and-mlops-standard.md |
| TOP-H-001 | H | Cloud, on-premises, híbrido, edge y selección de proveedores | cloud-architecture-and-provider-governance-standard.md |
| TOP-H-002 | H | Redes, DNS, balanceo, CDN, ingress/egress y service discovery | network-segmentation-and-egress-standard.md; brecha de DNS/CDN/load balancing |
| TOP-H-003 | H | Contenedores, orquestación, Kubernetes y runtime | kubernetes-and-container-orchestration-standard.md; container-and-runtime-hardening-standard.md |
| TOP-H-004 | H | Infraestructura como código, configuración y policy as code | infrastructure-as-code-and-platform-automation-standard.md |
| TOP-H-005 | H | Secretos y configuración por ambiente | secrets-and-credential-management-standard.md |
| TOP-H-006 | H | Alta disponibilidad, failover, resiliencia y continuidad | high-availability-and-failover-standard.md |
| TOP-H-007 | H | Backup, disaster recovery, RTO/RPO y pruebas de restauración | backup-disaster-recovery-and-continuity-standard.md |
| TOP-H-008 | H | SRE, SLI/SLO/SLA, error budgets, guardias y runbooks | site-reliability-engineering-and-slo-standard.md |
| TOP-H-009 | H | Observabilidad, alertas, capacidad y gestión de incidentes | observability-and-telemetry-standard.md |
| TOP-H-010 | H | Costos cloud, FinOps, presupuestos y optimización | finops-and-technology-cost-management-standard.md |
| TOP-I-001 | I | Pirámide de pruebas, unitarias, integración, contratos y E2E | testing-strategy-and-quality-gates-standard.md |
| TOP-I-002 | I | Pruebas funcionales, regresión, aceptación y exploratorias | testing-strategy-and-quality-gates-standard.md |
| TOP-I-003 | I | Rendimiento, carga, estrés, soak, escalabilidad y capacidad | capacity-planning-and-load-testing-standard.md |
| TOP-I-004 | I | Seguridad, fuzzing, property-based, mutación y análisis estático | secure-software-development-lifecycle-standard.md; testing-strategy-and-quality-gates-standard.md; cobertura parcial |
| TOP-I-005 | I | Resiliencia, chaos engineering y pruebas de recuperación | high-availability-and-failover-standard.md; backup-disaster-recovery-and-continuity-standard.md; brecha posible chaos dedicado |
| TOP-I-006 | I | Accesibilidad, compatibilidad, usabilidad y pruebas móviles | accessibility-and-inclusive-design-standard.md; mobile-application-engineering-standard.md |
| TOP-I-007 | I | CI/CD, artefactos inmutables, SBOM, firmas y procedencia | ci-cd-and-software-supply-chain-standard.md |
| TOP-I-008 | I | Revisión de código, calidad, deuda técnica y gates | testing-strategy-and-quality-gates-standard.md |
| TOP-J-001 | J | IA generativa, agentes, RAG, evaluación, guardrails y supervisión humana | artificial-intelligence-and-agent-systems-standard.md |
| TOP-J-002 | J | Machine learning, MLOps, datos/modelos, drift y reproducibilidad | machine-learning-and-mlops-standard.md |
| TOP-J-003 | J | IoT, dispositivos, firmware, telemetría y gestión de flotas | iot-and-device-fleet-standard.md |
| TOP-J-004 | J | Sistemas de tiempo real, streaming y baja latencia | real-time-and-streaming-systems-standard.md |
| TOP-J-005 | J | Sistemas financieros, pagos, conciliación y controles antifraude | payment-integration-and-financial-controls-standard.md |
| TOP-J-006 | J | Salud, datos clínicos y seguridad de pacientes cuando aplique | brecha de biblioteca — salud/datos clínicos/seguridad de pacientes |
| TOP-J-007 | J | Sistemas críticos, safety engineering y análisis de peligros | brecha de biblioteca — safety engineering y análisis de peligros |
| TOP-J-008 | J | Blockchain o tecnologías distribuidas especializadas solo si existe necesidad | brecha de biblioteca — blockchain si se justifica |
| TOP-J-009 | J | Geoespacial, mapas, geocodificación y datos de ubicación | brecha de biblioteca — geoespacial/mapas/geocodificación |
| TOP-J-010 | J | Búsqueda, recomendación, analítica y plataformas de datos | search-and-information-retrieval-standard.md; brecha parcial analítica/plataformas de datos |

## 5. Reglas de evaluación de cobertura

1. El agente DEBE revisar el documento relacionado completo y comprobar si contiene objetivo, alcance, requisitos verificables, amenazas/fallos, controles, pruebas, evidencias, responsabilidades y revisión.
2. Si el documento solo menciona el tema, la cobertura es parcial; no debe marcarse como cubierto.
3. Si el tema está fuera del alcance, registrar `No aplica` con fundamento y disparadores de reevaluación.
4. Si el tema aplica y la cobertura es insuficiente, registrar `Brecha de biblioteca`, crear acción con responsable/fecha y proponer un estándar o ampliación.
5. Si el tema aplica y está cubierto, registrar el estándar adoptado y sus requisitos en la matriz de conformidad.
6. Los temas nuevos descubiertos durante el proyecto reciben ID provisional `TOP-NEW-[familia]-NNN`; el mantenedor asignará ID permanente en la siguiente versión sin reutilizar IDs retirados.
7. No se permite inferir cobertura por el nombre de un archivo, por similitud semántica ni porque exista una herramienta que podría resolverlo.

## 6. Conteo e integridad

- Estándares documentales inventariados: 66.
- Temas de descubrimiento A–J inventariados: 92.
- Total de elementos que requieren evaluación: 158.
- Las plantillas y los README sirven de navegación y no sustituyen las filas `STD-*` y `TOP-*`.
- En cada cambio de catálogo o de árbol documental, actualizar este manifiesto y el changelog en el mismo PR.
