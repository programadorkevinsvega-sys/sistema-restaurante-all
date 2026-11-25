# Estándar de protección contra abuso de APIs

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Reducir abuso automatizado, scraping, agotamiento de recursos y extracción no autorizada sin bloquear injustificadamente usuarios legítimos.

## Requisitos

- Definir límites por identidad, tenant, IP, ruta, operación, costo y proveedor según riesgo.
- Combinar rate limiting con cuotas, concurrency limits, límites de payload y presupuestos de ejecución.
- Aplicar controles contra credential stuffing, enumeración, scraping y automatización maliciosa.
- Usar señales de riesgo y detección adaptativa sin depender de una sola señal fácilmente falsificable.
- Proteger endpoints de autenticación, recuperación, búsquedas costosas, exports y operaciones financieras.
- Responder con errores consistentes y tiempos de espera razonables.
- Evitar que el rate limit permita denegación de servicio contra una víctima mediante claves controladas por atacante.
- Definir excepciones para integraciones confiables con credenciales y cuotas propias.
- Proteger APIs públicas con controles de origen, CORS correcto y autenticación apropiada; CORS no es autorización.
- Registrar señales de abuso minimizando datos personales.

## Verificación

Pruebas de carga, ráfagas, distribuido, evasión por IP, abuso de cuentas, fairness multi-tenant y falsos positivos.
