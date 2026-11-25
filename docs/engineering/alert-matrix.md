# Matriz de alertas con severidad y runbook

**Estado:** diseño aprobado — subfase 0.8
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.8
**Autoridad:** ADR-0015, ADR-0026
**Documentos relacionados:**

- [Estrategia de observabilidad](./observability-design.md)
- [Runbooks de respuesta a incidentes](./incident-response-runbooks.md)

---

## 1. Convenciones

| Campo | Descripción |
|---|---|
| **Severidad** | `critical` / `high` / `medium` / `low` |
| **Señal** | Métrica o condición que dispara la alerta |
| **Ventana** | Período de evaluación |
| **Umbral** | Condición de disparo; valores concretos se fijan con carga medida |
| **Propietario** | Responsable de triaje inicial |
| **Runbook** | Sección del runbook de respuesta |
| **Resolución** | Condición de cierre de la alerta |

Toda alerta tiene propietario, runbook y condición de resolución.
Los umbrales se dimensionan antes de producción con métricas reales; no se fijan valores arbitrarios aquí.

---

## 2. Alertas de disponibilidad de procesos

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Proceso no disponible | Critical | Health check / up metric = 0 | > 1 min | Ops | INC-01 |
| Tasa de errores HTTP elevada | High | `http_requests_total{status=~"5.."}` / total | > umbral en ventana de 5 min | Ops | INC-02 |
| Latencia p99 elevada | High | `http_request_duration_seconds` p99 | > umbral SLO en 5 min | Ops | INC-02 |
| gRPC error rate elevado | High | `grpc_server_requests_total{code!="OK"}` / total | > umbral en 5 min | Ops | INC-02 |
| Reinicios frecuentes del proceso | High | Contador de reinicios del contenedor | > N reinicios en 10 min | Ops | INC-01 |

---

## 3. Alertas de PostgreSQL

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Pool de conexiones agotado | Critical | Conexiones adquiridas = max del pool | > 90% por > 2 min | Ops | INC-03 |
| Primario no disponible | Critical | Health check PostgreSQL primario | > 30 s | Ops | INC-03 |
| Lag de réplica excesivo | High | Lag de replicación (bytes/segundos) | > umbral configurado | Ops | INC-03 |
| Deadlocks sostenidos | High | `pg_stat_database_deadlocks` | > N en ventana | Ops | INC-03 |
| Consultas lentas sostenidas | Medium | Duración de consultas lentas (p99) | > umbral en 10 min | Dev | INC-03 |
| Almacenamiento PostgreSQL crítico | Critical | Espacio libre en disco | < 15% | Ops | INC-03 |
| Réplica síncrona no disponible | High | Estado de standby síncrono | Desconectado > 1 min | Ops | INC-03 |
| Backup vencido | High | Antigüedad del último backup base | > frecuencia objetivo + margen | Ops | INC-06 |

---

## 4. Alertas de NATS / JetStream

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Nodo NATS no disponible | Critical | Health check / cluster state | > 1 min | Ops | INC-04 |
| Consumer lag excesivo | High | `nats_consumer_num_pending` | > umbral por consumer | Ops | INC-04 |
| Pending ACK creciente | High | `nats_consumer_num_ack_pending` | > umbral sin reducción en 5 min | Ops | INC-04 |
| Redeliveries excesivos | High | `nats_consumer_num_redelivered` | > N en ventana | Dev | INC-04 |
| Almacenamiento JetStream crítico | Critical | Espacio libre de JetStream | < 20% | Ops | INC-04 |
| Outbox con antigüedad excesiva | High | Antigüedad del mensaje pendiente más antiguo en Outbox | > umbral de negocio | Dev | INC-04 |
| DLQ con mensajes nuevos | High | Contador de mensajes en DLQ | > 0 en ventana | Dev | INC-04 |

---

## 5. Alertas de Redis

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Nodo Redis no disponible | Critical | Health check | > 1 min | Ops | INC-05 |
| Memoria Redis crítica | Critical | `redis_memory_used_bytes` / max | > 85% | Ops | INC-05 |
| Evictions inesperadas | High | `redis_evicted_keys_total` | > 0 en ventana de operación normal | Ops | INC-05 |
| Latencia Redis elevada | Medium | Latencia de comandos p99 | > umbral | Ops | INC-05 |
| Hit ratio muy bajo | Medium | `redis_keyspace_hits` / (hits + misses) | < umbral mínimo | Dev | INC-05 |

---

## 6. Alertas de seguridad

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Ráfaga de login fallido | Critical | `audit.user.login_failed` por actor/IP | > N en ventana de 5 min | Security | INC-SEC-01 |
| Intento de acceso entre tenants | Critical | `audit.access.cross_tenant_attempt` | Cualquier evento | Security | INC-SEC-01 |
| Intento de escalada de privilegios | Critical | `audit.access.privilege_escalation_attempt` | Cualquier evento | Security | INC-SEC-01 |
| Cambio privilegiado anómalo | High | `audit.user.role_assigned` fuera de horario o desde IP inusual | Heurística | Security | INC-SEC-02 |
| Exportación masiva inusual | High | `audit.export.massive_data` volumen anómalo | > umbral por actor | Security | INC-SEC-02 |
| Webhook con firma inválida repetido | High | `audit.webhook.invalid_signature` | > N en ventana | Dev | INC-SEC-02 |
| Secreto con sospecha de exposición | Critical | Evento manual o detección de Gitleaks | Cualquier evento | Security | INC-SEC-03 |
| Certificado próximo a vencer | High | Días hasta expiración | < 30 días (externo) / < 7 días (interno) | Ops | ROT-01/02 |

---

## 7. Alertas de workers y Sagas

| Alerta | Severidad | Señal | Umbral | Propietario | Runbook |
|---|---|---|---|---|---|
| Saga requiriendo intervención | High | Estado `intervention_required` en tabla `sagas` | > 0 | Dev | INC-04 |
| Worker sin progreso | High | Worker activo pero 0 mensajes procesados en ventana | > N min sin actividad | Dev | INC-04 |
| Job periódico no ejecutado | High | Ausencia de ejecución exitosa en ventana esperada | > 2× frecuencia objetivo | Dev | INC-04 |

---

## 8. Alertas de observabilidad (meta-alertas)

| Alerta | Severidad | Señal | Umbral | Propietario |
|---|---|---|---|---|
| Collector no recibiendo datos | High | Ausencia de señales de un proceso por > 5 min | — | Ops |
| Almacenamiento de logs crítico | Critical | Espacio libre en Loki | < 15% | Ops |
| Almacenamiento de trazas crítico | High | Espacio libre en Tempo | < 20% | Ops |
| Prometheus sin scraping de un proceso | High | Target down en Prometheus | > 2 min | Ops |

---

## 9. Estado de implementación

Diseño aprobado. No existen reglas de Alertmanager configuradas, umbrales fijados
ni notificaciones activas. Los umbrales se fijan con métricas de carga real antes de
producción. La implementación comienza junto con la infraestructura de observabilidad.
