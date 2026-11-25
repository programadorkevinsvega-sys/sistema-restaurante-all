# Estándar de validación de entradas e integridad de datos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Asegurar que los datos que cruzan fronteras sean sintáctica y semánticamente válidos, autorizados y seguros para su uso.

## Capas

La validación debe existir en la frontera de entrada y reforzarse en aplicación/dominio y persistencia. El frontend puede mejorar experiencia, pero nunca constituye el control autoritativo.

## Requisitos

- Definir para cada campo tipo, formato, longitud, rango, precisión, cardinalidad, nullabilidad, obligatoriedad y normalización.
- Usar allowlists para campos, filtros, ordenamientos, operadores y valores enumerados.
- Rechazar o manejar explícitamente campos desconocidos, especialmente en escrituras.
- Evitar mass assignment mediante DTOs específicos por operación.
- No confiar en identificadores de actor, tenant, permisos, precio, estado o auditoría enviados por el cliente.
- Normalizar solo cuando la semántica lo permita; preservar datos originales cuando sea legal o funcionalmente necesario.
- Usar consultas parametrizadas y evitar concatenación de SQL.
- Codificar salidas según contexto HTML, JavaScript, URL, SQL o shell.
- Validar URLs contra SSRF, DNS rebinding, redirects, rangos privados y protocolos no permitidos.
- Limitar tamaño, profundidad, cantidad, compresión, tiempo y complejidad de parsers.
- Validar archivos por contenido real, no solo extensión o MIME declarado.
- Validar también mensajes, jobs, importaciones, webhooks y respuestas de proveedores.
- Separar validación sintáctica, reglas de negocio, autorización e invariantes de persistencia.

## Pruebas

Pruebas negativas, límites, Unicode, normalización, fuzzing, property-based tests, inyección, mass assignment, SSRF, archivos maliciosos y entradas duplicadas o fuera de orden.

## Criterio de salida

Ninguna frontera crítica depende exclusivamente de validación de frontend o de mensajes de error del cliente.
