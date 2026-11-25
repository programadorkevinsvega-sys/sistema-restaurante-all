# ADR-0025: Protección contra abuso de APIs, bots, DDoS y extracción de datos

- Estado: **Proposed**
- Fecha: 2026-11-25
- Ámbito: APIs públicas/internas, autenticación, automatización, cuotas, scraping, consumo de recursos, integraciones y egreso de datos.
- Complementa: ADR-0003, ADR-0007, ADR-0010, ADR-0011, ADR-0013, ADR-0015, ADR-0016, ADR-0017 y ADR-0020 a ADR-0022.
- Aprobación: pendiente de aprobación explícita.

## Contexto

Una API puede ser correcta y permitir abuso: fuerza bruta, credential stuffing, enumeración, scraping, exportaciones masivas, automatización de pedidos, consumo ilimitado de IA/SMS/correo, solicitudes costosas o DDoS. Límites solo por IP no bastan en un SaaS multi-tenant detrás de NAT/proxies.

## Decisión propuesta

### 1. Límites multidimensionales

Aplicar límites según riesgo combinando IP/red normalizada desde proxies confiables, identidad autenticada, tenant, API key/integración, dispositivo/sesión si la señal es confiable, ruta/método/clase de operación y proveedor facturable. No confiar en headers de IP enviados directamente por clientes.

Distinguir autenticación, lecturas, búsquedas, escrituras, exportaciones, informes, archivos, operaciones financieras e integraciones.

### 2. Rate limits, cuotas y concurrencia

- Límites por ventana y clase de operación.
- Cuotas por tenant/proveedor para recursos facturables o limitados.
- Concurrencia máxima por usuario, tenant, proceso, worker y proveedor.
- Límites de body, headers, parámetros, profundidad, resultados y duración.
- Paginación y máximo de registros para listados/exportaciones.
- Rechazar temprano solicitudes fuera de límites.
- Respuestas consistentes sin revelar detalles internos.
- Límites por plan solo si contrato y reglas de PLATFORM lo determinan; plan no sustituye autorización.
- Agotamiento de cuota no debe convertirse en consumo ilimitado ante fallos de contabilización.

### 3. Backpressure y resiliencia

Timeouts explícitos HTTP/gRPC/DB/Redis/NATS/proveedores; colas y buffers acotados; backpressure; reintentos limitados con backoff+jitter; circuit breakers cuando una dependencia lenta amplifique el fallo. No reintentar operaciones mutables de resultado incierto sin idempotencia/reconciliación. Los límites no deben romper ACKs, Outbox/Inbox ni garantías JetStream.

### 4. Autenticación y cuentas

Alinear con ADR-0011: límites progresivos contra fuerza bruta, spraying y credential stuffing; respuestas que eviten enumeración; protección de recuperación/MFA; límites por cuenta y origen; detección de anomalías. Evitar bloqueos globales que permitan denegar servicio a una víctima sin controles compensatorios.

### 5. Bots y scraping

Detectar automatización anómala por frecuencia, secuencia, volumen y comportamiento. Proteger catálogo, búsqueda, reservas, pedidos, autenticación y exportaciones. Evitar enumeración secuencial y recolección masiva. CAPTCHA no es defensa única ni debe exigirse indiscriminadamente. API keys con alcance, expiración, revocación, rotación y cuotas; integraciones legítimas tendrán identificación y límites propios. Evitar falsos positivos contra accesibilidad y clientes autorizados.

### 6. DDoS y borde

Diferenciar ataque volumétrico de abuso de aplicación. Mitigación volumétrica corresponde a proveedor/red; WAF y rate limit no la sustituyen. Proteger BFF con límites de conexión, tamaño, timeout y concurrencia. Mantener endpoints internos privados. Degradar funciones no críticas de forma controlada y mantener runbooks.

### 7. Denial of Wallet

Definir presupuesto/cuota por tenant y proveedor para IA, correo, SMS, mapas, pagos, almacenamiento y otros servicios facturables. Limitar cantidad, tamaño, duración y concurrencia. Aplicar deduplicación/idempotencia y caché apropiada. Evitar que una petición pequeña dispare procesamiento externo ilimitado. Alertar aumentos anómalos. Definir comportamiento ante cuota agotada o proveedor caído.

### 8. Exportación y exfiltración

Cada exportación se autoriza en el módulo propietario y limita tenant, filtros, campos y volumen. Registrar solicitante, propósito y resultado. Reforzar controles en datos sensibles y exportaciones masivas. URLs firmadas tendrán alcance limitado y expiración breve; la URL no sustituye autorización inicial. Restringir destinos salientes, detectar lecturas/descargas anómalas y poder aislar tenant/integración/proceso comprometido.

### 9. Redis y límites

Este ADR no aprueba automáticamente Redis para rate limiting. Cualquier uso debe ser compatible con ADR-0016, que define Redis Cluster como caché y delimita usos. No convertirlo en broker, cola durable, fuente autoritativa, almacenamiento único de sesiones o lock de negocio. Evaluar atomicidad, expiración, particiones, failover, reloj, scope tenant y degradación. Si cambia la responsabilidad arquitectónica de Redis, requerirá decisión específica.

### 10. Auditoría y pruebas

Registrar abuso, bloqueos, cuota agotada, exportaciones y excepciones sin secretos/payloads sensibles. Correlacionar conforme ADR-0015. Probar fuerza bruta, enumeración, scraping, ráfagas, solicitudes lentas, payloads grandes, colas llenas, proveedor lento/caído, cuota agotada, exportación masiva, replay, retries, NAT y bypass de proxy. Verificar ausencia de efectos parciales/duplicados.

## Alternativas consideradas

Rate limit solo por IP, límite global uniforme, CAPTCHA como defensa principal, WAF como sustituto de DDoS y reintentar cualquier timeout se rechazan. Uso implícito de Redis también se rechaza.

## Consecuencias

Protege disponibilidad, costos, equidad entre tenants y datos. Requiere calibración y observabilidad; límites excesivos afectan clientes legítimos y límites laxos no frenan abuso.

## Límites

No fija números universales, proveedor WAF/CDN/anti-DDoS ni mecanismo de rate limit. No implementa middleware ni infraestructura.

## Plan futuro

Clasificar endpoints por costo/riesgo; definir límites iniciales; aplicar controles en borde y módulo propietario; crear métricas/runbooks; probar abuso/carga/fallos; ajustar con datos reales.

## Estado de implementación

Proposed. No implementa rate limits, cuotas, WAF, DDoS, CAPTCHA, controles Redis ni reglas de red.
