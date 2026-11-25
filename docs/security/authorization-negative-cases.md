# Casos negativos de autorización

**Estado:** diseño aprobado — subfase 0.4
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.4
**Autoridad:** ADR-0021, ADR-0028
**Documentos relacionados:**
- [Modelo de identidad y autorización](./identity-and-authorization-model.md)
- [Matriz rol/atributo/acción/ámbito](./rbac-abac-matrix.md)
- [Modelo de amenazas](./threat-model.md)

Los escenarios especifican resultados esperados; no implican que las pruebas estén escritas
o ejecutadas. Toda operación protegida debe rechazarse ante contexto inválido.

## 1. Convenciones

- Rechazo HTTP 401/403 o 404 cuando ocultar existencia sea necesario.
- Rechazo gRPC `UNAUTHENTICATED` o `PERMISSION_DENIED`.
- Ningún dato protegido ni efecto secundario ante rechazo.
- Mensajes al cliente no revelan detalles internos.

## 2. Cruce de tenant (BOLA)

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-T-01 | Usuario tenant A solicita recurso de B | Denegación, sin datos |
| NEG-T-02 | Cliente suplanta `tenant_id` en payload | Se ignora; prevalece contexto firmado |
| NEG-T-03 | Worker procesa mensaje con tenant distinto del recurso | Rechazo, sin efecto, auditoría |
| NEG-T-04 | Enumeración de IDs de otro tenant | Respuesta no revela existencia |
| NEG-T-05 | Admin tenant A lista usuarios de B | Denegación |

## 3. Escalada vertical y horizontal

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-E-01 | Cajero intenta operación tenant_admin | Denegación |
| NEG-E-02 | Admin tenant intenta endpoint PLATFORM | Denegación |
| NEG-E-03 | Tenant admin asigna rol platform_operator | Denegación; sin cambio |
| NEG-E-04 | Usuario se asigna rol superior | Denegación; sin cambio |
| NEG-E-05 | Operador PLATFORM accede a datos sin concesión excepcional vigente | Denegación |
| NEG-H-01 | Cajero de sucursal A consulta ventas de B | Denegación |
| NEG-H-02 | Manager marca X modifica marca Y | Denegación |
| NEG-H-03 | Usuario exporta datos de sucursal ajena | Denegación |
| NEG-H-04 | Usuario accede pedido ajeno del mismo turno | Denegación |

## 4. Sesión y autenticación

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-S-01 | Solicitud sin autenticación | 401 |
| NEG-S-02 | Token/aserción con firma inválida o manipulada | 401 |
| NEG-S-03 | Contexto expirado | 401 |
| NEG-S-04 | Sesión revocada | 401 |
| NEG-S-05 | Refresh token reutilizado | Revocar familia; 401 |
| NEG-S-06 | Acción sensible sin MFA/reautenticación requerida | 403 |

## 5. Mass assignment

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-M-01 | Payload cambia tenant | Campo no es autoridad; rechazar o ignorar según DTO |
| NEG-M-02 | Payload cambia propietario | Rechazo o campo ignorado |
| NEG-M-03 | Payload agrega roles/permisos inesperados | 400 |
| NEG-M-04 | Payload manipula precio calculado por servidor | Recalcular en servidor |
| NEG-M-05 | Mensaje negocio incluye contexto como autoridad | Ignorar; contexto separado |

## 6. Workers y mensajería

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-W-01 | Mensaje sin tenant cuando es obligatorio | Rechazo; sin efecto |
| NEG-W-02 | Tenant del mensaje no coincide con recurso | Rechazo; sin efecto |
| NEG-W-03 | Worker carece de permiso de servicio | PERMISSION_DENIED |
| NEG-W-04 | Mensaje duplicado | Resultado idempotente; sin efecto duplicado |
| NEG-W-05 | Tenant dado de baja | Rechazo; sin efecto |

## 7. Subrecursos y adjuntos

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-R-01 | URL directa a archivo de otro tenant | Acceso denegado |
| NEG-R-02 | Filtro de búsqueda suplanta tenant | Resultados solo del tenant autenticado |
| NEG-R-03 | Exportación incluye datos fuera del periodo permitido | Datos excluidos |
| NEG-R-04 | Referencia indirecta a reporte de otro tenant | Denegación |

## 8. Integridad del contexto entre procesos

| ID | Escenario | Resultado esperado |
|---|---|---|
| NEG-C-01 | Firma alterada | UNAUTHENTICATED; sin efecto |
| NEG-C-02 | IDENTITY presentado como PLATFORM o viceversa | Rechazo; no reinterpretar roles |
| NEG-C-03 | Audiencia incorrecta para el receptor | Rechazo |
| NEG-C-04 | `kid` desconocido o retirado | Rechazo y alerta; sin fallback |
| NEG-C-05 | Aserción expirada o aún no vigente | Rechazo |
| NEG-C-06 | Replay de operación no repetible | Rechazo o idempotencia contractual; nunca duplicar |
| NEG-C-07 | Certificado mTLS de workload no autorizado | Rechazo de conexión/RPC |
| NEG-C-08 | Confusión entre actor humano e identidad de servicio | Rechazo |
| NEG-C-09 | Tenant, rol o ámbito alterado sin nueva firma | Firma inválida o denegación |
| NEG-C-10 | Operador PLATFORM sin concesión excepcional accede a negocio | Denegación del módulo propietario |
| NEG-C-11 | Admin BFF usa IDENTITY para operador o Public BFF usa PLATFORM para tenant | Rechazo |
| NEG-C-12 | Fallo de KMS/distribución/verificación de claves | Fallo cerrado; nunca omitir firma |

## 9. Protocolo de ejecución

Cada caso automatizado configura estado inicial, ejecuta la solicitud adversa, comprueba el
código de rechazo, verifica ausencia de datos y efectos secundarios y comprueba auditoría
cuando corresponda. Cualquier fallo bloquea el avance del módulo.

## 10. Estado de implementación

Diseño aprobado. Los escenarios están especificados, pero las pruebas automatizadas no están
escritas ni ejecutadas. Se implementan con las subfases de cada módulo, comenzando por IDENTITY
y autorización RBAC/ABAC.
