-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 7: PROCUREMENT (PROVEEDORES, COMPRAS, RECEPCIONES Y ACUERDOS)
-- Ubicacion del crate: crates/modules/procurement
-- Schema PostgreSQL: procurement
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD EXCLUSIVA DE PROCUREMENT
--   * Maestro de proveedores externos y sus contactos/direcciones.
--   * Clasificacion, homologacion, evaluacion y documentacion de proveedores.
--   * Relacion comercial proveedor-empresa del tenant.
--   * Referencias de catalogo del proveedor (SKU/pack del proveedor).
--   * Solicitudes de cotizacion (RFQ), invitaciones y ofertas recibidas.
--   * Comparacion/evaluacion de ofertas y acuerdos comerciales marco.
--   * Solicitudes internas de compra, aprobaciones y ordenes de compra.
--   * Recepciones, discrepancias y facturas de proveedores con conciliacion.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO)
--   * Saldos, lotes y movimientos de existencias: inventory.
--   * Cuentas por pagar, pagos y asientos contables: finance.
--
-- OTROS LIMITES
--   * Catalog es propietario de productos, variantes y unidades.
--   * Organization es propietario de empresas y sucursales.
--   * Identity es propietario de usuarios, roles y permisos.
--   * Inventory es propietario de bodegas, existencias y movimientos.
--   * Procurement NO crea FK ni consulta tablas internas de esos modulos.
--   * company_id, branch_id, catalog_variant_id, unit_id y actor_user_id
--     son referencias logicas UUID validadas mediante puertos de aplicacion.
--   * Solo tenant_id tiene FK fisica al registro canonico platform.tenants.
--
-- SEGURIDAD
--   * Todas las tablas del schema son tenant-scoped y tienen RLS.
--   * El backend fija SET LOCAL app.tenant_id dentro de cada transaccion.
--   * El tenant se obtiene de la sesion autenticada; nunca del body del cliente.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * RLS no reemplaza autorizacion por company_id/branch_id ni permisos Identity.
--
-- INSTALACION
--   Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   Se recomienda instalar despues de Organization, Identity y Catalog,
--   aunque no crea FK a ellos. Instalar una sola vez en una base nueva.
--
-- NOTA SOBRE platform.modules
--   Platform es propietario del catalogo comercial de modulos; esta migracion
--   no lo modifica. El codigo comercial habilitado debe ser 'procurement'.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS procurement;

COMMENT ON SCHEMA procurement IS
'Gestion de proveedores, sourcing, solicitudes y ordenes de compra, recepciones, conciliacion de facturas y acuerdos comerciales. No administra saldos ni movimientos de inventario.';

-- ---------------------------------------------------------------------------
-- 0. Funciones del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION procurement.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION procurement.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id de un registro de Procurement';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro de %.% es append-only; registre una compensacion o un nuevo evento', TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Condiciones de pago (catalogo interno de Procurement)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.payment_terms (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    terms_code              varchar(40) NOT NULL,
    name                    varchar(120) NOT NULL,
    description             text,
    due_days                integer NOT NULL DEFAULT 0 CHECK (due_days >= 0),
    discount_days           integer CHECK (discount_days IS NULL OR discount_days >= 0),
    discount_rate           numeric(7,4) CHECK (discount_rate IS NULL OR discount_rate BETWEEN 0 AND 100),
    is_immediate            boolean NOT NULL DEFAULT false,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_terms_code_not_blank CHECK (btrim(terms_code) <> ''),
    CONSTRAINT payment_terms_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT payment_terms_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_terms_code_unique UNIQUE (tenant_id, terms_code)
);

CREATE INDEX ix_procurement_payment_terms_active
    ON procurement.payment_terms (tenant_id, is_active, due_days);

-- ---------------------------------------------------------------------------
-- 2. Categorias de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_categories (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    parent_category_id  uuid,
    category_code       varchar(50) NOT NULL,
    name                varchar(120) NOT NULL,
    description         text,
    is_active           boolean NOT NULL DEFAULT true,
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_categories_code_not_blank CHECK (btrim(category_code) <> ''),
    CONSTRAINT supplier_categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT supplier_categories_not_self_parent CHECK (parent_category_id IS NULL OR parent_category_id <> id),
    CONSTRAINT supplier_categories_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_categories_parent_fk FOREIGN KEY (tenant_id, parent_category_id)
        REFERENCES procurement.supplier_categories (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_categories_code_unique UNIQUE (tenant_id, category_code)
);

CREATE INDEX ix_supplier_categories_parent
    ON procurement.supplier_categories (tenant_id, parent_category_id, sort_order);

-- ---------------------------------------------------------------------------
-- 3. Maestro de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.suppliers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_code           varchar(50) NOT NULL,
    legal_name              varchar(220) NOT NULL,
    trade_name              varchar(220),
    entity_type             varchar(30) NOT NULL DEFAULT 'legal_entity'
                            CHECK (entity_type IN ('natural_person', 'legal_entity', 'nonprofit', 'government', 'other')),
    tax_country_code        char(2) NOT NULL DEFAULT 'CO',
    tax_identifier_type     varchar(40),
    tax_identifier          varchar(100),
    tax_verification_digit  varchar(8),
    primary_email           varchar(320),
    primary_phone           varchar(50),
    website_url             text,
    default_currency        char(3) NOT NULL DEFAULT 'COP',
    supplier_status         varchar(24) NOT NULL DEFAULT 'prospect'
                            CHECK (supplier_status IN ('prospect', 'pending_review', 'approved', 'suspended', 'rejected', 'inactive', 'archived')),
    risk_level              varchar(16) NOT NULL DEFAULT 'unrated'
                            CHECK (risk_level IN ('unrated', 'low', 'medium', 'high', 'critical')),
    source_channel          varchar(30) NOT NULL DEFAULT 'manual'
                            CHECK (source_channel IN ('manual', 'referral', 'portal', 'integration', 'import', 'other')),
    notes                   text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id      uuid,
    updated_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz,
    CONSTRAINT suppliers_code_not_blank CHECK (btrim(supplier_code) <> ''),
    CONSTRAINT suppliers_legal_name_not_blank CHECK (btrim(legal_name) <> ''),
    CONSTRAINT suppliers_country_upper CHECK (tax_country_code = upper(tax_country_code)),
    CONSTRAINT suppliers_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT suppliers_tax_identifier_pair CHECK (
        (tax_identifier IS NULL AND tax_identifier_type IS NULL)
        OR (tax_identifier IS NOT NULL AND tax_identifier_type IS NOT NULL
            AND btrim(tax_identifier) <> '' AND btrim(tax_identifier_type) <> '')
    ),
    CONSTRAINT suppliers_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT suppliers_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT suppliers_tenant_code_unique UNIQUE (tenant_id, supplier_code)
);

CREATE UNIQUE INDEX uq_procurement_supplier_tax_id
    ON procurement.suppliers (
        tenant_id,
        tax_country_code,
        tax_identifier_type,
        upper(regexp_replace(tax_identifier, '[^A-Za-z0-9]', '', 'g'))
    )
    WHERE tax_identifier IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX ix_procurement_suppliers_status
    ON procurement.suppliers (tenant_id, supplier_status, legal_name)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_procurement_suppliers_risk
    ON procurement.suppliers (tenant_id, risk_level, supplier_status)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_procurement_suppliers_name
    ON procurement.suppliers (tenant_id, lower(legal_name))
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Contactos de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_contacts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id         uuid NOT NULL,
    contact_type        varchar(24) NOT NULL DEFAULT 'commercial'
                        CHECK (contact_type IN ('commercial', 'billing', 'logistics', 'technical', 'legal', 'management', 'other')),
    full_name           varchar(180) NOT NULL,
    job_title           varchar(120),
    email               varchar(320),
    phone_country_code  varchar(8),
    phone_number        varchar(40),
    is_primary          boolean NOT NULL DEFAULT false,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT supplier_contacts_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT supplier_contacts_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_contacts_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_supplier_primary_contact_type
    ON procurement.supplier_contacts (tenant_id, supplier_id, contact_type)
    WHERE is_primary = true AND deleted_at IS NULL;
CREATE INDEX ix_supplier_contacts_supplier
    ON procurement.supplier_contacts (tenant_id, supplier_id, contact_type)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 5. Direcciones de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_addresses (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id         uuid NOT NULL,
    address_type        varchar(24) NOT NULL DEFAULT 'registered'
                        CHECK (address_type IN ('registered', 'billing', 'warehouse', 'dispatch', 'returns', 'other')),
    label               varchar(120),
    address_line_1      varchar(240) NOT NULL,
    address_line_2      varchar(240),
    neighborhood        varchar(120),
    city                varchar(120) NOT NULL,
    region              varchar(120),
    postal_code         varchar(24),
    country_code        char(2) NOT NULL DEFAULT 'CO',
    latitude            numeric(10,7),
    longitude           numeric(10,7),
    delivery_instructions text,
    is_primary          boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_addresses_line_not_blank CHECK (btrim(address_line_1) <> ''),
    CONSTRAINT supplier_addresses_city_not_blank CHECK (btrim(city) <> ''),
    CONSTRAINT supplier_addresses_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT supplier_addresses_latitude_range CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT supplier_addresses_longitude_range CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT supplier_addresses_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_addresses_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_supplier_primary_address_type
    ON procurement.supplier_addresses (tenant_id, supplier_id, address_type)
    WHERE is_primary = true AND is_active = true;
CREATE INDEX ix_supplier_addresses_supplier
    ON procurement.supplier_addresses (tenant_id, supplier_id, address_type, is_active);

-- ---------------------------------------------------------------------------
-- 6. Asignacion de categorias a proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_category_assignments (
    tenant_id       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id     uuid NOT NULL,
    category_id     uuid NOT NULL,
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    assigned_by_user_id uuid,
    PRIMARY KEY (tenant_id, supplier_id, category_id),
    CONSTRAINT supplier_category_assignments_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_category_assignments_category_fk FOREIGN KEY (tenant_id, category_id)
        REFERENCES procurement.supplier_categories (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_supplier_category_assignments_category
    ON procurement.supplier_category_assignments (tenant_id, category_id, supplier_id);

-- ---------------------------------------------------------------------------
-- 7. Relacion comercial de proveedor con cada empresa legal del tenant
-- company_id es referencia logica a Organization (no FK entre modulos).
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_company_profiles (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    payment_terms_id         uuid,
    account_reference       varchar(100),
    preferred_currency      char(3) NOT NULL DEFAULT 'COP',
    credit_limit            numeric(20,4) CHECK (credit_limit IS NULL OR credit_limit >= 0),
    lead_time_days          integer CHECK (lead_time_days IS NULL OR lead_time_days >= 0),
    minimum_order_value     numeric(20,4) CHECK (minimum_order_value IS NULL OR minimum_order_value >= 0),
    is_preferred            boolean NOT NULL DEFAULT false,
    relationship_status     varchar(20) NOT NULL DEFAULT 'pending'
                            CHECK (relationship_status IN ('pending', 'active', 'suspended', 'blocked', 'inactive')),
    internal_notes          text,
    created_by_user_id      uuid,
    updated_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_company_profiles_currency_upper CHECK (preferred_currency = upper(preferred_currency)),
    CONSTRAINT supplier_company_profiles_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_company_profiles_terms_fk FOREIGN KEY (tenant_id, payment_terms_id)
        REFERENCES procurement.payment_terms (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_company_profiles_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_company_profiles_unique UNIQUE (tenant_id, company_id, supplier_id)
);

CREATE INDEX ix_supplier_company_profiles_company
    ON procurement.supplier_company_profiles (tenant_id, company_id, relationship_status);
CREATE INDEX ix_supplier_company_profiles_supplier
    ON procurement.supplier_company_profiles (tenant_id, supplier_id, relationship_status);

CREATE TABLE procurement.supplier_branch_profiles (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    relationship_status     varchar(20) NOT NULL DEFAULT 'active'
                            CHECK (relationship_status IN ('active', 'suspended', 'blocked', 'inactive')),
    is_preferred            boolean NOT NULL DEFAULT false,
    is_exclusive            boolean NOT NULL DEFAULT false,
    internal_notes          text,
    created_by_user_id      uuid,
    updated_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_branch_profiles_company_supplier_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id)
        REFERENCES procurement.supplier_company_profiles (tenant_id, company_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT supplier_branch_profiles_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_branch_profiles_scope_unique
        UNIQUE (tenant_id, company_id, branch_id, supplier_id)
);

CREATE INDEX ix_supplier_branch_profiles_branch
    ON procurement.supplier_branch_profiles (tenant_id, company_id, branch_id, relationship_status);
CREATE INDEX ix_supplier_branch_profiles_supplier
    ON procurement.supplier_branch_profiles (tenant_id, supplier_id, relationship_status);

-- ---------------------------------------------------------------------------
-- 8. Referencias del catalogo del proveedor (SKU y presentacion del proveedor)
-- catalog_variant_id y purchase_unit_id son referencias logicas a Catalog.
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_catalog_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id             uuid NOT NULL,
    company_id              uuid,
    catalog_variant_id      uuid NOT NULL,
    supplier_item_code      varchar(100),
    supplier_item_name      varchar(220) NOT NULL,
    purchase_unit_id        uuid,
    units_per_pack          numeric(18,6) NOT NULL DEFAULT 1 CHECK (units_per_pack > 0),
    minimum_order_quantity  numeric(18,6) CHECK (minimum_order_quantity IS NULL OR minimum_order_quantity > 0),
    standard_lead_time_days integer CHECK (standard_lead_time_days IS NULL OR standard_lead_time_days >= 0),
    last_quoted_price       numeric(20,6) CHECK (last_quoted_price IS NULL OR last_quoted_price >= 0),
    last_quoted_currency    char(3),
    last_quoted_at          timestamptz,
    is_preferred            boolean NOT NULL DEFAULT false,
    is_active               boolean NOT NULL DEFAULT true,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_catalog_items_name_not_blank CHECK (btrim(supplier_item_name) <> ''),
    CONSTRAINT supplier_catalog_items_currency_upper CHECK (last_quoted_currency IS NULL OR last_quoted_currency = upper(last_quoted_currency)),
    CONSTRAINT supplier_catalog_items_last_quote_shape CHECK (
        (last_quoted_price IS NULL AND last_quoted_currency IS NULL AND last_quoted_at IS NULL)
        OR (last_quoted_price IS NOT NULL AND last_quoted_currency IS NOT NULL AND last_quoted_at IS NOT NULL)
    ),
    CONSTRAINT supplier_catalog_items_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_catalog_items_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_catalog_items_supplier_variant_unique UNIQUE (tenant_id, supplier_id, catalog_variant_id)
);

CREATE INDEX ix_supplier_catalog_items_variant
    ON procurement.supplier_catalog_items (tenant_id, catalog_variant_id, is_active);
CREATE INDEX ix_supplier_catalog_items_supplier
    ON procurement.supplier_catalog_items (tenant_id, supplier_id, is_active);

-- ---------------------------------------------------------------------------
-- 9. Documentos de homologacion / cumplimiento del proveedor
-- storage_key apunta a storage externo; no se guardan binarios en PostgreSQL.
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_documents (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id             uuid NOT NULL,
    document_type           varchar(50) NOT NULL,
    document_number         varchar(120),
    document_name           varchar(220) NOT NULL,
    storage_provider        varchar(40) NOT NULL,
    storage_key             text NOT NULL,
    mime_type               varchar(120),
    file_size_bytes         bigint CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    checksum_sha256         char(64),
    issued_at               date,
    expires_at              date,
    verification_status     varchar(20) NOT NULL DEFAULT 'pending'
                            CHECK (verification_status IN ('pending', 'verified', 'rejected', 'expired', 'not_required')),
    verified_at             timestamptz,
    verified_by_user_id     uuid,
    rejection_reason        text,
    uploaded_by_user_id     uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_documents_type_not_blank CHECK (btrim(document_type) <> ''),
    CONSTRAINT supplier_documents_name_not_blank CHECK (btrim(document_name) <> ''),
    CONSTRAINT supplier_documents_storage_key_not_blank CHECK (btrim(storage_key) <> ''),
    CONSTRAINT supplier_documents_dates CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT supplier_documents_checksum_format CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT supplier_documents_verification_shape CHECK (
        (verification_status <> 'verified' OR (verified_at IS NOT NULL AND verified_by_user_id IS NOT NULL))
        AND (verification_status <> 'rejected' OR (verified_at IS NOT NULL AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND (verification_status <> 'expired' OR expires_at IS NOT NULL)
    ),
    CONSTRAINT supplier_documents_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_documents_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_supplier_documents_expiry
    ON procurement.supplier_documents (tenant_id, supplier_id, expires_at, verification_status);
CREATE INDEX ix_supplier_documents_supplier
    ON procurement.supplier_documents (tenant_id, supplier_id, document_type, created_at DESC);

-- ---------------------------------------------------------------------------
-- 10. Evaluaciones / homologacion de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_qualification_reviews (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id             uuid NOT NULL,
    review_type             varchar(30) NOT NULL DEFAULT 'initial'
                            CHECK (review_type IN ('initial', 'periodic', 'incident', 'renewal', 'ad_hoc')),
    review_status           varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (review_status IN ('draft', 'in_progress', 'approved', 'conditionally_approved', 'rejected', 'expired')),
    quality_score           numeric(6,2) CHECK (quality_score IS NULL OR quality_score BETWEEN 0 AND 100),
    delivery_score          numeric(6,2) CHECK (delivery_score IS NULL OR delivery_score BETWEEN 0 AND 100),
    price_score             numeric(6,2) CHECK (price_score IS NULL OR price_score BETWEEN 0 AND 100),
    compliance_score        numeric(6,2) CHECK (compliance_score IS NULL OR compliance_score BETWEEN 0 AND 100),
    overall_score           numeric(6,2) CHECK (overall_score IS NULL OR overall_score BETWEEN 0 AND 100),
    findings                jsonb NOT NULL DEFAULT '[]'::jsonb,
    corrective_actions      jsonb NOT NULL DEFAULT '[]'::jsonb,
    reviewed_by_user_id     uuid,
    reviewed_at             timestamptz,
    valid_until             date,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_reviews_findings_array CHECK (jsonb_typeof(findings) = 'array'),
    CONSTRAINT supplier_reviews_actions_array CHECK (jsonb_typeof(corrective_actions) = 'array'),
    CONSTRAINT supplier_reviews_decision_shape CHECK (
        (review_status NOT IN ('approved', 'conditionally_approved', 'rejected')
         OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL))
    ),
    CONSTRAINT supplier_reviews_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_reviews_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_supplier_reviews_supplier
    ON procurement.supplier_qualification_reviews (tenant_id, supplier_id, created_at DESC);
CREATE INDEX ix_supplier_reviews_expiry
    ON procurement.supplier_qualification_reviews (tenant_id, review_status, valid_until);

-- ---------------------------------------------------------------------------
-- 11. Solicitudes de cotizacion / RFQ (no son solicitudes internas de compra)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.sourcing_requests (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    rfq_number              varchar(60) NOT NULL,
    title                   varchar(220) NOT NULL,
    description             text,
    sourcing_type           varchar(24) NOT NULL DEFAULT 'competitive_quote'
                            CHECK (sourcing_type IN ('competitive_quote', 'request_for_information', 'request_for_proposal', 'tender')),
    request_status          varchar(24) NOT NULL DEFAULT 'draft'
                            CHECK (request_status IN ('draft', 'published', 'receiving_quotes', 'evaluation', 'awarded', 'cancelled', 'closed')),
    currency                char(3) NOT NULL DEFAULT 'COP',
    issue_at                timestamptz,
    response_deadline       timestamptz,
    valid_until             timestamptz,
    delivery_terms          text,
    payment_terms_id        uuid,
    evaluation_criteria     jsonb NOT NULL DEFAULT '[]'::jsonb,
    requested_by_user_id    uuid,
    approved_by_user_id     uuid,
    awarded_supplier_id     uuid,
    awarded_quote_id        uuid,
    awarded_at              timestamptz,
    cancellation_reason     text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sourcing_requests_number_not_blank CHECK (btrim(rfq_number) <> ''),
    CONSTRAINT sourcing_requests_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT sourcing_requests_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT sourcing_requests_deadline CHECK (response_deadline IS NULL OR issue_at IS NULL OR response_deadline > issue_at),
    CONSTRAINT sourcing_requests_award_pair CHECK ((awarded_supplier_id IS NULL AND awarded_quote_id IS NULL) OR (awarded_supplier_id IS NOT NULL AND awarded_quote_id IS NOT NULL)),
    CONSTRAINT sourcing_requests_award_shape CHECK (
        (request_status <> 'awarded' OR (awarded_at IS NOT NULL AND awarded_quote_id IS NOT NULL))
        AND (awarded_at IS NULL OR awarded_quote_id IS NOT NULL)
    ),
    CONSTRAINT sourcing_requests_status_shape CHECK (
        (request_status NOT IN ('published', 'receiving_quotes', 'evaluation', 'awarded', 'closed')
         OR (issue_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (request_status <> 'cancelled'
             OR (cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> ''))
    ),
    CONSTRAINT sourcing_requests_eval_array CHECK (jsonb_typeof(evaluation_criteria) = 'array'),
    CONSTRAINT sourcing_requests_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT sourcing_requests_payment_terms_fk FOREIGN KEY (tenant_id, payment_terms_id)
        REFERENCES procurement.payment_terms (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sourcing_requests_awarded_supplier_fk FOREIGN KEY (tenant_id, awarded_supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sourcing_requests_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sourcing_requests_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT sourcing_requests_number_unique UNIQUE (tenant_id, company_id, rfq_number)
);

CREATE INDEX ix_sourcing_requests_company_status
    ON procurement.sourcing_requests (tenant_id, company_id, request_status, created_at DESC);
CREATE INDEX ix_sourcing_requests_deadline
    ON procurement.sourcing_requests (tenant_id, request_status, response_deadline)
    WHERE request_status IN ('published', 'receiving_quotes');

-- ---------------------------------------------------------------------------
-- 12. Lineas solicitadas en una RFQ (variante/unidad son referencias logicas)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.sourcing_request_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sourcing_request_id     uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    catalog_variant_id      uuid NOT NULL,
    item_description        varchar(240) NOT NULL,
    requested_quantity      numeric(18,6) NOT NULL CHECK (requested_quantity > 0),
    unit_id                 uuid,
    target_unit_price       numeric(20,6) CHECK (target_unit_price IS NULL OR target_unit_price >= 0),
    required_by             date,
    specification           text,
    is_optional             boolean NOT NULL DEFAULT false,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sourcing_request_lines_description_not_blank CHECK (btrim(item_description) <> ''),
    CONSTRAINT sourcing_request_lines_request_fk FOREIGN KEY (tenant_id, sourcing_request_id)
        REFERENCES procurement.sourcing_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sourcing_request_lines_tenant_request_id_unique UNIQUE (tenant_id, sourcing_request_id, id),
    CONSTRAINT sourcing_request_lines_number_unique UNIQUE (tenant_id, sourcing_request_id, line_number)
);

CREATE INDEX ix_sourcing_request_lines_variant
    ON procurement.sourcing_request_lines (tenant_id, catalog_variant_id);

-- ---------------------------------------------------------------------------
-- 13. Invitaciones a proveedores para participar en una RFQ
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_invitations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sourcing_request_id     uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    invitation_status       varchar(20) NOT NULL DEFAULT 'invited'
                            CHECK (invitation_status IN ('invited', 'viewed', 'accepted', 'declined', 'submitted', 'expired', 'revoked')),
    invited_at              timestamptz NOT NULL DEFAULT now(),
    responded_at            timestamptz,
    invited_by_user_id      uuid,
    response_note           text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_invitations_request_fk FOREIGN KEY (tenant_id, sourcing_request_id)
        REFERENCES procurement.sourcing_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invitations_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invitations_tenant_scope_unique UNIQUE (tenant_id, id, sourcing_request_id, supplier_id),
    CONSTRAINT supplier_invitations_one_per_supplier UNIQUE (tenant_id, sourcing_request_id, supplier_id)
);

CREATE INDEX ix_supplier_invitations_supplier
    ON procurement.supplier_invitations (tenant_id, supplier_id, invitation_status, invited_at DESC);

-- ---------------------------------------------------------------------------
-- 14. Cotizaciones recibidas (oferta del proveedor para una RFQ)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_quotes (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sourcing_request_id     uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    invitation_id           uuid NOT NULL,
    quote_number            varchar(80),
    revision_number         integer NOT NULL DEFAULT 1 CHECK (revision_number > 0),
    quote_status            varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (quote_status IN ('draft', 'submitted', 'under_review', 'accepted', 'rejected', 'withdrawn', 'expired')),
    currency                char(3) NOT NULL DEFAULT 'COP',
    exchange_rate           numeric(20,10) CHECK (exchange_rate IS NULL OR exchange_rate > 0),
    subtotal_amount         numeric(20,4) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_amount         numeric(20,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount              numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    freight_amount          numeric(20,4) NOT NULL DEFAULT 0 CHECK (freight_amount >= 0),
    total_amount            numeric(20,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    tax_included            boolean NOT NULL DEFAULT false,
    payment_terms_text      text,
    delivery_lead_time_days integer CHECK (delivery_lead_time_days IS NULL OR delivery_lead_time_days >= 0),
    valid_until             date,
    submitted_at            timestamptz,
    supplier_notes          text,
    evaluation_score        numeric(6,2) CHECK (evaluation_score IS NULL OR evaluation_score BETWEEN 0 AND 100),
    evaluated_by_user_id    uuid,
    evaluated_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_quotes_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT supplier_quotes_number_not_blank CHECK (quote_number IS NULL OR btrim(quote_number) <> ''),
    CONSTRAINT supplier_quotes_status_shape CHECK (
        (quote_status NOT IN ('submitted', 'under_review', 'accepted', 'rejected', 'withdrawn')
         OR submitted_at IS NOT NULL)
        AND (quote_status NOT IN ('accepted', 'rejected')
             OR (evaluated_by_user_id IS NOT NULL AND evaluated_at IS NOT NULL))
    ),
    CONSTRAINT supplier_quotes_invitation_fk FOREIGN KEY (tenant_id, invitation_id, sourcing_request_id, supplier_id)
        REFERENCES procurement.supplier_invitations (tenant_id, id, sourcing_request_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT supplier_quotes_request_supplier_fk FOREIGN KEY (tenant_id, sourcing_request_id)
        REFERENCES procurement.sourcing_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_quotes_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_quotes_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_quotes_scope_id_unique UNIQUE (tenant_id, sourcing_request_id, supplier_id, id),
    CONSTRAINT supplier_quotes_supplier_id_unique UNIQUE (tenant_id, supplier_id, id),
    CONSTRAINT supplier_quotes_revision_unique UNIQUE (tenant_id, sourcing_request_id, supplier_id, revision_number)
);

CREATE INDEX ix_supplier_quotes_request_status
    ON procurement.supplier_quotes (tenant_id, sourcing_request_id, quote_status, total_amount);
CREATE INDEX ix_supplier_quotes_supplier
    ON procurement.supplier_quotes (tenant_id, supplier_id, created_at DESC);

-- Agregar FK de awarded_quote_id despues de crear supplier_quotes.
ALTER TABLE procurement.sourcing_requests
    ADD CONSTRAINT sourcing_requests_awarded_quote_fk
    FOREIGN KEY (tenant_id, id, awarded_supplier_id, awarded_quote_id)
    REFERENCES procurement.supplier_quotes (tenant_id, sourcing_request_id, supplier_id, id)
    ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- 15. Lineas de cotizacion
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_quote_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sourcing_request_id     uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    quote_id                uuid NOT NULL,
    request_line_id         uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    supplier_item_code      varchar(100),
    quoted_description      varchar(240),
    offered_quantity        numeric(18,6) NOT NULL CHECK (offered_quantity > 0),
    unit_price              numeric(20,6) NOT NULL CHECK (unit_price >= 0),
    discount_rate           numeric(7,4) NOT NULL DEFAULT 0 CHECK (discount_rate BETWEEN 0 AND 100),
    tax_rate                numeric(7,4) NOT NULL DEFAULT 0 CHECK (tax_rate BETWEEN 0 AND 100),
    tax_amount              numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total              numeric(20,4) NOT NULL CHECK (line_total >= 0),
    minimum_order_quantity  numeric(18,6) CHECK (minimum_order_quantity IS NULL OR minimum_order_quantity > 0),
    available_quantity      numeric(18,6) CHECK (available_quantity IS NULL OR available_quantity >= 0),
    lead_time_days          integer CHECK (lead_time_days IS NULL OR lead_time_days >= 0),
    brand_offered           varchar(120),
    specification_notes     text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_quote_lines_quote_fk FOREIGN KEY (tenant_id, sourcing_request_id, supplier_id, quote_id)
        REFERENCES procurement.supplier_quotes (tenant_id, sourcing_request_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_quote_lines_request_line_fk FOREIGN KEY (tenant_id, sourcing_request_id, request_line_id)
        REFERENCES procurement.sourcing_request_lines (tenant_id, sourcing_request_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_quote_lines_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_quote_lines_number_unique UNIQUE (tenant_id, quote_id, line_number),
    CONSTRAINT supplier_quote_lines_request_line_unique UNIQUE (tenant_id, quote_id, request_line_id)
);

CREATE INDEX ix_supplier_quote_lines_request_line
    ON procurement.supplier_quote_lines (tenant_id, sourcing_request_id, request_line_id);

-- ---------------------------------------------------------------------------
-- 16. Acuerdos comerciales marco con proveedores (no son ordenes de compra)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_agreements (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    source_quote_id         uuid,
    agreement_number        varchar(80) NOT NULL,
    agreement_type          varchar(30) NOT NULL DEFAULT 'framework'
                            CHECK (agreement_type IN ('framework', 'pricing', 'service_level', 'confidentiality', 'other')),
    agreement_status        varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (agreement_status IN ('draft', 'pending_signature', 'active', 'suspended', 'expired', 'terminated')),
    currency                char(3) NOT NULL DEFAULT 'COP',
    payment_terms_id        uuid,
    starts_on               date,
    ends_on                 date,
    auto_renew              boolean NOT NULL DEFAULT false,
    renewal_notice_days     integer CHECK (renewal_notice_days IS NULL OR renewal_notice_days >= 0),
    agreement_document_key  text,
    signed_at               timestamptz,
    signed_by_user_id       uuid,
    commercial_terms        jsonb NOT NULL DEFAULT '{}'::jsonb,
    notes                   text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_agreements_number_not_blank CHECK (btrim(agreement_number) <> ''),
    CONSTRAINT supplier_agreements_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT supplier_agreements_dates CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
    CONSTRAINT supplier_agreements_terms_object CHECK (jsonb_typeof(commercial_terms) = 'object'),
    CONSTRAINT supplier_agreements_signature_shape CHECK (
        agreement_status <> 'active' OR (signed_at IS NOT NULL AND signed_by_user_id IS NOT NULL)
    ),
    CONSTRAINT supplier_agreements_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_agreements_quote_fk FOREIGN KEY (tenant_id, supplier_id, source_quote_id)
        REFERENCES procurement.supplier_quotes (tenant_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_agreements_payment_terms_fk FOREIGN KEY (tenant_id, payment_terms_id)
        REFERENCES procurement.payment_terms (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_agreements_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_agreements_number_unique UNIQUE (tenant_id, company_id, agreement_number)
);

CREATE INDEX ix_supplier_agreements_supplier
    ON procurement.supplier_agreements (tenant_id, supplier_id, agreement_status, ends_on);
CREATE INDEX ix_supplier_agreements_company
    ON procurement.supplier_agreements (tenant_id, company_id, agreement_status, starts_on);

-- ---------------------------------------------------------------------------
-- 17. Lineas / precios negociados del acuerdo marco
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_agreement_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    agreement_id            uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    catalog_variant_id      uuid NOT NULL,
    supplier_item_code      varchar(100),
    agreed_unit_price       numeric(20,6) NOT NULL CHECK (agreed_unit_price >= 0),
    currency                char(3) NOT NULL,
    minimum_quantity        numeric(18,6) CHECK (minimum_quantity IS NULL OR minimum_quantity > 0),
    maximum_quantity        numeric(18,6) CHECK (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity),
    valid_from              date,
    valid_until             date,
    price_conditions        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_agreement_lines_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT supplier_agreement_lines_dates CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from),
    CONSTRAINT supplier_agreement_lines_conditions_object CHECK (jsonb_typeof(price_conditions) = 'object'),
    CONSTRAINT supplier_agreement_lines_agreement_fk FOREIGN KEY (tenant_id, agreement_id)
        REFERENCES procurement.supplier_agreements (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_agreement_lines_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT supplier_agreement_lines_number_unique UNIQUE (tenant_id, agreement_id, line_number)
);

CREATE INDEX ix_supplier_agreement_lines_variant
    ON procurement.supplier_agreement_lines (tenant_id, catalog_variant_id, valid_from, valid_until);

-- ---------------------------------------------------------------------------
-- 18. Solicitudes internas de compra y aprobaciones
-- branch_id NULL representa una solicitud central de la empresa.
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.purchase_requests (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid,
    request_number          varchar(80) NOT NULL,
    request_origin          varchar(24) NOT NULL DEFAULT 'manual'
                            CHECK (request_origin IN ('manual', 'replenishment', 'centralized')),
    source_reference_id     uuid,
    request_status          varchar(24) NOT NULL DEFAULT 'draft'
                            CHECK (request_status IN ('draft', 'submitted', 'approved', 'partially_ordered', 'ordered', 'rejected', 'cancelled')),
    priority                smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    currency                char(3) NOT NULL DEFAULT 'COP',
    estimated_total         numeric(20,4) CHECK (estimated_total IS NULL OR estimated_total >= 0),
    requested_by_user_id    uuid,
    approved_by_user_id     uuid,
    rejected_by_user_id     uuid,
    submitted_at            timestamptz,
    approved_at             timestamptz,
    rejected_at             timestamptz,
    cancelled_at            timestamptz,
    required_by             date,
    justification           text,
    rejection_reason        text,
    cancellation_reason     text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_requests_number_not_blank CHECK (btrim(request_number) <> ''),
    CONSTRAINT purchase_requests_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT purchase_requests_replenishment_source CHECK (
        request_origin <> 'replenishment' OR source_reference_id IS NOT NULL
    ),
    CONSTRAINT purchase_requests_status_shape CHECK (
        (request_status NOT IN ('submitted', 'approved', 'partially_ordered', 'ordered', 'rejected')
         OR submitted_at IS NOT NULL)
        AND (request_status NOT IN ('approved', 'partially_ordered', 'ordered')
             OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (request_status <> 'rejected'
             OR (rejected_at IS NOT NULL AND rejected_by_user_id IS NOT NULL
                 AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND (request_status <> 'cancelled'
             OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL
                 AND btrim(cancellation_reason) <> ''))
    ),
    CONSTRAINT purchase_requests_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT purchase_requests_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT purchase_requests_company_id_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT purchase_requests_number_unique UNIQUE (tenant_id, company_id, request_number)
);

CREATE INDEX ix_procurement_purchase_requests_scope_status
    ON procurement.purchase_requests (tenant_id, company_id, branch_id, request_status, created_at DESC);
CREATE INDEX ix_procurement_purchase_requests_source
    ON procurement.purchase_requests (tenant_id, request_origin, source_reference_id)
    WHERE source_reference_id IS NOT NULL;

CREATE TABLE procurement.purchase_request_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    purchase_request_id     uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    catalog_variant_id      uuid NOT NULL,
    unit_id                 uuid,
    item_description        varchar(240) NOT NULL,
    requested_quantity      numeric(18,6) NOT NULL CHECK (requested_quantity > 0),
    estimated_unit_price    numeric(20,6) CHECK (estimated_unit_price IS NULL OR estimated_unit_price >= 0),
    required_by             date,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_request_lines_description_not_blank CHECK (btrim(item_description) <> ''),
    CONSTRAINT purchase_request_lines_request_fk FOREIGN KEY (tenant_id, purchase_request_id)
        REFERENCES procurement.purchase_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_request_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT purchase_request_lines_tenant_request_id_unique UNIQUE (tenant_id, purchase_request_id, id),
    CONSTRAINT purchase_request_lines_number_unique UNIQUE (tenant_id, purchase_request_id, line_number)
);

CREATE INDEX ix_procurement_purchase_request_lines_variant
    ON procurement.purchase_request_lines (tenant_id, catalog_variant_id);

CREATE TABLE procurement.purchase_request_approvals (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    purchase_request_id     uuid NOT NULL,
    action                  varchar(20) NOT NULL
                            CHECK (action IN ('submitted', 'approved', 'rejected', 'returned', 'cancelled', 'ordered')),
    actor_user_id           uuid NOT NULL,
    reason                  text,
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_request_approvals_request_fk FOREIGN KEY (tenant_id, purchase_request_id)
        REFERENCES procurement.purchase_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_request_approvals_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_purchase_request_approvals
    ON procurement.purchase_request_approvals (tenant_id, purchase_request_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 19. Ordenes de compra y asignaciones de destino por sucursal/bodega
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.purchase_orders (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid,
    supplier_id             uuid NOT NULL,
    purchase_request_id     uuid,
    order_number            varchar(80) NOT NULL,
    order_status            varchar(24) NOT NULL DEFAULT 'draft'
                            CHECK (order_status IN ('draft', 'pending_approval', 'approved', 'issued', 'partially_received', 'received', 'cancelled', 'closed')),
    currency                char(3) NOT NULL DEFAULT 'COP',
    payment_terms_id        uuid,
    subtotal_amount         numeric(20,4) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_amount         numeric(20,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount              numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    freight_amount          numeric(20,4) NOT NULL DEFAULT 0 CHECK (freight_amount >= 0),
    total_amount            numeric(20,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    ordered_at              timestamptz NOT NULL DEFAULT now(),
    expected_delivery_at    timestamptz,
    approved_by_user_id     uuid,
    approved_at             timestamptz,
    issued_by_user_id       uuid,
    issued_at               timestamptz,
    received_at             timestamptz,
    cancelled_at            timestamptz,
    cancellation_reason     text,
    created_by_user_id      uuid,
    notes                   text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_orders_number_not_blank CHECK (btrim(order_number) <> ''),
    CONSTRAINT purchase_orders_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT purchase_orders_cancel_shape CHECK (
        order_status <> 'cancelled'
        OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> '')
    ),
    CONSTRAINT purchase_orders_status_shape CHECK (
        (order_status NOT IN ('approved', 'issued', 'partially_received', 'received', 'closed')
         OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (order_status NOT IN ('issued', 'partially_received', 'received', 'closed')
             OR (issued_at IS NOT NULL AND issued_by_user_id IS NOT NULL))
        AND (order_status <> 'received' OR received_at IS NOT NULL)
    ),
    CONSTRAINT purchase_orders_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT purchase_orders_supplier_profile_fk FOREIGN KEY (tenant_id, company_id, supplier_id)
        REFERENCES procurement.supplier_company_profiles (tenant_id, company_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_source_request_fk FOREIGN KEY (tenant_id, company_id, purchase_request_id)
        REFERENCES procurement.purchase_requests (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_payment_terms_fk FOREIGN KEY (tenant_id, payment_terms_id)
        REFERENCES procurement.payment_terms (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_orders_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT purchase_orders_company_id_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT purchase_orders_source_request_scope_unique
        UNIQUE (tenant_id, company_id, id, purchase_request_id),
    CONSTRAINT purchase_orders_supplier_scope_id_unique UNIQUE (tenant_id, company_id, supplier_id, id),
    CONSTRAINT purchase_orders_number_unique UNIQUE (tenant_id, company_id, order_number)
);

CREATE INDEX ix_procurement_purchase_orders_scope_status
    ON procurement.purchase_orders (tenant_id, company_id, branch_id, order_status, ordered_at DESC);
CREATE INDEX ix_procurement_purchase_orders_supplier
    ON procurement.purchase_orders (tenant_id, supplier_id, order_status, ordered_at DESC);

CREATE TABLE procurement.purchase_order_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    purchase_request_id     uuid,
    purchase_request_line_id uuid,
    line_number             integer NOT NULL CHECK (line_number > 0),
    catalog_variant_id      uuid NOT NULL,
    unit_id                 uuid,
    item_description        varchar(240) NOT NULL,
    supplier_item_code      varchar(100),
    ordered_quantity        numeric(18,6) NOT NULL CHECK (ordered_quantity > 0),
    unit_price              numeric(20,6) NOT NULL CHECK (unit_price >= 0),
    discount_amount         numeric(20,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount              numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total              numeric(20,4) NOT NULL CHECK (line_total >= 0),
    required_by             date,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_order_lines_description_not_blank CHECK (btrim(item_description) <> ''),
    CONSTRAINT purchase_order_lines_request_pair CHECK (
        (purchase_request_id IS NULL AND purchase_request_line_id IS NULL)
        OR (purchase_request_id IS NOT NULL AND purchase_request_line_id IS NOT NULL)
    ),
    CONSTRAINT purchase_order_lines_order_fk FOREIGN KEY (tenant_id, company_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_order_lines_request_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_request_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, id, purchase_request_id) ON DELETE RESTRICT,
    CONSTRAINT purchase_order_lines_request_line_fk
        FOREIGN KEY (tenant_id, purchase_request_id, purchase_request_line_id)
        REFERENCES procurement.purchase_request_lines (tenant_id, purchase_request_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_order_lines_tenant_order_id_unique UNIQUE (tenant_id, company_id, purchase_order_id, id),
    CONSTRAINT purchase_order_lines_number_unique UNIQUE (tenant_id, purchase_order_id, line_number)
);

CREATE INDEX ix_procurement_purchase_order_lines_variant
    ON procurement.purchase_order_lines (tenant_id, catalog_variant_id);
CREATE INDEX ix_procurement_purchase_order_lines_request
    ON procurement.purchase_order_lines (tenant_id, purchase_request_id, purchase_request_line_id)
    WHERE purchase_request_line_id IS NOT NULL;

CREATE TABLE procurement.purchase_order_allocations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    purchase_order_line_id  uuid NOT NULL,
    target_branch_id        uuid,
    target_warehouse_id     uuid NOT NULL,
    allocated_quantity      numeric(18,6) NOT NULL CHECK (allocated_quantity > 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_order_allocations_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id)
        REFERENCES procurement.purchase_order_lines (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_order_allocations_scope_id_unique
        UNIQUE (tenant_id, company_id, purchase_order_id, purchase_order_line_id, id, target_warehouse_id),
    CONSTRAINT purchase_order_allocations_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_procurement_order_allocation_branch
    ON procurement.purchase_order_allocations
       (tenant_id, purchase_order_line_id, target_branch_id, target_warehouse_id)
    WHERE target_branch_id IS NOT NULL;
CREATE UNIQUE INDEX uq_procurement_order_allocation_central
    ON procurement.purchase_order_allocations
       (tenant_id, purchase_order_line_id, target_warehouse_id)
    WHERE target_branch_id IS NULL;
CREATE INDEX ix_procurement_order_allocations_warehouse
    ON procurement.purchase_order_allocations (tenant_id, target_warehouse_id, target_branch_id);

CREATE TABLE procurement.purchase_order_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    purchase_order_id   uuid NOT NULL,
    previous_status     varchar(24),
    new_status          varchar(24) NOT NULL
                        CHECK (new_status IN ('draft', 'pending_approval', 'approved', 'issued', 'partially_received', 'received', 'cancelled', 'closed')),
    actor_user_id       uuid,
    reason              text,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT purchase_order_status_history_order_fk FOREIGN KEY (tenant_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT purchase_order_status_history_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_order_status_history
    ON procurement.purchase_order_status_history (tenant_id, purchase_order_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 20. Recepciones fisicas y discrepancias (el stock lo registra Inventory)
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.goods_receipts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    branch_id               uuid,
    warehouse_id            uuid NOT NULL,
    receipt_number          varchar(80) NOT NULL,
    receipt_status          varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (receipt_status IN ('draft', 'posted', 'cancelled')),
    delivered_at            timestamptz,
    received_at             timestamptz NOT NULL DEFAULT now(),
    posted_at               timestamptz,
    posted_by_user_id       uuid,
    cancelled_at            timestamptz,
    cancellation_reason     text,
    freight_amount          numeric(20,4) NOT NULL DEFAULT 0 CHECK (freight_amount >= 0),
    other_charges_amount    numeric(20,4) NOT NULL DEFAULT 0 CHECK (other_charges_amount >= 0),
    notes                   text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT goods_receipts_number_not_blank CHECK (btrim(receipt_number) <> ''),
    CONSTRAINT goods_receipts_post_shape CHECK (
        receipt_status <> 'posted' OR (posted_at IS NOT NULL AND posted_by_user_id IS NOT NULL)
    ),
    CONSTRAINT goods_receipts_cancel_shape CHECK (
        receipt_status <> 'cancelled'
        OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> '')
    ),
    CONSTRAINT goods_receipts_purchase_order_fk FOREIGN KEY (tenant_id, company_id, supplier_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT goods_receipts_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT goods_receipts_purchase_order_scope_id_unique
        UNIQUE (tenant_id, company_id, purchase_order_id, id, warehouse_id),
    CONSTRAINT goods_receipts_number_unique UNIQUE (tenant_id, company_id, supplier_id, receipt_number)
);

CREATE INDEX ix_procurement_goods_receipts_order
    ON procurement.goods_receipts (tenant_id, purchase_order_id, receipt_status, received_at DESC);
CREATE INDEX ix_procurement_goods_receipts_warehouse
    ON procurement.goods_receipts (tenant_id, company_id, warehouse_id, receipt_status);

CREATE TABLE procurement.goods_receipt_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    goods_receipt_id        uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    purchase_order_line_id  uuid NOT NULL,
    allocation_id           uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    quantity_received       numeric(18,6) NOT NULL CHECK (quantity_received > 0),
    quantity_accepted       numeric(18,6) NOT NULL DEFAULT 0 CHECK (quantity_accepted >= 0),
    quantity_rejected       numeric(18,6) NOT NULL DEFAULT 0 CHECK (quantity_rejected >= 0),
    inspection_status       varchar(20) NOT NULL DEFAULT 'pending'
                            CHECK (inspection_status IN ('pending', 'accepted', 'partially_rejected', 'rejected')),
    supplier_lot_number     varchar(100),
    expires_on              date,
    discrepancy_reason      text,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT goods_receipt_lines_quantities CHECK (
        quantity_accepted + quantity_rejected <= quantity_received
    ),
    CONSTRAINT goods_receipt_lines_inspection_shape CHECK (
        (inspection_status = 'pending' AND quantity_accepted = 0 AND quantity_rejected = 0)
        OR (inspection_status = 'accepted' AND quantity_accepted = quantity_received AND quantity_rejected = 0)
        OR (inspection_status = 'partially_rejected' AND quantity_accepted > 0
            AND quantity_rejected > 0 AND quantity_accepted + quantity_rejected = quantity_received)
        OR (inspection_status = 'rejected' AND quantity_accepted = 0
            AND quantity_rejected = quantity_received)
    ),
    CONSTRAINT goods_receipt_lines_discrepancy_reason CHECK (
        quantity_rejected = 0 OR (discrepancy_reason IS NOT NULL AND btrim(discrepancy_reason) <> '')
    ),
    CONSTRAINT goods_receipt_lines_receipt_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, goods_receipt_id, warehouse_id)
        REFERENCES procurement.goods_receipts (tenant_id, company_id, purchase_order_id, id, warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT goods_receipt_lines_order_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id)
        REFERENCES procurement.purchase_order_lines (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT goods_receipt_lines_allocation_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id, allocation_id, warehouse_id)
        REFERENCES procurement.purchase_order_allocations
            (tenant_id, company_id, purchase_order_id, purchase_order_line_id, id, target_warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT goods_receipt_lines_tenant_order_line_id_unique
        UNIQUE (tenant_id, company_id, purchase_order_id, purchase_order_line_id, id),
    CONSTRAINT goods_receipt_lines_number_unique UNIQUE (tenant_id, goods_receipt_id, line_number)
);

CREATE INDEX ix_procurement_receipt_lines_order_line
    ON procurement.goods_receipt_lines (tenant_id, purchase_order_line_id, goods_receipt_id);

-- ---------------------------------------------------------------------------
-- 21. Facturas de proveedor para conciliacion de tres vias
-- FINANCE conserva cuentas por pagar y pagos; Procurement conserva la factura
-- y su conciliacion contra la orden y las recepciones.
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_invoices (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    invoice_number           varchar(120) NOT NULL,
    invoice_status           varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (invoice_status IN ('draft', 'received', 'matched', 'disputed', 'approved', 'rejected', 'void')),
    invoice_date             date NOT NULL,
    due_date                 date,
    currency                 char(3) NOT NULL DEFAULT 'COP',
    subtotal_amount          numeric(20,4) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_amount          numeric(20,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount               numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    freight_amount           numeric(20,4) NOT NULL DEFAULT 0 CHECK (freight_amount >= 0),
    total_amount             numeric(20,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    received_at              timestamptz,
    matched_at               timestamptz,
    approved_at              timestamptz,
    approved_by_user_id      uuid,
    rejected_at              timestamptz,
    rejection_reason         text,
    dispute_reason           text,
    voided_at                timestamptz,
    void_reason              text,
    source_document_key      text,
    created_by_user_id       uuid,
    notes                    text,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_invoices_number_not_blank CHECK (btrim(invoice_number) <> ''),
    CONSTRAINT supplier_invoices_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT supplier_invoices_due_date CHECK (due_date IS NULL OR due_date >= invoice_date),
    CONSTRAINT supplier_invoices_status_shape CHECK (
        (invoice_status NOT IN ('received', 'matched', 'disputed', 'approved', 'rejected')
         OR received_at IS NOT NULL)
        AND (invoice_status NOT IN ('matched', 'approved') OR matched_at IS NOT NULL)
        AND (invoice_status <> 'approved' OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (invoice_status <> 'rejected'
             OR (rejected_at IS NOT NULL AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND (invoice_status <> 'disputed'
             OR (dispute_reason IS NOT NULL AND btrim(dispute_reason) <> ''))
        AND (invoice_status <> 'void'
             OR (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason) <> ''))
    ),
    CONSTRAINT supplier_invoices_supplier_profile_fk FOREIGN KEY (tenant_id, company_id, supplier_id)
        REFERENCES procurement.supplier_company_profiles (tenant_id, company_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invoices_tenant_company_supplier_id_unique UNIQUE (tenant_id, company_id, supplier_id, id)
);

CREATE UNIQUE INDEX uq_procurement_supplier_invoice_number
    ON procurement.supplier_invoices (tenant_id, company_id, supplier_id, lower(btrim(invoice_number)));
CREATE INDEX ix_procurement_supplier_invoices_status
    ON procurement.supplier_invoices (tenant_id, company_id, invoice_status, due_date);
CREATE INDEX ix_procurement_supplier_invoices_supplier
    ON procurement.supplier_invoices (tenant_id, supplier_id, invoice_date DESC);

CREATE TABLE procurement.supplier_invoice_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_id             uuid NOT NULL,
    supplier_invoice_id     uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    purchase_order_line_id  uuid NOT NULL,
    goods_receipt_line_id   uuid,
    line_number             integer NOT NULL CHECK (line_number > 0),
    item_description        varchar(240) NOT NULL,
    invoiced_quantity       numeric(18,6) NOT NULL CHECK (invoiced_quantity > 0),
    unit_price              numeric(20,6) NOT NULL CHECK (unit_price >= 0),
    tax_amount              numeric(20,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total              numeric(20,4) NOT NULL CHECK (line_total >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT supplier_invoice_lines_description_not_blank CHECK (btrim(item_description) <> ''),
    CONSTRAINT supplier_invoice_lines_invoice_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id, supplier_invoice_id)
        REFERENCES procurement.supplier_invoices (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invoice_lines_order_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invoice_lines_order_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id)
        REFERENCES procurement.purchase_order_lines (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invoice_lines_receipt_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id, goods_receipt_line_id)
        REFERENCES procurement.goods_receipt_lines
            (tenant_id, company_id, purchase_order_id, purchase_order_line_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_invoice_lines_tenant_invoice_id_unique
        UNIQUE (tenant_id, supplier_invoice_id, id),
    CONSTRAINT supplier_invoice_lines_number_unique UNIQUE (tenant_id, supplier_invoice_id, line_number)
);

CREATE INDEX ix_procurement_invoice_lines_order_line
    ON procurement.supplier_invoice_lines (tenant_id, purchase_order_line_id, goods_receipt_line_id);

-- ---------------------------------------------------------------------------
-- 22. Historial append-only de cambios de estado del proveedor
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.supplier_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    supplier_id         uuid NOT NULL,
    previous_status     varchar(24),
    new_status          varchar(24) NOT NULL,
    reason              text,
    changed_by_user_id  uuid,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT supplier_status_history_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT supplier_status_history_status CHECK (
        new_status IN ('prospect', 'pending_review', 'approved', 'suspended', 'rejected', 'inactive', 'archived')
        AND (previous_status IS NULL OR previous_status IN ('prospect', 'pending_review', 'approved', 'suspended', 'rejected', 'inactive', 'archived'))
    ),
    CONSTRAINT supplier_status_history_supplier_fk FOREIGN KEY (tenant_id, supplier_id)
        REFERENCES procurement.suppliers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT supplier_status_history_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_supplier_status_history_supplier
    ON procurement.supplier_status_history (tenant_id, supplier_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- 23. Inbox idempotente para eventos consumidos por Procurement
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id            uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    payload_sha256      char(64) NOT NULL,
    source_module       varchar(80) NOT NULL,
    processed_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT processed_events_hash_format CHECK (payload_sha256 ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT processed_events_tenant_event_unique UNIQUE (tenant_id, event_id),
    CONSTRAINT processed_events_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_processed_events_type
    ON procurement.processed_events (tenant_id, event_type, processed_at DESC);

-- ---------------------------------------------------------------------------
-- 24. Outbox transaccional para publicar eventos de Procurement
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.event_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id            uuid NOT NULL DEFAULT gen_random_uuid(),
    aggregate_type      varchar(100) NOT NULL,
    aggregate_id        uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    event_version       smallint NOT NULL DEFAULT 1 CHECK (event_version > 0),
    payload             jsonb NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    available_at        timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    attempt_count       integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error          text,
    CONSTRAINT event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT event_outbox_event_unique UNIQUE (tenant_id, event_id),
    CONSTRAINT event_outbox_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_outbox_pending
    ON procurement.event_outbox (tenant_id, available_at, occurred_at)
    WHERE published_at IS NULL;
CREATE INDEX ix_procurement_outbox_aggregate
    ON procurement.event_outbox (tenant_id, aggregate_type, aggregate_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 25. Indices auxiliares y comentarios de integracion
-- ---------------------------------------------------------------------------

COMMENT ON TABLE procurement.suppliers IS
'Entidad proveedora externa dentro de un tenant. Puede relacionarse con multiples empresas legales del mismo tenant mediante supplier_company_profiles.';
COMMENT ON TABLE procurement.supplier_company_profiles IS
'Relacion comercial de un proveedor con una company_id de Organization. company_id es referencia logica validada mediante OrganizationPort.';
COMMENT ON TABLE procurement.supplier_branch_profiles IS
'Disponibilidad, preferencia o exclusividad de un proveedor por sucursal. La aplicacion valida branch_id y hace cumplir exclusividad en las operaciones de compra.';
COMMENT ON TABLE procurement.supplier_catalog_items IS
'Equivalencia entre la referencia comercial del proveedor y catalog_variant_id. No es propietario del producto ni de la unidad de catalogo.';
COMMENT ON TABLE procurement.sourcing_requests IS
'Solicitud de informacion/cotizacion competitiva (RFQ), distinta de una solicitud interna de compra.';
COMMENT ON TABLE procurement.supplier_quotes IS
'Oferta versionada recibida de un proveedor invitado a una RFQ. Una oferta aceptada no crea por si sola una orden de compra.';
COMMENT ON TABLE procurement.supplier_agreements IS
'Acuerdo comercial marco o de precios. No representa una orden de compra ni una recepcion de inventario.';
COMMENT ON TABLE procurement.purchase_requests IS
'Solicitud interna de compra por sucursal o central. branch_id NULL representa una solicitud de la empresa.';
COMMENT ON TABLE procurement.purchase_orders IS
'Compromiso formal de compra emitido a un proveedor. Las lineas y asignaciones pueden distribuirse entre sucursales y bodegas.';
COMMENT ON TABLE procurement.goods_receipts IS
'Recepcion fisica parcial o completa vinculada a una orden y bodega. Al postear, Procurement publica un evento para que Inventory registre existencias y lotes.';
COMMENT ON TABLE procurement.supplier_invoices IS
'Factura de proveedor y estado de conciliacion de tres vias. Finance administra cuentas por pagar y pagos.';
COMMENT ON TABLE procurement.processed_events IS
'Inbox idempotente. Registrar event_id y aplicar la consecuencia del evento en la misma transaccion; si el ID ya existe, comparar payload_sha256.';
COMMENT ON TABLE procurement.event_outbox IS
'Outbox transaccional. Insertar evento en la misma transaccion que el cambio de negocio; el publicador marca published_at tras confirmacion del broker.';

-- ---------------------------------------------------------------------------
-- 26. updated_at y proteccion de tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'payment_terms', 'supplier_categories', 'suppliers', 'supplier_contacts',
        'supplier_addresses', 'supplier_company_profiles', 'supplier_branch_profiles',
        'supplier_catalog_items',
        'supplier_documents', 'supplier_qualification_reviews', 'sourcing_requests',
        'sourcing_request_lines', 'supplier_invitations', 'supplier_quotes',
        'supplier_quote_lines', 'supplier_agreements', 'supplier_agreement_lines',
        'purchase_requests', 'purchase_request_lines', 'purchase_orders',
        'purchase_order_lines', 'purchase_order_allocations', 'goods_receipts',
        'goods_receipt_lines', 'supplier_invoices', 'supplier_invoice_lines'
    ] LOOP
        EXECUTE format('CREATE TRIGGER trg_%I_set_updated_at BEFORE UPDATE ON procurement.%I FOR EACH ROW EXECUTE FUNCTION procurement.set_updated_at()', v_table, v_table);
        EXECUTE format('CREATE TRIGGER trg_%I_prevent_tenant_change BEFORE UPDATE ON procurement.%I FOR EACH ROW EXECUTE FUNCTION procurement.prevent_tenant_change()', v_table, v_table);
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'supplier_category_assignments', 'purchase_request_approvals',
        'purchase_order_status_history', 'supplier_status_history',
        'processed_events', 'event_outbox'
    ] LOOP
        EXECUTE format('CREATE TRIGGER trg_%I_prevent_tenant_change BEFORE UPDATE ON procurement.%I FOR EACH ROW EXECUTE FUNCTION procurement.prevent_tenant_change()', v_table, v_table);
    END LOOP;
END;
$$;

CREATE TRIGGER trg_supplier_status_history_append_only
BEFORE UPDATE OR DELETE ON procurement.supplier_status_history
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_purchase_request_approvals_append_only
BEFORE UPDATE OR DELETE ON procurement.purchase_request_approvals
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_purchase_order_status_history_append_only
BEFORE UPDATE OR DELETE ON procurement.purchase_order_status_history
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_processed_events_append_only
BEFORE UPDATE OR DELETE ON procurement.processed_events
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

-- ---------------------------------------------------------------------------
-- 27. Inicializacion idempotente de catalogos por tenant
-- Debe llamarse dentro de una transaccion con SET LOCAL app.tenant_id.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION procurement.initialize_tenant_procurement(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM procurement.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO procurement.payment_terms (tenant_id, terms_code, name, due_days, is_immediate)
    VALUES
        (p_tenant_id, 'DUE_ON_RECEIPT', 'Pago inmediato', 0, true),
        (p_tenant_id, 'NET_15', '15 dias', 15, false),
        (p_tenant_id, 'NET_30', '30 dias', 30, false)
    ON CONFLICT (tenant_id, terms_code) DO NOTHING;

    INSERT INTO procurement.supplier_categories (tenant_id, category_code, name, sort_order)
    VALUES
        (p_tenant_id, 'FOOD', 'Alimentos', 10),
        (p_tenant_id, 'BEVERAGES', 'Bebidas', 20),
        (p_tenant_id, 'PACKAGING', 'Empaques y desechables', 30),
        (p_tenant_id, 'CLEANING', 'Aseo y limpieza', 40),
        (p_tenant_id, 'EQUIPMENT', 'Equipos y mantenimiento', 50),
        (p_tenant_id, 'SERVICES', 'Servicios', 60),
        (p_tenant_id, 'OTHER', 'Otros', 90)
    ON CONFLICT (tenant_id, category_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 28. RLS en todas las tablas tenant-scoped del schema
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'payment_terms', 'supplier_categories', 'suppliers', 'supplier_contacts',
        'supplier_addresses', 'supplier_category_assignments', 'supplier_company_profiles',
        'supplier_branch_profiles', 'supplier_catalog_items', 'supplier_documents',
        'supplier_qualification_reviews',
        'sourcing_requests', 'sourcing_request_lines', 'supplier_invitations',
        'supplier_quotes', 'supplier_quote_lines', 'supplier_agreements',
        'supplier_agreement_lines', 'purchase_requests', 'purchase_request_lines',
        'purchase_request_approvals', 'purchase_orders', 'purchase_order_lines',
        'purchase_order_allocations', 'purchase_order_status_history',
        'goods_receipts', 'goods_receipt_lines', 'supplier_invoices',
        'supplier_invoice_lines', 'supplier_status_history', 'processed_events',
        'event_outbox'
    ] LOOP
        EXECUTE format('ALTER TABLE procurement.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE procurement.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format('CREATE POLICY tenant_isolation ON procurement.%I USING (tenant_id = procurement.current_tenant_id()) WITH CHECK (tenant_id = procurement.current_tenant_id())', v_table);
    END LOOP;
END;
$$;

COMMIT;

-- ============================================================================
-- GUIA DE INTEGRACION PARA RUST / CONTRATOS
-- ============================================================================
-- Permisos a registrar mediante una migracion PROPIA de Identity:
--   procurement.suppliers.read / procurement.suppliers.create
--   procurement.suppliers.update / procurement.suppliers.approve
--   procurement.suppliers.suspend / procurement.suppliers.documents.manage
--   procurement.suppliers.evaluate / procurement.suppliers.categories.manage
--   procurement.suppliers.branch_profiles.manage
--   procurement.sourcing.read / procurement.sourcing.create
--   procurement.sourcing.publish / procurement.sourcing.cancel
--   procurement.quotes.read / procurement.quotes.submit
--   procurement.quotes.evaluate / procurement.quotes.award
--   procurement.agreements.read / procurement.agreements.manage
--   procurement.requests.read / procurement.requests.create
--   procurement.requests.approve / procurement.requests.reject
--   procurement.orders.read / procurement.orders.create
--   procurement.orders.approve / procurement.orders.issue / procurement.orders.cancel
--   procurement.receipts.read / procurement.receipts.create / procurement.receipts.post
--   procurement.invoices.read / procurement.invoices.create
--   procurement.invoices.match / procurement.invoices.approve
--
-- Contratos/puertos sugeridos:
--   OrganizationCompanyScopePort: validar company_id del tenant y su estado.
--   CatalogVariantPort: validar catalog_variant_id y snapshots de item/unidad.
--   InventoryWarehouseScopePort: validar warehouse_id y su relacion con company/branch.
--   IdentityActorAuthorizationPort: validar actor, permiso y alcance.
--   InventoryReceiptPort: aplicar una recepcion posteada en Inventory de forma idempotente.
--   EventPublisherPort / EventInboxPort: outbox e inbox con contratos versionados.
--   DocumentStoragePort: subir/leer documentos mediante storage externo.
--   ClockPort / IdGeneratorPort: pruebas deterministas.
--
-- Eventos publicados sugeridos:
--   procurement.supplier_approved.v1
--   procurement.supplier_suspended.v1
--   procurement.sourcing_published.v1
--   procurement.quote_submitted.v1
--   procurement.sourcing_awarded.v1
--   procurement.agreement_activated.v1
--   procurement.purchase_request_approved.v1
--   procurement.purchase_order_issued.v1
--   procurement.receipt_posted.v1
--   procurement.supplier_invoice_matched.v1
--
-- Eventos consumidos sugeridos:
--   organization.company_suspended.v1
--   identity.user_deactivated.v1 (para revocar actor/acciones pendientes)
--   inventory.stock_below_reorder_point.v1 (para proponer solicitudes de compra)
--
-- Invariantes obligatorios de aplicacion:
--   * Validar company_id contra Organization antes de crear perfiles, RFQ o acuerdos.
--   * Validar catalog_variant_id / unit_id contra Catalog antes de guardar RFQ/ofertas.
--   * Solo proveedores approved pueden recibir invitaciones a sourcing (salvo
--     excepcion aprobada y auditada).
--   * No aceptar cotizaciones fuera del plazo salvo extension documentada.
--   * Al adjudicar, actualizar RFQ y guardar el evento outbox en una transaccion.
--   * Una adjudicacion no elude la aprobacion de la solicitud de compra ni la orden.
--   * Validar solicitud aprobada, perfil activo del proveedor y limites de aprobacion
--     antes de emitir una orden de compra.
--   * Validar que la suma de asignaciones por linea no exceda la cantidad ordenada.
--   * Al postear una recepcion, guardar el cambio y el evento outbox en una transaccion;
--     Inventory debe procesarlo idempotentemente y registrar existencias/lotes.
--   * La conciliacion de facturas compara cantidades/precios de orden y recepcion;
--     una discrepancia no debe habilitar aprobacion ni cuentas por pagar.
--   * No exponer storage_key ni URLs privadas de documentos al navegador.
--   * Para event_id repetido, comparar payload_sha256; mismo ID con hash distinto
--     debe rechazarse y generar alerta de seguridad.
--   * Limitar cambios de cotizaciones una vez submitted; las revisiones se
--     representan como nuevas revisiones/versiones, no mutando una oferta evaluada.
--   * Hacer idempotente la publicacion/consumo de eventos y usar reintentos con backoff.
--   * RLS por tenant no sustituye autorizacion por empresa/sucursal.
--
-- IMPORTANTE SOBRE EL ORDEN:
--   Platform -> Organization -> Identity -> Catalog -> Procurement.
-- ============================================================================
-- FIN MODULO 7: PROCUREMENT
-- ============================================================================
