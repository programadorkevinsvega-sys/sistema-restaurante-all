# Política de secretos

**Estado:** diseño aprobado — subfase 0.7
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.7
**Autoridad:** ADR-0023
**Documentos relacionados:**

- [Modelo de red](./network-model.md)
- [Política TLS/criptográfica](./tls-crypto-policy.md)
- [Runbooks de rotación](./rotation-runbooks.md)

---

## 1. Propósito

Define las reglas de gestión de secretos para los cuatro procesos de Restaurant OS.
No selecciona un proveedor de gestor de secretos; esa decisión se toma en el diseño
de despliegue de cada entorno.

---

## 2. Qué es un secreto

Son secretos y se rigen por esta política:

- DSN y credenciales de PostgreSQL (`*_runtime`, `*_migrator`, `replication_user`, `backup_reader`).
- Credenciales de Redis Cluster (contraseñas ACL, certificados cliente).
- Credenciales de NATS (tokens, certificados, claves NKey).
- Credenciales de proveedores externos (PSP, email, SMS, integraciones).
- Claves de firma de tokens de sesión y refresh tokens.
- Claves de cifrado en reposo (datos, backups, almacenamiento de objetos).
- Certificados TLS y sus claves privadas.
- Claves API de observabilidad y exporters.
- Secretos de CI/CD (tokens de registro de imágenes, credenciales de despliegue).
- Cualquier valor que, si se expone, permita acceso no autorizado a un sistema o dato.

---

## 3. Dónde se almacenan los secretos

| Entorno | Gestor de secretos | Prohibido |
|---|---|---|
| Producción | Gestor externo dedicado (Vault, AWS Secrets Manager, GCP Secret Manager u equivalente) | Git, variables de entorno en texto plano, imágenes, logs, tickets |
| Staging | Gestor separado del de producción | Mismo gestor que producción |
| Desarrollo | Archivos locales no versionados (`.env` en `.gitignore`) o gestor local | Git, repositorio compartido, imágenes |

Los secretos de producción nunca se copian a staging ni desarrollo.

---

## 4. Separación de secretos por dimensión

Cada secreto es único según estas dimensiones:

- **Por proceso:** Admin BFF, Public BFF, Admin Platform Backend, Public Backend tienen credenciales distintas para cada servicio de datos.
- **Por módulo:** cada módulo tiene su propio `*_runtime` PostgreSQL; no comparten credencial.
- **Por propósito:** migración, runtime, backup, monitoreo y administración son identidades diferentes.
- **Por entorno:** producción, staging y desarrollo tienen secretos completamente independientes.

---

## 5. Ciclo de vida de un secreto

```text
Emisión → Distribución → Uso → Rotación → Revocación → Eliminación
```

| Etapa | Regla |
|---|---|
| Emisión | Generada por el gestor o con entropía criptográfica suficiente; nunca manualmente predecible |
| Distribución | Inyectada en el proceso en tiempo de ejecución; nunca en variables de build ni capas de imagen |
| Uso | Solo el proceso autorizado la usa; sin logging, sin pasar a hijos salvo necesidad explícita |
| Rotación | Programada antes de expiración; sin downtime cuando sea posible (rotación en caliente) |
| Revocación | Inmediata ante sospecha de exposición; proceso documentado en runbook |
| Eliminación | Después de verificar que ningún proceso activo la usa |

---

## 6. Reglas de uso

- No registrar secretos en logs, trazas, métricas, eventos de auditoría ni respuestas de API.
- No pasar secretos como argumentos de línea de comandos.
- No incluir secretos en variables de entorno de build (solo de runtime).
- No versionar secretos en Git bajo ninguna circunstancia, incluyendo branches privadas.
- No reutilizar secretos entre entornos.
- No compartir secretos entre los cuatro procesos.
- Gitleaks en CI detecta exposición accidental en el repositorio (control ya activo desde PR #33).

---

## 7. Acceso humano a secretos privilegiados

- Requiere MFA activo.
- Requiere justificación registrada (issue, ticket o registro en gestor de secretos).
- Acceso temporal con expiración automática cuando el gestor lo soporte.
- Registrado en AUDIT con actor, recurso, timestamp y justificación.
- El acceso humano a secretos de producción se revisa periódicamente y se revoca cuando ya no es necesario.

---

## 8. Ante sospecha o confirmación de exposición

1. **No copiar ni compartir el valor expuesto** en ningún canal (chat, ticket, email).
2. Identificar el secreto afectado y su alcance (qué sistemas y datos puede acceder).
3. Notificar al responsable de seguridad del repositorio.
4. **Revocar y rotar inmediatamente** sin esperar confirmación de uso malicioso.
5. Verificar logs de acceso durante el período de exposición.
6. Registrar el incidente conforme al proceso de respuesta a incidentes (subfase 0.8).
7. Revisar y corregir la causa raíz antes de emitir nuevas credenciales.

Eliminar el commit o archivo no es suficiente. El historial de Git puede contener el valor;
la rotación es siempre obligatoria.

---

## 9. Inventario de secretos requeridos por proceso

| Proceso | Secretos requeridos |
|---|---|
| Admin Platform Backend | DSN `platform_runtime`, credencial Redis PLATFORM, credencial NATS PLATFORM, clave firma tokens, certificados TLS cliente |
| Public Backend | DSN `*_runtime` × 19 módulos, credencial Redis × módulos elegibles, credencial NATS, credenciales proveedores externos, clave firma tokens, certificados TLS cliente |
| Admin BFF | Certificados TLS servidor, clave verificación tokens |
| Public BFF | Certificados TLS servidor, clave verificación tokens, credenciales proveedores públicos si aplica |
| Workers Outbox/Inbox | Credencial NATS worker, DSN `*_runtime` del módulo propio |
| CI/CD | Token registro de imágenes, credencial de despliegue temporaria |
| Backup | Credencial `backup_reader`, clave cifrado de backups |
| Monitoreo | Credencial `monitoring_reader`, token exporters |

---

## 10. Estado de implementación

Política aprobada. No existe gestor de secretos configurado, credenciales emitidas
ni ciclos de rotación activos. La implementación comienza con el aprovisionamiento
de infraestructura en cada entorno.
