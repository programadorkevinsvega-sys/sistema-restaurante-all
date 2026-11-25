# Validación de entradas y contratos de datos

**Estado:** especificación técnica propuesta, vinculada a ADR-0019.
**Ámbito:** Admin Platform Backend, Admin BFF, Public BFF, Public Backend, módulos, workers, consumidores e integraciones.

## 1. Principios operativos

1. Ninguna fuente de entrada es confiable por defecto.
2. La validación se ejecuta en cada frontera de confianza y en el módulo propietario.
3. El frontend mejora la experiencia; no es una barrera de seguridad.
4. El BFF valida la solicitud HTTP; el backend vuelve a validar el contrato y las reglas del módulo.
5. La validación sintáctica no sustituye dominio, autorización ni persistencia.
6. Las reglas permanecen en el módulo propietario.
7. Toda superficie tiene límites finitos de tamaño, cardinalidad, profundidad, tiempo y concurrencia.
8. Los errores son estables, seguros y distinguibles de fallos internos.
9. Las entradas rechazadas no se registran completas ni se usan como dimensiones de métricas.
10. Los límites concretos se documentan por campo y operación; no se heredan valores arbitrarios de un validador genérico.

## 2. Mapa de responsabilidades

| Frontera | Qué valida | Qué no decide |
|---|---|---|
| Frontend | Requeridos, formato y rangos visibles | Seguridad, autorización o verdad de dominio |
| Admin BFF / Public BFF | Parseo HTTP, tipos, forma, tamaño, parámetros, allowlists | Invariantes, persistencia o permisos finales |
| Admin Platform Backend | Contratos y reglas de PLATFORM | Reglas de módulos ajenos |
| Public Backend | Contratos y reglas de sus módulos | Reglas internas de otros módulos |
| Módulo propietario | Aplicación, invariantes, transiciones y ownership | Datos de schemas ajenos |
| Worker / consumidor NATS | Esquema, versión, contexto, idempotencia y dominio | Confiar ciegamente en productor |
| Persistencia propietaria | Integridad y concurrencia finales | Feedback completo de API |

Una operación puede validarse en BFF y backend. El backend debe seguir siendo seguro si se invoca directamente o desde otro consumidor.

## 3. Flujo de solicitud

1. Aplicar límites de transporte antes de leer cuerpos grandes.
2. Verificar método, ruta, Content-Type, codificación y tamaño.
3. Parsear con límites de profundidad y rechazo de estructuras ambiguas.
4. Validar DTO, campos permitidos, tipos, nulabilidad y formatos.
5. Construir contexto autenticado desde mecanismos confiables; no tomar actor/tenant del body.
6. Aplicar rate limiting y controles de abuso según riesgo.
7. Enviar mediante contrato público del módulo.
8. Backend vuelve a validar en su frontera.
9. Módulo aplica reglas de aplicación y dominio.
10. Comprobar autorización y ownership por separado.
11. Ejecutar reglas dependientes del estado dentro de transacción o control de concurrencia.
12. Persistir usando parámetros y restricciones del schema propietario.
13. Convertir errores conocidos a códigos públicos; registrar fallos internos redactados.
14. Propagar trazabilidad sin payloads sensibles.

## 4. Catálogo de reglas por tipo

| Tipo | Reglas mínimas |
|---|---|
| Texto corto | Longitud, requerido/opcional, espacios y caracteres permitidos si aplica |
| Texto libre | Límite de bytes/caracteres, política de contenido, no ejecutar como código |
| Contraseña | Exclusivamente ADR-0011; no normalizar ni truncar |
| Email | Sintaxis y límites; propiedad se verifica mediante flujo aparte |
| Teléfono | Formato/contexto país; verificación OTP es flujo aparte |
| UUID | Parseo y versión conforme ADR-0012; existencia/ownership aparte |
| Entero | Rango y rechazo de overflow/coerción |
| Decimal/dinero | Precisión y escala; no float como autoridad monetaria |
| Fecha | Calendario válido; distinguir fecha civil e instante |
| Timestamp | Zona/offset inequívoco o UTC según contrato |
| Enum/estado | Valores definidos y transiciones de dominio |
| Booleano | Representación definida; no convertir cadenas arbitrarias |
| Colección | Cardinalidad y duplicados |
| Objeto/JSON | Esquema, campos, profundidad, tamaño y complejidad |
| URL | Esquemas/destinos permitidos; anti-SSRF si el servidor la consume |
| Archivo | Tamaño, firma, formato real, dimensiones, análisis y almacenamiento |
| Cursor | Integridad, versión y alcance; nunca autorización |
| Idempotency key | Formato, alcance y relación con hash de payload |
| Campo dinámico | Allowlist de claves, tipos, profundidad y tamaño |

### 4.1 Campos de autoridad

Los DTO de entrada no deben aceptar por asignación masiva tenant efectivo, actor, roles, permisos, ownership interno, estados de aprobación/pago, timestamps de auditoría, campos calculados, hashes, secretos ni flags internos. Si una operación administrativa necesita modificar alguno, debe existir comando explícito, autorización y validación de dominio.

## 5. Ausencia, nulabilidad y actualizaciones

Los contratos distinguen campo requerido, opcional, nullable, solo lectura, calculado, parcial y de reemplazo. En una actualización parcial, ausencia significa conservar; null significa limpiar solo si el contrato lo permite. No usar un DTO genérico de entidad para crear, actualizar, aprobar, cancelar y ejecutar.

## 6. Normalización

No existe un sanitize(input) universal. No truncar ni eliminar caracteres silenciosamente. No normalizar contraseñas, tokens, firmas, secretos, claves de idempotencia o IDs opacos. Texto libre se preserva salvo política expresa. Cualquier normalización Unicode, espacios o casing documenta algoritmo, momento y compatibilidad. Preservar original cuando importe para auditoría, firma, consentimiento o evidencia.

## 7. Consultas y paginación

Cada endpoint define filtros, operadores, campos ordenables, cardinalidad, profundidad, tamaño de página, cursor y orden estable. No interpolar identificadores SQL; parametrizar valores. Consultas costosas, reportes y exportaciones tienen cuotas, timeouts y concurrencia. El cliente no elige columnas, joins o recursos fuera del contrato.

## 8. Archivos y medios

Cada carga define tipos admitidos, máximo de bytes, cantidad, cuotas, dimensiones/duración, validación de firma, decodificación con límites, análisis antimalware/cuarentena cuando aplique, almacenamiento no ejecutable, autorización de descarga y retención. No confiar en Content-Type ni extensión. No concatenar nombre de archivo a una ruta. Proteger contra traversal, sobrescritura, archivos políglotas y expansión explosiva.

## 9. URLs e integraciones externas

Si el backend obtiene contenido desde una URL suministrada, aplica anti-SSRF: esquemas permitidos, rechazo de loopback/privadas/link-local/reservadas, validación DNS y destino efectivo, control de redirecciones, puertos, tiempo y tamaño, bloqueo de metadatos cloud y redes administrativas. Respuestas de proveedores se consideran entradas no confiables.

## 10. Errores

Formato conceptual, no DTO implementado:
- code: código estable, por ejemplo validation.required.
- message: mensaje general seguro/localizable.
- field_errors: lista acotada de ruta y código.
- request_id: correlación no sensible.

No incluir valor original completo, stack trace, SQL, constraint interno, secreto ni existencia de recursos de otros tenants.

| Situación | HTTP | gRPC |
|---|---:|---|
| Sintaxis/estructura inválida | 400 | INVALID_ARGUMENT |
| Semántica inválida | 422 | INVALID_ARGUMENT |
| Tamaño excedido | 413 | RESOURCE_EXHAUSTED |
| Tipo no admitido | 415 | INVALID_ARGUMENT |
| Conflicto de estado | 409 | FAILED_PRECONDITION / ALREADY_EXISTS |
| Límite de recursos | 429 | RESOURCE_EXHAUSTED |
| No autenticado | 401 | UNAUTHENTICATED |
| No autorizado | 403 o 404 según ocultación | PERMISSION_DENIED / NOT_FOUND |
| Error inesperado | 500 | INTERNAL |

El mapeo final respeta cada contrato y nunca convierte errores internos en errores de usuario.

## 11. Mensajería y trabajos asíncronos

Consumidores JetStream/NATS/Outbox/Inbox validan tipo, versión, campos, productor/subject autorizado, contexto, IDs, secuencia, idempotencia y reglas del módulo. Mensajes inválidos permanentes no se reintentan indefinidamente: se clasifican y ponen en cuarentena/DLQ. Redrive requiere corregir la causa y preservar idempotencia.

## 12. Pruebas mínimas por operación

1. Válido mínimo y máximo.
2. Ausente, null, vacío y solo espacios.
3. Tipo incorrecto y formato malformado.
4. Valores fuera de rango.
5. Unicode y entradas extensas.
6. Campos desconocidos y mass assignment.
7. Duplicados, cardinalidad y profundidad.
8. ID válido de otro tenant y recurso inexistente.
9. Estado inválido y concurrencia.
10. Payload/archivo excesivo o malicioso.
11. Reintentos, duplicados e idempotencia.
12. Errores sin datos sensibles.
13. Fuzz/property tests para parsers y estructuras complejas.

No sustituir la frontera real por un mock y presentar el resultado como validación real.

## 13. Observabilidad

Métricas agregadas: rechazos por servicio/módulo/operación/código, clases de error, buckets de tamaño/latencia, límites alcanzados, mensajes inválidos, cuarentena y redrive. No usar valores de campos, IDs, correos, tenant IDs ni payloads como labels. No registrar cuerpos completos ni secretos; redactar conforme ADR-0015 y ADR-0018.

## 14. Checklist de revisión

- [ ] DTO específico por operación, sin entidad de persistencia.
- [ ] Requeridos, opcionales, nullables y solo lectura definidos.
- [ ] Tipos, formatos, rangos, precisión y cardinalidad definidos.
- [ ] Límites de cuerpo, profundidad y complejidad definidos.
- [ ] Campos desconocidos/extensiones tratados.
- [ ] Tenant y actor derivados de contexto confiable.
- [ ] Autorización y ownership comprobados.
- [ ] Estado validado con control de concurrencia.
- [ ] Filtros, orden y paginación limitados.
- [ ] Archivos y URLs con controles específicos.
- [ ] Errores estables y sin filtración.
- [ ] Tests negativos, límites y abuso incorporados.
- [ ] OpenAPI/Protobuf actualizados desde sus fuentes.
- [ ] Logs y métricas sin payloads ni datos sensibles.

## 15. Límites

No selecciona crates ni middleware, no fija límites numéricos universales, no modifica reglas de negocio y no autoriza SQL, migraciones, schemas, roles ni datos. Las dependencias se seleccionarán al implementar con versiones fijadas y compatibilidad verificada.

## Referencias

- [ADR-0019: Validación de entradas, contratos y protección de integridad](../adr/0019-input-validation-and-data-integrity.md).
- [ADR-0002: OpenAPI, Protobuf y código generado](../adr/0002-openapi-protobuf-generated-clients.md).
- [ADR-0009: Límites de crates y dependencias](../adr/0009-crate-boundaries-and-dependencies.md).
- [ADR-0011: Protección de contraseñas y autenticación](../adr/0011-password-hashing-and-authentication-security.md).
- [ADR-0015: Observabilidad integral](../adr/0015-integrated-observability-platform.md).
