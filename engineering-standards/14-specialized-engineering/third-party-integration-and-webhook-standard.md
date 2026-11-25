# Estándar de integraciones externas y webhooks

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a proveedores externos, callbacks, webhooks, APIs de terceros y sincronizaciones.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Inventariar proveedor, finalidad, datos compartidos, dueño, criticidad, SLA, límites, región y plan de salida.
- Aislar adaptadores; evitar propagar modelos propietarios del proveedor por el dominio.
- Autenticar webhooks mediante firma criptográfica, timestamp/ventana anti-replay y rotación de secretos; validar antes de procesar.
- Tratar payloads como no confiables; validar esquema, tamaño, tipos y campos desconocidos.
- Responder rápido y procesar de forma durable; deduplicar eventos, tolerar reintentos y no asumir orden.
- Definir timeouts, límites, circuit breaker, backoff+jitter, cuotas y manejo de 429/5xx.
- Mantener correlación, auditoría, reconciliación y manejo de eventos perdidos.
- Versionar contratos y probar sandbox, fallos, duplicados, firmas inválidas y cambios incompatibles.
- Definir baja del proveedor, exportación, eliminación de credenciales y continuidad manual.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.
- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.
- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.
- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.
- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.

## 8. Amenazas y escenarios de fallo específicos

Evaluar spoofing de proveedor, replay, SSRF mediante callbacks, rotación fallida de secretos, payload malicioso, reintentos explosivos, pérdida/duplicación/desorden de eventos, indisponibilidad prolongada, cambio incompatible de API y dependencia sin salida viable.

## 9. Pruebas de aceptación mínimas

- Rechazar firma inválida, timestamp fuera de ventana y evento repetido; aceptar rotación de claves sin interrupción.
- Probar payload inválido, campos desconocidos, tamaños extremos y contenido malicioso.
- Simular 429, 5xx, timeout, DNS/TLS fallido, proveedor lento y caída prolongada; verificar backoff, límites y circuit breaking.
- Verificar recepción rápida con procesamiento durable y deduplicación incluso tras reinicio.
- Reconciliar eventos recibidos con estado del proveedor para detectar huecos.
- Probar revocación de credenciales, exportación y procedimiento manual de continuidad/salida.

## 10. Operación y evidencias

Conservar inventario de proveedores, contratos/versiones, scopes de credenciales, pruebas de firma/replay, métricas de errores/lag, reconciliaciones, runbooks y ejercicios de salida.