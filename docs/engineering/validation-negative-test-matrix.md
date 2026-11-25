# Matriz de pruebas negativas y fuzzing

**Estado:** diseño aprobado — subfase 0.5
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.5
**Autoridad:** ADR-0019
**Documentos relacionados:**

- [Catálogo de reglas y formatos](./validation-rules-catalog.md)
- [Catálogo de errores públicos](./public-error-catalog.md)
- [Checklist de revisión de validación](./validation-review-checklist.md)
- [Casos negativos de autorización](../security/authorization-negative-cases.md)

---

## 1. Propósito

Define los casos negativos mínimos que debe cubrir cada operación. No es una lista exhaustiva;
es el piso mínimo antes de que una operación pase a integración.

Los casos de autorización (cruce de tenant, escalada) están en
`authorization-negative-cases.md`. Este documento cubre validación de entrada, límites,
mass assignment, inyección y abuso.

---

## 2. Casos por categoría

### 2.1 Campos obligatorios y nulabilidad

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-01 | Campo obligatorio ausente | Body sin el campo | 400 `validation.required` |
| NEG-V-02 | Campo obligatorio con string vacío | `"name": ""` | 400 `validation.required` |
| NEG-V-03 | Campo obligatorio con solo espacios | `"name": "   "` | 400 `validation.required` |
| NEG-V-04 | Campo no-nullable con null explícito | `"name": null` | 400 `validation.null` |
| NEG-V-05 | Body vacío en operación que requiere campos | `{}` | 400 con todos los campos obligatorios |
| NEG-V-06 | Body ausente en POST/PUT | Sin body | 400 |

### 2.2 Tipos y formatos

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-07 | String en campo entero | `"quantity": "diez"` | 400 `validation.type` |
| NEG-V-08 | Número float en campo decimal/dinero | `"price": 19.99` (número JSON) | 400 `validation.format` |
| NEG-V-09 | UUID malformado | `"id": "no-es-uuid"` | 400 `validation.format` |
| NEG-V-10 | UUID versión incorrecta (v4 donde se espera v7) | UUID v4 válido | 400 `validation.format` según contrato |
| NEG-V-11 | Fecha inválida | `"date": "2026-02-30"` | 400 `validation.format` |
| NEG-V-12 | Timestamp sin zona | `"ts": "2026-11-25T10:00:00"` | 400 `validation.format` cuando el contrato exige zona |
| NEG-V-13 | Email malformado | `"email": "no-es-email"` | 400 `validation.format` |
| NEG-V-14 | Enum con valor desconocido | `"status": "INVENTADO"` | 400 `validation.enum` |
| NEG-V-15 | Booleano como string | `"active": "true"` | 400 `validation.type` |

### 2.3 Longitud y rango

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-16 | String más corto que mínimo | 0 chars en campo min 1 | 400 `validation.length.min` |
| NEG-V-17 | String más largo que máximo | 201 chars en campo max 200 | 400 `validation.length.max` |
| NEG-V-18 | Número menor que mínimo | `-1` en campo min 0 | 422 `validation.range.min` |
| NEG-V-19 | Número mayor que máximo | `10000000` en campo max 999999 | 422 `validation.range.max` |
| NEG-V-20 | Decimal con más precisión de la permitida | `"19.999"` en campo de 2 decimales | 422 `validation.precision` |
| NEG-V-21 | Entero con overflow | `9999999999999999999` | 400 `validation.range.max` |

### 2.4 Colecciones y anidamiento

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-22 | Array con más elementos del máximo | 101 items en campo max 100 | 400 `validation.cardinality.max` |
| NEG-V-23 | Array vacío cuando mínimo es 1 | `[]` en campo min 1 | 400 `validation.cardinality.min` |
| NEG-V-24 | Duplicados en array que los prohíbe | `[A, A, B]` | 400 `validation.duplicate` |
| NEG-V-25 | JSON con profundidad mayor a la permitida | Objeto 11 niveles en campo max 10 | 400 `validation.type` |
| NEG-V-26 | Payload JSON muy grande | Body de 100 MB | 413 `limit.payload_too_large` |

### 2.5 Mass assignment

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-27 | `tenant_id` en body de creación | Campo extra en JSON | Ignorado; usa contexto autenticado |
| NEG-V-28 | `created_at` en body de creación | Campo extra en JSON | 400 `validation.unknown_field` o ignorado; documentado por contrato |
| NEG-V-29 | `status` interno en body | Estado de flujo interno en campo | 400 `validation.unknown_field` |
| NEG-V-30 | `role` o `permissions` en body de usuario | Campo de privilegio extra | 400 `validation.unknown_field` |
| NEG-V-31 | `price` calculado por servidor enviado en body | Precio en body de pedido | Ignorado; servidor recalcula |
| NEG-V-32 | Campo de auditoría `approved_by` en body | Campo de auditoría en body | 400 `validation.unknown_field` |

### 2.6 Inyección

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-33 | SQL injection en campo de texto | `"name": "'; DROP TABLE products; --"` | Almacenado como texto literal o rechazado por longitud; nunca ejecutado |
| NEG-V-34 | SQL injection en parámetro de filtro | `?filter=name'; DROP TABLE--` | 400 o resultado vacío; nunca ejecutado |
| NEG-V-35 | HTML/script en campo de texto libre | `<script>alert(1)</script>` | Almacenado como texto o rechazado; nunca ejecutado ni renderizado sin escape |
| NEG-V-36 | Path traversal en nombre de archivo | `"filename": "../../../etc/passwd"` | 400 `validation.format` |
| NEG-V-37 | Null bytes en string | `"name": "abc\u0000def"` | 400 `validation.format` |
| NEG-V-38 | SSRF en campo URL | `"webhook_url": "http://169.254.169.254/latest/meta-data/"` | 400 `validation.format` o `domain.rule_violation` |

### 2.7 Archivos

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-39 | Archivo que supera el tamaño máximo | Archivo de 51 MB en límite de 50 MB | 413 `file.size_exceeded` |
| NEG-V-40 | Extensión permitida con contenido real diferente | `.jpg` que es en realidad un `.exe` | 400 `file.type_not_allowed` |
| NEG-V-41 | Archivo ZIP bomb | ZIP que expande a cientos de GB | 400 `file.corrupted` o `limit.payload_too_large` |
| NEG-V-42 | Nombre de archivo con path traversal | `"../../secret.txt"` | 400 `validation.format` |
| NEG-V-43 | Content-Type falso | Declara `image/jpeg`, envía `text/html` | 400 `file.type_not_allowed` |

### 2.8 Idempotencia

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-44 | Mismo idempotency key, mismo payload (reintento) | Segunda llamada idéntica | 200/201 con mismo resultado; sin efecto duplicado |
| NEG-V-45 | Mismo idempotency key, payload diferente | Segunda llamada con body distinto | 409 `idempotency.conflict` |
| NEG-V-46 | Idempotency key con formato inválido | `"key": "no-es-uuid"` | 400 `validation.format` |

### 2.9 Concurrencia

| ID | Caso | Configuración | Resultado esperado |
|---|---|---|---|
| NEG-V-47 | Dos creaciones simultáneas con mismo identificador único | Race condition en SKU único | Una éxito (201), otra 409 `resource.conflict` |
| NEG-V-48 | Dos actualizaciones simultáneas al mismo recurso | Control optimista | Una éxito, otra 409 `resource.locked` o manejo de versión |
| NEG-V-49 | Transición de estado simultánea | Dos llamadas para aprobar el mismo pedido | Una éxito, otra 409 `domain.invalid_transition` |

### 2.10 Paginación y filtros

| ID | Caso | Entrada adversa | Resultado esperado |
|---|---|---|---|
| NEG-V-50 | `page_size` superior al máximo | `page_size=10000` en límite de 100 | 400 `validation.range.max` o truncado al máximo |
| NEG-V-51 | Cursor manipulado | Cursor con bytes aleatorios | 400 `validation.format` |
| NEG-V-52 | Campo de ordenamiento no permitido | `sort=password_hash` | 400 `validation.enum` |
| NEG-V-53 | Profundidad de filtro excesiva | Filtro anidado 15 niveles | 400 |
| NEG-V-54 | Inyección en cursor opaco | Cursor con SQL codificado en base64 | 400; sin ejecución SQL |

---

## 3. Pruebas de fuzzing / property-based

Las siguientes áreas requieren fuzz testing o property-based testing además de los casos anteriores:

| Área | Objetivo |
|---|---|
| Parseo de JSON | Bytes aleatorios, UTF-8 inválido, estructuras muy profundas |
| Parseo de Protobuf | Bytes malformados, campos con tag desconocido, varint inválido |
| Cursores de paginación | Base64 inválido, estructura interna corrupta, versión desconocida |
| Parseo de archivos | Headers corrompidos, contenido truncado, formatos políglotas |
| Expresiones de búsqueda | Strings con operadores, SQL, regex costosas |
| Campos decimal | Strings que no son números, NaN, Infinity, notación científica |

Los fuzz targets se implementan por módulo y se integran en CI cuando exista el código correspondiente.

---

## 4. Protocolo de ejecución

Cada caso negativo se implementa como prueba automatizada con:

1. Configuración del estado inicial necesario.
2. Envío de la entrada adversa.
3. Aserción del código HTTP/gRPC esperado.
4. Aserción de que el body de error no contiene datos internos.
5. Aserción de que no hubo efecto secundario (sin escritura en BD, sin evento publicado).

Los casos se ejecutan en la suite de pruebas del módulo antes de cada PR.
Un fallo bloquea el merge independientemente del resto de las pruebas.

---

## 5. Estado de implementación

Diseño aprobado. Las pruebas no están escritas ni ejecutadas.
Se implementan módulo a módulo a partir de la subfase 1.3, en paralelo con cada operación.
