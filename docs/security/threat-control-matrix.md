# Matriz amenaza / control / fase / evidencia

**Estado:** vigente
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.3
**Fuente de amenazas:** [Modelo de amenazas](./threat-model.md)
**Riesgos residuales:** [Registro de riesgos residuales](./residual-risk-register.md)

---

## Lectura de la tabla

- **ID amenaza:** referencia al ID en `threat-model.md`.
- **Control:** descripción del control técnico u organizativo.
- **Tipo:** Preventivo / Detectivo / Correctivo.
- **Fase de implementación:** subfase del plan maestro donde se implementa.
- **ADR de referencia:** decisión arquitectónica que sustenta el control.
- **Estado:** Diseñado / En implementación / Implementado / Verificado.
- **Evidencia:** enlace o descripción de la evidencia cuando el estado sea Implementado o Verificado.

Un control en estado Diseñado significa que existe la decisión pero no el código, configuración ni prueba.

---

## Suplantación

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| S-01 | Tokens de sesión de corta duración; rotación de refresh token; revocación inmediata en logout | Preventivo | 0.4 | ADR-0011, ADR-0022 | Diseñado | — |
| S-01 | Detección de reutilización de token revocado; alerta y bloqueo automático | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| S-02 | Identidad de servicio por proceso; mTLS entre procesos; sin credenciales compartidas | Preventivo | 0.7 | ADR-0023 | Diseñado | — |
| S-03 | Argon2id para contraseñas; límite de intentos; bloqueo progresivo; MFA disponible | Preventivo | 0.4 | ADR-0011 | Diseñado | — |
| S-04 | Verificación de firma de callback (HMAC/JWT según proveedor); rechazo de callbacks sin firma válida | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| S-05 | Identidad de worker con permisos mínimos; validación de origen de mensaje; rechazo sin contexto válido | Preventivo | 0.4 | ADR-0021 | Diseñado | — |

## Manipulación

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| T-01 | Consultas parametrizadas obligatorias (SQLx compile-time); sin interpolación de SQL | Preventivo | 0.6 | ADR-0019 | Diseñado | — |
| T-02 | Validación y recálculo de precios/descuentos en backend propietario; BFF no modifica reglas de negocio | Preventivo | 0.5 | ADR-0019, ADR-0020 | Diseñado | — |
| T-03 | Outbox/Inbox con idempotencia; ACK explícito; rechazo de mensajes sin ID único o firma | Preventivo | 0.6 | ADR-0003, ADR-0013 | Diseñado | — |
| T-04 | Validación de tipo MIME, extensión, tamaño y contenido en uploads; antivirus/sandbox cuando aplique | Preventivo | 0.7 | ADR-0027 | Diseñado | — |
| T-05 | Acciones fijadas a SHA en CI; lockfile comprometido = bloqueo de pipeline; firma de artefactos | Preventivo | 0.2 | ADR-0024 | Diseñado | — |

## Repudio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| R-01 | Registro de actor, timestamp, operación y contexto en AUDIT para toda operación financiera | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| R-02 | Registro de cambios de configuración de tenant con actor y diff en AUDIT | Detectivo | 0.8 | ADR-0026 | Diseñado | — |
| R-03 | Acceso excepcional de soporte requiere autorización, registro y notificación al tenant | Detectivo/Correctivo | 0.8 | ADR-0026 | Diseñado | — |

## Divulgación de información

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| D-01 | Aislamiento multi-tenant en PostgreSQL mediante RLS y rol por módulo; validación de tenant en cada operación de módulo propietario | Preventivo | 0.6 | ADR-0021 | Diseñado | — |
| D-01 | Pruebas de cruce de tenant en cada endpoint y operación | Detectivo | 0.4 | ADR-0021 | Diseñado | — |
| D-02 | RBAC + ABAC evaluado en módulo propietario; sin autorización delegada al BFF | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| D-03 | Logs sin contraseñas, tokens, datos de pago ni payload personal; redacción automática | Preventivo | 0.8 | ADR-0015, ADR-0026 | Diseñado | — |
| D-04 | Rate limiting por actor y tenant en exportaciones y reportes; paginación obligatoria; alerta por volumen anómalo | Preventivo/Detectivo | 0.5 | ADR-0025 | Diseñado | — |
| D-05 | Gitleaks en CI (configurado); secretos en gestor externo; sin secretos en código ni artefactos | Preventivo | 0.2 | ADR-0024 | Implementado | Workflow `documentation-security.yml`; verificado PR #33 |
| D-06 | Tokens PSP en lugar de datos de tarjeta; sin almacenamiento de PAN; flujo PCI delegado a proveedor | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| D-07 | Validación y lista de destinos permitidos para URLs controladas por usuario; sin fetch de URLs arbitrarias | Preventivo | 0.5 | ADR-0019, ADR-0025 | Diseñado | — |

## Denegación de servicio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| DS-01 | Rate limiting por IP y por token en BFF; WAF con reglas de abuso y DDoS | Preventivo | 0.7 | ADR-0025 | Diseñado | — |
| DS-02 | Pool de conexiones por módulo con límites configurados; circuit breaker ante PostgreSQL degradado | Preventivo | 0.6 | ADR-0010 | Diseñado | — |
| DS-03 | Límite de tamaño de payload y archivos validado antes de procesamiento; rechazo temprano | Preventivo | 0.5 | ADR-0027 | Diseñado | — |
| DS-04 | Throttling por actor y tenant en endpoints costosos; timeouts de consulta; presupuesto de recursos | Preventivo | 0.5 | ADR-0025 | Diseñado | — |
| DS-05 | Backpressure en consumidores NATS; límite de mensajes en vuelo; alerta por profundidad de cola | Preventivo/Detectivo | 0.6 | ADR-0017 | Diseñado | — |

## Elevación de privilegios

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| E-01 | RBAC evaluado en módulo propietario; roles mínimos por defecto; sin herencia implícita | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-02 | Separación de identidad entre operador de plataforma y administrador de tenant; PLATFORM no comparte sesión con módulos de negocio | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-03 | DTO específicos por operación; rechazo de campos desconocidos en escrituras HTTP; sin mass assignment | Preventivo | 0.5 | ADR-0019 | Diseñado | — |
| E-04 | Workers validan contexto de tenant y actor antes de ejecutar operación; rechazo sin contexto válido | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| E-05 | Permisos mínimos por job en CI; environments protegidos; sin secretos de producción en PRs | Preventivo | 0.2 | ADR-0024 | Implementado | Workflow `documentation-security.yml` con `contents: read`; verificado |
| E-06 | CSP estricta; cookies HttpOnly y Secure; tokens no accesibles desde JS cuando sea posible | Preventivo | 0.4 | ADR-0022 | Diseñado | — |
| E-07 | SameSite en cookies; CSRF token o verificación de origen en operaciones de estado | Preventivo | 0.4 | ADR-0022 | Diseñado | — |

## Amenazas de dominio

| ID amenaza | Control | Tipo | Fase | ADR | Estado | Evidencia |
|---|---|---|---|---|---|---|
| DOM-01 | Cambios de precio requieren rol autorizado; registro en AUDIT con actor y valor anterior/nuevo | Preventivo/Detectivo | 0.4 / 0.8 | ADR-0021 | Diseñado | — |
| DOM-02 | Ajustes de inventario requieren justificación y actor; alerta por ajustes fuera de rango | Preventivo/Detectivo | 0.4 / 0.8 | ADR-0021 | Diseñado | — |
| DOM-03 | Anulación de pagos confirmados requiere rol específico, flujo de aprobación y registro | Preventivo | Fase 2 | ADR-0020 | Diseñado | — |
| DOM-04 | Aislamiento de sucursal verificado en cada operación; sin acceso cruzado por ID enviado por cliente | Preventivo | 0.4 | ADR-0021 | Diseñado | — |
| DOM-05 | Recetas versionadas con historial inmutable; modificación requiere nueva versión | Preventivo | Fase 3 | ADR-0001 | Diseñado | — |
