-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 15: BILLING (FACTURACION COMERCIAL Y DOCUMENTOS FISCALES)
-- Ubicacion del crate: crates/modules/billing
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD DE BILLING
--   * Emision de facturas de venta y otros documentos comerciales/fiscales
--     emitidos por cada restaurante a sus propios clientes.
--   * Tipos de documento, perfiles fiscales del emisor, jurisdicciones,
--     autorizaciones/rangos de numeracion y series por empresa/sucursal.
--   * Instantaneas inmutables de emisor, receptor, productos, precios, impuestos
--     y totales al emitir un documento.
--   * Notas credito/debito, referencias entre documentos y soportes.
--   * Transmision a autoridades fiscales/proveedores electronicos, intentos,
--     respuestas, artefactos XML/UBL/PDF, entregas y contingencias.
--   * Inbox, Outbox e idempotencia para integracion entre modulos.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO)
--   * Facturacion SaaS de suscripciones que Open Restaurant-OS cobra a tenants:
--     platform.invoices, platform.invoice_items y platform.billing_payments.
--   * Ventas, pedidos, devoluciones comerciales y calculo de la operacion de
--     origen: sales. Billing conserva source_module/source_document_id como UUID
--     logicos y snapshots documentales.
--   * Maestro de clientes y sus perfiles: customers. Billing conserva los datos
--     del receptor como instantanea legal del documento emitido.
--   * Catalogo de productos y precios: catalog. Billing conserva snapshots.
--   * Tarifas, categorias y calculo fiscal operativo: finance. Billing conserva
--     el desglose fiscal recibido mediante contratos y snapshots por documento.
--   * Procesamiento de pagos y reembolsos monetarios: payments.
--   * Libro mayor, cuentas por cobrar/pagar, declaraciones y conciliacion:
--     finance.
--   * Secretos, credenciales y conectores de terceros: integrations/KMS/Vault.
--
-- LIMITES Y SEGURIDAD
--   * La unica FK externa de este modulo es platform.tenants(id).
--   * No crea FK fisicas hacia sales, customers, catalog, finance, payments,
--     organization, identity ni platform.invoices.
--   * Todas las tablas tenant-scoped tienen tenant_id y RLS + FORCE RLS.
--   * Cada transaccion autenticada establece SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant se deriva del contexto autenticado; nunca confiar en HTTP body.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * Datos tributarios identificables deben cifrarse en la aplicacion; se
--     almacenan ciphertext y HMAC de busqueda, nunca secretos en texto plano.
--   * XML/UBL/PDF se guardan en object storage; aqui solo se guardan referencias,
--     hashes, tipo MIME y metadatos. No guardar binarios grandes en la BD.
--   * Los documentos emitidos y sus lineas son inmutables. Las correcciones se
--     realizan con notas credito/debito, anulaciones permitidas por ley o nuevos
--     documentos, nunca editando el contenido fiscal emitido.
--
-- COLOMBIA Y OTRAS JURISDICCIONES
--   * El modelo es multi-jurisdiccion y no fija IVA, retenciones, resoluciones,
--     numeracion ni reglas tributarias por defecto.
--   * Para Colombia se pueden configurar autoridad DIAN, resoluciones, prefijos,
--     rangos, CUFE/CUDE/QR y perfil UBL mediante los campos de autoridad y
--     metadata nacional. Las reglas vigentes deben validarse por jurisdiccion.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * platform.invoices pertenece a la facturacion SaaS de la plataforma y NO
--     se reutiliza ni modifica aqui. El schema de este modulo es billing.
--   * Ejecutar una sola vez en una base nueva, o como migracion versionada.
--   * No ejecutar encima de un schema billing ya existente.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS billing;

COMMENT ON SCHEMA billing IS
'Facturacion comercial/fiscal de los restaurantes a sus clientes. No administra suscripciones SaaS de la plataforma, ventas origen, cobros ni contabilidad.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION billing.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Billing';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una correccion compensatoria',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION billing.prevent_issued_document_content_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_mutable_columns text[] := ARRAY[
        'status', 'submitted_at', 'accepted_at', 'rejected_at', 'cancelled_at',
        'voided_at', 'last_authority_response_at', 'authority_document_id',
        'authority_validation_code', 'authority_validation_url',
        'authority_qr_payload', 'cancellation_reason', 'updated_at'
    ];
BEGIN
    IF OLD.status IN ('cancelled', 'voided') THEN
        IF (to_jsonb(NEW) - ARRAY['updated_at']) IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['updated_at']) THEN
            RAISE EXCEPTION 'Un documento cancelado o anulado es inmutable';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status <> 'draft' THEN
        IF NEW.cancellation_reason IS DISTINCT FROM OLD.cancellation_reason
           AND NEW.status NOT IN ('cancelled', 'voided') THEN
            RAISE EXCEPTION 'El motivo solo puede registrarse al cancelar o anular el documento';
        END IF;
        IF (to_jsonb(NEW) - v_mutable_columns) IS DISTINCT FROM
           (to_jsonb(OLD) - v_mutable_columns) THEN
            RAISE EXCEPTION 'El contenido de un documento fiscal no puede modificarse despues de emitido; utilice una nota o documento correctivo';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.validate_document_initial_state()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status <> 'draft' OR NEW.document_number IS NOT NULL OR NEW.issue_at IS NOT NULL THEN
        RAISE EXCEPTION 'Los documentos deben crearse como borradores sin numero ni fecha de emision';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.validate_document_state_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_allowed boolean := false;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;

    v_allowed := CASE OLD.status
        WHEN 'draft' THEN NEW.status IN ('issued', 'cancelled')
        WHEN 'issued' THEN NEW.status IN ('queued', 'submitted', 'rejected', 'contingency', 'cancelled', 'voided')
        WHEN 'queued' THEN NEW.status IN ('submitted', 'accepted', 'rejected', 'contingency', 'cancelled', 'voided')
        WHEN 'submitted' THEN NEW.status IN ('accepted', 'rejected', 'contingency', 'cancelled', 'voided')
        WHEN 'rejected' THEN NEW.status IN ('queued', 'submitted', 'cancelled', 'voided')
        WHEN 'contingency' THEN NEW.status IN ('queued', 'submitted', 'accepted', 'rejected', 'cancelled', 'voided')
        WHEN 'accepted' THEN NEW.status IN ('cancelled', 'voided')
        ELSE false
    END;

    IF NOT v_allowed THEN
        RAISE EXCEPTION 'Transicion de estado documental no permitida: % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.prevent_document_child_mutation_after_issue()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_document_id uuid;
    v_document_status varchar(24);
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
        v_document_id := OLD.document_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
        v_document_id := NEW.document_id;
        IF TG_OP = 'UPDATE' AND NEW.document_id IS DISTINCT FROM OLD.document_id THEN
            RAISE EXCEPTION 'No se puede mover una linea/detalle a otro documento';
        END IF;
    END IF;

    SELECT status
      INTO v_document_status
      FROM billing.documents
     WHERE tenant_id = v_tenant_id
       AND id = v_document_id
     FOR UPDATE;

    IF v_document_status IS NULL THEN
        RAISE EXCEPTION 'Documento % no encontrado para tenant %', v_document_id, v_tenant_id;
    END IF;

    IF v_document_status <> 'draft' THEN
        RAISE EXCEPTION 'No se pueden insertar, modificar o eliminar lineas/detalles de un documento que ya no esta en borrador';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION billing.record_document_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO billing.document_status_history (
            tenant_id, document_id, previous_status, new_status,
            changed_by_user_id, change_source, reason
        ) VALUES (
            NEW.tenant_id, NEW.id, NULL, NEW.status,
            NEW.created_by_user_id, 'application', 'Creacion del documento'
        );
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO billing.document_status_history (
            tenant_id, document_id, previous_status, new_status,
            changed_by_user_id, change_source, reason
        ) VALUES (
            NEW.tenant_id, NEW.id, OLD.status, NEW.status,
            NULL, 'application', NULL
        );

        -- La emision inicial publica su evento especifico desde issue_document().
        IF NOT (OLD.status = 'draft' AND NEW.status = 'issued') THEN
            INSERT INTO billing.event_outbox (
                tenant_id, aggregate_type, aggregate_id, event_type, event_version, payload
            ) VALUES (
                NEW.tenant_id, 'billing_document', NEW.id,
                'billing.document_status_changed.v1', 1,
                jsonb_build_object(
                    'document_id', NEW.id,
                    'previous_status', OLD.status,
                    'new_status', NEW.status,
                    'document_number', NEW.document_number,
                    'company_id', NEW.company_id,
                    'branch_id', NEW.branch_id
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion general, jurisdicciones y perfiles fiscales del emisor
-- ---------------------------------------------------------------------------

CREATE TABLE billing.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_country_code            char(2),
    default_currency_code           char(3),
    default_document_locale         varchar(12) NOT NULL DEFAULT 'es',
    default_timezone                varchar(80) NOT NULL DEFAULT 'UTC',
    electronic_invoicing_enabled    boolean NOT NULL DEFAULT false,
    require_recipient_email         boolean NOT NULL DEFAULT false,
    document_retention_years        smallint NOT NULL DEFAULT 10,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_settings_country_format CHECK (default_country_code IS NULL OR default_country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT billing_settings_currency_format CHECK (default_currency_code IS NULL OR default_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT billing_settings_retention CHECK (document_retention_years BETWEEN 1 AND 100),
    CONSTRAINT billing_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TABLE billing.fiscal_jurisdictions (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    jurisdiction_code               varchar(60) NOT NULL,
    country_code                    char(2) NOT NULL,
    subdivision_code                varchar(40),
    authority_code                  varchar(60) NOT NULL,
    authority_name                  varchar(180) NOT NULL,
    environment                     varchar(16) NOT NULL DEFAULT 'test'
                                    CHECK (environment IN ('test', 'production')),
    electronic_submission_required  boolean NOT NULL DEFAULT false,
    document_profile                varchar(80),
    national_rules                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_jurisdictions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT fiscal_jurisdictions_code_unique UNIQUE (tenant_id, jurisdiction_code, environment),
    CONSTRAINT fiscal_jurisdictions_country_format CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT fiscal_jurisdictions_code_nonblank CHECK (btrim(jurisdiction_code) <> ''),
    CONSTRAINT fiscal_jurisdictions_authority_nonblank CHECK (btrim(authority_code) <> ''),
    CONSTRAINT fiscal_jurisdictions_rules_object CHECK (jsonb_typeof(national_rules) = 'object')
);

CREATE TABLE billing.issuer_profiles (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    fiscal_jurisdiction_id          uuid NOT NULL,
    profile_code                    varchar(60) NOT NULL,
    tax_identifier_type             varchar(40),
    tax_identifier_ciphertext       bytea,
    tax_identifier_lookup_hmac      varchar(128),
    tax_regime_code                 varchar(80),
    tax_responsibilities             jsonb NOT NULL DEFAULT '[]'::jsonb,
    economic_activity_code          varchar(80),
    fiscal_email_ciphertext         bytea,
    fiscal_phone_ciphertext         bytea,
    fiscal_address_snapshot         jsonb NOT NULL DEFAULT '{}'::jsonb,
    electronic_invoicing_provider   varchar(80),
    provider_credential_secret_ref  varchar(240),
    provider_settings               jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_default                      boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT issuer_profiles_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT issuer_profiles_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT issuer_profiles_scope_unique UNIQUE (tenant_id, company_id, fiscal_jurisdiction_id, id),
    CONSTRAINT issuer_profiles_code_unique UNIQUE (tenant_id, company_id, profile_code),
    CONSTRAINT issuer_profiles_jurisdiction_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id)
        REFERENCES billing.fiscal_jurisdictions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT issuer_profiles_code_nonblank CHECK (btrim(profile_code) <> ''),
    CONSTRAINT issuer_profiles_tax_id_cipher_pair CHECK (
        (tax_identifier_ciphertext IS NULL) = (tax_identifier_lookup_hmac IS NULL)
    ),
    CONSTRAINT issuer_profiles_responsibilities_array CHECK (jsonb_typeof(tax_responsibilities) = 'array'),
    CONSTRAINT issuer_profiles_address_object CHECK (jsonb_typeof(fiscal_address_snapshot) = 'object'),
    CONSTRAINT issuer_profiles_provider_object CHECK (jsonb_typeof(provider_settings) = 'object')
);
CREATE UNIQUE INDEX uq_billing_default_issuer_profile
    ON billing.issuer_profiles (tenant_id, company_id, fiscal_jurisdiction_id)
    WHERE is_default AND is_active;

-- ---------------------------------------------------------------------------
-- 2. Tipos documentales, autorizaciones fiscales y series de numeracion
-- ---------------------------------------------------------------------------

CREATE TABLE billing.document_types (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    fiscal_jurisdiction_id          uuid NOT NULL,
    document_code                   varchar(60) NOT NULL,
    document_name                   varchar(160) NOT NULL,
    document_class                  varchar(30) NOT NULL
                                    CHECK (document_class IN ('invoice', 'credit_note', 'debit_note', 'pos_receipt', 'support_document', 'export_invoice', 'self_billing', 'other')),
    requires_authorization          boolean NOT NULL DEFAULT false,
    requires_electronic_submission  boolean NOT NULL DEFAULT false,
    requires_recipient_tax_id       boolean NOT NULL DEFAULT false,
    is_fiscal_document              boolean NOT NULL DEFAULT true,
    allowed_source_modules          text[] NOT NULL DEFAULT ARRAY['sales']::text[],
    national_document_code          varchar(80),
    schema_profile                  varchar(80),
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_types_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_types_scope_unique UNIQUE (tenant_id, fiscal_jurisdiction_id, id),
    CONSTRAINT document_types_code_unique UNIQUE (tenant_id, fiscal_jurisdiction_id, document_code),
    CONSTRAINT document_types_jurisdiction_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id)
        REFERENCES billing.fiscal_jurisdictions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_types_code_nonblank CHECK (btrim(document_code) <> ''),
    CONSTRAINT document_types_name_nonblank CHECK (btrim(document_name) <> ''),
    CONSTRAINT document_types_sources_nonempty CHECK (cardinality(allowed_source_modules) > 0)
);

CREATE TABLE billing.fiscal_authorizations (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    fiscal_jurisdiction_id          uuid NOT NULL,
    document_type_id                uuid NOT NULL,
    authorization_code              varchar(160) NOT NULL,
    authorization_date              date,
    prefix                          varchar(30) NOT NULL DEFAULT '',
    range_start                     bigint NOT NULL,
    range_end                       bigint NOT NULL,
    valid_from                      date NOT NULL,
    valid_until                     date NOT NULL,
    technical_key_secret_ref        varchar(240),
    authority_metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_authorizations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT fiscal_authorizations_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT fiscal_authorizations_scope_unique UNIQUE (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, id),
    CONSTRAINT fiscal_authorizations_code_unique UNIQUE (tenant_id, company_id, fiscal_jurisdiction_id, authorization_code),
    CONSTRAINT fiscal_authorizations_jurisdiction_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id)
        REFERENCES billing.fiscal_jurisdictions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fiscal_authorizations_document_type_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id, document_type_id)
        REFERENCES billing.document_types (tenant_id, fiscal_jurisdiction_id, id) ON DELETE RESTRICT,
    CONSTRAINT fiscal_authorizations_range_check CHECK (range_start > 0 AND range_end >= range_start),
    CONSTRAINT fiscal_authorizations_dates_check CHECK (valid_until >= valid_from),
    CONSTRAINT fiscal_authorizations_code_nonblank CHECK (btrim(authorization_code) <> ''),
    CONSTRAINT fiscal_authorizations_metadata_object CHECK (jsonb_typeof(authority_metadata) = 'object')
);

CREATE TABLE billing.document_series (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    branch_id                       uuid,
    issuer_profile_id               uuid NOT NULL,
    fiscal_jurisdiction_id          uuid NOT NULL,
    document_type_id                uuid NOT NULL,
    fiscal_authorization_id         uuid,
    series_code                     varchar(60) NOT NULL,
    prefix                          varchar(30) NOT NULL DEFAULT '',
    suffix                          varchar(30) NOT NULL DEFAULT '',
    first_number                    bigint NOT NULL DEFAULT 1,
    last_number                     bigint NOT NULL,
    next_number                     bigint NOT NULL DEFAULT 1,
    padding_length                  smallint NOT NULL DEFAULT 0,
    valid_from                      date NOT NULL,
    valid_until                     date,
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_series_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_series_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT document_series_scope_unique UNIQUE (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, id),
    CONSTRAINT document_series_issuer_fk FOREIGN KEY (tenant_id, company_id, fiscal_jurisdiction_id, issuer_profile_id)
        REFERENCES billing.issuer_profiles (tenant_id, company_id, fiscal_jurisdiction_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_series_jurisdiction_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id)
        REFERENCES billing.fiscal_jurisdictions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_series_document_type_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id, document_type_id)
        REFERENCES billing.document_types (tenant_id, fiscal_jurisdiction_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_series_authorization_fk FOREIGN KEY (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, fiscal_authorization_id)
        REFERENCES billing.fiscal_authorizations (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_series_range_check CHECK (first_number > 0 AND last_number >= first_number AND last_number < 9223372036854775807),
    CONSTRAINT document_series_next_check CHECK (
        next_number >= first_number AND
        (next_number <= last_number OR next_number::numeric - 1 = last_number)
    ),
    CONSTRAINT document_series_padding_check CHECK (padding_length BETWEEN 0 AND 24),
    CONSTRAINT document_series_dates_check CHECK (valid_until IS NULL OR valid_until >= valid_from),
    CONSTRAINT document_series_code_nonblank CHECK (btrim(series_code) <> '')
);
CREATE UNIQUE INDEX uq_billing_document_series_scope
    ON billing.document_series (tenant_id, company_id, branch_id, document_type_id, series_code) NULLS NOT DISTINCT;
CREATE INDEX ix_billing_document_series_active
    ON billing.document_series (tenant_id, company_id, branch_id, document_type_id)
    WHERE is_active;

-- ---------------------------------------------------------------------------
-- 3. Documento fiscal/comercial unificado: factura, nota credito/debito, POS
-- ---------------------------------------------------------------------------

CREATE TABLE billing.documents (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    branch_id                       uuid,
    issuer_profile_id               uuid NOT NULL,
    fiscal_jurisdiction_id          uuid NOT NULL,
    document_type_id                uuid NOT NULL,
    series_id                       uuid,
    document_number                 varchar(100),
    source_module                   varchar(60) NOT NULL DEFAULT 'manual',
    source_document_id              uuid,
    source_event_id                 varchar(180),
    customer_id                     uuid,
    customer_name_snapshot           varchar(240) NOT NULL,
    customer_trade_name_snapshot     varchar(240),
    customer_tax_id_type             varchar(40),
    customer_tax_id_ciphertext       bytea,
    customer_tax_id_lookup_hmac      varchar(128),
    customer_tax_regime_snapshot     varchar(100),
    customer_email_ciphertext        bytea,
    customer_phone_ciphertext        bytea,
    customer_address_snapshot_ciphertext bytea,
    issuer_name_snapshot             varchar(240) NOT NULL,
    issuer_tax_id_type               varchar(40),
    issuer_tax_id_ciphertext         bytea,
    issuer_tax_id_lookup_hmac        varchar(128),
    issuer_address_snapshot          jsonb NOT NULL DEFAULT '{}'::jsonb,
    issue_at                        timestamptz,
    due_at                          timestamptz,
    currency_code                   char(3) NOT NULL,
    exchange_rate                   numeric(24,10) NOT NULL DEFAULT 1,
    subtotal_amount                 numeric(19,4) NOT NULL DEFAULT 0,
    discount_amount                numeric(19,4) NOT NULL DEFAULT 0,
    charge_amount                  numeric(19,4) NOT NULL DEFAULT 0,
    tax_amount                     numeric(19,4) NOT NULL DEFAULT 0,
    withholding_amount             numeric(19,4) NOT NULL DEFAULT 0,
    rounding_amount                numeric(19,4) NOT NULL DEFAULT 0,
    total_amount                   numeric(19,4) NOT NULL DEFAULT 0,
    payment_terms_snapshot          varchar(500),
    payment_method_summary         varchar(160),
    operation_type                 varchar(40) NOT NULL DEFAULT 'standard',
    status                          varchar(24) NOT NULL DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'issued', 'queued', 'submitted', 'accepted', 'rejected', 'contingency', 'cancelled', 'voided')),
    authority_document_id          varchar(240),
    authority_validation_code      varchar(300),
    authority_validation_url       text,
    authority_qr_payload            text,
    last_authority_response_at     timestamptz,
    submitted_at                   timestamptz,
    accepted_at                    timestamptz,
    rejected_at                    timestamptz,
    cancelled_at                   timestamptz,
    voided_at                      timestamptz,
    cancellation_reason            text,
    metadata                       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id             uuid,
    created_at                     timestamptz NOT NULL DEFAULT now(),
    updated_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT documents_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT documents_tenant_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT documents_scope_unique UNIQUE (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, id),
    CONSTRAINT documents_source_unique UNIQUE (tenant_id, source_module, source_document_id, document_type_id),
    CONSTRAINT documents_issuer_fk FOREIGN KEY (tenant_id, company_id, fiscal_jurisdiction_id, issuer_profile_id)
        REFERENCES billing.issuer_profiles (tenant_id, company_id, fiscal_jurisdiction_id, id) ON DELETE RESTRICT,
    CONSTRAINT documents_jurisdiction_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id)
        REFERENCES billing.fiscal_jurisdictions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT documents_document_type_fk FOREIGN KEY (tenant_id, fiscal_jurisdiction_id, document_type_id)
        REFERENCES billing.document_types (tenant_id, fiscal_jurisdiction_id, id) ON DELETE RESTRICT,
    CONSTRAINT documents_series_fk FOREIGN KEY (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, series_id)
        REFERENCES billing.document_series (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, id) ON DELETE RESTRICT,
    CONSTRAINT documents_number_nonblank CHECK (document_number IS NULL OR btrim(document_number) <> ''),
    CONSTRAINT documents_source_module_nonblank CHECK (btrim(source_module) <> ''),
    CONSTRAINT documents_customer_name_nonblank CHECK (btrim(customer_name_snapshot) <> ''),
    CONSTRAINT documents_issuer_name_nonblank CHECK (btrim(issuer_name_snapshot) <> ''),
    CONSTRAINT documents_currency_format CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT documents_exchange_rate_positive CHECK (exchange_rate > 0),
    CONSTRAINT documents_amounts_nonnegative CHECK (
        subtotal_amount >= 0 AND discount_amount >= 0 AND discount_amount <= subtotal_amount AND
        charge_amount >= 0 AND tax_amount >= 0 AND withholding_amount >= 0 AND total_amount >= 0
    ),
    CONSTRAINT documents_total_consistent CHECK (
        total_amount = subtotal_amount - discount_amount + charge_amount + tax_amount - withholding_amount + rounding_amount
    ),
    CONSTRAINT documents_dates_valid CHECK (due_at IS NULL OR issue_at IS NULL OR due_at >= issue_at),
    CONSTRAINT documents_issuer_address_object CHECK (jsonb_typeof(issuer_address_snapshot) = 'object'),
    CONSTRAINT documents_customer_tax_id_cipher_pair CHECK ((customer_tax_id_ciphertext IS NULL) = (customer_tax_id_lookup_hmac IS NULL)),
    CONSTRAINT documents_issuer_tax_id_cipher_pair CHECK ((issuer_tax_id_ciphertext IS NULL) = (issuer_tax_id_lookup_hmac IS NULL)),
    CONSTRAINT documents_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT documents_cancelled_shape CHECK (
        (status = 'cancelled') = (cancelled_at IS NOT NULL) AND
        (status IN ('cancelled', 'voided')) = (NULLIF(btrim(cancellation_reason), '') IS NOT NULL)
    ),
    CONSTRAINT documents_voided_shape CHECK ((status = 'voided') = (voided_at IS NOT NULL)),
    CONSTRAINT documents_accepted_shape CHECK (status <> 'accepted' OR accepted_at IS NOT NULL),
    CONSTRAINT documents_rejected_shape CHECK (status <> 'rejected' OR rejected_at IS NOT NULL),
    CONSTRAINT documents_submitted_shape CHECK (status NOT IN ('submitted', 'accepted', 'rejected') OR submitted_at IS NOT NULL),
    CONSTRAINT documents_issued_shape CHECK (
        status NOT IN ('issued', 'queued', 'submitted', 'accepted', 'rejected', 'contingency', 'voided')
        OR (document_number IS NOT NULL AND issue_at IS NOT NULL)
    )
);
CREATE UNIQUE INDEX uq_billing_documents_number
    ON billing.documents (tenant_id, company_id, fiscal_jurisdiction_id, document_type_id, document_number)
    WHERE document_number IS NOT NULL;
CREATE UNIQUE INDEX uq_billing_documents_source_event
    ON billing.documents (tenant_id, source_module, source_event_id, document_type_id)
    WHERE source_event_id IS NOT NULL;
CREATE INDEX ix_billing_documents_company_date
    ON billing.documents (tenant_id, company_id, issue_at DESC)
    WHERE issue_at IS NOT NULL;
CREATE INDEX ix_billing_documents_branch_status
    ON billing.documents (tenant_id, branch_id, status, created_at DESC);
CREATE INDEX ix_billing_documents_customer
    ON billing.documents (tenant_id, customer_id, issue_at DESC)
    WHERE customer_id IS NOT NULL;
CREATE INDEX ix_billing_documents_authority_id
    ON billing.documents (tenant_id, authority_document_id)
    WHERE authority_document_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Lineas, impuestos, descuentos/cargos, totales y referencias documentales
-- ---------------------------------------------------------------------------

CREATE TABLE billing.document_lines (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    line_number                     integer NOT NULL,
    source_line_id                  uuid,
    product_id                      uuid,
    variant_id                      uuid,
    sku_snapshot                    varchar(100),
    item_code_snapshot              varchar(100),
    description                     varchar(500) NOT NULL,
    unit_code                       varchar(30),
    quantity                        numeric(19,6) NOT NULL,
    unit_price                      numeric(19,6) NOT NULL,
    gross_amount                    numeric(19,4) NOT NULL,
    discount_amount                numeric(19,4) NOT NULL DEFAULT 0,
    charge_amount                  numeric(19,4) NOT NULL DEFAULT 0,
    taxable_base_amount             numeric(19,4) NOT NULL DEFAULT 0,
    tax_amount                     numeric(19,4) NOT NULL DEFAULT 0,
    line_total_amount               numeric(19,4) NOT NULL,
    metadata                       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_lines_doc_line_unique UNIQUE (tenant_id, document_id, id),
    CONSTRAINT document_lines_number_unique UNIQUE (tenant_id, document_id, line_number),
    CONSTRAINT document_lines_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_lines_number_positive CHECK (line_number > 0),
    CONSTRAINT document_lines_description_nonblank CHECK (btrim(description) <> ''),
    CONSTRAINT document_lines_quantity_positive CHECK (quantity > 0),
    CONSTRAINT document_lines_unit_price_nonnegative CHECK (unit_price >= 0),
    CONSTRAINT document_lines_gross_consistent CHECK (gross_amount = round(quantity * unit_price, 4)),
    CONSTRAINT document_lines_amounts_nonnegative CHECK (
        gross_amount >= 0 AND discount_amount >= 0 AND charge_amount >= 0 AND
        discount_amount <= gross_amount AND
        taxable_base_amount >= 0 AND tax_amount >= 0 AND line_total_amount >= 0
    ),
    CONSTRAINT document_lines_total_consistent CHECK (
        line_total_amount = gross_amount - discount_amount + charge_amount + tax_amount
    ),
    CONSTRAINT document_lines_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX ix_billing_document_lines_document
    ON billing.document_lines (tenant_id, document_id, line_number);
CREATE INDEX ix_billing_document_lines_product
    ON billing.document_lines (tenant_id, product_id)
    WHERE product_id IS NOT NULL;

CREATE TABLE billing.document_line_taxes (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    document_line_id                uuid NOT NULL,
    tax_code_snapshot               varchar(80) NOT NULL,
    tax_name_snapshot               varchar(160) NOT NULL,
    tax_category_snapshot            varchar(80),
    jurisdiction_code               varchar(80),
    rate_percent                    numeric(12,8) NOT NULL DEFAULT 0,
    taxable_base_amount             numeric(19,4) NOT NULL,
    tax_amount                      numeric(19,4) NOT NULL,
    exemption_reason                varchar(300),
    finance_tax_rate_id             uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_line_taxes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_line_taxes_line_fk FOREIGN KEY (tenant_id, document_id, document_line_id)
        REFERENCES billing.document_lines (tenant_id, document_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_line_taxes_rate_nonnegative CHECK (rate_percent BETWEEN 0 AND 100),
    CONSTRAINT document_line_taxes_amounts_nonnegative CHECK (taxable_base_amount >= 0 AND tax_amount >= 0),
    CONSTRAINT document_line_taxes_code_nonblank CHECK (btrim(tax_code_snapshot) <> ''),
    CONSTRAINT document_line_taxes_name_nonblank CHECK (btrim(tax_name_snapshot) <> '')
);
CREATE INDEX ix_billing_document_line_taxes_document
    ON billing.document_line_taxes (tenant_id, document_id, document_line_id);

CREATE TABLE billing.document_adjustments (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    document_line_id                uuid,
    adjustment_type                 varchar(12) NOT NULL CHECK (adjustment_type IN ('discount', 'charge')),
    adjustment_code                 varchar(80),
    description                     varchar(300) NOT NULL,
    calculation_method              varchar(16) NOT NULL DEFAULT 'fixed'
                                    CHECK (calculation_method IN ('fixed', 'percentage')),
    percentage_rate                 numeric(12,8),
    base_amount                     numeric(19,4) NOT NULL DEFAULT 0,
    adjustment_amount               numeric(19,4) NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_adjustments_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_adjustments_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_adjustments_line_fk FOREIGN KEY (tenant_id, document_id, document_line_id)
        REFERENCES billing.document_lines (tenant_id, document_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_adjustments_amount_positive CHECK (base_amount >= 0 AND adjustment_amount >= 0),
    CONSTRAINT document_adjustments_percentage_check CHECK (percentage_rate IS NULL OR (percentage_rate >= 0 AND percentage_rate <= 100)),
    CONSTRAINT document_adjustments_method_shape CHECK (
        (calculation_method = 'fixed' AND percentage_rate IS NULL) OR
        (calculation_method = 'percentage' AND percentage_rate IS NOT NULL)
    ),
    CONSTRAINT document_adjustments_description_nonblank CHECK (btrim(description) <> '')
);

CREATE TABLE billing.document_tax_totals (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    tax_code_snapshot               varchar(80) NOT NULL,
    tax_name_snapshot               varchar(160) NOT NULL,
    jurisdiction_code               varchar(80),
    rate_percent                    numeric(12,8) NOT NULL DEFAULT 0,
    taxable_base_amount             numeric(19,4) NOT NULL,
    tax_amount                      numeric(19,4) NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_tax_totals_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_tax_totals_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_tax_totals_scope_unique UNIQUE (tenant_id, document_id, tax_code_snapshot, rate_percent, jurisdiction_code),
    CONSTRAINT document_tax_totals_nonnegative CHECK (rate_percent BETWEEN 0 AND 100 AND taxable_base_amount >= 0 AND tax_amount >= 0)
);

CREATE TABLE billing.withholding_lines (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    withholding_code                varchar(80) NOT NULL,
    withholding_name                varchar(160) NOT NULL,
    jurisdiction_code               varchar(80),
    rate_percent                    numeric(12,8) NOT NULL DEFAULT 0,
    taxable_base_amount             numeric(19,4) NOT NULL,
    withholding_amount              numeric(19,4) NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT withholding_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT withholding_lines_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT withholding_lines_rate_nonnegative CHECK (rate_percent BETWEEN 0 AND 100),
    CONSTRAINT withholding_lines_amounts_nonnegative CHECK (taxable_base_amount >= 0 AND withholding_amount >= 0)
);

CREATE TABLE billing.document_references (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    document_id                     uuid NOT NULL,
    referenced_document_id          uuid,
    reference_type                  varchar(40) NOT NULL,
    external_document_number        varchar(120),
    external_issuer_tax_id_hash      varchar(128),
    reference_reason                varchar(500),
    reference_date                  date,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_references_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_references_document_fk FOREIGN KEY (tenant_id, company_id, document_id)
        REFERENCES billing.documents (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_references_related_fk FOREIGN KEY (tenant_id, company_id, referenced_document_id)
        REFERENCES billing.documents (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_references_not_self CHECK (referenced_document_id IS NULL OR referenced_document_id <> document_id),
    CONSTRAINT document_references_type_nonblank CHECK (btrim(reference_type) <> '')
);

CREATE TABLE billing.credit_debit_note_details (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    note_kind                       varchar(12) NOT NULL CHECK (note_kind IN ('credit', 'debit')),
    reason_code                     varchar(80) NOT NULL,
    reason_description              varchar(500) NOT NULL,
    correction_scope                varchar(24) NOT NULL DEFAULT 'full'
                                    CHECK (correction_scope IN ('full', 'partial', 'amount_only', 'text_only')),
    affected_document_number        varchar(120),
    national_reason_code            varchar(100),
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT credit_debit_note_details_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT credit_debit_note_details_document_unique UNIQUE (tenant_id, document_id),
    CONSTRAINT credit_debit_note_details_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT credit_debit_note_reason_nonblank CHECK (btrim(reason_code) <> '' AND btrim(reason_description) <> ''),
    CONSTRAINT credit_debit_note_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

-- ---------------------------------------------------------------------------
-- 5. Historial documental, transmision, respuestas y artefactos electronicos
-- ---------------------------------------------------------------------------

CREATE TABLE billing.document_status_history (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    previous_status                 varchar(24),
    new_status                      varchar(24) NOT NULL,
    changed_by_user_id              uuid,
    change_source                   varchar(30) NOT NULL DEFAULT 'application',
    reason                          text,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_status_history_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_billing_document_status_history
    ON billing.document_status_history (tenant_id, document_id, occurred_at DESC);

CREATE TABLE billing.fiscal_submissions (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    provider_code                   varchar(80) NOT NULL,
    environment                     varchar(16) NOT NULL CHECK (environment IN ('test', 'production')),
    transmission_protocol           varchar(30) NOT NULL DEFAULT 'api',
    submission_reference            varchar(240),
    submission_status               varchar(24) NOT NULL DEFAULT 'pending'
                                    CHECK (submission_status IN ('pending', 'queued', 'submitted', 'accepted', 'rejected', 'failed', 'cancelled')),
    requested_at                    timestamptz,
    submitted_at                    timestamptz,
    completed_at                    timestamptz,
    next_retry_at                   timestamptz,
    attempt_count                   integer NOT NULL DEFAULT 0,
    last_error_code                 varchar(120),
    last_error_message              text,
    provider_metadata               jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_submissions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT fiscal_submissions_document_id_unique UNIQUE (tenant_id, document_id, id),
    CONSTRAINT fiscal_submissions_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fiscal_submissions_provider_nonblank CHECK (btrim(provider_code) <> ''),
    CONSTRAINT fiscal_submissions_attempt_nonnegative CHECK (attempt_count >= 0),
    CONSTRAINT fiscal_submissions_metadata_object CHECK (jsonb_typeof(provider_metadata) = 'object')
);
CREATE INDEX ix_billing_fiscal_submissions_status
    ON billing.fiscal_submissions (tenant_id, submission_status, next_retry_at)
    WHERE submission_status IN ('pending', 'queued', 'failed');
CREATE INDEX ix_billing_fiscal_submissions_document
    ON billing.fiscal_submissions (tenant_id, document_id, created_at DESC);

CREATE TABLE billing.submission_attempts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    fiscal_submission_id            uuid NOT NULL,
    attempt_number                  integer NOT NULL,
    request_payload_hash            varchar(128),
    provider_request_id              varchar(240),
    response_http_status            smallint,
    attempt_status                  varchar(20) NOT NULL
                                    CHECK (attempt_status IN ('started', 'succeeded', 'rejected', 'failed', 'timed_out')),
    error_code                      varchar(120),
    error_message                   text,
    started_at                      timestamptz NOT NULL DEFAULT now(),
    completed_at                    timestamptz,
    elapsed_ms                      integer,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT submission_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT submission_attempts_submission_fk FOREIGN KEY (tenant_id, fiscal_submission_id)
        REFERENCES billing.fiscal_submissions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT submission_attempts_number_unique UNIQUE (tenant_id, fiscal_submission_id, attempt_number),
    CONSTRAINT submission_attempts_number_positive CHECK (attempt_number > 0),
    CONSTRAINT submission_attempts_http_status CHECK (response_http_status IS NULL OR response_http_status BETWEEN 100 AND 599),
    CONSTRAINT submission_attempts_elapsed_nonnegative CHECK (elapsed_ms IS NULL OR elapsed_ms >= 0)
);
CREATE INDEX ix_billing_submission_attempts_submission
    ON billing.submission_attempts (tenant_id, fiscal_submission_id, attempt_number DESC);

CREATE TABLE billing.authority_responses (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    submission_attempt_id           uuid NOT NULL,
    response_kind                   varchar(24) NOT NULL CHECK (response_kind IN ('acknowledgement', 'acceptance', 'rejection', 'warning', 'validation')),
    authority_code                  varchar(100),
    authority_message               text,
    authority_document_id           varchar(240),
    validation_code                 varchar(300),
    validation_url                  text,
    qr_payload                      text,
    received_at                     timestamptz NOT NULL DEFAULT now(),
    response_payload_hash           varchar(128),
    safe_response_metadata           jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT authority_responses_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT authority_responses_attempt_fk FOREIGN KEY (tenant_id, submission_attempt_id)
        REFERENCES billing.submission_attempts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT authority_responses_metadata_object CHECK (jsonb_typeof(safe_response_metadata) = 'object')
);
CREATE INDEX ix_billing_authority_responses_attempt
    ON billing.authority_responses (tenant_id, submission_attempt_id, received_at DESC);

CREATE TABLE billing.electronic_artifacts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    fiscal_submission_id            uuid,
    artifact_type                   varchar(24) NOT NULL
                                    CHECK (artifact_type IN ('xml', 'ubl', 'pdf', 'html', 'json', 'qr', 'acknowledgement', 'other')),
    storage_provider                varchar(60) NOT NULL,
    storage_object_key              varchar(500) NOT NULL,
    mime_type                       varchar(160) NOT NULL,
    file_name                       varchar(240),
    file_size_bytes                 bigint NOT NULL,
    sha256_hash                     varchar(64) NOT NULL,
    is_authoritative_copy           boolean NOT NULL DEFAULT false,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT electronic_artifacts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT electronic_artifacts_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT electronic_artifacts_submission_fk FOREIGN KEY (tenant_id, document_id, fiscal_submission_id)
        REFERENCES billing.fiscal_submissions (tenant_id, document_id, id) ON DELETE RESTRICT,
    CONSTRAINT electronic_artifacts_size_positive CHECK (file_size_bytes >= 0),
    CONSTRAINT electronic_artifacts_hash_format CHECK (sha256_hash ~ '^[A-Fa-f0-9]{64}$'),
    CONSTRAINT electronic_artifacts_storage_nonblank CHECK (btrim(storage_object_key) <> '')
);
CREATE INDEX ix_billing_electronic_artifacts_document
    ON billing.electronic_artifacts (tenant_id, document_id, artifact_type, created_at DESC);

-- ---------------------------------------------------------------------------
-- 6. Entrega a clientes, adjuntos y operacion en contingencia
-- ---------------------------------------------------------------------------

CREATE TABLE billing.document_delivery_records (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    delivery_channel                varchar(20) NOT NULL CHECK (delivery_channel IN ('email', 'sms', 'whatsapp', 'portal', 'print', 'other')),
    recipient_address_ciphertext    bytea NOT NULL,
    recipient_address_lookup_hmac   varchar(128),
    delivery_status                 varchar(20) NOT NULL DEFAULT 'queued'
                                    CHECK (delivery_status IN ('queued', 'sent', 'delivered', 'bounced', 'failed', 'opened')),
    provider_code                   varchar(80),
    provider_message_id             varchar(240),
    attempted_at                    timestamptz,
    delivered_at                    timestamptz,
    last_error                      text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_delivery_records_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_delivery_records_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_billing_document_delivery_status
    ON billing.document_delivery_records (tenant_id, document_id, delivery_status, created_at DESC);

CREATE TABLE billing.document_attachments (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    attachment_type                 varchar(40) NOT NULL,
    storage_provider                varchar(60) NOT NULL,
    storage_object_key              varchar(500) NOT NULL,
    file_name                       varchar(240),
    mime_type                       varchar(160) NOT NULL,
    file_size_bytes                 bigint NOT NULL,
    sha256_hash                     varchar(64) NOT NULL,
    uploaded_by_user_id             uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_attachments_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT document_attachments_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT document_attachments_size_nonnegative CHECK (file_size_bytes >= 0),
    CONSTRAINT document_attachments_hash_format CHECK (sha256_hash ~ '^[A-Fa-f0-9]{64}$'),
    CONSTRAINT document_attachments_storage_nonblank CHECK (btrim(storage_object_key) <> '')
);

CREATE TABLE billing.contingency_records (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    document_id                     uuid NOT NULL,
    contingency_code                varchar(80) NOT NULL,
    contingency_reason              text NOT NULL,
    started_at                      timestamptz NOT NULL,
    ended_at                        timestamptz,
    fallback_number                 varchar(120),
    regularized_at                  timestamptz,
    regularization_reference        varchar(240),
    contingency_status              varchar(20) NOT NULL DEFAULT 'active'
                                    CHECK (contingency_status IN ('active', 'pending_regularization', 'regularized', 'cancelled')),
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT contingency_records_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT contingency_records_document_fk FOREIGN KEY (tenant_id, document_id)
        REFERENCES billing.documents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT contingency_records_document_unique UNIQUE (tenant_id, document_id),
    CONSTRAINT contingency_records_dates_check CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT contingency_records_regularized_shape CHECK (contingency_status <> 'regularized' OR regularized_at IS NOT NULL),
    CONSTRAINT contingency_records_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT contingency_records_reason_nonblank CHECK (btrim(contingency_reason) <> '')
);

-- ---------------------------------------------------------------------------
-- 7. Webhooks, Inbox, Outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE billing.provider_webhook_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_code                   varchar(80) NOT NULL,
    provider_event_id               varchar(240) NOT NULL,
    event_type                      varchar(180) NOT NULL,
    signature_verified              boolean NOT NULL DEFAULT false,
    payload_hash                    varchar(128) NOT NULL,
    safe_payload                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    processing_status               varchar(20) NOT NULL DEFAULT 'received'
                                    CHECK (processing_status IN ('received', 'processing', 'processed', 'failed', 'ignored')),
    received_at                     timestamptz NOT NULL DEFAULT now(),
    processed_at                    timestamptz,
    processing_error                text,
    CONSTRAINT provider_webhook_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT provider_webhook_events_provider_unique UNIQUE (tenant_id, provider_code, provider_event_id),
    CONSTRAINT provider_webhook_events_payload_object CHECK (jsonb_typeof(safe_payload) = 'object')
);
CREATE INDEX ix_billing_webhook_events_pending
    ON billing.provider_webhook_events (tenant_id, processing_status, received_at)
    WHERE processing_status IN ('received', 'failed');

CREATE TABLE billing.processed_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_name                   varchar(120) NOT NULL,
    event_id                        varchar(180) NOT NULL,
    event_type                      varchar(180) NOT NULL,
    payload_hash                    varchar(128),
    processed_at                    timestamptz NOT NULL DEFAULT now(),
    result_reference_id             uuid,
    CONSTRAINT processed_events_consumer_nonblank CHECK (btrim(consumer_name) <> ''),
    CONSTRAINT processed_events_event_nonblank CHECK (btrim(event_id) <> ''),
    CONSTRAINT processed_events_unique UNIQUE (tenant_id, consumer_name, event_id)
);

CREATE TABLE billing.event_outbox (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type                  varchar(100) NOT NULL,
    aggregate_id                    uuid NOT NULL,
    event_type                      varchar(180) NOT NULL,
    event_version                   integer NOT NULL DEFAULT 1,
    payload                         jsonb NOT NULL,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    available_at                    timestamptz NOT NULL DEFAULT now(),
    published_at                    timestamptz,
    publish_attempts                integer NOT NULL DEFAULT 0,
    last_error                      text,
    CONSTRAINT billing_event_outbox_version_positive CHECK (event_version > 0),
    CONSTRAINT billing_event_outbox_attempts_nonnegative CHECK (publish_attempts >= 0),
    CONSTRAINT billing_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT billing_event_outbox_unique UNIQUE (tenant_id, id)
);
CREATE INDEX ix_billing_event_outbox_pending
    ON billing.event_outbox (tenant_id, available_at, occurred_at)
    WHERE published_at IS NULL;

CREATE TABLE billing.idempotency_records (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_scope                 varchar(120) NOT NULL,
    idempotency_key                 varchar(180) NOT NULL,
    request_hash                    varchar(128) NOT NULL,
    response_status                 integer,
    response_body                   jsonb,
    resource_id                     uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    expires_at                      timestamptz,
    CONSTRAINT billing_idempotency_scope_nonblank CHECK (btrim(operation_scope) <> ''),
    CONSTRAINT billing_idempotency_key_nonblank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT billing_idempotency_status CHECK (response_status IS NULL OR response_status BETWEEN 100 AND 599),
    CONSTRAINT billing_idempotency_response_object CHECK (response_body IS NULL OR jsonb_typeof(response_body) = 'object'),
    CONSTRAINT billing_idempotency_unique UNIQUE (tenant_id, operation_scope, idempotency_key)
);
CREATE INDEX ix_billing_idempotency_expiry
    ON billing.idempotency_records (tenant_id, expires_at)
    WHERE expires_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Numeracion fiscal atomica e inicializacion del tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.issue_document(
    p_tenant_id uuid,
    p_document_id uuid,
    p_series_id uuid,
    p_issued_at timestamptz DEFAULT now()
)
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    v_document billing.documents%ROWTYPE;
    v_series billing.document_series%ROWTYPE;
    v_type billing.document_types%ROWTYPE;
    v_authorization billing.fiscal_authorizations%ROWTYPE;
    v_number bigint;
    v_document_number varchar(100);
    v_line_count integer;
    v_line_total_amount numeric(24,4);
    v_header_adjustment_total numeric(24,4);
    v_required_authorization boolean;
    v_timezone varchar(80);
    v_issue_date date;
BEGIN
    IF billing.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant no coincide con el contexto autenticado';
    END IF;

    SELECT * INTO v_document
      FROM billing.documents
     WHERE tenant_id = p_tenant_id AND id = p_document_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Documento % no encontrado', p_document_id;
    END IF;
    IF v_document.status <> 'draft' OR v_document.document_number IS NOT NULL THEN
        RAISE EXCEPTION 'Solo se pueden emitir documentos en borrador sin numero asignado';
    END IF;
    IF p_issued_at IS NULL THEN
        RAISE EXCEPTION 'La fecha de emision es obligatoria';
    END IF;

    SELECT COALESCE(default_timezone, 'UTC') INTO v_timezone
      FROM billing.tenant_settings
     WHERE tenant_id = p_tenant_id;
    v_timezone := COALESCE(v_timezone, 'UTC');
    v_issue_date := (p_issued_at AT TIME ZONE v_timezone)::date;

    SELECT * INTO v_series
      FROM billing.document_series
     WHERE tenant_id = p_tenant_id AND id = p_series_id
     FOR UPDATE;

    IF NOT FOUND OR NOT v_series.is_active THEN
        RAISE EXCEPTION 'Serie documental inexistente o inactiva';
    END IF;

    IF v_series.company_id <> v_document.company_id
       OR v_series.issuer_profile_id <> v_document.issuer_profile_id
       OR v_series.fiscal_jurisdiction_id <> v_document.fiscal_jurisdiction_id
       OR v_series.document_type_id <> v_document.document_type_id
       OR (v_series.branch_id IS NOT NULL AND v_series.branch_id IS DISTINCT FROM v_document.branch_id) THEN
        RAISE EXCEPTION 'La serie no corresponde a la empresa, sucursal, emisor, jurisdiccion o tipo documental';
    END IF;

    IF (v_issue_date < v_series.valid_from)
       OR (v_series.valid_until IS NOT NULL AND v_issue_date > v_series.valid_until) THEN
        RAISE EXCEPTION 'La fecha de emision esta fuera de la vigencia de la serie';
    END IF;

    SELECT * INTO v_type
      FROM billing.document_types
     WHERE tenant_id = p_tenant_id AND id = v_document.document_type_id;

    IF NOT FOUND OR NOT v_type.is_active THEN
        RAISE EXCEPTION 'Tipo documental inexistente o inactivo';
    END IF;
    IF v_type.fiscal_jurisdiction_id <> v_document.fiscal_jurisdiction_id THEN
        RAISE EXCEPTION 'El tipo documental no pertenece a la jurisdiccion del documento';
    END IF;
    IF NOT (v_document.source_module = ANY(v_type.allowed_source_modules)) THEN
        RAISE EXCEPTION 'El tipo documental no permite documentos originados en el modulo %', v_document.source_module;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM billing.issuer_profiles ip
         WHERE ip.tenant_id = p_tenant_id
           AND ip.id = v_document.issuer_profile_id
           AND ip.company_id = v_document.company_id
           AND ip.fiscal_jurisdiction_id = v_document.fiscal_jurisdiction_id
           AND ip.is_active
    ) THEN
        RAISE EXCEPTION 'El perfil fiscal del emisor no existe o esta inactivo';
    END IF;
    IF v_type.is_fiscal_document AND NOT EXISTS (
        SELECT 1 FROM billing.issuer_profiles ip
         WHERE ip.tenant_id = p_tenant_id
           AND ip.id = v_document.issuer_profile_id
           AND ip.tax_identifier_ciphertext IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'El perfil fiscal del emisor requiere identificacion tributaria cifrada';
    END IF;
    IF v_type.requires_recipient_tax_id AND v_document.customer_tax_id_ciphertext IS NULL THEN
        RAISE EXCEPTION 'El tipo documental requiere identificacion tributaria del receptor';
    END IF;
    IF EXISTS (
        SELECT 1 FROM billing.tenant_settings ts
         WHERE ts.tenant_id = p_tenant_id
           AND ts.require_recipient_email
    ) AND v_document.customer_email_ciphertext IS NULL THEN
        RAISE EXCEPTION 'La configuracion del tenant exige correo electronico del receptor';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM billing.fiscal_jurisdictions fj
         WHERE fj.tenant_id = p_tenant_id
           AND fj.id = v_document.fiscal_jurisdiction_id
           AND fj.is_active
    ) THEN
        RAISE EXCEPTION 'La jurisdiccion fiscal no existe o esta inactiva';
    END IF;

    v_required_authorization := v_type.requires_authorization;
    IF v_required_authorization THEN
        IF v_series.fiscal_authorization_id IS NULL THEN
            RAISE EXCEPTION 'El tipo documental requiere una autorizacion fiscal asociada a la serie';
        END IF;
        SELECT * INTO v_authorization
          FROM billing.fiscal_authorizations
         WHERE tenant_id = p_tenant_id
           AND id = v_series.fiscal_authorization_id
           AND company_id = v_document.company_id
           AND fiscal_jurisdiction_id = v_document.fiscal_jurisdiction_id
           AND document_type_id = v_document.document_type_id
           AND is_active
         FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Autorizacion fiscal no encontrada o inactiva';
        END IF;
        IF v_authorization.prefix IS DISTINCT FROM v_series.prefix THEN
            RAISE EXCEPTION 'El prefijo de la serie no coincide con el prefijo autorizado por la autoridad fiscal';
        END IF;
        IF v_issue_date NOT BETWEEN v_authorization.valid_from AND v_authorization.valid_until THEN
            RAISE EXCEPTION 'La autorizacion fiscal no esta vigente para la fecha de emision';
        END IF;
    END IF;

    SELECT count(*) INTO v_line_count
      FROM billing.document_lines
     WHERE tenant_id = p_tenant_id AND document_id = p_document_id;
    IF v_line_count = 0 THEN
        RAISE EXCEPTION 'No se puede emitir un documento sin lineas';
    END IF;

    IF v_type.document_class IN ('credit_note', 'debit_note') THEN
        IF NOT EXISTS (
            SELECT 1
              FROM billing.credit_debit_note_details nd
             WHERE nd.tenant_id = p_tenant_id
               AND nd.document_id = p_document_id
               AND nd.note_kind = CASE WHEN v_type.document_class = 'credit_note' THEN 'credit' ELSE 'debit' END
        ) THEN
            RAISE EXCEPTION 'Las notas credito/debito requieren detalle de motivo compatible con el tipo documental';
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM billing.document_references dr
             WHERE dr.tenant_id = p_tenant_id
               AND dr.document_id = p_document_id
               AND (dr.referenced_document_id IS NOT NULL OR dr.external_document_number IS NOT NULL)
        ) THEN
            RAISE EXCEPTION 'Las notas credito/debito requieren referencia al documento relacionado';
        END IF;
    END IF;

    -- Comprueba que el encabezado coincide con las instantaneas de sus lineas.
    IF v_document.subtotal_amount <> (
        SELECT COALESCE(sum(gross_amount), 0)
          FROM billing.document_lines
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'El subtotal del documento no coincide con la suma de sus lineas';
    END IF;

    IF v_document.discount_amount <> (
        SELECT COALESCE(sum(discount_amount), 0) + COALESCE((
            SELECT sum(adjustment_amount)
              FROM billing.document_adjustments
             WHERE tenant_id = p_tenant_id AND document_id = p_document_id
               AND document_line_id IS NULL AND adjustment_type = 'discount'
        ), 0)
          FROM billing.document_lines
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'El descuento total no coincide con los descuentos de lineas y encabezado';
    END IF;

    IF v_document.charge_amount <> (
        SELECT COALESCE(sum(charge_amount), 0) + COALESCE((
            SELECT sum(adjustment_amount)
              FROM billing.document_adjustments
             WHERE tenant_id = p_tenant_id AND document_id = p_document_id
               AND document_line_id IS NULL AND adjustment_type = 'charge'
        ), 0)
          FROM billing.document_lines
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'Los cargos totales no coinciden con los cargos de lineas y encabezado';
    END IF;

    IF v_document.tax_amount <> (
        SELECT COALESCE(sum(tax_amount), 0)
          FROM billing.document_lines
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'El impuesto total no coincide con la suma de impuestos de las lineas';
    END IF;

    IF v_document.withholding_amount <> (
        SELECT COALESCE(sum(withholding_amount), 0)
          FROM billing.withholding_lines
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'Las retenciones totales no coinciden con el detalle de retenciones';
    END IF;

    SELECT COALESCE(sum(line_total_amount), 0)
      INTO v_line_total_amount
      FROM billing.document_lines
     WHERE tenant_id = p_tenant_id AND document_id = p_document_id;

    SELECT COALESCE(sum(CASE adjustment_type
        WHEN 'charge' THEN adjustment_amount
        ELSE -adjustment_amount
    END), 0)
      INTO v_header_adjustment_total
      FROM billing.document_adjustments
     WHERE tenant_id = p_tenant_id
       AND document_id = p_document_id
       AND document_line_id IS NULL;

    IF v_document.total_amount <>
       v_line_total_amount + v_header_adjustment_total
       - v_document.withholding_amount + v_document.rounding_amount THEN
        RAISE EXCEPTION 'El total del encabezado no coincide con la suma de lineas, ajustes, retenciones y redondeo';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM billing.document_tax_totals
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) AND v_document.tax_amount <> (
        SELECT COALESCE(sum(tax_amount), 0)
          FROM billing.document_tax_totals
         WHERE tenant_id = p_tenant_id AND document_id = p_document_id
    ) THEN
        RAISE EXCEPTION 'Los totales tributarios por codigo no coinciden con el impuesto total del documento';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM billing.document_lines dl
          LEFT JOIN (
              SELECT tenant_id, document_id, document_line_id, sum(tax_amount) AS tax_sum
                FROM billing.document_line_taxes
               WHERE tenant_id = p_tenant_id AND document_id = p_document_id
               GROUP BY tenant_id, document_id, document_line_id
          ) tx ON tx.tenant_id = dl.tenant_id
             AND tx.document_id = dl.document_id
             AND tx.document_line_id = dl.id
         WHERE dl.tenant_id = p_tenant_id
           AND dl.document_id = p_document_id
           AND COALESCE(tx.tax_sum, 0) <> dl.tax_amount
    ) THEN
        RAISE EXCEPTION 'El desglose tributario de una o mas lineas no coincide con su impuesto de linea';
    END IF;

    v_number := v_series.next_number;
    IF v_number < v_series.first_number OR v_number > v_series.last_number THEN
        RAISE EXCEPTION 'La serie documental agoto su rango de numeracion';
    END IF;

    IF v_required_authorization AND
       (v_number < v_authorization.range_start OR v_number > v_authorization.range_end) THEN
        RAISE EXCEPTION 'El consecutivo esta fuera del rango de la autorizacion fiscal';
    END IF;

    v_document_number := COALESCE(v_series.prefix, '') ||
        CASE WHEN v_series.padding_length > 0
             THEN lpad(v_number::text, v_series.padding_length, '0')
             ELSE v_number::text END ||
        COALESCE(v_series.suffix, '');

    UPDATE billing.document_series
       SET next_number = next_number + 1,
           updated_at = now()
     WHERE tenant_id = p_tenant_id AND id = p_series_id;

    UPDATE billing.documents
       SET series_id = p_series_id,
           document_number = v_document_number,
           issue_at = p_issued_at,
           status = 'issued',
           updated_at = now()
     WHERE tenant_id = p_tenant_id AND id = p_document_id;

    INSERT INTO billing.event_outbox (
        tenant_id, aggregate_type, aggregate_id, event_type, event_version, payload
    ) VALUES (
        p_tenant_id, 'billing_document', p_document_id,
        'billing.document_issued.v1', 1,
        jsonb_build_object(
            'document_id', p_document_id,
            'document_number', v_document_number,
            'document_type_id', v_document.document_type_id,
            'company_id', v_document.company_id,
            'branch_id', v_document.branch_id,
            'source_module', v_document.source_module,
            'source_document_id', v_document.source_document_id,
            'issued_at', p_issued_at
        )
    );

    RETURN v_document_number;
END;
$$;

CREATE OR REPLACE FUNCTION billing.initialize_tenant_billing(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF billing.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant no coincide con el contexto autenticado';
    END IF;

    INSERT INTO billing.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Indices operativos adicionales
-- ---------------------------------------------------------------------------

CREATE INDEX ix_billing_issuer_profiles_company
    ON billing.issuer_profiles (tenant_id, company_id, is_active);
CREATE INDEX ix_billing_authorizations_validity
    ON billing.fiscal_authorizations (tenant_id, company_id, document_type_id, valid_from, valid_until)
    WHERE is_active;
CREATE INDEX ix_billing_documents_source
    ON billing.documents (tenant_id, source_module, source_document_id)
    WHERE source_document_id IS NOT NULL;
CREATE INDEX ix_billing_document_adjustments_document
    ON billing.document_adjustments (tenant_id, document_id, adjustment_type);
CREATE INDEX ix_billing_document_tax_totals_document
    ON billing.document_tax_totals (tenant_id, document_id);
CREATE INDEX ix_billing_withholding_lines_document
    ON billing.withholding_lines (tenant_id, document_id);
CREATE INDEX ix_billing_document_references_document
    ON billing.document_references (tenant_id, document_id);
CREATE INDEX ix_billing_document_references_related
    ON billing.document_references (tenant_id, company_id, referenced_document_id)
    WHERE referenced_document_id IS NOT NULL;
CREATE INDEX ix_billing_contingency_active
    ON billing.contingency_records (tenant_id, contingency_status, started_at DESC)
    WHERE contingency_status IN ('active', 'pending_regularization');

-- ---------------------------------------------------------------------------
-- 10. Triggers de actualizacion, aislamiento, inmutabilidad y estados
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'fiscal_jurisdictions', 'issuer_profiles',
        'document_types', 'fiscal_authorizations', 'document_series',
        'documents', 'fiscal_submissions', 'document_delivery_records',
        'contingency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON billing.%I FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'fiscal_jurisdictions', 'issuer_profiles', 'document_types',
        'fiscal_authorizations', 'document_series', 'documents',
        'document_lines', 'document_line_taxes', 'document_adjustments',
        'document_tax_totals', 'withholding_lines', 'document_references',
        'credit_debit_note_details', 'document_status_history',
        'fiscal_submissions', 'submission_attempts', 'authority_responses',
        'electronic_artifacts', 'document_delivery_records', 'document_attachments',
        'contingency_records', 'provider_webhook_events', 'processed_events',
        'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON billing.%I FOR EACH ROW EXECUTE FUNCTION billing.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_billing_document_content_immutable
    BEFORE UPDATE ON billing.documents
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_issued_document_content_change();

CREATE TRIGGER trg_billing_document_initial_state
    BEFORE INSERT ON billing.documents
    FOR EACH ROW EXECUTE FUNCTION billing.validate_document_initial_state();

CREATE TRIGGER trg_billing_document_state_transition
    BEFORE UPDATE OF status ON billing.documents
    FOR EACH ROW EXECUTE FUNCTION billing.validate_document_state_transition();

CREATE TRIGGER trg_billing_document_status_history
    AFTER INSERT OR UPDATE OF status ON billing.documents
    FOR EACH ROW EXECUTE FUNCTION billing.record_document_status_change();

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'document_lines', 'document_line_taxes', 'document_adjustments',
        'document_tax_totals', 'withholding_lines', 'document_references',
        'credit_debit_note_details'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON billing.%I FOR EACH ROW EXECUTE FUNCTION billing.prevent_document_child_mutation_after_issue()',
            'trg_' || v_table || '_draft_only', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_billing_document_status_history_append_only
    BEFORE UPDATE OR DELETE ON billing.document_status_history
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_append_only_mutation();

CREATE TRIGGER trg_billing_submission_attempts_append_only
    BEFORE UPDATE OR DELETE ON billing.submission_attempts
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_append_only_mutation();

CREATE TRIGGER trg_billing_authority_responses_append_only
    BEFORE UPDATE OR DELETE ON billing.authority_responses
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_append_only_mutation();

CREATE TRIGGER trg_billing_electronic_artifacts_append_only
    BEFORE UPDATE OR DELETE ON billing.electronic_artifacts
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_append_only_mutation();

CREATE TRIGGER trg_billing_processed_events_append_only
    BEFORE UPDATE OR DELETE ON billing.processed_events
    FOR EACH ROW EXECUTE FUNCTION billing.prevent_append_only_mutation();

-- ---------------------------------------------------------------------------
-- 11. RLS + FORCE RLS en todas las tablas tenant-scoped
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'fiscal_jurisdictions', 'issuer_profiles',
        'document_types', 'fiscal_authorizations', 'document_series',
        'documents', 'document_lines', 'document_line_taxes',
        'document_adjustments', 'document_tax_totals', 'withholding_lines',
        'document_references', 'credit_debit_note_details',
        'document_status_history', 'fiscal_submissions', 'submission_attempts',
        'authority_responses', 'electronic_artifacts', 'document_delivery_records',
        'document_attachments', 'contingency_records', 'provider_webhook_events',
        'processed_events', 'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE billing.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE billing.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON billing.%I USING (tenant_id = billing.current_tenant_id()) WITH CHECK (tenant_id = billing.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Comentarios de propiedad y uso
-- ---------------------------------------------------------------------------

COMMENT ON TABLE billing.documents IS
'Factura/documento comercial o fiscal emitido por un tenant a sus clientes. No es platform.invoices, que factura las suscripciones SaaS.';
COMMENT ON TABLE billing.document_lines IS
'Instantanea inmutable de cada linea del documento: descripcion, SKU, cantidad, precio y montos al momento de emitir.';
COMMENT ON TABLE billing.document_line_taxes IS
'Instantanea de impuestos calculados por Finance y recibidos por contrato. Billing no es propietario de las tarifas tributarias.';
COMMENT ON TABLE billing.fiscal_authorizations IS
'Autorizaciones/rangos asignados por una autoridad fiscal. Los codigos, prefijos y rangos se configuran por jurisdiccion y empresa.';
COMMENT ON TABLE billing.electronic_artifacts IS
'Ubicaciones y hashes de XML/UBL/PDF/QR almacenados en object storage; no almacena blobs binarios.';
COMMENT ON TABLE billing.provider_webhook_events IS
'Eventos recibidos de proveedores/autoridades. Validar firma criptografica en el adaptador antes de marcar signature_verified=true.';
COMMENT ON FUNCTION billing.issue_document(uuid, uuid, uuid, timestamptz) IS
'Asigna un consecutivo de forma transaccional y emite un documento borrador. Debe ejecutarse en una transaccion autenticada con app.tenant_id configurado.';

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 15: BILLING
-- ============================================================================
