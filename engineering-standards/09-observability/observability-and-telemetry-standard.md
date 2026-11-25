# Estándar de observabilidad y telemetría

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proporcionar evidencia operativa correlacionable sin exponer datos sensibles ni crear costos incontrolados.

## Logs

- Emitir logs estructurados con timestamp UTC, servicio, entorno, nivel, evento y resultado.
- Incluir contexto de correlación y trazabilidad cuando esté disponible.
- Redactar secretos, tokens, contraseñas, datos de pago y datos personales sensibles.
- No registrar payloads completos por defecto.
- Definir niveles, retención, acceso, integridad y política de borrado.

## Métricas

- Medir RED (rate, errors, duration) y USE (utilization, saturation, errors) según componente.
- Medir colas, pools, workers, dependencias, cache, almacenamiento y procesos de recuperación.
- Evitar IDs únicos, emails, tokens y etiquetas de alta cardinalidad.
- Definir unidades, tipo, labels y propietario de cada métrica.

## Trazas

- Propagar contexto de trazas entre HTTP, RPC, mensajería y trabajos asíncronos.
- No confundir trace ID con event ID, command ID, correlation ID o ID de negocio.
- Crear spans para dependencias significativas y registrar errores de forma segura.
- Muestrear según volumen y valor diagnóstico sin perder trazas de errores críticos cuando la plataforma lo permita.

## Alertas y dashboards

- Alertar por síntomas de usuario, SLO, saturación y pérdida de capacidad, no solo por CPU.
- Cada alerta debe tener severidad, propietario, acción y runbook.
- Evitar alertas duplicadas o sin acción.
- Correlacionar métricas, logs y trazas.
- Proteger endpoints y datos de telemetría con RBAC y red privada.

## Resiliencia de observabilidad

La falla del sistema de telemetría no debe detener automáticamente el negocio. Los buffers deben tener límites y backpressure; la propia plataforma de observabilidad debe monitorearse.

## Verificación

Pruebas de propagación, redacción, cardinalidad, pérdida de collector, alertas, permisos y runbooks.
