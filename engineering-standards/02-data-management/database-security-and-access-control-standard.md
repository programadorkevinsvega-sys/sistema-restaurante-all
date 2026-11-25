# Estándar de seguridad y control de acceso a bases de datos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proteger la confidencialidad, integridad y disponibilidad de los datos persistidos, limitando el acceso desde aplicaciones, operadores y procesos automatizados.

## Requisitos

- Cada aplicación, servicio, worker, migrador y función operativa debe utilizar una identidad diferenciada cuando el riesgo lo justifique.
- Aplicar mínimo privilegio: separar permisos de lectura, escritura, DDL, migración, administración, backup y monitoreo.
- Las credenciales de runtime no deben tener privilegios de propietario ni permisos de administración innecesarios.
- Separar cuentas de migración y runtime; los cambios de esquema no deben ejecutarse con la identidad normal de la aplicación.
- Restringir acceso de red a motores y planos de administración; no exponerlos públicamente por defecto.
- Exigir cifrado de transporte y validación de certificados en conexiones remotas.
- Usar consultas parametrizadas; no concatenar entradas para construir SQL.
- Aplicar controles de aislamiento por tenant o propietario en la capa apropiada y reforzarlos con controles nativos cuando el modelo lo permita.
- No confiar únicamente en filtros de aplicación para proteger datos de alto impacto si existen controles nativos adecuados.
- Proteger backups, snapshots, logs de auditoría, réplicas y exportaciones con controles equivalentes a los datos de origen.
- Deshabilitar extensiones, funciones, procedimientos y capacidades administrativas innecesarias.
- Registrar cambios de privilegios, accesos administrativos, DDL y operaciones sensibles, evitando capturar datos personales o secretos innecesarios.
- Definir rotación, revocación y revisión periódica de permisos.
- Probar recuperación y acceso de emergencia sin compartir credenciales ordinarias.

## Operación

Mantener inventario de identidades, permisos, propietarios, dependencias, rutas de acceso y procedimientos de emergencia. Revisar permisos tras cambios de equipo, servicio, arquitectura o proveedor.

## Verificación

Pruebas de permisos positivos y negativos, acceso cruzado entre tenants, separación runtime/migración, exposición de red, rotación de credenciales y auditoría de operaciones privilegiadas.
