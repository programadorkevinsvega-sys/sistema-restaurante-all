# Runbooks de rotación de secretos y certificados

**Estado:** diseño aprobado — subfase 0.7
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.7
**Autoridad:** ADR-0023
**Documentos relacionados:**

- [Política de secretos](./secrets-policy.md)
- [Política TLS/criptográfica](./tls-crypto-policy.md)
- [Plan backup/restore/PITR](../architecture/backup-restore-plan.md)

---

## 1. Propósito

Define los procedimientos para rotar secretos y certificados sin downtime cuando sea posible,
y el protocolo de emergencia cuando la rotación sea urgente por compromiso sospechado.

Son procedimientos de diseño. Los comandos y herramientas concretos se completan cuando
se seleccione el gestor de secretos y la infraestructura de cada entorno.

---

## 2. Tipos de rotación

| Tipo | Disparador | Urgencia |
|---|---|---|
| Programada | Expiración próxima o calendario de rotación | Normal; con planificación |
| Por incidente | Sospecha o confirmación de exposición | Inmediata; sin planificación previa |
| Por offboarding | Salida de colaborador con acceso | Dentro de 24 horas |
| Por actualización de política | Cambio de algoritmo o longitud mínima | Normal; con planificación |

---

## 3. Runbook: Rotación programada de credencial PostgreSQL (`*_runtime`)

**Aplica a:** credenciales runtime de cada módulo en producción.
**Frecuencia objetivo:** según política del gestor de secretos (ej. 90 días).
**Downtime esperado:** ninguno si se sigue el procedimiento en caliente.

### Pasos

1. Verificar que el proceso tiene health checks funcionando y el pool puede reconectarse.
2. Generar la nueva credencial en el gestor de secretos con el mismo nivel de permisos.
3. Configurar el gestor para servir la credencial nueva como activa al proceso.
4. El proceso detecta la rotación y reconecta el pool con la nueva credencial (o reiniciar el proceso si no hay reconexión automática).
5. Verificar métricas del pool: conexiones activas normales, sin errores de autenticación.
6. Revocar la credencial anterior en PostgreSQL y en el gestor.
7. Registrar la rotación con fecha, actor, módulo y resultado.

**Verificación post-rotación:**

- [ ] Pool reconectado sin errores.
- [ ] No hay errores `password authentication failed` en logs.
- [ ] Credencial anterior revocada y no funcional.
- [ ] Registro en bitácora de rotación.

---

## 4. Runbook: Rotación de certificado TLS de servicio (mTLS interno)

**Aplica a:** certificados de Admin BFF, Public BFF, Admin Platform Backend, Public Backend.
**Frecuencia objetivo:** según validez del certificado (días o semanas para internos).
**Downtime esperado:** ninguno con rolling restart.

### Pasos

1. Emitir nuevo certificado desde la CA intermedia interna con el mismo SAN.
2. Actualizar el secreto en el gestor con el nuevo par certificado/clave.
3. Reiniciar los procesos gradualmente (rolling restart) para que carguen el nuevo certificado.
4. Verificar que los procesos pares aceptan el nuevo certificado (sin errores TLS en logs).
5. Revocar el certificado anterior en la CA (CRL o OCSP).
6. Registrar la rotación.

**Verificación post-rotación:**

- [ ] Fecha de expiración del nuevo certificado verificada con `openssl x509 -noout -dates`.
- [ ] Sin errores TLS handshake en logs de todos los procesos.
- [ ] Certificado anterior revocado.

---

## 5. Runbook: Rotación de certificado TLS público (HTTPS externo)

**Aplica a:** certificado del Load Balancer / punto de entrada público.
**Frecuencia objetivo:** automatizada (Let's Encrypt o equivalente, 60-90 días).
**Downtime esperado:** ninguno con renovación automatizada.

### Pasos (renovación automatizada)

1. El agente de renovación (certbot, cert-manager u equivalente) solicita nuevo certificado.
2. El LB carga el nuevo certificado sin reiniciar (recarga en caliente cuando sea posible).
3. Verificar que el certificado activo tiene la nueva fecha de expiración.
4. Alertar si la renovación falla más de N días antes de la expiración.

### Pasos (renovación manual si falla la automatizada)

1. Identificar el motivo del fallo (DNS, ACL, credencial del agente).
2. Corregir la causa raíz.
3. Forzar la renovación manual siguiendo el procedimiento del agente.
4. Verificar y registrar.

---

## 6. Runbook: Rotación de clave de firma de tokens de sesión

**Aplica a:** clave usada por IDENTITY para firmar access tokens y refresh tokens.
**Frecuencia objetivo:** según política (ej. 30 días o por sospecha de compromiso).
**Downtime esperado:** ninguno con período de gracia; sesiones existentes pueden quedar inválidas si no hay gracia.

### Pasos con período de gracia

1. Generar la nueva clave y publicarla en el gestor de secretos con un identificador de versión (kid).
2. Configurar IDENTITY para aceptar tokens firmados con la clave anterior Y la nueva durante el período de gracia.
3. Los nuevos tokens se firman con la clave nueva.
4. Al expirar el período de gracia, retirar la aceptación de la clave anterior.
5. Revocar la clave anterior en el gestor.
6. Registrar la rotación.

**Período de gracia:** duración máxima de un access token (todos los tokens anteriores expiran naturalmente).

---

## 7. Runbook: Rotación de emergencia (secreto comprometido)

**Disparador:** confirmación o sospecha fundada de que un secreto fue expuesto.
**Tiempo objetivo:** iniciar en menos de 1 hora de detectado.

### Pasos

1. **No compartir el valor comprometido** en ningún canal de comunicación.
2. Identificar el secreto: qué es, qué sistemas puede acceder, período de exposición.
3. Notificar al responsable de seguridad del repositorio.
4. **Revocar el secreto comprometido inmediatamente** en el gestor de secretos y en el sistema destino (PostgreSQL, Redis, NATS, proveedor externo).
5. Emitir el secreto de reemplazo y distribuirlo a los procesos afectados.
6. Reiniciar los procesos que usan el secreto para que carguen el nuevo.
7. Revisar logs de acceso durante el período de exposición para detectar uso malicioso.
8. Evaluar si el incidente requiere notificación a tenants afectados (conforme a ADR-0018 y política de respuesta a incidentes).
9. Documentar el incidente con timeline, causa raíz, impacto y medidas tomadas.
10. Revisar la causa raíz y corregir el proceso que permitió la exposición.

**Criterio de cierre:** secreto comprometido revocado y no funcional; secreto nuevo verificado en uso; incidente documentado; causa raíz corregida o con plan de corrección.

---

## 8. Registro de rotaciones

Cada rotación se registra con:

| Campo | Descripción |
|---|---|
| Fecha y hora | UTC |
| Actor | Persona o sistema que ejecutó la rotación |
| Secreto / certificado | Identificador (sin el valor) |
| Entorno | Producción, staging, desarrollo |
| Tipo de rotación | Programada, incidente, offboarding, política |
| Resultado | Exitosa / fallida |
| Verificaciones | Lista de checks completados |
| Notas | Incidencias o desviaciones del procedimiento |

El registro se almacena en un lugar protegido (no el mismo sistema cuyo secreto se rotó).

---

## 9. Estado de implementación

Runbooks aprobados como diseño. No existen automatizaciones de rotación configuradas,
agentes de renovación activos ni registros de rotación. La implementación comienza
con el aprovisionamiento de infraestructura y el gestor de secretos de cada entorno.
