# Runbooks de respuesta a incidentes

**Estado:** diseño aprobado — subfase 0.8
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.8
**Autoridad:** ADR-0026
**Documentos relacionados:**

- [Matriz de alertas](./alert-matrix.md)
- [Plan de respuesta y ejercicios](./incident-response-plan.md)
- [Runbooks de rotación](../infrastructure/rotation-runbooks.md)
- [Plan backup/restore/PITR](../architecture/backup-restore-plan.md)

---

## Convenciones

Cada runbook define: disparador, severidad inicial, pasos ordenados y criterio de cierre.
Los comandos concretos se completan cuando la infraestructura esté provisionada.
"Preservar evidencia" significa no borrar logs ni contenedores hasta tener una copia.

---

## INC-01 — Proceso no disponible o en crash loop

**Disparador:** health check falla > 1 min o contenedor reiniciando repetidamente.
**Severidad:** Critical.

### Pasos

1. Verificar estado del contenedor/pod: logs de los últimos reinicios.
2. Identificar si es OOM kill, panic de Rust, fallo de liveness probe o error de inicio.
3. Preservar logs del crash antes de que roten.
4. Si es OOM: revisar límites de memoria y carga actual; escalar verticalmente si hay margen.
5. Si es error de inicio: verificar secretos, DSN, certificados y conectividad a dependencias.
6. Si es panic: revisar stack trace en logs; escalar a desarrollo.
7. Reiniciar el proceso una vez identificada y mitigada la causa.
8. Verificar que el proceso pasa health checks y sirve tráfico.
9. Revisar si otros procesos del mismo tipo están afectados.
10. Documentar causa, duración y resolución.

**Criterio de cierre:** proceso estable por > 10 min sin reinicios; health checks verdes.

---

## INC-02 — Tasa de errores o latencia elevada

**Disparador:** `http_requests_total{status=~"5.."}` o latencia p99 supera SLO.
**Severidad:** High.

### Pasos

1. Identificar qué endpoint(s) o módulo(s) generan los errores.
2. Revisar trazas con errores en Tempo para localizar el span fallido.
3. Revisar logs del proceso con `error_code` correspondiente.
4. Verificar si la causa es una dependencia (PostgreSQL, Redis, NATS, proveedor externo).
5. Si es una dependencia: escalar al runbook correspondiente (INC-03/04/05).
6. Si es código: identificar si es regresión de despliegue reciente; evaluar rollback.
7. Si es carga: verificar rate limiting y pools; evaluar escalar réplicas.
8. Comunicar impacto estimado a responsables según severidad.
9. Resolver causa y verificar normalización de métricas.

**Criterio de cierre:** tasa de errores y latencia dentro de SLO por > 10 min.

---

## INC-03 — Incidente de PostgreSQL

**Disparador:** primario no disponible, pool agotado, lag de réplica excesivo o almacenamiento crítico.
**Severidad:** Critical / High según la señal.

### Pasos: primario no disponible

1. Verificar estado del clúster HA: ¿el gestor HA está promoviendo un standby?
2. No intervenir manualmente en la promoción si el gestor HA está actuando.
3. Verificar que el fencing del primario anterior se completó antes de que el nuevo acepte escrituras.
4. Monitorear reconexión de los pools de los cuatro procesos al nuevo primario.
5. Verificar que los pools descartan conexiones obsoletas correctamente.
6. Verificar integridad de datos: ¿hubo transacciones en vuelo al momento de la caída?
7. Documentar el failover: timestamps, nodo caído, nodo promovido, duración.

### Pasos: pool agotado

1. Identificar qué módulo tiene el pool agotado.
2. Verificar si hay transacciones largas o sin confirmar bloqueando conexiones.
3. Verificar si hay un spike de carga justificado o una fuga de conexiones.
4. Si hay transacciones colgadas: identificar y terminar con precaución (preservar evidencia primero).
5. Si es fuga: escalar a desarrollo para revisar código del módulo.
6. Evaluar aumentar temporalmente el límite del pool si hay margen en `max_connections`.

### Pasos: almacenamiento crítico

1. Identificar qué está creciendo: datos, WAL retenido, slot de replicación inactivo.
2. Si hay slot inactivo: evaluar eliminarlo después de verificar que la réplica está reconstruida.
3. Si es crecimiento de datos: alertar a producto; no borrar datos sin autorización.
4. Si es WAL: verificar que el archivado está funcionando; limpiar WAL archivado antiguo si la retención lo permite.

**Criterio de cierre:** clúster estable, pools reconectados, lag dentro de límites, almacenamiento con margen suficiente.

---

## INC-04 — Incidente de NATS / JetStream / Workers

**Disparador:** nodo NATS no disponible, consumer lag excesivo, DLQ con mensajes, Saga con intervención requerida.
**Severidad:** Critical / High.

### Pasos: nodo NATS no disponible

1. Verificar estado del clúster: ¿hay quorum? ¿cuántos nodos están activos?
2. Si hay quorum: el clúster sigue operativo; verificar que los procesos reconectan.
3. Si se perdió quorum: escalar; JetStream está degradado.
4. Verificar que los mensajes en Outbox siguen acumulándose (están en PostgreSQL, seguros).
5. Una vez restaurado NATS, el dispatcher retomará la publicación automáticamente.

### Pasos: consumer lag / DLQ

1. Identificar el consumer y stream afectados.
2. Revisar logs del worker para identificar el error que causa el rechazo.
3. Si es error permanente: los mensajes ya están en DLQ; no se reintentan automáticamente.
4. Corregir la causa raíz antes de hacer redrive.
5. Para redrive: verificar idempotencia del consumer; reenviar desde DLQ con la misma clave idempotente.
6. Monitorear que el lag se reduce después del redrive.

### Pasos: Saga con `intervention_required`

1. Identificar el `saga_id`, `saga_type` y el paso que falló.
2. Revisar logs y trazas del paso fallido.
3. Determinar si el efecto del paso ocurrió o no (consultar estado del módulo participante).
4. Ejecutar el comando de recuperación autorizado del módulo propietario.
5. Actualizar el estado de la Saga si se requiere intervención manual.
6. Documentar la intervención con actor, timestamp y resultado.

**Criterio de cierre:** clúster estable, lag dentro de límites, DLQ vacío o gestionado, Sagas resueltas.

---

## INC-05 — Incidente de Redis

**Disparador:** nodo Redis no disponible, memoria crítica, evictions inesperadas.
**Severidad:** Critical / High.

### Pasos: nodo no disponible

1. Redis Cluster redistribuye slots automáticamente si hay quorum.
2. Verificar que los procesos reconectan correctamente.
3. Redis es caché; los datos autoritativos siguen en PostgreSQL.
4. Verificar que los fallback a primario PostgreSQL funcionan para consultas críticas.
5. Si la pérdida de Redis es total: los procesos operan con mayor carga en PostgreSQL hasta restaurar.

### Pasos: memoria crítica o evictions

1. Identificar qué claves están creciendo más (via `redis_exporter` o comandos de monitoreo).
2. Verificar si las TTLs están configuradas correctamente.
3. No aumentar `maxmemory` indefinidamente sin análisis de capacidad.
4. Evaluar si hay un módulo con un patrón de escritura anómalo.
5. Escalar a desarrollo si el problema es de código.

**Criterio de cierre:** clúster estable, memoria dentro de límites, evictions bajo control.

---

## INC-SEC-01 — Incidente de seguridad: acceso no autorizado o credenciales comprometidas

**Disparador:** ráfaga de login fallido, intento de cruce de tenant, escalada de privilegios, secreto comprometido.
**Severidad:** Critical.

### Pasos

1. **Preservar evidencia** antes de cualquier acción: copiar logs, trazas y eventos de auditoría relevantes.
2. Revocar inmediatamente la credencial o sesión comprometida.
3. Si es credencial de servicio: seguir el runbook de rotación de emergencia (`rotation-runbooks.md`).
4. Identificar el alcance: ¿qué tenants, módulos y datos pudieron verse afectados?
5. Aislar el tenant o proceso si el impacto lo justifica.
6. Revisar logs de acceso durante el período de exposición para identificar uso malicioso.
7. Notificar al responsable de seguridad del repositorio.
8. Evaluar si hay obligación de notificación a tenants afectados (ver plan de respuesta).
9. Corregir la causa raíz.
10. Documentar el incidente completo.

**Criterio de cierre:** credencial revocada y no funcional; causa raíz corregida; alcance documentado; notificaciones realizadas si correspondían.

---

## INC-SEC-02 — Cambio privilegiado anómalo o exportación inusual

**Disparador:** cambio de roles fuera de horario, exportación masiva anómala, webhook con firma inválida repetido.
**Severidad:** High.

### Pasos

1. Verificar en eventos de auditoría quién ejecutó la acción, desde dónde y cuándo.
2. Contactar al actor para verificar si la acción fue legítima.
3. Si fue no autorizada: revocar sesión del actor y cambiar credenciales.
4. Si fue legítima pero anómala: revisar umbrales de alerta para reducir falsos positivos.
5. Documentar el triaje y resolución.

**Criterio de cierre:** acción verificada (legítima o ilegítima); si ilegítima, credenciales revocadas y causa corregida.

---

## INC-06 — Backup vencido o fallo de restauración

**Disparador:** último backup más antiguo de lo esperado, fallo en verificación periódica de restauración.
**Severidad:** High.

### Pasos

1. Verificar por qué falló el backup: credenciales, espacio, conectividad con el destino.
2. Corregir la causa y forzar un backup inmediato.
3. Verificar integridad del nuevo backup.
4. Si el fallo de restauración es en la verificación periódica: identificar el motivo (backup corrupto, credencial de descifrado, versión de PostgreSQL).
5. Escalar si no se puede restaurar desde ningún backup reciente.
6. Documentar y revisar el proceso de backup para prevenir recurrencia.

**Criterio de cierre:** backup reciente exitoso y verificado; restauración funcional en entorno aislado.

---

## Estado de implementación

Runbooks aprobados como diseño. Los comandos concretos se completan cuando la
infraestructura esté provisionada. Los ejercicios de simulación se ejecutan antes
de exponer superficies productivas.
