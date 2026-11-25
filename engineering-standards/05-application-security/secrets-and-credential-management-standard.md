# Estándar de gestión de secretos y credenciales

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Prevenir exposición, uso excesivo y permanencia innecesaria de secretos.

## Requisitos

- Los secretos no deben almacenarse en repositorios, código, imágenes, logs, tickets ni artefactos públicos.
- Usar un gestor de secretos o mecanismo equivalente con control de acceso, auditoría y cifrado.
- Preferir identidades de workload y credenciales de corta duración sobre secretos estáticos.
- Separar credenciales por entorno, servicio y propósito.
- Aplicar mínimo privilegio y limitar lectura de secretos.
- Definir rotación, revocación, expiración y respuesta ante compromiso.
- Evitar compartir credenciales humanas y de servicio.
- No registrar valores, fragmentos reutilizables ni hashes que permitan recuperar secretos.
- Proteger backups, variables de CI y archivos temporales.
- Rotar también certificados, claves API, tokens de proveedores y credenciales de emergencia.

## Operación

Mantener inventario con propietario, finalidad, sistemas consumidores, fecha de rotación y procedimiento de revocación. Probar rotación sin interrupción cuando sea posible.

## Verificación

Secret scanning, revisión de permisos, pruebas de rotación y revocación, auditoría de acceso y ejercicios de filtración simulada.
