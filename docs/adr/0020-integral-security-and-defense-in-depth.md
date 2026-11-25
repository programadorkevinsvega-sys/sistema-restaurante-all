# ADR-0020: Marco integral de seguridad y defensa en profundidad

- Estado: **Proposed**
- Fecha: 2026-11-25
- Ámbito: producto, aplicaciones, datos, procesos, infraestructura, desarrollo, operación y proveedores.
- Complementa: ADR-0001 a ADR-0019 según su estado; especialmente ADR-0007, ADR-0008, ADR-0011 a ADR-0018.
- Desarrollado por: ADR-0021 a ADR-0027.
- Aprobación: pendiente de aprobación explícita del propietario del producto.

## Contexto

Restaurant OS es un SaaS multi-tenant compuesto por cuatro procesos independientes, dos BFF, módulos propietarios de dominios, workers, mensajería, bases de datos, caché, almacenamiento y proveedores externos. Las superficies administrativas, públicas, operativas y de integración están expuestas a amenazas distintas. Una única barrera —autenticación, WAF, red privada, validación frontend o escáner— no es suficiente.

Los riesgos incluyen suplantación, robo de sesiones, escalada de privilegios, acceso cruzado entre tenants, inyección, abuso de APIs, manipulación de reglas comerciales, replay de mensajes, archivos maliciosos, exfiltración, compromiso de dependencias, ransomware e interrupción del servicio.

## Decisión propuesta

### 1. Principios obligatorios

1. Defensa en profundidad: controles preventivos, detectivos y correctivos.
2. Denegar por defecto acciones, conexiones, destinos y permisos.
3. Mínimo privilegio para usuarios, servicios, procesos, módulos, workers, pipelines y proveedores.
4. Verificación en cada frontera; no confiar en validaciones realizadas por otra capa.
5. Autorización final en el backend y módulo propietario del recurso.
6. Aislamiento multi-tenant validado por servidor; un identificador del cliente no constituye autoridad.
7. Separación de responsabilidades: los BFF componen/exponen interfaces y no adquieren ownership de dominios ni datos.
8. Preservar transacciones locales, Outbox/Inbox, idempotencia, Sagas y contratos versionados.
9. Privacidad desde el diseño, minimización y retención conforme a ADR-0014 y ADR-0018.
10. Trazabilidad sin guardar contraseñas, tokens, secretos, cookies, claves privadas, datos completos de pago ni payloads personales sensibles.
11. Fallos seguros: una dependencia caída nunca concede permisos ni provoca efectos duplicados.
12. Cada control debe tener propietario, pruebas, criterios de aceptación y evidencia.
13. Documentar un control no significa que esté implementado, configurado, probado o desplegado.

### 2. Activos y superficies

El marco cubre Admin Platform Backend (PLATFORM), Public Backend (demás módulos), Admin BFF, Public BFF, navegadores y clientes futuros, gRPC/Protobuf, NATS Core, JetStream, workers, Outbox/Inbox, Sagas, PostgreSQL, Redis, almacenamiento de objetos, backups, contenedores, redes, certificados, secretos, CI/CD, artefactos y proveedores de pagos, correo, mensajería, analítica, IA e integraciones.

### 3. Modelo de amenazas y fronteras

Se tratarán como fronteras independientes: navegador→BFF; BFF→backend; backend→backend; proceso→PostgreSQL/Redis/NATS; servicio→proveedor; CI/CD→producción; operador→datos y administración.

Cada análisis deberá considerar:
- suplantación, robo/reutilización de sesión y compromiso de credenciales;
- BOLA/IDOR, escalada horizontal/vertical y acceso entre tenants;
- XSS, CSRF, SSRF, SQL/command injection, traversal y deserialización insegura;
- fuerza bruta, scraping, bots, DDoS y agotamiento de recursos/costos;
- manipulación de precios, descuentos, inventario, caja, pagos y concurrencia;
- mensajes falsificados, replay, duplicados, eventos fuera de orden y credenciales internas comprometidas;
- malware, parsers vulnerables, bombas de descompresión y descargas no autorizadas;
- exposición de secretos, contenedores, dependencias, workflows y artefactos comprometidos;
- amenazas internas, exportación masiva, exfiltración y abuso de herramientas de IA;
- ransomware, borrado malicioso, corrupción y pérdida de disponibilidad.

### 4. Responsabilidades

- Los cuatro procesos mantienen identidad de servicio, permisos, configuración y ciclo de vida separados.
- Los BFF aplican controles de borde, pero no sustituyen autorización del módulo propietario ni consultan directamente PostgreSQL de negocio.
- Cada módulo conserva schema, rol, migraciones e historial SQLx independientes. No se crea historial ni schema compartido.
- PLATFORM administra el ciclo SaaS, no los datos de negocio de otros módulos.
- Workers y consumidores aplican identidad, autorización, validación, límites e idempotencia.
- Proveedores externos son fronteras no confiables: validar respuestas, firmas, callbacks y destinos.
- La telemetría no concede acceso a datos ni se convierte en repositorio paralelo.

### 5. Controles transversales mínimos

Cada funcionalidad evalúa identidad, autorización, tenant y alcance; validación de tipos/campos/límites; protección de sesiones, secretos y comunicaciones; límites de tamaño, tiempo, concurrencia, frecuencia y costo; integridad, idempotencia y replay; errores y degradación segura; auditoría; minimización/retención; pruebas negativas y de aislamiento.

Los detalles especializados se definen en ADR-0021 a ADR-0027. La validación de entradas se alinea con ADR-0019 cuando sea aceptado; no se presupone su aprobación mientras PR #26 permanezca abierto.

### 6. Excepciones y riesgo residual

Toda excepción registra motivo, activo/frontera, alcance, propietario, riesgo, controles compensatorios, fecha de expiración y plan de cierre. No hay excepciones indefinidas ni aceptación implícita. Una desviación de ADR aceptado requiere el proceso de gobernanza y aprobación explícita.

La aceptación de riesgo corresponde a la autoridad de producto/negocio designada. No se delega automáticamente a un escáner ni a un agente.

### 7. Preparación para producción

Antes de habilitar una superficie se aportará evidencia proporcional al riesgo de autenticación/autorización, aislamiento multi-tenant, validación y límites, secretos/TLS, análisis de dependencias e imágenes, auditoría/alertas/runbooks, backups y recuperación cuando aplique, pruebas de seguridad, tratamiento de hallazgos y aceptación de riesgos residuales.

La fase legal final de ADR-0018 no posterga los controles técnicos que deben construirse desde las fases que procesan datos.

### 8. Límites

No selecciona proveedores, WAF, SIEM, KMS/HSM, antivirus, scanners ni parámetros operativos universales. No cambia ownership, topología, protocolos, schemas, roles, SQL ni migraciones.

## Alternativas consideradas

- Confiar solo en el perímetro de red: rechazado; hay cuentas válidas, procesos internos y dependencias comprometibles.
- Delegar seguridad al frontend/BFF: rechazado; el cliente es manipulable y el módulo propietario autoriza.
- Crear un servicio central con acceso a todos los datos: rechazado; rompe ownership y amplía el impacto.
- Usar un ADR monolítico: rechazado; los dominios especializados requieren decisiones separadas.
- Considerar CI o un escáner como garantía: rechazado.

## Consecuencias

Beneficios: lenguaje común, límites claros, controles consistentes y preparación verificable. Costos: más diseño, pruebas, operación, evidencias y mantenimiento; controles mal calibrados pueden afectar latencia y experiencia.

## Plan de implementación futuro

1. Aprobar el marco y ADR especializados.
2. Inventariar activos, datos, fronteras y amenazas por proceso.
3. Traducir decisiones a requisitos y pruebas.
4. Priorizar autorización, aislamiento y amenazas críticas.
5. Integrar análisis automatizados y gates.
6. Instrumentar detección, auditoría y runbooks.
7. Ejecutar pruebas de penetración y ejercicios de respuesta.
8. Revisar riesgos en cambios materiales y antes de cada mercado productivo.

## Estado de implementación

Proposed. No implementa middleware, políticas, herramientas, pruebas, infraestructura ni controles. No modifica SQL, migraciones, schemas, roles, datos o despliegues.
