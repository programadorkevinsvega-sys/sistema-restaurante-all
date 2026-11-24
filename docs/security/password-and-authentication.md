# Seguridad de contraseñas y autenticación

**Estado:** especificación técnica aprobada y vigente, asociada a [ADR-0011 Accepted](../adr/0011-password-hashing-and-authentication-security.md). No constituye una implementación.  
**Propietario funcional:** IDENTITY, exclusivamente en Public Backend.  
**Ámbito:** credenciales locales, autenticación, MFA, sesiones, recuperación y controles contra abuso.

## 1. Propósito y límites

Este documento desarrolla la decisión aceptada en requisitos verificables para su futura implementación. No crea crates, código, endpoints, tablas, migraciones, secretos, infraestructura ni dependencias.

IDENTITY es la única autoridad de credenciales. Admin BFF y Public BFF transportan solicitudes hacia contratos autorizados de IDENTITY; no calculan ni verifican hashes y no leen PostgreSQL de IDENTITY. Admin Platform Backend consume esos contratos cuando corresponda, sin duplicar usuarios o credenciales.

Los BFF pueden recibir la contraseña en la frontera HTTPS y transmitirla exclusivamente por gRPC autenticado y cifrado al servicio IDENTITY. El valor solo existe en memoria durante el flujo de autenticación y nunca se persiste, registra, traza o publica en eventos.

## 2. Hashing de contraseñas

### 2.1 Algoritmo y parámetros

- Algoritmo obligatorio para nuevas credenciales: Argon2id.
- Parámetros mínimos: memoria 19 MiB, iteraciones 2, paralelismo 1.
- Salt: al menos 16 bytes generados por un CSPRNG, único por hash.
- Codificación persistida: PHC string con algoritmo, versión, parámetros, salt y hash.
- La biblioteca elegida deberá generar salts seguros y verificar el formato PHC; no implementar Argon2 ni generación aleatoria criptográfica manualmente.
- Nunca almacenar la contraseña original, ni usar MD5, SHA-1, SHA-256 u otro hash rápido como sustituto.
- No comparar hashes de contraseñas como texto ni asumir que contraseñas iguales producen hashes iguales: el salt único hace que los resultados sean distintos.

Los parámetros son un mínimo, no un máximo. Deben medirse en la infraestructura objetivo y aumentarse si el presupuesto de latencia y memoria lo permite. Cualquier reducción por debajo del mínimo requiere un ADR posterior.

### 2.2 Persistencia

La aplicación almacenará el PHC completo en `identity.password_credentials.password_hash`. El salt no requiere columna separada porque forma parte del PHC. `password_algorithm` debe corresponder con el algoritmo real. El historial conservará hashes anteriores según la política configurada y retención limitada.

No se almacenarán hashes ni secretos de autenticación en eventos de dominio, Outbox, Inbox, trazas, logs, métricas, mensajes de error ni metadatos de usuario.

### 2.3 Actualización de parámetros

Cada autenticación correcta comprobará si el hash usa una versión o costo inferior a la política actual. Si está obsoleto, se calculará un nuevo hash con salt nuevo y se actualizará de forma atómica, evitando sobrescribir cambios concurrentes de contraseña.

No se requiere reset masivo solo por elevar parámetros: el rehash progresivo se hará al autenticar. Si una cuenta no vuelve a iniciar sesión, su hash antiguo permanece hasta que se autentique o se aplique un procedimiento de recuperación autorizado.

## 3. Política de contraseñas

- Longitud mínima objetivo: 15 caracteres.
- Longitud máxima admitida: al menos 64 caracteres; el sistema no truncará la entrada.
- Aceptar espacios, caracteres imprimibles y Unicode.
- Contar longitud por puntos de código Unicode. Cualquier normalización debe definirse de forma consistente y no cambiarse para usuarios existentes sin plan de compatibilidad.
- No imponer reglas arbitrarias de composición como exigir mayúsculas, números y símbolos en combinaciones fijas.
- Bloquear contraseñas comunes, esperadas o conocidas como comprometidas. La comprobación no debe revelar la contraseña a un tercero.
- Permitir gestores de contraseñas, autocompletado y pegar contraseñas.
- No exigir rotación periódica arbitraria; forzar cambio cuando exista evidencia de compromiso o recuperación.
- No usar preguntas de seguridad ni pistas accesibles antes de autenticar.

**Compatibilidad pendiente:** la definición SQL actual usa `password_min_length DEFAULT 12`. La política aprobada de 15 caracteres requiere alinear configuración persistida, validación y pruebas mediante una tarea SQL/migración separada, autorizada expresamente. Este documento no modifica esa definición ni autoriza ejecutar migraciones.

## 4. Protección contra ataques online

### 4.1 Throttling y bloqueos

- Limitar intentos por cuenta y por IP/origen.
- Mantener el estado de límites de forma compartida entre réplicas; no depender solo de contadores locales en memoria.
- Respetar `identity.tenant_auth_settings.max_failed_attempts` y `lockout_duration_seconds` como parámetros configurables.
- Aplicar demoras progresivas, límites de concurrencia y detección de patrones de credential stuffing.
- No depender únicamente del bloqueo permanente de una cuenta, que podría usarse para denegar servicio al usuario legítimo.
- Responder con mensajes genéricos que no distingan usuario inexistente, contraseña incorrecta, cuenta bloqueada o estado de verificación.
- Registrar el evento de seguridad con identificadores y metadatos mínimos, nunca con la contraseña ni el hash.

La tecnología de almacenamiento distribuido del throttling no queda fijada aquí. Al implementar, se debe elegir una capacidad existente y aprobada que sobreviva a múltiples réplicas; no introducir Redis u otro servicio por inferencia.

### 4.2 Protección de Argon2id y Tokio

- Aplicar controles de tamaño de solicitud y throttling antes del cálculo costoso.
- Ejecutar Argon2id fuera de los workers asíncronos principales de Tokio, mediante trabajo bloqueante.
- Proteger el trabajo bloqueante con un límite explícito de concurrencia y un presupuesto de memoria. El límite debe derivarse de memoria disponible por réplica, costo Argon2id por operación y concurrencia objetivo.
- Aplicar backpressure cuando se alcance el límite; no crear una tarea ilimitada por cada intento.
- Definir timeout, cancelación y comportamiento ante saturación sin revelar detalles internos al cliente.
- Probar bajo carga que el login no degrada gRPC, HTTP, workers ni otros módulos del proceso.

Para cuentas inexistentes se usará un camino de verificación ficticia con costo comparable, cuando sea necesario, para reducir diferencias temporales que permitan enumeración. No se revelará si la cuenta existe.

## 5. MFA, sesiones y recuperación

### MFA

- Mantener TOTP y WebAuthn como métodos contemplados por IDENTITY.
- MFA es obligatorio para usuarios/roles privilegiados conforme a la política de tenant ya diseñada.
- La ampliación a todos los usuarios es una decisión de producto separada.
- Los secretos TOTP y OIDC se cifran o gestionan mediante KMS/Vault; no se guardan en claro.
- Los códigos de recuperación son aleatorios, de un solo uso, con expiración y almacenados mediante hash.

### Sesiones y tokens

- Access tokens de corta duración; no persistirlos como credenciales recuperables.
- Refresh tokens aleatorios, almacenados solo mediante hash.
- Rotación de refresh tokens, detección de reutilización y revocación de la familia de sesión ante reutilización.
- Expiración por inactividad y absoluta según política del tenant.
- Revocación al cambiar contraseña, recuperar cuenta o detectar compromiso, conforme al riesgo y política definida.
- No mantener estado autoritativo de sesión solo en memoria de una réplica.

### Recuperación

- Tokens de recuperación con entropía criptográfica, un solo uso, expiración y almacenamiento mediante hash.
- Respuestas de solicitud de recuperación genéricas para no enumerar cuentas.
- Invalidar tokens pendientes y sesiones comprometidas al completar la recuperación, según el flujo aprobado.
- No usar preguntas de seguridad ni información personal como factor de recuperación.

## 6. Secretos y observabilidad

- No registrar contraseñas, PHC strings, salts, pepper, refresh tokens, access tokens, códigos MFA ni tokens de recuperación.
- Aplicar redacción en logs y trazas de errores de autenticación.
- Eventos de auditoría solo registran resultado, motivo categorizado, tenant/usuario cuando corresponda y contexto mínimo.
- No incluir secretos en métricas, atributos OpenTelemetry, baggage, headers de correlación ni eventos NATS.
- Pepper no forma parte del requisito inicial. Si se adopta, se guarda fuera de PostgreSQL en KMS/Vault, con versión y plan de rotación/recuperación.

## 7. Secuencia futura de implementación

La secuencia no autoriza comenzar implementación. Cada etapa se ejecutará en su tarea/PR y con las autorizaciones correspondientes.

1. **Inspección y diseño:** leer crate IDENTITY, contratos, configuración SQLx, dependencias y pruebas existentes. No asumir que existen manifests o código.
2. **Hasher:** seleccionar crate Rust mantenido y compatible con el workspace real; fijar versión. Implementar hashing PHC, verificación, validación de parámetros y rehash.
3. **Flujos de credenciales:** integrar registro, cambio y verificación con IDENTITY. Evitar que contratos expongan hashes.
4. **Política:** aplicar longitud, blocklist, Unicode y compatibilidad de tenant settings. Cualquier cambio SQL se tramita por separado y con autorización expresa.
5. **Resiliencia:** throttling compartido, límites por cuenta/IP, concurrencia y memoria acotadas para Argon2id, backpressure y mensajes genéricos.
6. **MFA y sesiones:** TOTP/WebAuthn, códigos de recuperación, refresh rotation, expiración y revocación.
7. **Verificación de seguridad:** pruebas y evidencia descritas en la sección siguiente.

## 8. Matriz mínima de pruebas futuras

| Área | Prueba requerida |
|---|---|
| Salt | Dos usuarios con la misma contraseña obtienen PHC distintos |
| Verificación | La contraseña correcta verifica y una incorrecta falla |
| PHC | Formato malformado, parámetros no admitidos y versiones antiguas se manejan de forma segura |
| Rehash | Hash obsoleto se actualiza tras login válido; fallo de actualización no produce estado inconsistente |
| Persistencia | Nunca se guarda contraseña en claro ni se filtra el hash a contratos |
| Política | Longitud mínima/máxima, Unicode, espacios, blocklist y ausencia de truncamiento |
| Enumeración | Respuestas y caminos temporales no revelan fácilmente existencia de cuenta |
| Throttling | Límites por cuenta/IP coordinados entre réplicas y bloqueo temporal recuperable |
| Tokio | Saturación controlada, límite de concurrencia, memoria acotada y backpressure |
| MFA | TOTP/WebAuthn, códigos de recuperación de un solo uso y rechazo de replay |
| Sesiones | Rotación, detección de reutilización, expiración y revocación |
| Recuperación | Token aleatorio, hash almacenado, expiración y uso único |
| Observabilidad | Logs, trazas, eventos y métricas sin contraseñas ni secretos |

Las pruebas deberán ejecutarse y reportarse con comando, entorno y resultado. La existencia de esta matriz no significa que estén implementadas ni ejecutadas.

## 9. Referencias técnicas

- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) — algoritmo, salt, PHC y costos mínimos de Argon2id.
- [NIST SP 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html) — longitud, blocklists, Unicode, no truncamiento y ausencia de rotación periódica arbitraria.
- [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html) — especificación de Argon2.


## 10. Estado

**Especificación técnica aprobada conforme a ADR-0011 Accepted; implementación pendiente.** No se han creado crates, código, endpoints, tablas, migraciones, secretos, infraestructura ni dependencias por este documento. No se han modificado archivos SQL ni migraciones.
