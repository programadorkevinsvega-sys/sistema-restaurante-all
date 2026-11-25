# Estándar de ownership y acceso a datos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Mantener autoridad clara sobre los datos y limitar el acceso a lo estrictamente necesario.

## Requisitos

- Cada conjunto de datos debe tener propietario, clasificación, finalidad y responsable de acceso.
- El propietario define esquema, invariantes, retención, contratos de lectura/escritura y ciclo de vida.
- Los consumidores acceden mediante APIs, eventos o proyecciones autorizadas.
- No se permite modificar directamente tablas ajenas para integrar dominios.
- Las proyecciones deben ser reconstruibles o contar con estrategia de reconciliación.
- Los datos replicados deben tener propósito, frescura y política de eliminación documentados.
- Los roles de runtime, migración, administración, backup y monitoreo deben separarse cuando el riesgo lo justifique.
- El acceso de soporte debe ser limitado, justificado, auditado y revocable.

## Bases de datos compartidas

Una instancia física compartida no elimina la separación lógica de ownership. Deben definirse esquemas, roles, permisos, políticas y límites de acceso. El aislamiento físico puede ser necesario por regulación, riesgo o blast radius.

## Integridad

Las invariantes críticas deben aplicarse en la capa autoritativa y, cuando corresponda, reforzarse con restricciones de persistencia. No depender únicamente de validaciones de interfaz.

## Verificación

Matriz de acceso, pruebas negativas de permisos, auditoría de consultas y revisión de rutas de escritura.
