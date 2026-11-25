# Catálogo maestro de estándares de ingeniería

**Versión:** 0.2.0 | **Estado:** Draft | **Carácter:** índice normativo de descubrimiento

## 1. Propósito y regla de exhaustividad

Este catálogo es el punto de entrada obligatorio para cualquier agente, arquitecto o equipo que inicie un proyecto usando esta biblioteca. Su función es evitar que la selección dependa de la memoria, preferencias o sesgos del agente.

**El agente DEBE recorrer todas las familias y registrar un resultado para cada estándar y tema del catálogo.** No basta con leer el README ni seleccionar solo los documentos que parezcan relevantes. Si un tema no tiene todavía un estándar especializado, debe registrarse como brecha documental y no inventarse que está cubierto.

La biblioteca es extensible: el catálogo no afirma que sea posible enumerar para siempre toda disciplina existente. La revisión de cobertura debe buscar activamente nuevas áreas, tecnologías, obligaciones y amenazas.

## 2. Estados de aplicabilidad y adopción

Cada elemento tendrá exactamente uno de estos estados en el registro del proyecto:

- **Adoptado:** aplica y sus requisitos son obligatorios para el proyecto.
- **Adoptado con adaptación:** aplica con ajustes explícitos y trazables.
- **Aplazado:** aplica, pero su implantación tiene fecha, responsable, riesgo aceptado y controles temporales.
- **No aplicable:** no corresponde al alcance; exige justificación verificable y disparadores de reevaluación.
- **Rechazado:** el propietario decide no adoptarlo; exige ADR o excepción, impacto y mitigación.
- **Pendiente de decisión:** requiere respuesta del propietario; no autoriza al agente a asumir.
- **Brecha de biblioteca:** el tema es pertinente pero carece de estándar suficiente; requiere investigación y creación/revisión documental.

No usar "omitido", "no revisado", vacío ni silencio como estado final. Una decisión pendiente bloquea únicamente el diseño o la implementación que dependa de ella; el agente debe señalar el bloqueo concreto.

## 3. Catálogo por familias

La siguiente lista es una taxonomía de descubrimiento. Cada tema debe evaluarse, aunque el proyecto no lo utilice.

### A. Gobernanza, producto y ciclo de vida
- Gobierno de estándares, jerarquía documental, lenguaje normativo y versionado.
- Descubrimiento de requisitos, historias, casos de uso y criterios de aceptación.
- Gestión de alcance, cambios, riesgos, dependencias y trazabilidad.
- ADR, RFC, revisiones técnicas, excepciones y obsolescencia.
- Documentación de arquitectura, decisiones, operación y usuario.
- Gestión de configuración, ambientes, feature flags y cambios de esquema.
- Gestión de releases, compatibilidad, rollback y comunicación de cambios.
- Propiedad intelectual, licencias, atribución y uso de código/datos de terceros.
- Gestión de proveedores, contratos, SLA y salida/portabilidad.

### B. Arquitectura y diseño de software
- Monolito, monolito modular, microservicios, SOA, serverless y arquitecturas híbridas.
- Arquitectura hexagonal, clean architecture, capas, vertical slices y componentes.
- DDD, bounded contexts, context mapping, agregados y eventos de dominio.
- Separación de responsabilidades, acoplamiento, cohesión y dependencias.
- Arquitecturas orientadas a eventos, mensajes, streaming y workflows.
- Sistemas reactivos, tiempo real, edge, offline-first y event sourcing cuando proceda.
- Evolución, modularización, strangler pattern y retiro de sistemas legados.
- Diseño para testabilidad, extensibilidad, portabilidad y mantenibilidad.

### C. Datos y persistencia
- Modelado conceptual, lógico y físico; normalización y desnormalización.
- SQL, NoSQL, documentos, clave-valor, grafos, series temporales y búsqueda.
- Ownership, límites de escritura, integridad, consistencia y transacciones.
- Migraciones, versionado de esquemas, compatibilidad y rollback/roll-forward.
- Identificadores, secuencias, claves naturales/sustitutas y generación distribuida.
- Multi-tenancy, aislamiento, residencia y segregación de datos.
- Gobierno, catálogo, linaje, calidad, clasificación y retención.
- Cifrado, masking, tokenización, anonimización y eliminación.
- Backups, restauración, PITR, archivado y portabilidad.
- Object/blob storage, archivos, medios y ciclo de vida.
- Replicación, particionado, sharding, búsqueda y analítica.

### D. Sistemas distribuidos e integración
- RPC, HTTP, gRPC, GraphQL, WebSocket, SSE y protocolos binarios.
- Mensajería, brokers, colas, pub/sub, streaming y contratos de eventos.
- Outbox, Inbox, deduplicación, idempotencia, orden y replay.
- Sagas, workflows, compensaciones y coordinación distribuida.
- Reintentos, timeout, circuit breaker, bulkhead, backpressure y rate control.
- Webhooks, callbacks, polling, sincronización y conectores externos.
- Consistencia eventual, reconciliación, entrega y semántica de procesamiento.
- Jobs, scheduler, leases, locks y ejecución distribuida.
- Integraciones con pagos, correo, SMS, identidad, mapas y sistemas empresariales.

### E. APIs, experiencia de desarrollador y frontend
- Diseño de APIs, contratos, versionado, compatibilidad y errores.
- Autenticación de clientes, autorización por recurso, scopes y cuotas.
- BFF, gateway, composición y límites de confianza.
- Arquitectura frontend, estado, formularios, routing y componentes.
- Seguridad web, CSP, CORS, CSRF, XSS, cookies y sesiones.
- Accesibilidad, diseño inclusivo, UX, usabilidad y diseño responsivo.
- Internacionalización, localización, zonas horarias, formatos y RTL.
- SEO, renderizado SSR/SSG/CSR, rendimiento web y Core Web Vitals.
- Compatibilidad de navegadores, degradación progresiva y privacidad analítica.

### F. Aplicaciones móviles y clientes
- Android/iOS, arquitectura cliente y ciclo de vida.
- Almacenamiento local, secretos, permisos y protección del dispositivo.
- Sincronización offline, conflictos, colas locales y conectividad intermitente.
- Notificaciones push, deep links, enlaces universales y distribución.
- Actualizaciones, compatibilidad, telemetría y gestión de versiones.
- Accesibilidad móvil, pruebas en dispositivos y seguridad móvil.

### G. Seguridad, privacidad y confianza
- Threat modeling, clasificación de activos, límites de confianza y abuso.
- Secure SDLC, OWASP y controles por tecnología.
- Identidad, autenticación, autorización, MFA, sesiones y ciclo de credenciales.
- Secretos, certificados, PKI, criptografía y gestión de claves.
- Validación, sanitización, serialización y deserialización segura.
- SSRF, inyección, traversal, deserialización, XSS, CSRF y otros riesgos.
- Seguridad de archivos, malware, contenido y cadena de procesamiento.
- Seguridad de red, egress, DNS, TLS, WAF y DDoS.
- Seguridad de contenedores, hosts, cloud, CI/CD y supply chain.
- Auditoría, detección, respuesta a incidentes y forense.
- Privacidad por diseño, consentimiento, derechos y retención.
- Seguridad de IA, datos de entrenamiento, prompt injection y fuga de información.

### H. Infraestructura, plataforma y operaciones
- Cloud, on-premises, híbrido, edge y selección de proveedores.
- Redes, DNS, balanceo, CDN, ingress/egress y service discovery.
- Contenedores, orquestación, Kubernetes y runtime.
- Infraestructura como código, configuración y policy as code.
- Secretos y configuración por ambiente.
- Alta disponibilidad, failover, resiliencia y continuidad.
- Backup, disaster recovery, RTO/RPO y pruebas de restauración.
- SRE, SLI/SLO/SLA, error budgets, guardias y runbooks.
- Observabilidad, alertas, capacidad y gestión de incidentes.
- Costos cloud, FinOps, presupuestos y optimización.

### I. Calidad, pruebas y entrega
- Pirámide de pruebas, unitarias, integración, contratos y E2E.
- Pruebas funcionales, regresión, aceptación y exploratorias.
- Rendimiento, carga, estrés, soak, escalabilidad y capacidad.
- Seguridad, fuzzing, property-based, mutación y análisis estático.
- Resiliencia, chaos engineering y pruebas de recuperación.
- Accesibilidad, compatibilidad, usabilidad y pruebas móviles.
- CI/CD, artefactos inmutables, SBOM, firmas y procedencia.
- Revisión de código, calidad, deuda técnica y gates.

### J. Especialidades de dominio y emergentes
- IA generativa, agentes, RAG, evaluación, guardrails y supervisión humana.
- Machine learning, MLOps, datos/modelos, drift y reproducibilidad.
- IoT, dispositivos, firmware, telemetría y gestión de flotas.
- Sistemas de tiempo real, streaming y baja latencia.
- Sistemas financieros, pagos, conciliación y controles antifraude.
- Salud, datos clínicos y seguridad de pacientes cuando aplique.
- Sistemas críticos, safety engineering y análisis de peligros.
- Blockchain o tecnologías distribuidas especializadas solo si existe necesidad.
- Geoespacial, mapas, geocodificación y datos de ubicación.
- Búsqueda, recomendación, analítica y plataformas de datos.

## 4. Mapeo a estándares existentes

El índice de cada carpeta identifica los documentos disponibles. Los temas sin documento propio deben evaluarse contra los estándares transversales y, cuando sean materialmente aplicables, declararse como brecha de biblioteca. No se debe fingir cobertura completa por proximidad temática.

## 5. Criterios para agregar un estándar

Crear un estándar especializado cuando el tema:
- tenga amenazas, controles, ciclo de vida o pruebas propias;
- requiera decisiones repetibles entre proyectos;
- no pueda explicarse adecuadamente como una sección breve de otro documento;
- tenga suficiente estabilidad y aplicabilidad para justificar mantenimiento.

Evitar duplicación: usar un estándar principal y referencias cruzadas, definiendo claramente el propietario del requisito.

## 6. Revisión de exhaustividad

Antes de cerrar la planificación de un proyecto, el agente debe:
- recorrer todas las familias A–J;
- revisar documentos existentes y brechas;
- preguntar por tecnologías y capacidades especializadas;
- registrar todos los estados;
- explicar por qué no aplican las áreas descartadas;
- revisar si el alcance cambió y activar reevaluación.

## 7. Evolución del catálogo

El catálogo debe revisarse periódicamente y ante nuevas amenazas, cambios regulatorios, tecnologías relevantes, incidentes, auditorías o solicitudes de proyectos. Mantener historial de cambios y compatibilidad con versiones anteriores.
