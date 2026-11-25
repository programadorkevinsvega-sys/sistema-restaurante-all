# Diseño de object storage y flujo seguro de archivos — subfase 0.9

**Estado:** diseño aprobado — subfase 0.9
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.9
**Autoridad:** ADR-0023, ADR-0027
**Documentos relacionados:**

- [Política de secretos](../infrastructure/secrets-policy.md)
- [Política TLS/criptográfica](../infrastructure/tls-crypto-policy.md)
- [Catálogo de eventos auditables](../engineering/audit-events-catalog.md)

---

## 1. Propósito

Define el diseño de object storage para Restaurant OS: aislamiento por entorno y módulo,
ownership de metadata, acceso temporal autorizado y flujo seguro de archivos subidos por
usuarios o generados por el sistema.

No selecciona proveedor de object storage.

---

## 2. Estructura de buckets / prefijos

Cada entorno y cada propósito tienen un bucket o prefijo separado.
No existe un bucket único compartido entre módulos ni entornos.

| Bucket / prefijo | Propietario | Contenido |
|---|---|---|
| `prod-platform-files` | PLATFORM | Logos, documentos de onboarding de tenants |
| `prod-identity-files` | IDENTITY | Avatares de usuario (si aplica) |
| `prod-billing-docs` | BILLING | Documentos fiscales emitidos (PDF/XML) |
| `prod-reporting-exports` | REPORTING | Exportaciones generadas |
| `prod-finance-docs` | FINANCE | Documentos contables y conciliaciones |
| `prod-integrations-files` | INTEGRATIONS | Archivos de importación/exportación de integraciones |
| `prod-tmp-quarantine` | Infraestructura | Archivos en cuarentena pendientes de análisis |
| `prod-backups-postgresql` | Infraestructura | Backups PostgreSQL (separado de archivos de negocio) |
| `staging-*` | Mismo patrón | Sin datos productivos |
| `dev-*` | Mismo patrón | Sin datos productivos |

**Reglas de acceso:**

- Cada módulo tiene credenciales propias acotadas a su bucket/prefijo.
- Ningún módulo lee objetos de otro módulo directamente.
- Los BFF no tienen acceso directo a object storage; obtienen URLs presignadas desde los módulos propietarios.
- El bucket de cuarentena solo es accesible por el servicio de análisis y el rol de ops.

---

## 3. Metadata de ownership

Cada objeto almacena metadata mínima en sus etiquetas/headers:

| Campo | Descripción |
|---|---|
| `owner-module` | Módulo propietario del objeto |
| `tenant-id` | Hash del tenant (nunca el UUID en claro como nombre visible) |
| `resource-type` | Tipo de recurso al que pertenece el archivo |
| `resource-id` | ID del recurso asociado |
| `upload-actor` | Hash del `user_id` que subió el archivo |
| `content-classification` | `public` / `internal` / `confidential` / `restricted` |
| `retention-policy` | Política aplicable según módulo y regulación |

La metadata es responsabilidad del módulo propietario. No se almacena en texto plano
información personal sensible que no sea estrictamente necesaria.

---

## 4. Acceso temporal mediante URLs presignadas

Los clientes (BFF → frontend) nunca acceden directamente a object storage.
El módulo propietario genera URLs presignadas bajo demanda.

```text
Frontend → BFF → Módulo propietario → [genera URL presignada con TTL corto]
                                              → Frontend descarga/sube directamente
```text
**Reglas de URLs presignadas:**

- TTL máximo: 15 minutos para descarga; 5 minutos para upload.
- Incluir restricciones de Content-Type y tamaño máximo en la URL de upload.
- Una URL presignada no otorga permisos; el módulo verifica autorización antes de generarla.
- Registrar en AUDIT la generación de URLs para recursos sensibles (documentos fiscales, exportaciones).
- Las URLs no se loguean completas; solo el `resource_id` y el actor.

---

## 5. Flujo de upload seguro

```text
1. Cliente envía solicitud de upload al BFF
2. BFF reenvía al módulo propietario (gRPC)
3. Módulo verifica autorización del actor sobre el recurso
4. Módulo valida metadatos: tipo MIME esperado, tamaño máximo, tenant scope
5. Módulo genera URL presignada de upload con TTL 5 min y restricciones
6. Cliente sube el archivo directamente al object storage
7. Object storage notifica al módulo (webhook / polling) que el upload completó
8. Módulo inicia pipeline de validación y análisis (ver sección 6)
9. Módulo actualiza el estado del recurso solo después de que el archivo pase validación
10. Módulo registra el evento en AUDIT con actor, recurso y resultado
```text
---

## 6. Pipeline de validación y cuarentena

Todo archivo subido por un usuario pasa por validación antes de quedar disponible.

```text
Upload completado
      │
      ▼
[Cuarentena] ─── el archivo NO está accesible todavía
      │
      ▼
[Validación de tipo real]
  - Verificar magic bytes / firma del formato
  - Rechazar si no coincide con el Content-Type declarado
      │
      ▼
[Validación de tamaño y dimensiones]
  - Verificar que no supera el límite del módulo
  - Para imágenes: dimensiones dentro del rango permitido
      │
      ▼
[Análisis de contenido]
  - Antivirus / sandbox (cuando esté disponible en el entorno)
  - Detección de bomba de descompresión para archivos comprimidos
  - Para PDFs: validar estructura; no ejecutar JavaScript embebido
      │
      ├── FALLA → Archivo rechazado y eliminado; evento en AUDIT
      │
      └── PASA → Mover a bucket de producción
                 Módulo actualiza estado del recurso a "disponible"
                 Evento en AUDIT
```text
**Tipos permitidos por módulo (ejemplos):**

| Módulo | Tipos permitidos | Tamaño máximo |
|---|---|---|
| PLATFORM | `image/png`, `image/jpeg`, `image/webp` | 2 MB |
| BILLING | `application/pdf`, `text/xml` | 10 MB |
| REPORTING | `application/pdf`, `text/csv`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` | 50 MB |
| INTEGRATIONS | `text/csv`, `application/json`, `text/xml` | 20 MB |

Los tipos y límites se amplían módulo a módulo con justificación documentada.

---

## 7. Descarga segura

- Los objetos no tienen URL pública permanente; solo URLs presignadas con TTL corto.
- El módulo verifica autorización antes de generar la URL de descarga.
- El objeto se sirve con headers de seguridad:
  - `Content-Disposition: attachment` para forzar descarga y no ejecución.
  - `Content-Type` correcto (nunca `text/html` para archivos de usuario).
  - `X-Content-Type-Options: nosniff`.
- Los backups y exportaciones masivas requieren rol específico y se registran en AUDIT.

---

## 8. Ciclo de vida y retención

| Clase de objeto | Retención | Responsable |
|---|---|---|
| Documentos fiscales (BILLING) | Según regulación fiscal por jurisdicción (mínimo 5 años) | BILLING |
| Exportaciones de reporting | 30 días (configurable por tenant) | REPORTING |
| Archivos de integración | 30 días tras procesamiento | INTEGRATIONS |
| Logos y avatares | Mientras el recurso exista; eliminar al borrar el recurso | PLATFORM / IDENTITY |
| Archivos en cuarentena | 7 días; eliminar si fallan validación | Infraestructura |
| Backups PostgreSQL | Según política de backup aprobada | Infraestructura |

La eliminación de objetos de un tenant dado de baja sigue la política de ADR-0014;
no se elimina inmediatamente si hay obligaciones legales de retención.

---

## 9. Cifrado y seguridad

- Cifrado en reposo habilitado para todos los buckets de producción.
- TLS obligatorio para todas las operaciones (upload, download, URL presignada).
- Credenciales de acceso separadas por módulo y entorno; en gestor de secretos.
- Ningún objeto en bucket de producción es accesible públicamente de forma anónima.
- Los backups del object storage (si aplica) tienen las mismas protecciones que los backups de PostgreSQL.

---

## 10. Estado de implementación

Diseño aprobado. No existen buckets creados, credenciales emitidas, pipelines de validación
configurados ni objetos almacenados. La implementación comienza módulo a módulo cuando cada
módulo implemente sus operaciones de archivo en sus subfases correspondientes.
