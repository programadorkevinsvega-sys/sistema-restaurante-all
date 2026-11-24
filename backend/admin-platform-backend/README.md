# Admin Platform Backend

Proceso/binario independiente propietario únicamente del módulo `PLATFORM`.

La implementación de PLATFORM vive en `backend/admin-platform-backend/modules/platform/` y administra el ciclo de vida SaaS: tenants, planes, suscripciones, límites y capacidades propias de la plataforma. Para identidad consume los contratos del módulo IDENTITY, propiedad de Public Backend; no duplica usuarios, membresías ni tablas de identidad.

La distribución está definida en [ADR-0008](../../docs/adr/0008-module-ownership-across-four-processes.md).