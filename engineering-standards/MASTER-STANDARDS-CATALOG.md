# Catálogo maestro de estándares de ingeniería

**Versión:** 0.3.0 | **Estado:** Draft | **Carácter:** índice normativo de descubrimiento

## 1. Propósito y regla de exhaustividad

Este catálogo es el punto de entrada obligatorio para cualquier agente, arquitecto o equipo que inicie un proyecto usando esta biblioteca. Su función es evitar que la selección dependa de la memoria, preferencias o sesgos del agente.

**El agente DEBE recorrer todas las familias y registrar un resultado para cada estándar documental y cada tema del catálogo.** La fuente canónica del inventario identificable es el [Inventario exhaustivo y matriz de cobertura](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md), con IDs estables STD IDs y TOP IDs. No basta con leer el README ni seleccionar solo documentos que parezcan relevantes. No se permite un registro parcial ni omitir filas.

La biblioteca es extensible: la taxonomía no afirma que enumere para siempre toda disciplina existente. El agente debe buscar nuevas áreas, tecnologías, obligaciones, amenazas y riesgos emergentes. Los temas nuevos se registran provisionalmente y se proponen para la siguiente revisión del inventario.

## 2. Aplicabilidad y estado de adopción: dimensiones separadas

Cada elemento debe tener exactamente una clasificación de aplicabilidad y un estado de adopción. No son sinónimos.

**Aplicabilidad:** Aplica, Condicional o No aplica. Para Condicional, registrar disparador, evidencia y resultado. Para No aplica, registrar justificación y disparador de reevaluación.

**Estado de adopción:**

- **Adoptado:** aplica y sus requisitos son obligatorios.

- **Adoptado con adaptación:** aplica con ajustes explícitos y trazables.

- **Aplazado:** aplica, pero su implantación tiene fecha, responsable, riesgo aceptado y controles temporales.

- **No aplicable:** solo válido cuando la aplicabilidad sea No aplica.

- **Rechazado:** el propietario decide no adoptar un elemento aplicable; exige decisión explícita, impacto y mitigación.

- **Pendiente de decisión:** requiere respuesta del propietario; no autoriza al agente a asumir.

- **Brecha de biblioteca:** el tema es pertinente pero carece de estándar suficiente; requiere investigación y creación/revisión documental.

No usar omitido, no revisado, vacío ni silencio como estado final. No clasificar como No aplicable un requisito que aplica pero fue rechazado. Una decisión pendiente bloquea únicamente el diseño o implementación que dependa de ella.

## 3. Catálogo por familias

La siguiente lista es la taxonomía de descubrimiento. Cada tema tiene ID estable en el inventario y debe evaluarse individualmente.

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

## 4. Mapeo y límites de cobertura

El inventario vincula cada tema con documentos relacionados y clasifica brechas conocidas. Un documento relacionado puede cubrir solo parte del tema. El agente debe verificar alcance, requisitos, amenazas, controles, pruebas y evidencias; la similitud de nombres no demuestra cobertura. Temas como salud, safety engineering, geoespacial, blockchain, SEO, notificaciones móviles, gobierno de datos, DNS/CDN y otras brechas señaladas deben declararse como tales cuando resulten pertinentes.

## 5. Criterios para agregar un estándar

Crear un estándar especializado cuando el tema tenga amenazas, controles, ciclo de vida o pruebas propias; requiera decisiones repetibles; no pueda explicarse adecuadamente como sección breve de otro documento; y tenga suficiente estabilidad y aplicabilidad. Evitar duplicación y definir propietario de cada requisito.

## 6. Revisión de exhaustividad

Antes de cerrar la planificación, el agente debe recorrer todas las familias A–J y todos los IDs STD IDs y TOP IDs, crear una fila por ID, revisar documentos completos y brechas, registrar aplicabilidad y adopción por separado, justificar no aplicabilidad y reevaluar si cambia el alcance.

## 7. Evolución

El catálogo y el inventario deben revisarse juntos ante nuevos estándares, amenazas, regulación, tecnologías, incidentes, auditorías o solicitudes. Mantener historial, IDs estables y compatibilidad. Nunca reutilizar un ID retirado.
