# Estándar offline-first y sincronización de clientes

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica cuando la aplicación debe funcionar sin conectividad o sincronizar datos entre cliente y servidor.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Identificar operaciones permitidas offline y distinguir comandos pendientes de resultados confirmados por servidor.

- Definir fuente autoritativa, modelo de consistencia, política de conflicto y resolución por tipo de dato.

- Mantener outbox local durable, identificadores de operación, idempotencia y reintentos con límites.

- No inferir éxito remoto por guardar localmente; mostrar estado pendiente, sincronizado, fallido o conflicto.

- Definir expiración, revocación, borrado remoto, protección del dispositivo y cifrado local.

- Resolver orden causal y versiones; no usar únicamente reloj del dispositivo.

- Diseñar sincronización incremental, cursores, tombstones, límites de payload y recuperación tras interrupción.

- Evitar conflictos destructivos mediante operaciones semánticas, versionado o resolución humana cuando sea necesario.

- Probar desconexión, reconexión, duplicados, reloj incorrecto, cambio de cuenta, dispositivo perdido y versiones antiguas.

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

Evaluar repetición maliciosa de comandos, manipulación de estado local, pérdida/robo del dispositivo, revocación mientras está offline, conflicto concurrente, reordenamiento, reloj manipulado, cursor inválido, tombstones expirados, sincronización parcial y divergencia prolongada.

## 9. Pruebas de aceptación mínimas

- Enviar el mismo comando repetidas veces y comprobar efecto único e idempotencia extremo a extremo.

- Cortar conectividad en cada fase de una operación y verificar estados honestos y recuperación.

- Simular conflictos concurrentes por campo, agregado y eliminación; verificar política determinista o escalamiento humano.

- Alterar reloj, cursores, versiones, orden de eventos y respuestas duplicadas.

- Revocar usuario/dispositivo y verificar que las operaciones pendientes no se ejecutan sin autorización vigente.

- Medir límites de cola, almacenamiento, reintentos, payload y sincronización masiva.

## 10. Operación y evidencias

Conservar especificación de consistencia, matriz de conflictos por entidad, pruebas de replay, métricas de lag/cola/reintentos, política de expiración y evidencia de revocación y recuperación.
