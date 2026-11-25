# Estándar de diseño de contratos API

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Definir interfaces explícitas, tipadas, documentadas y verificables entre clientes, servicios y sistemas externos.

## Requisitos

- Cada API debe tener propietario, consumidores, finalidad, clasificación de datos, autenticación y autorización documentadas.
- El contrato debe ser la fuente de verdad de la interfaz; el código generado no debe editarse manualmente.
- Los contratos deben definir tipos, obligatoriedad, nullabilidad, límites, formatos, unidades, semántica, errores y reglas de compatibilidad.
- Los campos desconocidos deben manejarse con política explícita. En comandos de escritura se debería rechazar lo desconocido para evitar mass assignment.
- Las operaciones de lectura y escritura deben separarse semánticamente cuando sus efectos y permisos difieran.
- Las APIs no deben exponer entidades internas ni permitir que el cliente controle campos de auditoría, tenant, actor, permisos o estado calculado.
- Las operaciones costosas deben tener paginación, límites, filtros permitidos y límites de complejidad.
- Las llamadas externas deben definir timeout, cancelación, límites y política de reintento.
- Los endpoints mutables deben considerar idempotencia y concurrencia.
- Los contratos deben incluir ejemplos válidos y casos de error.

## HTTP y RPC

HTTP debe definir métodos, códigos, headers, cacheabilidad y semántica de recursos. RPC debe definir servicios, métodos, deadlines, cancelación, metadata y errores. La elección de protocolo se documenta según latencia, compatibilidad, ecosistema, observabilidad y exposición.

## Seguridad

No confiar en que ocultar campos o endpoints en frontend constituye autorización. Validar identidad, permiso, ámbito y estado en el servidor propietario.

## Verificación

Lint de contrato, pruebas de compatibilidad, generación reproducible, pruebas de autorización y validación de payloads límite.
