# ADR-0023: Seguridad de infraestructura, redes, secretos y criptografía

- Estado: **Accepted**
- Fecha: 2026-11-25
- Ámbito: redes, contenedores, ejecución, secretos, certificados, cifrado, PostgreSQL, Redis, NATS, backups y almacenamiento.
- Complementa: ADR-0007, ADR-0010, ADR-0012, ADR-0015, ADR-0016, ADR-0017, ADR-0018 y ADR-0020.
- Aprobación: aprobada explícitamente por el propietario del producto el 2026-11-25.

## Contexto

La seguridad depende también del entorno de los cuatro procesos. Un servicio de datos expuesto, contenedor privilegiado, secreto reutilizado, clave sin rotación o backup accesible puede anular controles de aplicación. Los ADR existentes definen topologías y garantías específicas; este ADR establece postura transversal sin reemplazarlas.

## Decisión

### 1. Redes y exposición

- Separar redes/reglas por entorno y función: entrada pública, aplicación, datos, administración y observabilidad.
- Exponer solo puntos de entrada necesarios.
- PostgreSQL, Redis, NATS, métricas y administración permanecen privados.
- Aplicar allowlists de entrada y salida con mínimo privilegio.
- Restringir egress por proceso para reducir SSRF, movimiento lateral y exfiltración.
- Acceso administrativo por canal privado controlado, MFA y trazabilidad; VPN/bastión se decide en diseño de infraestructura.
- Separar redes, identidades y secretos de desarrollo, pruebas, staging y producción.
- No copiar datos productivos a entornos inferiores salvo autorización y anonimización/minimización.

### 2. Contenedores y procesos

Ejecutar como no-root; evitar privileged; retirar capabilities innecesarias; filesystem read-only cuando sea viable; limitar CPU, memoria, procesos, descriptores y temporales; aplicar seccomp/AppArmor o equivalentes; usar imágenes mínimas y mantenidas, fijadas por digest cuando corresponda; escanear imágenes; separar permisos de build/runtime/administración; aislar parsers y procesadores de archivos conforme a ADR-0027.

### 3. Secretos y credenciales

- Usar gestor de secretos apropiado para producción; no seleccionar proveedor aquí.
- Separar credenciales por proceso, entorno, finalidad y privilegio.
- Prohibido guardar secretos en Git, imágenes, logs, bundles, artefactos o tickets.
- Preferir credenciales cortas y federación cuando esté disponible.
- Definir emisión, distribución, rotación, expiración, revocación, recuperación y auditoría.
- Exposición confirmada/sospechada activa rotación y evaluación de alcance.
- No compartir secretos entre los cuatro procesos.
- Credenciales de migración, runtime, backup, monitoreo y administración son identidades diferentes.
- Acceso humano a secretos privilegiados requiere MFA, justificación, temporalidad y registro.

### 4. Certificados y cifrado en tránsito

TLS obligatorio en fronteras sensibles conforme a ADR de PostgreSQL, Redis y NATS. Validar certificado y hostname; prohibido desactivar validación para resolver errores. TLS 1.2 mínimo y 1.3 preferido donde lo establecen los ADR específicos. Evaluar mTLS para servicio-a-servicio y administración con identidad y autorización por operación. Definir emisión, renovación, rotación, revocación y alertas de certificados. Red privada no sustituye autenticación/autorización.

### 5. Criptografía y claves

Usar algoritmos/bibliotecas mantenidos; no diseñar criptografía propia. Separar claves de cifrado, firma, autenticación y otros propósitos. Clasificar datos y definir cifrado en reposo según sensibilidad/obligación. Evaluar KMS/HSM sin seleccionar proveedor aquí. Cada clave tiene propietario, propósito, alcance, ciclo de vida, rotación, respaldo y recuperación. Proteger backups/exportaciones. UUIDv7, identificadores opacos y URLs firmadas no sustituyen autorización.

### 6. PostgreSQL y backups

Respetar ADR-0001, ADR-0010 y ADR-0012: ownership por módulo, roles mínimos, pools, topología HA single-writer y réplicas. No exponer PostgreSQL públicamente. Aplicaciones no usan superuser ni credenciales de migración. No crear permisos cruzados. Migraciones contra primario según proceso aprobado. Proteger y cifrar backups base, WAL, snapshots y copias PITR. Réplica no sustituye backup. Separar acceso a backups de credenciales runtime.

### 7. Redis y NATS

Redis respeta ADR-0016: Redis Cluster, TLS, ACL, ownership de claves y caché; no se convierte en fuente autoritativa, broker, cola durable, almacén único de sesión o lock de negocio por inferencia. NATS respeta ADR-0017: TLS, identidades, ACL por cuenta/subject, separación Core/JetStream, quorum, persistencia y recuperación. No usar credenciales administrativas compartidas para operaciones rutinarias.

### 8. Continuidad y recuperación

Definir RPO/RTO por clase de servicio/dato y validar topología. Mantener copias cifradas, protegidas y con credenciales separadas; evaluar copias inmutables/aisladas. Probar restauraciones e integridad. Evitar que una sola identidad comprometida borre producción y copias. Runbooks para corrupción, borrado, ransomware, pérdida de región y compromiso. La restauración debe reconciliar datos sujetos a eliminación/legal hold conforme ADR-0014/0018.

### 9. Observabilidad y cambios

Registrar cambios administrativos de red, permisos, secretos, certificados y configuración. Alertar exposición pública inesperada, certificados próximos a vencer, accesos fallidos y fallos de backup. Respetar ADR-0015: telemetría privada, mínimo privilegio y redacción. La pérdida de observabilidad no desactiva controles.

### 10. Identidad de proceso y contexto autenticado firmado

- mTLS es obligatorio entre los cuatro procesos. Cada proceso/worker tiene identidad de
  workload propia; el certificado autentica el proceso que conecta.
- Las aserciones de contexto de usuario tenant las emite IDENTITY en Public Backend; las
  aserciones de operador SaaS las emite PLATFORM en Admin Platform Backend.
- Cada aserción incorpora actor, issuer, audience, vigencia, ámbito y `kid`, y se firma
  mediante la clave privada correspondiente en AWS KMS.
- Los receptores verifican firma localmente, además de mTLS, audiencia, emisor, vigencia,
  estado de confianza de la clave y autorización del módulo propietario.
- Los BFF no inventan ni amplían claims. La identidad humana y la identidad del workload
  permanecen diferenciadas.
- AWS Certificate Manager / Private CA puede evaluarse para certificados; no se impone una
  CA concreta ni se selecciona runtime en este ADR.
- No se instalará ni operará Vault autogestionado como requisito de esta arquitectura.

## Alternativas consideradas

Exponer datos públicamente con autenticación; compartir secretos; contenedores privilegiados; desactivar validación TLS; tratar réplicas como backups: todo rechazado. Seleccionar proveedor KMS/infraestructura ahora se aplaza por requerir evaluación.

## Consecuencias

Reduce movimiento lateral, exposición, compromiso de secretos y riesgo de recuperación. Añade operación de certificados, segmentación, gestores de secretos, hardening, backups y pruebas; una mala configuración puede impedir failover/recuperación.

## Límites

No selecciona orquestador, VPN, bastión, WAF, CA concreta, imagen base ni parámetros de firewall. La decisión de usar AWS KMS, Secrets Manager e IAM queda aceptada; el runtime y la integración de certificados se concretan en 0.7. No modifica SQL ni migraciones.

## Plan futuro

Inventariar redes/puertos/identidades; diseñar matriz entrada-egress; definir PKI y secretos; seleccionar runtime; configurar KMS, IAM y Secrets Manager; endurecer imágenes; validar TLS/ACL de PostgreSQL, Redis y NATS; proteger backups; automatizar auditoría y alertas.

## Estado de implementación

Accepted. No instala servicios, cambia firewalls, crea secretos/certificados/roles/backups ni despliega infraestructura. La elección de AWS administrado y el uso de mTLS/contexto firmado están aceptados documentalmente, pero aún no desplegados.
