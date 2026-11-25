# Checklist de revisión de validación

**Estado:** diseño aprobado — subfase 0.5
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.5
**Autoridad:** ADR-0019
**Documentos relacionados:**

- [Catálogo de reglas y formatos](./validation-rules-catalog.md)
- [Plantilla de contrato de entrada](./input-contract-template.md)
- [Catálogo de errores públicos](./public-error-catalog.md)
- [Matriz de pruebas negativas](./validation-negative-test-matrix.md)

---

## 1. Propósito

Este checklist se aplica antes de aprobar el PR de cualquier operación que exponga una
frontera de entrada (endpoint HTTP, método gRPC, consumidor de mensajes o worker).

Un PR que no satisface todos los ítems aplicables no pasa la revisión de validación,
independientemente del estado del resto de las pruebas.

---

## 2. Contrato de entrada

- [ ] Existe una instancia de la plantilla de contrato completada para esta operación.
- [ ] Cada campo tiene tipo, obligatorio/opcional, nullable y reglas de longitud/rango/formato.
- [ ] Los campos de solo servidor están explícitamente listados como prohibidos en escritura.
- [ ] Los DTO de entrada son específicos para esta operación; no reutilizan entidades de persistencia.
- [ ] Las actualizaciones parciales definen semántica de ausente, null y valor explícitamente.
- [ ] `tenant_id` y `user_id` se obtienen del contexto autenticado; no son campos de entrada.
- [ ] Los campos calculados, hashes, timestamps de auditoría y estados internos no son asignables.

---

## 3. Validación estructural y sintáctica

- [ ] Se valida presencia de campos obligatorios antes de cualquier lógica de dominio.
- [ ] Se valida el tipo de cada campo; sin coerciones implícitas.
- [ ] Los UUIDs se validan en formato y versión (UUIDv7 para IDs nuevos).
- [ ] Los decimales/importes se reciben como string decimal; no como float JSON.
- [ ] Las fechas y timestamps incluyen validación de zona horaria cuando el contrato lo requiere.
- [ ] Los enums solo aceptan valores definidos; los desconocidos se rechazan.
- [ ] Los campos desconocidos en escrituras HTTP se rechazan con `validation.unknown_field`.
- [ ] Las colecciones tienen cardinalidad mínima y máxima validadas.
- [ ] Los objetos anidados tienen profundidad y tamaño máximo validados.

---

## 4. Validación de dominio y estado

- [ ] Las reglas de dominio se aplican en el módulo propietario; no solo en el BFF.
- [ ] Las transiciones de estado se validan con el estado actual del recurso, dentro de transacción.
- [ ] Las referencias a otros recursos verifican existencia y pertenencia al tenant del contexto.
- [ ] La autorización se valida de forma separada a la validación de entrada.
- [ ] Un valor semánticamente inválido retorna 422, no 400.
- [ ] Un conflicto de estado retorna 409, no 500.

---

## 5. Límites de recursos

- [ ] El tamaño del body/payload tiene límite configurado antes de deserializar.
- [ ] Los archivos tienen límite de tamaño, tipo y cantidad definidos y verificados sobre contenido real.
- [ ] Las URLs suministradas por usuario tienen controles anti-SSRF cuando el servidor las consume.
- [ ] Los filtros, cursores y parámetros de paginación tienen límites y allowlists.
- [ ] Los endpoints costosos tienen rate limiting y timeout definidos.

---

## 6. Errores

- [ ] Todos los errores usan códigos del catálogo público; no mensajes de bibliotecas internas.
- [ ] Los errores no incluyen stack traces, SQL, constraint names ni valores del campo rechazado.
- [ ] Los errores 403 y 404 no revelan existencia de recursos de otros tenants cuando corresponde.
- [ ] Los errores de negocio no se devuelven como 500.
- [ ] El `request_id` está presente en todas las respuestas de error.
- [ ] Los mensajes de error son seguros y localizables.

---

## 7. Mensajería y workers

- [ ] Los consumidores validan esquema, versión y contexto del mensaje antes de procesar.
- [ ] Los mensajes inválidos permanentes van a DLQ; no se reintentan indefinidamente.
- [ ] La idempotencia se verifica antes de ejecutar el efecto; no después.
- [ ] Un mensaje sin `tenant_id` válido se rechaza; sin efecto y con log.

---

## 8. Observabilidad y privacidad

- [ ] Los logs y trazas no incluyen el valor del campo rechazado, contraseñas, tokens ni payloads completos.
- [ ] Las métricas de rechazo usan clase/código de error; no valores de campos ni IDs de usuario.
- [ ] El `request_id` permite correlacionar el error en logs sin exponer datos sensibles.

---

## 9. Pruebas

- [ ] Existen pruebas para los casos de la matriz de pruebas negativas aplicables a esta operación.
- [ ] Las pruebas de validación se ejecutan contra la frontera real; no contra mocks del validador.
- [ ] Las pruebas de mass assignment verifican que los campos prohibidos son ignorados o rechazados.
- [ ] Las pruebas de tenant cruzado verifican que un UUID válido de otro tenant no da acceso.
- [ ] Los resultados de pruebas están en la evidencia del PR.

---

## 10. Contrato OpenAPI / Protobuf

- [ ] El esquema OpenAPI o Protobuf refleja los campos, tipos y restricciones del contrato.
- [ ] Los archivos de contrato se generan desde su fuente; no se editan manualmente.
- [ ] Los cambios de contrato que rompen compatibilidad están identificados y tienen estrategia de migración.

---

## Notas de uso

- Marcar N/A con justificación cuando un ítem no aplica a la operación.
- El checklist se incluye como parte de la descripción del PR o como comentario de revisión.
- Un ítem sin marcar o sin N/A justificado bloquea la aprobación del PR.
