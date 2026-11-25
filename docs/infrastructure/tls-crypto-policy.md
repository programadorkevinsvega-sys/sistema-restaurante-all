# Política TLS y criptografía

**Estado:** diseño aprobado — subfase 0.7
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.7
**Autoridad:** ADR-0023, ADR-0016, ADR-0017
**Documentos relacionados:**

- [Modelo de red](./network-model.md)
- [Política de secretos](./secrets-policy.md)
- [Runbooks de rotación](./rotation-runbooks.md)

---

## 1. Principios

- TLS obligatorio en todas las fronteras sensibles; nunca desactivar validación para resolver errores.
- Algoritmos y bibliotecas mantenidos; no diseñar criptografía propia.
- Cada clave tiene propietario, propósito, alcance, ciclo de vida, rotación, respaldo y recuperación.

---

## 2. TLS por frontera

| Frontera | Versión mínima | Versión preferida | mTLS | Notas |
|---|---|---|---|---|
| Cliente → Load balancer | TLS 1.2 | TLS 1.3 | No | Certificado servidor validado por cliente |
| LB → BFF interno | TLS 1.2 | TLS 1.3 | Opcional | Según infraestructura |
| BFF → Backend (gRPC) | TLS 1.2 | TLS 1.3 | Sí | mTLS entre procesos internos |
| Backend → Backend (gRPC) | TLS 1.2 | TLS 1.3 | Sí | mTLS entre procesos internos |
| Proceso → PostgreSQL | TLS 1.2 | TLS 1.3 | Sí | `sslmode=verify-full`; nunca `disable` ni `allow` |
| Proceso → Redis Cluster | TLS 1.2 | TLS 1.3 | Sí | Certificado cliente por proceso |
| Proceso → NATS | TLS 1.2 | TLS 1.3 | Sí | Certificado cliente por cuenta |
| Proceso → Proveedor externo | TLS 1.2 | TLS 1.3 | No (proveedor) | Validar hostname y cadena de confianza |
| Proceso → Object storage | TLS 1.2 | TLS 1.3 | No (proveedor) | HTTPS obligatorio |
| Replicación PostgreSQL | TLS 1.2 | TLS 1.3 | Sí | Certificado replication_user |
| Administración (bastion/ops) | TLS 1.3 | TLS 1.3 | Sí | Acceso solo desde zona `ops` |

**Reglas comunes a todas las fronteras:**

- Validar certificado y hostname/SAN; nunca `InsecureSkipVerify: true` en producción.
- Rechazar certificados auto-firmados no anclados en la CA de confianza del entorno.
- No usar SSLv3, TLS 1.0 ni TLS 1.1.
- Cipher suites: preferir ECDHE + AES-GCM o ChaCha20-Poly1305; deshabilitar suites sin forward secrecy.

---

## 3. Certificados

### 3.1 PKI interna

Para comunicaciones internas (mTLS entre procesos, PostgreSQL, Redis, NATS):

- CA raíz interna con clave almacenada offline o en KMS/HSM; no en filesystem del servidor.
- CA intermedia para emisión de certificados de servicio.
- Certificados de servicio con `SAN` que identifiquen el proceso/componente.
- Validez corta para certificados de servicio (días o semanas); renovación automatizada.

### 3.2 Certificados externos (TLS público)

- Emitidos por CA pública de confianza (Let's Encrypt, DigiCert u equivalente).
- Renovación automatizada con margen suficiente antes de expiración.
- HSTS activado con `includeSubDomains` y `preload` cuando corresponda.
- OCSP stapling habilitado cuando el servidor lo soporte.

### 3.3 Alertas de certificados

| Alerta | Umbral |
|---|---|
| Certificado próximo a vencer (externo) | 30 días antes |
| Certificado próximo a vencer (interno) | 7 días antes |
| Certificado expirado | Inmediato |
| Fallo de renovación automatizada | Inmediato |

---

## 4. Cifrado en reposo

| Dato | Cifrado requerido | Gestión de clave |
|---|---|---|
| Volúmenes PostgreSQL (producción) | Sí | Clave de volumen en KMS; rotación periódica |
| Backups PostgreSQL | Sí | Clave de backup separada de la de volumen |
| Snapshots Redis | Sí | Clave de snapshot |
| Almacenamiento de objetos (producción) | Sí | Clave por bucket o prefijo de módulo |
| Secretos TOTP/OIDC en IDENTITY | Sí | Clave de aplicación en KMS/Vault |
| Datos de desarrollo | No requerido | — |

---

## 5. Gestión de claves criptográficas

| Regla | Descripción |
|---|---|
| Separación de propósito | Claves de cifrado, firma, autenticación y derivación son claves distintas |
| Sin claves compartidas entre procesos | Cada proceso tiene sus propias claves de firma de tokens |
| Propietario | Cada clave tiene un propietario responsable de su ciclo de vida |
| Respaldo | Clave de respaldo almacenada offline o en KMS secundario; no en el mismo sistema |
| Rotación | Programada antes de expiración; sin downtime cuando sea posible |
| Revocación | Inmediata ante sospecha de compromiso |
| Auditoría | Acceso a claves críticas registrado con actor, timestamp y motivo |

Los algoritmos concretos (AES-256-GCM, ChaCha20-Poly1305, Ed25519, etc.) se fijan en el
diseño de despliegue de cada componente, usando bibliotecas mantenidas y auditadas.

---

## 6. Lo que no se hace

- No diseñar algoritmos criptográficos propios.
- No usar MD5, SHA-1 ni DES para ningún propósito de seguridad.
- No usar ECB como modo de cifrado por bloques.
- No hardcodear claves en código fuente, variables de entorno de build ni imágenes.
- No compartir claves de firma de tokens entre los cuatro procesos.
- No usar UUIDv7 ni timestamps como secreto o clave criptográfica.

---

## 7. Estado de implementación

Política aprobada. No existen CAs configuradas, certificados emitidos, claves generadas
ni cifrado en reposo activado. La implementación comienza con el aprovisionamiento
de infraestructura en cada entorno.
