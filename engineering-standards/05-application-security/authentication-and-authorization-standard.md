# Estándar de autenticación y autorización

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Verificar quién o qué realiza una acción y si tiene permiso sobre el recurso y contexto específicos.

## Autenticación

- Separar identidad humana, identidad de servicio y credenciales de integración.
- Almacenar contraseñas con algoritmo adaptativo de hash diseñado para contraseñas, sal única y parámetros actualizables.
- No cifrar contraseñas reversiblemente ni reutilizar hashes como tokens.
- Diseñar MFA y step-up para operaciones de riesgo según criticidad.
- Proteger recuperación de cuenta, sesiones, refresh tokens, revocación y rotación.
- Limitar intentos y detectar abuso sin permitir enumeración de cuentas.
- Definir expiración, audiencia, issuer, firma, algoritmo permitido y rotación para tokens.

## Autorización

- Denegar por defecto.
- Evaluar permisos en cada operación sensible, no solo al iniciar sesión.
- Combinar roles y atributos cuando el dominio lo requiera, con reglas explícitas y auditables.
- Evaluar sujeto, acción, recurso, tenant, relación, estado y contexto.
- Evitar BOLA/IDOR: conocer un ID no concede acceso.
- Aplicar autorización en el servicio propietario y en procesos asíncronos.
- No confiar en roles o tenant enviados por el cliente.
- Separar privilegios administrativos de plataforma, tenant y soporte.
- Las elevaciones y accesos excepcionales deben ser temporales, justificados y auditados.

## Verificación

Pruebas horizontales y verticales, tenant cruzado, revocación, expiración, token malformado, confused deputy y permisos de workers.
