# Public Backend

Proceso/binario independiente propietario de todos los módulos de negocio canónicos excepto PLATFORM, que pertenece a Admin Platform Backend.

Los módulos se implementan una sola vez bajo `backend/public-backend/modules/<modulo>/`: IDENTITY, ORGANIZATION, CATALOG, SALES, PAYMENTS, CASH, KITCHEN, INVENTORY, PROCUREMENT, PRODUCTION, BILLING, FINANCE, WORKFORCE, CUSTOMERS, INTEGRATIONS, AUTOMATION, ANALYTICS, AUDIT y REPORTING.

Conservan las responsabilidades de dominio definidas en `requisitos.md`; no se fusionan por compartir backend. La distribución está definida en [ADR-0008](../../docs/adr/0008-module-ownership-across-four-processes.md).