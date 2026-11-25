# Estándar de sistemas en tiempo real y streaming

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a WebSocket, SSE, telemetría, eventos continuos, baja latencia y procesamiento de streams.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir latencia objetivo, throughput, jitter, pérdida tolerable, orden, retención y semántica de entrega.
- Diferenciar tiempo real estricto de near-real-time; no prometer límites sin plataforma y medición.
- Controlar buffers, backpressure, slow consumers, desconexión y reanudación por cursor.
- Definir particionado, claves de orden, ventanas, watermark y eventos tardíos cuando corresponda.
- Autenticar conexiones, autorizar canales y limitar conexiones, mensajes y tamaños.
- Evitar estado de sesión crítico en nodos efímeros; diseñar reconexión y afinidad solo cuando sea necesaria.
- Manejar duplicados, replay, evolución de esquemas y retención.
- Probar picos, consumidores lentos, pérdida de red, failover, skew de reloj y saturación.

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

Evaluar agotamiento de conexiones/buffers, slow consumers, abuso de canales, fuga entre suscriptores, replay, eventos fuera de orden, poison messages, particiones, lag creciente, pérdida de cursor, skew temporal y cascadas por reconexión masiva.

## 9. Pruebas de aceptación mínimas

- Medir latencia p50/p95/p99, throughput, jitter, pérdida y lag bajo carga representativa.
- Simular consumidor lento, buffer lleno, payload excesivo, conexión abrupta y tormenta de reconexión.
- Verificar autorización por canal y aislamiento de datos en cada reconexión/suscripción.
- Probar replay, cursor expirado, duplicados, eventos tardíos, orden por clave y evolución incompatible de esquema.
- Forzar failover, partición de red y saturación; comprobar backpressure y recuperación sin cascada.
- Validar límites de conexiones, mensajes, tamaño, frecuencia y duración.

## 10. Operación y evidencias

Conservar SLI de latencia/lag/errores/conexiones, límites de buffers, políticas de retención, pruebas de carga/failover, dashboards, alertas y runbooks de consumidor lento y reconexión masiva.