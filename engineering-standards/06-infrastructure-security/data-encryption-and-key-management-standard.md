# Estándar de cifrado de datos y gestión de claves

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proteger datos almacenados y respaldos mediante cifrado apropiado y una gestión controlada del ciclo de vida de claves criptográficas.

## Requisitos

- Clasificar los datos y definir cuándo el cifrado en reposo es obligatorio por sensibilidad, amenaza, contrato o regulación.
- Cifrar medios, volúmenes, backups, snapshots y objetos almacenados según el riesgo; el cifrado de disco no sustituye controles por registro o campo cuando estos sean necesarios.
- Evaluar cifrado a nivel de aplicación o campo para datos de alta sensibilidad y escenarios donde administradores de infraestructura no deban acceder al contenido.
- Utilizar algoritmos, modos y bibliotecas criptográficas mantenidos y recomendados por estándares reconocidos; no diseñar criptografía propia.
- Generar claves con fuentes criptográficamente seguras y mantenerlas separadas de los datos cifrados.
- Gestionar claves mediante KMS, HSM o mecanismo equivalente con control de acceso, auditoría, separación de funciones y protección contra borrado accidental.
- Definir jerarquía de claves, propósito, propietario, alcance, versión, rotación, expiración, revocación y recuperación.
- Limitar quién puede crear, usar, exportar, rotar o destruir claves.
- No registrar claves, plaintext sensible ni material criptográfico en logs, repositorios, imágenes o tickets.
- Diseñar rotación y re-cifrado sin pérdida de disponibilidad ni de capacidad de recuperación.
- Mantener copias y procedimientos de recuperación de claves compatibles con el modelo de backup; una copia cifrada irrecuperable equivale a pérdida de datos.
- Definir destrucción criptográfica y tratamiento de claves comprometidas.
- Documentar qué datos no se cifran a nivel de campo y por qué, sin presentar el cifrado como sustituto de autorización.

## Operación

Probar rotación, recuperación, revocación y restauración en entornos controlados. Supervisar expiración, errores de KMS/HSM, uso anómalo y accesos privilegiados.

## Verificación

Pruebas de cifrado y descifrado, permisos de claves, rotación, recuperación, revocación, restauración de backups y ausencia de material secreto en artefactos.
