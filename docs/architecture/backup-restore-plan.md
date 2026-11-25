# Plan backup / restore / PITR

**Estado:** diseño aprobado — subfase 0.6
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.6
**Autoridad:** ADR-0012, ADR-0014
**Base:** [PostgreSQL HA y réplicas de lectura](./postgresql-ha-and-read-replicas.md)

---

## 1. Propósito

Define la estrategia de backup, restauración y Point-in-Time Recovery (PITR) para PostgreSQL.
Es un diseño; no configura herramientas, cron jobs ni credenciales.

---

## 2. Principios

- La replicación física **no sustituye** el backup. Una réplica propaga deletes,
  corrupción lógica y errores de aplicación.
- El backup es independiente del clúster HA y se almacena fuera del dominio de fallo del clúster.
- PITR permite volver a cualquier instante cubierto por el archivado de WAL.
- Los backups se verifican periódicamente con restauración real; una copia no verificada
  no es un backup confiable.

---

## 3. Estrategia de backup

### 3.1 Tipos de backup

| Tipo | Frecuencia objetivo | Herramienta | Uso |
|---|---|---|---|
| Base consistente (full) | Diaria en producción | pgBackRest o pg_basebackup | Punto de partida para PITR |
| Archivado continuo de WAL | Continuo | pgBackRest o barman | PITR a cualquier instante |
| Snapshot de volumen | Diaria o por evento | Según infraestructura | Recuperación rápida de nodo |
| Backup lógico | Semanal (complementario) | pg_dump por schema | Recuperación selectiva de módulo |

La frecuencia exacta, retención y ventanas de backup se dimensionan por entorno antes de producción.

### 3.2 Retención

| Entorno | Backup base | Archivado WAL | Mínimo PITR |
|---|---|---|---|
| Producción | A definir por política de datos y regulación | Continuo | A definir por RPO aprobado |
| Staging | Menor retención | Continuo | Suficiente para pruebas |
| Desarrollo | Sin backup formal | No requerido | No aplica |

Los valores exactos se aprueban como parte de la política de retención de datos conforme a ADR-0014 y ADR-0018.

### 3.3 Almacenamiento de backups

- Almacenamiento separado del clúster; fuera del mismo dominio de fallo.
- Cifrado en tránsito (TLS) y en reposo.
- Control de acceso: solo `backup_reader` y el agente de backup tienen acceso.
- Protección contra borrado accidental o malicioso (retención mínima en el destino).
- No almacenar credenciales de backup en el repositorio ni en variables de entorno sin gestión de secretos.

---

## 4. Point-in-Time Recovery (PITR)

PITR permite restaurar la base a cualquier instante cubierto por los backups base y el WAL archivado.

**Casos de uso:**

- Error humano: DELETE o UPDATE masivo no intencional.
- Corrupción lógica propagada a réplicas.
- Bug de aplicación que corrompió datos antes de detectarse.

**Proceso conceptual:**

1. Identificar el instante objetivo anterior al incidente.
2. Restaurar el backup base más reciente anterior al instante objetivo.
3. Aplicar WAL archivado hasta el instante objetivo.
4. Verificar integridad de los datos restaurados.
5. Promover como nuevo primario solo después de verificación.

**Restricciones:**

- PITR no es instantáneo; el tiempo de recuperación depende del volumen de WAL a aplicar.
- El RTO real se mide con pruebas periódicas; no se asume un valor sin medición.
- Un PITR a un instante pasado descarta todas las transacciones posteriores a ese instante.

---

## 5. Runbooks requeridos antes de producción

Antes de exponer cualquier superficie productiva, deben existir y probarse los siguientes runbooks:

| Escenario | Runbook | Prueba requerida |
|---|---|---|
| Pérdida del primario | Failover manual y automático | Simulación de caída del primario |
| Pérdida de zona de disponibilidad | Recuperación multi-zona | Simulación de zona caída |
| Error humano (delete masivo) | PITR a instante anterior | Restauración completa y verificación de datos |
| Corrupción lógica | PITR + verificación de integridad | Simulación de corrupción controlada |
| Réplica irrecuperable | Reconstrucción de standby desde base | Simulación de standby corrupto |
| Backup vencido o inaccesible | Procedimiento de emergencia | Verificación de acceso y frescura de backup |
| WAL archivado interrumpido | Restauración del archivado | Simulación de interrupción de archivado |
| Restauración selectiva de módulo | pg_dump/restore de schema | Restauración de un schema en staging |

---

## 6. Verificación periódica

| Verificación | Frecuencia objetivo | Criterio |
|---|---|---|
| Restauración completa del backup base | Mensual en producción | Cluster restaurado y operativo en entorno aislado |
| PITR a instante aleatorio | Mensual en producción | Datos consistentes; duración medida y dentro de RTO |
| Integridad del archivado WAL | Semanal | Sin gaps en el archivado; todos los segmentos accesibles |
| Acceso y descifrado del backup | Semanal | Backup descifrable con las claves vigentes |
| Prueba de failover | Trimestral en producción | Failover completado; fencing verificado; sin split-brain |

Los resultados de cada verificación se registran con fecha, entorno, duración y responsable.
Una verificación fallida bloquea el avance a producción hasta resolverse.

---

## 7. Métricas y alertas de backup

| Métrica | Alerta cuando |
|---|---|
| Antigüedad del último backup base | Supera la frecuencia objetivo |
| Último WAL archivado | Retraso superior al umbral configurado |
| Espacio disponible en destino de backup | Inferior al margen configurado |
| Resultado de la última restauración de verificación | Fallida o no ejecutada en el período |
| Gaps en el archivado WAL | Cualquier gap detectado |

---

## 8. Retención de datos y baja de tenant

Conforme a ADR-0014, la baja de un tenant no elimina inmediatamente sus datos.
Los backups contienen datos de todos los tenants activos e inactivos durante el período de retención.

- El período de retención de backups debe considerar las obligaciones legales y fiscales por jurisdicción.
- La eliminación definitiva de datos de un tenant se coordina con la política de retención aprobada.
- Los backups no se modifican para eliminar datos de un tenant específico; se gestiona a nivel de datos activos.

---

## 9. Estado de implementación

Diseño aprobado. No existen herramientas de backup configuradas, cron jobs activos,
destinos de almacenamiento provisionados ni runbooks ejecutados. La implementación
comienza en la subfase 0.7 junto con la infraestructura.
