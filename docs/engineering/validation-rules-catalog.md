# Catálogo de reglas y formatos de validación

**Estado:** diseño aprobado — subfase 0.5
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.5
**Autoridad:** ADR-0019, ADR-0012, ADR-0011
**Documentos relacionados:**

- [Validación de entradas y contratos de datos](../architecture/input-validation-and-data-contracts.md)
- [Plantilla de contrato de entrada](./input-contract-template.md)
- [Catálogo de errores públicos](./public-error-catalog.md)
- [Checklist de revisión de validación](./validation-review-checklist.md)

---

## 1. Propósito y límites

Este catálogo define las reglas mínimas de validación por tipo de dato. Cada módulo las aplica
en sus propios contratos; no existe un validador central compartido que sea autoridad de dominio.

Los límites numéricos concretos (longitudes, rangos, cardinalidades) se fijan por contrato de
módulo en el momento de implementación. Este catálogo establece qué se debe definir, no los
valores universales.

---

## 2. Tipos primitivos

### 2.1 Texto corto (nombres, códigos, etiquetas)

| Regla | Descripción |
|---|---|
| Longitud mínima | Definida por contrato; nunca asumir que 1 es suficiente |
| Longitud máxima | Definida por contrato; en bytes y caracteres Unicode cuando difieran |
| Requerido / opcional | Explícito por campo |
| Espacios al inicio/fin | Solo recortar si la regla del campo lo define; documentar |
| Caracteres permitidos | Allowlist explícita si aplica; de lo contrario, texto Unicode sin restricción de charset |
| Rechazo | Solo espacios, solo control chars, cadena vacía cuando no permitido |

### 2.2 Texto libre (descripción, notas, dirección)

| Regla | Descripción |
|---|---|
| Límite de bytes | Definido por contrato; medido antes de persistir |
| Límite de caracteres Unicode | Definido por contrato cuando difiere de bytes |
| Contenido HTML | Solo cuando el contrato lo permita explícitamente; con biblioteca mantenida y política estricta |
| No ejecutar como código | El valor se trata siempre como dato, nunca como plantilla, SQL o expresión |
| Preservar valor original | Para auditoría, firma o consentimiento; documentar si se normaliza |

### 2.3 Contraseña

Exclusivamente bajo las reglas de ADR-0011 y el documento de seguridad de contraseñas.
No aplican las reglas generales de texto a contraseñas: no truncar, no normalizar, no registrar.

### 2.4 Email

| Regla | Descripción |
|---|---|
| Formato | Sintaxis RFC 5321/5322 básica; validar estructura local@dominio |
| Longitud | Máximo 254 caracteres totales; local máximo 64 |
| Normalización | Solo lowercase del dominio si el contrato lo define; documentar |
| Verificación de propiedad | Flujo separado de OTP/enlace; no implícita en validación de formato |
| Unicidad | Control de concurrencia en módulo propietario; no solo consulta previa |

### 2.5 Teléfono

| Regla | Descripción |
|---|---|
| Formato | E.164 (`+<country><number>`) como representación canónica |
| Longitud | 8–15 dígitos según E.164; sin contar el `+` |
| Contexto país | Definido por contrato cuando el formato local sea admitido |
| Verificación | Flujo OTP separado; formato válido no implica número activo |

### 2.6 UUID

| Regla | Descripción |
|---|---|
| Formato | 8-4-4-4-12 hex con guiones; case-insensitive en entrada, lowercase canónico internamente |
| Versión | UUIDv7 para nuevos identificadores conforme ADR-0012 |
| Existencia y pertenencia | Verificadas por separado; formato válido no implica que el recurso exista ni pertenezca al tenant |
| Rechazo | UUID nil (`00000000-...`) rechazado salvo contrato explícito |

### 2.7 Entero

| Regla | Descripción |
|---|---|
| Rango | Mínimo y máximo definidos por contrato |
| Overflow | Rechazar valores fuera del tipo destino; sin coerción silenciosa |
| Representación | String decimal en JSON para enteros > 53 bits; documentar si se usa número JSON |
| Negativo / cero | Explícito por campo; no asumir que positivo es siempre válido |

### 2.8 Decimal / dinero

| Regla | Descripción |
|---|---|
| Representación | String decimal exacto en JSON (`"19.99"`); nunca `float` / `double` como autoridad monetaria |
| Precisión y escala | Definidas por contrato (ej. 2 decimales para COP/USD); rechazar más decimales de los permitidos |
| Rango | Mínimo y máximo definidos; importe cero puede ser válido o no según contexto |
| Redondeo | Regla explícita si aplica; documentar modo (HALF_UP, HALF_EVEN, etc.) |

### 2.9 Fecha (sin hora)

| Regla | Descripción |
|---|---|
| Formato | ISO 8601 `YYYY-MM-DD` |
| Validez | Fecha calendario válida; rechazar 2026-02-30 |
| Rango | Mínimo y máximo definidos por contrato cuando aplique |
| Zona horaria | No aplica a fecha civil; documentar si el módulo interpreta como fecha en zona específica |

### 2.10 Timestamp / datetime

| Regla | Descripción |
|---|---|
| Formato | ISO 8601 con offset (`2026-11-25T10:00:00-05:00`) o UTC (`2026-11-25T15:00:00Z`) |
| Zona | Offset explícito o UTC obligatorio; rechazar datetime sin zona cuando el contrato lo exija |
| Precisión | Definida por contrato (segundos, milisegundos); no asumir precisión del cliente |
| Rango | Razonable para el dominio; rechazar fechas de Unix epoch 0 o año 9999 si no tienen sentido |

### 2.11 Enum / estado

| Regla | Descripción |
|---|---|
| Valores admitidos | Solo los definidos en el contrato; rechazar cualquier otro incluyendo vacío |
| Transiciones | Validadas en dominio del módulo; valor válido no implica transición válida desde el estado actual |
| Mapeo de desconocidos | No mapear a valor por defecto; rechazar explícitamente |

### 2.12 Booleano

| Regla | Descripción |
|---|---|
| Representación | `true` / `false` JSON; no convertir `"yes"`, `"1"`, `"true"` como string |
| Ausente vs false | Semántica definida por contrato; ausente no siempre significa false |

---

## 3. Tipos compuestos

### 3.1 Colección (array / lista)

| Regla | Descripción |
|---|---|
| Cardinalidad mínima | Definida por contrato; puede ser 0 o 1 según el caso |
| Cardinalidad máxima | Definida por contrato; nunca ilimitada |
| Duplicados | Rechazados o permitidos según contrato; definir clave de unicidad |
| Orden | Significativo o no según contrato; documentar |
| Tipo de elementos | Validado individualmente con las reglas del tipo correspondiente |

### 3.2 Objeto / JSON anidado

| Regla | Descripción |
|---|---|
| Esquema | Definido por contrato; campos desconocidos rechazados en escrituras HTTP |
| Profundidad máxima | Definida por contrato; no ilimitada |
| Tamaño máximo | En bytes; definido por contrato |
| Complejidad | Límite de nodos/propiedades para prevenir ataques de parsing costoso |

### 3.3 Campo dinámico (mapa clave-valor)

| Regla | Descripción |
|---|---|
| Allowlist de claves | Solo claves definidas en el contrato; rechazar claves arbitrarias |
| Tipo de valores | Definido por clave; no `Any` sin restricción |
| Cardinalidad | Número máximo de entradas definido por contrato |
| Profundidad | Sin anidamiento salvo contrato explícito |

---

## 4. Tipos de dominio específicos

### 4.1 Idempotency key

| Regla | Descripción |
|---|---|
| Formato | UUIDv7 o string opaco; definido por contrato de la operación |
| Longitud | Máximo 128 caracteres si es string opaco |
| Alcance | Por operación y tenant; no global entre módulos |
| Reutilización con payload distinto | Según política de idempotencia de la operación; documentar comportamiento |
| No otorga autorización | Un key válido no es prueba de que el actor puede ejecutar la operación |

### 4.2 URL suministrada por usuario (cuando el servidor la consume)

| Regla | Descripción |
|---|---|
| Esquemas permitidos | Solo `https` por defecto; `http` solo con justificación documentada |
| Destinos permitidos | Allowlist de dominios/CIDR cuando sea viable |
| Rechazo anti-SSRF | Loopback, privadas (10.x, 172.16-31.x, 192.168.x), link-local, reservadas |
| Validación DNS | Resolver y verificar que el destino efectivo no es privado/reservado |
| Longitud | Máximo 2048 caracteres |
| Redirecciones | Límite de saltos y verificación del destino final |

### 4.3 Nombre de archivo

| Regla | Descripción |
|---|---|
| Uso | Solo para metadatos de presentación; nunca como componente de ruta del sistema |
| Caracteres prohibidos | `/`, `\`, `..`, null bytes y caracteres de control |
| Longitud | Máximo 255 bytes |
| Extensión | Verificar contra tipo real del contenido; no confiar en extensión declarada |

### 4.4 Cursor de paginación

| Regla | Descripción |
|---|---|
| Formato | Opaco (base64 de estructura interna); no exponer campos de BD |
| Integridad | Firma o hash para detectar manipulación |
| Versión | Incluir versión para invalidar cursores ante cambios de esquema |
| Alcance | Acotado al tenant y operación; no transferible entre tenants |
| No es autorización | Un cursor válido no otorga acceso a recursos sin verificación de permisos |

---

## 5. Reglas transversales

### 5.1 Campos que nunca acepta el cliente

Los siguientes campos son siempre de solo servidor y se rechazan si aparecen en escrituras:

- `tenant_id` efectivo (se toma del contexto autenticado)
- `user_id` / `actor_id` como campo de negocio en comandos
- `created_at`, `updated_at`, `deleted_at`
- `status` interno en creaciones (el módulo asigna el estado inicial)
- Roles, permisos, flags de aprobación o privilegio
- Hashes, tokens, secretos
- Campos calculados (totales, saldos, conteos derivados)

### 5.2 Normalización permitida

Solo cuando el contrato del campo lo define explícitamente:

| Normalización | Condición |
|---|---|
| Recorte de espacios al inicio/fin | Solo en campos donde el contrato lo especifica |
| Lowercase de email (dominio) | Solo si el contrato lo define; documentar |
| NFC Unicode | Solo si el contrato lo define; nunca para contraseñas, tokens ni firmas |
| Separadores de teléfono | Solo al almacenar en formato canónico E.164 |

### 5.3 Rechazo de entradas

No sanitizar entradas inválidas convirtiéndolas en aparentemente válidas. Si una entrada no cumple
las reglas, se rechaza con el código de error correspondiente. No truncar silenciosamente.

---

## 6. Estado de implementación

Diseño aprobado. No existen validadores, middleware, DTOs ni código implementado.
La implementación comienza módulo a módulo a partir de la subfase 1.3.
