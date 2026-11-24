# ADR-0011: Protección de contraseñas y controles de autenticación

- Estado: **Proposed**
- Propuesto: 2026-11-24
- Aceptado: pendiente de aprobación explícita del propietario del producto.
- Ámbito: módulo IDENTITY de Public Backend y sus consumidores autorizados.
- Complementa: ADR-0003, ADR-0007, ADR-0008 y ADR-0009.
- Documento operativo asociado: [Seguridad de contraseñas y autenticación](../security/password-and-authentication.md).

## Contexto

IDENTITY es el único propietario de las identidades y credenciales de usuarios de los tenants dentro de Public Backend. Admin BFF, Public BFF y los módulos consumidores utilizan sus contratos; no deben crear almacenes ni verificadores de contraseñas paralelos. Admin Platform Backend consume los contratos de IDENTITY cuando corresponda, sin duplicar usuarios ni credenciales.

El diseño SQL existente de IDENTITY ya contempla `identity.password_credentials.password_hash`, restringe `password_algorithm` a `argon2id`, contempla `identity.password_history`, políticas de autenticación por tenant, intentos fallidos, sesiones, MFA y hashes de refresh tokens y códigos de recuperación. Ese diseño no demuestra que los algoritmos o flujos estén implementados en la aplicación.

Las contraseñas no pueden almacenarse en texto plano ni protegerse con funciones hash rápidas de propósito general como MD5 o SHA-256. El sistema debe resistir tanto la filtración de la base de datos como ataques en línea contra el proceso de autenticación.

## Decisión propuesta

### 1. Propiedad y límites

1. IDENTITY en Public Backend es el único propietario de creación, cambio, verificación y recuperación de credenciales locales.
2. Los BFF actúan como fronteras HTTP y consumidores de contratos. No calculan hashes, no verifican contraseñas y no acceden directamente a tablas de IDENTITY.
3. Admin Platform Backend consume los contratos de IDENTITY cuando necesita identidad de usuarios; no duplica credenciales, usuarios ni autenticación autoritativa.
4. Las operaciones entre procesos usan los contratos gRPC definidos por la arquitectura. Las credenciales solo se transmiten por canales cifrados y autenticados; nunca se incluyen en eventos durables, Outbox/Inbox, trazas o logs.
5. Los contratos públicos no exponen `password_hash`, salt, pepper ni secretos de autenticación.

### 2. Hash de contraseñas

1. Argon2id será el único algoritmo admitido para nuevas contraseñas locales.
2. Cada hash utilizará un salt criptográficamente aleatorio, único e independiente. El salt tendrá al menos 16 bytes.
3. La biblioteca de hashing generará y codificará el salt; no se reutilizarán salts, no serán derivados de usuario/tenant y no se gestionarán manualmente.
4. El resultado se almacenará en formato PHC, que conserva algoritmo, parámetros, salt y hash. La aplicación verificará el formato y rechazará valores malformados sin revelar detalles internos.
5. Como configuración mínima de referencia se establece Argon2id con memoria de 19 MiB, 2 iteraciones y paralelismo 1. Se medirán y podrán elevar los costos en el hardware objetivo; nunca se reducirán por debajo de esta referencia sin un ADR posterior.
6. Se prohíbe usar MD5, SHA-1, SHA-256 u otros hashes rápidos directamente para almacenar contraseñas. bcrypt o scrypt no serán alternativas para nuevas credenciales; una eventual migración heredada requiere decisión específica.
7. Después de una autenticación correcta, la aplicación comprobará si el hash necesita actualización de parámetros y lo recalculará de forma segura cuando corresponda.

### 3. Política de contraseñas

1. La longitud mínima objetivo será de 15 caracteres y se permitirá una longitud máxima de al menos 64 caracteres. La política no impondrá reglas arbitrarias de composición por clases de caracteres.
2. Se aceptarán espacios y caracteres Unicode. La longitud se contará por puntos de código Unicode, sin truncar la contraseña. La normalización Unicode, si se adopta, será uniforme y documentada antes de habilitarla; nunca se cambiará silenciosamente para cuentas existentes.
3. Se rechazará la selección de contraseñas comunes, esperadas o conocidas como comprometidas mediante una lista de bloqueo. No se enviará la contraseña en texto claro a servicios externos para comprobarla.
4. No se exigirán cambios periódicos arbitrarios. Se forzará el cambio cuando exista evidencia de compromiso, recuperación de cuenta o una decisión de seguridad justificada.
5. El historial de contraseñas respetará la política configurable de IDENTITY; no se conservarán hashes indefinidamente y se aplicará retención limitada.
6. La política se aplicará en el backend, no solo en los formularios de los BFF.

La migración SQL existente declara actualmente un valor predeterminado de 12 para `password_min_length`. Este ADR no modifica esa migración. La implementación deberá incluir, en una tarea de esquema expresamente autorizada y antes de exigir la nueva política, la alineación del valor persistido y sus validaciones. No se permitirá una divergencia silenciosa entre configuración de tenant y política efectiva.

### 4. Pepper

El pepper no será requisito para la primera implementación. Si una decisión posterior lo incorpora, deberá almacenarse fuera de PostgreSQL en un gestor de secretos/KMS, tener versionado, procedimiento de rotación y estrategia de recuperación. Nunca se guardará junto al hash ni en variables/documentos versionados.

### 5. Defensa contra ataques en línea y agotamiento de recursos

1. El inicio de sesión aplicará limitación de intentos por cuenta y por origen, con estado compartido entre réplicas; no dependerá exclusivamente de memoria local.
2. Se respetarán los límites configurables de `identity.tenant_auth_settings`, incluyendo el umbral de intentos y duración de bloqueo. La respuesta al cliente será genérica y no revelará si la cuenta existe, está bloqueada o tiene una contraseña incorrecta.
3. Se aplicarán demoras progresivas y límites coordinados para evitar fuerza bruta y credential stuffing. El bloqueo de cuenta no será el único control ni permitirá una denegación de servicio trivial contra terceros.
4. La verificación Argon2id se ejecutará fuera de los hilos asíncronos principales de Tokio, en trabajo bloqueante con concurrencia y memoria máximas acotadas. Se aplicarán límites antes de iniciar cálculos costosos.
5. Para cuentas inexistentes se mantendrá un comportamiento de verificación que reduzca diferencias temporales evidentes, sin revelar la existencia de usuarios.
6. Se registrarán eventos de seguridad sin incluir contraseñas, hashes, tokens, secretos MFA ni datos sensibles innecesarios.

### 6. MFA, sesiones y recuperación

1. Se mantiene el diseño de IDENTITY para TOTP y WebAuthn; MFA será obligatorio para cuentas/roles privilegiados según la política de tenant existente. Ampliar su obligatoriedad a todos los usuarios requiere decisión explícita.
2. Los refresh tokens y códigos de recuperación se almacenarán únicamente como hashes; los códigos serán de un solo uso y tendrán expiración.
3. Los secretos TOTP y secretos OIDC se cifrarán o gestionarán mediante KMS/Vault; no se almacenarán en claro.
4. Las sesiones tendrán expiración, revocación y rotación de refresh tokens. Los BFF no mantendrán sesiones autoritativas en memoria local.
5. La recuperación de contraseña utilizará tokens aleatorios, de un solo uso, con expiración y almacenamiento seguro. No se utilizarán preguntas de seguridad ni datos personales como prueba de identidad.

## Alternativas consideradas

- **SHA-256/MD5 con salt:** rechazadas por ser demasiado rápidas para almacenamiento de contraseñas y facilitar ataques offline de alta velocidad.
- **bcrypt:** no elegido para credenciales nuevas; Argon2id ofrece resistencia basada en memoria y es la opción recomendada para nuevos sistemas.
- **Hash sin salt o salt compartido:** rechazado porque permite correlacionar contraseñas iguales y reutilizar tablas precalculadas.
- **Cifrado reversible de contraseñas:** rechazado porque la aplicación no necesita recuperar la contraseña original.
- **Hashing en los BFF:** rechazado porque fragmentaría la autoridad de credenciales y duplicaría lógica de seguridad fuera de IDENTITY.
- **Pepper obligatorio desde el inicio:** aplazado hasta contar con gestión de secretos, rotación y recuperación verificables.

## Consecuencias

### Positivas

- Contraseñas iguales producen hashes distintos por el salt aleatorio.
- El costo de memoria y cómputo de Argon2id eleva el costo de ataques offline.
- Existe una única autoridad para credenciales, autenticación y políticas.
- Los BFF y los demás backends no duplican secretos ni lógica de autenticación.
- La política contempla ataques online, agotamiento de recursos, MFA, sesiones y recuperación, no solo el algoritmo de hash.

### Costos y responsabilidades

- Argon2id consume memoria y CPU; exige dimensionamiento, límites de concurrencia y pruebas de carga.
- El estado de limitación de intentos debe coordinarse entre réplicas.
- La política de 15 caracteres requiere alinear el valor predeterminado actual de la configuración SQL en una futura tarea autorizada, sin editar migraciones en este cambio documental.
- La rotación de parámetros requiere rehash progresivo durante autenticaciones correctas y monitoreo de hashes obsoletos.
- MFA, recuperación y gestión de sesiones requieren flujos y pruebas de seguridad propios.

## Plan de implementación asociado

La implementación se realizará después de aprobar este ADR y siguiendo el documento operativo asociado:

1. Inspeccionar el crate IDENTITY, sus contratos, dependencias y persistencia real; fijar versiones de dependencias en los manifests y lockfile cuando existan.
2. Implementar un componente interno de hashing/verificación Argon2id en IDENTITY, sin exponer hashes o salts en contratos.
3. Integrar registro, cambio y verificación de contraseña; implementar rehash al autenticar cuando los parámetros queden obsoletos.
4. Alinear la política de longitud y bloqueo con la configuración del tenant mediante cambios SQL separados y expresamente autorizados.
5. Implementar limitación distribuida, concurrencia acotada y protección de Tokio.
6. Completar MFA, sesiones, refresh token rotation y recuperación segura.
7. Añadir pruebas unitarias, de integración, carga, concurrencia, abuso y regresión de seguridad.

Este ADR no autoriza por sí mismo cambios SQL, ejecución de migraciones, despliegues ni implementación. Esas tareas requieren su alcance y autorización correspondientes.

## Referencias

- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [NIST SP 800-63B-4 — Authentication and Authenticator Management](https://pages.nist.gov/800-63-4/sp800-63b.html)
- [RFC 9106 — Argon2 Memory-Hard Function for Password Hashing and Proof-of-Work Applications](https://www.rfc-editor.org/rfc/rfc9106.html)
