# Módulos de Public Backend

Este directorio contiene los módulos de negocio canónicos de Public Backend: `identity/`, `organization/`, `catalog/`, `sales/`, `payments/`, `cash/`, `kitchen/`, `inventory/`, `procurement/`, `production/`, `billing/`, `finance/`, `workforce/`, `customers/`, `integrations/`, `automation/`, `analytics/`, `audit/` y `reporting/`.

Cada módulo conserva su responsabilidad, schema, rol, migraciones e historial SQLx exclusivos. No crear tablas compartidas, FKs, joins ni consultas directas entre módulos. PLATFORM pertenece exclusivamente a Admin Platform Backend.