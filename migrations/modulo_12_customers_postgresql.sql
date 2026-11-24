-- ============================================================================
-- RESTAURANT OS - MODULO 12: CUSTOMERS
-- PostgreSQL 15+
-- Responsabilidad: clientes, datos de contacto, direcciones, consentimiento,
-- segmentacion basica y fidelizacion.
-- No administra ventas, pagos, campanas de marketing, caja ni autenticacion.
--
-- Dependencia fisica externa: platform.tenants (Modulo 0).
-- Dependencias de negocio externas: Organization, Identity, Sales y Payments
-- mediante UUID/contratos; no se crean FK hacia sus tablas privadas.
-- Codigo comercial del modulo en Platform: customers_loyalty.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS customers;

COMMENT ON SCHEMA customers IS
'Clientes, perfiles, contactos, direcciones, consentimientos, segmentos y fidelizacion. No procesa ventas ni pagos ni administra campanas de marketing.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION customers.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION customers.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION customers.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Customers';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION customers.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una correccion o un evento compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION customers.prevent_customer_merge_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_reaches_source boolean;
BEGIN
    IF NEW.merged_into_customer_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.merged_into_customer_id = NEW.id THEN
        RAISE EXCEPTION 'Un cliente no puede fusionarse consigo mismo';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tenant_id::text, 93871));

    WITH RECURSIVE chain(customer_id, merged_into_customer_id, path, is_cycle) AS (
        SELECT c.id, c.merged_into_customer_id, ARRAY[c.id], false
        FROM customers.customers c
        WHERE c.tenant_id = NEW.tenant_id
          AND c.id = NEW.merged_into_customer_id
        UNION ALL
        SELECT c.id, c.merged_into_customer_id, chain.path || c.id,
               c.id = ANY(chain.path)
        FROM customers.customers c
        JOIN chain ON c.id = chain.merged_into_customer_id
        WHERE c.tenant_id = NEW.tenant_id
          AND chain.merged_into_customer_id IS NOT NULL
          AND NOT chain.is_cycle
    )
    SELECT EXISTS (
        SELECT 1 FROM chain WHERE customer_id = NEW.id OR is_cycle
    ) INTO v_reaches_source;

    IF v_reaches_source THEN
        RAISE EXCEPTION 'La fusion crearia un ciclo entre clientes';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION customers.ensure_profile_customer_type()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_type varchar(20);
    v_contact_type varchar(20);
    v_contact_active boolean;
BEGIN
    SELECT c.customer_type INTO v_customer_type
    FROM customers.customers c
    WHERE c.tenant_id = NEW.tenant_id
      AND c.id = NEW.customer_id;

    IF v_customer_type IS NULL THEN
        RAISE EXCEPTION 'No existe el cliente asociado al perfil';
    END IF;

    IF TG_TABLE_NAME = 'customer_profiles' THEN
        IF v_customer_type <> 'individual' THEN
            RAISE EXCEPTION 'customer_profiles solo admite clientes de tipo individual';
        END IF;
    ELSIF TG_TABLE_NAME = 'customer_business_profiles' THEN
        IF v_customer_type <> 'business' THEN
            RAISE EXCEPTION 'customer_business_profiles solo admite clientes de tipo business';
        END IF;

        IF NEW.billing_email_contact_id IS NOT NULL THEN
            SELECT cp.contact_type, cp.is_active
              INTO v_contact_type, v_contact_active
              FROM customers.customer_contact_points cp
             WHERE cp.tenant_id = NEW.tenant_id
               AND cp.customer_id = NEW.customer_id
               AND cp.id = NEW.billing_email_contact_id;

            IF NOT FOUND OR v_contact_type <> 'email' OR NOT v_contact_active THEN
                RAISE EXCEPTION 'El contacto de facturacion debe ser un email activo del mismo cliente';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION customers.prevent_customer_type_change_with_profile()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.customer_type IS DISTINCT FROM OLD.customer_type THEN
        IF EXISTS (SELECT 1 FROM customers.customer_profiles p WHERE p.tenant_id = OLD.tenant_id AND p.customer_id = OLD.id)
           OR EXISTS (SELECT 1 FROM customers.customer_business_profiles p WHERE p.tenant_id = OLD.tenant_id AND p.customer_id = OLD.id) THEN
            RAISE EXCEPTION 'No se puede cambiar customer_type mientras exista un perfil especifico; convierta el perfil mediante un caso de uso explicito';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE customers.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_country_code            char(2) NOT NULL DEFAULT 'CO',
    default_language                varchar(12) NOT NULL DEFAULT 'es-CO',
    default_currency                char(3) NOT NULL DEFAULT 'COP',
    customer_code_prefix            varchar(12) NOT NULL DEFAULT 'CUS',
    next_customer_number            bigint NOT NULL DEFAULT 1 CHECK (next_customer_number > 0),
    allow_duplicate_contact_points  boolean NOT NULL DEFAULT true,
    loyalty_enabled                 boolean NOT NULL DEFAULT true,
    data_retention_days             integer CHECK (data_retention_days IS NULL OR data_retention_days > 0),
    settings                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customers_settings_country_upper CHECK (default_country_code = upper(default_country_code)),
    CONSTRAINT customers_settings_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT customers_settings_json_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Maestro de clientes
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customers (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    customer_code               varchar(50) NOT NULL,
    customer_type               varchar(20) NOT NULL DEFAULT 'individual'
                                CHECK (customer_type IN ('individual', 'business')),
    display_name                varchar(180) NOT NULL,
    status                      varchar(20) NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'inactive', 'blocked', 'merged', 'archived')),
    acquisition_source          varchar(30) NOT NULL DEFAULT 'pos'
                                CHECK (acquisition_source IN ('pos', 'web', 'mobile', 'import', 'api', 'referral', 'other')),
    preferred_locale            varchar(20),
    preferred_currency           char(3),
    external_reference          varchar(160),
    merged_into_customer_id     uuid,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz,
    CONSTRAINT customers_code_not_blank CHECK (btrim(customer_code) <> ''),
    CONSTRAINT customers_display_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT customers_currency_upper CHECK (preferred_currency IS NULL OR preferred_currency = upper(preferred_currency)),
    CONSTRAINT customers_no_self_merge CHECK (merged_into_customer_id IS NULL OR merged_into_customer_id <> id),
    CONSTRAINT customers_merge_status_consistent CHECK (
        (status = 'merged' AND merged_into_customer_id IS NOT NULL)
        OR (status <> 'merged' AND merged_into_customer_id IS NULL)
    ),
    CONSTRAINT customers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customers_merge_target_fk FOREIGN KEY (tenant_id, merged_into_customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_customers_code_per_tenant
    ON customers.customers (tenant_id, lower(customer_code))
    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_customers_external_reference
    ON customers.customers (tenant_id, external_reference)
    WHERE external_reference IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_customers_tenant_status_created
    ON customers.customers (tenant_id, status, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_customers_tenant_name
    ON customers.customers (tenant_id, lower(display_name))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_customers_merge_target
    ON customers.customers (tenant_id, merged_into_customer_id)
    WHERE merged_into_customer_id IS NOT NULL;

COMMENT ON TABLE customers.customers IS
'Maestro tenant-wide de clientes. La relacion con ventas se conserva mediante customer_id logico y contratos, sin FK a Sales.';

-- ---------------------------------------------------------------------------
-- 3. Perfil de persona natural
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_profiles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    customer_id         uuid NOT NULL,
    first_name          varchar(100),
    middle_name         varchar(100),
    last_name           varchar(100),
    second_last_name    varchar(100),
    birth_date          date,
    preferred_language  varchar(20),
    occupation          varchar(120),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_profiles_customer_unique UNIQUE (tenant_id, customer_id),
    CONSTRAINT customer_profiles_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_profiles_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 4. Perfil de cliente empresa (sin almacenar NIT en texto plano)
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_business_profiles (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL,
    customer_id                 uuid NOT NULL,
    legal_name                  varchar(220) NOT NULL,
    trade_name                  varchar(180),
    tax_id_vault_reference      varchar(300),
    tax_id_fingerprint          bytea,
    tax_id_last4                varchar(4),
    tax_regime_code             varchar(40),
    industry_code               varchar(40),
    billing_email_contact_id    uuid,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_business_profiles_customer_unique UNIQUE (tenant_id, customer_id),
    CONSTRAINT customer_business_profiles_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_business_profiles_legal_name_not_blank CHECK (btrim(legal_name) <> ''),
    CONSTRAINT customer_business_profiles_tax_last4 CHECK (tax_id_last4 IS NULL OR tax_id_last4 ~ '^[0-9A-Za-z]{4}$'),
    CONSTRAINT customer_business_profiles_tax_fingerprint_size CHECK (tax_id_fingerprint IS NULL OR octet_length(tax_id_fingerprint) >= 16),
    CONSTRAINT customer_business_profiles_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_customer_business_tax_id_fingerprint
    ON customers.customer_business_profiles (tenant_id, tax_id_fingerprint)
    WHERE tax_id_fingerprint IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Contactos. El valor real se cifra en la aplicacion/KMS; hash para busqueda.
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_contact_points (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    customer_id         uuid NOT NULL,
    contact_type        varchar(20) NOT NULL
                        CHECK (contact_type IN ('email', 'phone', 'whatsapp', 'website', 'other')),
    label               varchar(60),
    value_ciphertext    bytea NOT NULL,
    value_fingerprint   bytea NOT NULL,
    masked_value        varchar(200) NOT NULL,
    is_primary          boolean NOT NULL DEFAULT false,
    is_verified         boolean NOT NULL DEFAULT false,
    verified_at         timestamptz,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_contact_points_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_contact_points_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_contact_points_tenant_customer_id_unique UNIQUE (tenant_id, customer_id, id),
    CONSTRAINT customer_contact_points_ciphertext_nonempty CHECK (octet_length(value_ciphertext) > 0),
    CONSTRAINT customer_contact_points_fingerprint_nonempty CHECK (octet_length(value_fingerprint) >= 16),
    CONSTRAINT customer_contact_points_verified_consistent CHECK ((is_verified = false) OR verified_at IS NOT NULL)
);

CREATE INDEX ix_customer_contact_points_customer
    ON customers.customer_contact_points (tenant_id, customer_id, contact_type)
    WHERE is_active;
CREATE INDEX ix_customer_contact_points_fingerprint
    ON customers.customer_contact_points (tenant_id, contact_type, value_fingerprint)
    WHERE is_active;
CREATE UNIQUE INDEX uq_customer_primary_contact_type
    ON customers.customer_contact_points (tenant_id, customer_id, contact_type)
    WHERE is_primary AND is_active;

ALTER TABLE customers.customer_business_profiles
    ADD CONSTRAINT customer_business_billing_contact_fk
    FOREIGN KEY (tenant_id, customer_id, billing_email_contact_id)
    REFERENCES customers.customer_contact_points (tenant_id, customer_id, id) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- 6. Direcciones (lineas sensibles cifradas; ubicacion general estructurada)
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_addresses (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL,
    customer_id                 uuid NOT NULL,
    address_type                varchar(20) NOT NULL DEFAULT 'shipping'
                                CHECK (address_type IN ('home', 'billing', 'shipping', 'business', 'other')),
    recipient_name              varchar(180),
    address_line1_ciphertext    bytea NOT NULL,
    address_line2_ciphertext    bytea,
    address_fingerprint         bytea,
    city                        varchar(120),
    administrative_area         varchar(120),
    postal_code                 varchar(24),
    country_code                char(2) NOT NULL DEFAULT 'CO',
    delivery_instructions       text,
    latitude                    numeric(10,7),
    longitude                   numeric(10,7),
    is_default                  boolean NOT NULL DEFAULT false,
    is_active                   boolean NOT NULL DEFAULT true,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_addresses_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_addresses_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_addresses_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT customer_addresses_latitude CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT customer_addresses_longitude CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT customer_addresses_ciphertext_nonempty CHECK (octet_length(address_line1_ciphertext) > 0),
    CONSTRAINT customer_addresses_coordinates_pair CHECK ((latitude IS NULL) = (longitude IS NULL))
);

CREATE INDEX ix_customer_addresses_customer
    ON customers.customer_addresses (tenant_id, customer_id, address_type)
    WHERE is_active;
CREATE UNIQUE INDEX uq_customer_default_address_type
    ON customers.customer_addresses (tenant_id, customer_id, address_type)
    WHERE is_default AND is_active;

-- ---------------------------------------------------------------------------
-- 7. Relacion del cliente con empresas/sucursales del tenant (referencias logicas)
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_company_assignments (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    customer_id     uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid,
    relationship_type varchar(30) NOT NULL DEFAULT 'customer'
                      CHECK (relationship_type IN ('customer', 'account', 'partner', 'other')),
    status          varchar(20) NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'inactive', 'blocked')),
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_company_assignments_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_company_assignments_tenant_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_customer_company_assignment_global
    ON customers.customer_company_assignments (tenant_id, customer_id, company_id)
    WHERE branch_id IS NULL;
CREATE UNIQUE INDEX uq_customer_company_assignment_branch
    ON customers.customer_company_assignments (tenant_id, customer_id, company_id, branch_id)
    WHERE branch_id IS NOT NULL;
CREATE INDEX ix_customer_company_assignments_scope
    ON customers.customer_company_assignments (tenant_id, company_id, branch_id, status);

-- ---------------------------------------------------------------------------
-- 8. Preferencias no juridicas de experiencia del cliente
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_preferences (
    tenant_id               uuid NOT NULL,
    customer_id             uuid NOT NULL,
    preferred_channel       varchar(20)
                            CHECK (preferred_channel IS NULL OR preferred_channel IN ('email', 'phone', 'sms', 'whatsapp', 'app', 'none')),
    preferred_contact_time  varchar(30),
    language_code           varchar(20),
    preferences             jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at              timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, customer_id),
    CONSTRAINT customer_preferences_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_preferences_json_object CHECK (jsonb_typeof(preferences) = 'object')
);

-- ---------------------------------------------------------------------------
-- 9. Consentimientos legales: append-only. Cada cambio genera un nuevo registro.
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_consents (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    customer_id             uuid NOT NULL,
    purpose_code            varchar(60) NOT NULL,
    channel                 varchar(20) NOT NULL
                            CHECK (channel IN ('email', 'sms', 'phone', 'whatsapp', 'push', 'profiling', 'other')),
    consent_status          varchar(20) NOT NULL
                            CHECK (consent_status IN ('granted', 'withdrawn', 'denied')),
    legal_basis             varchar(40),
    notice_version          varchar(60),
    captured_at             timestamptz NOT NULL DEFAULT now(),
    capture_source          varchar(30) NOT NULL DEFAULT 'pos'
                            CHECK (capture_source IN ('pos', 'web', 'mobile', 'api', 'import', 'paper', 'other')),
    evidence_reference      varchar(300),
    captured_by_user_id     uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_consents_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_consents_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_consents_purpose_not_blank CHECK (btrim(purpose_code) <> '')
);

CREATE INDEX ix_customer_consents_latest
    ON customers.customer_consents (tenant_id, customer_id, purpose_code, channel, captured_at DESC);

-- ---------------------------------------------------------------------------
-- 10. Notas internas del cliente
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_notes (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    customer_id         uuid NOT NULL,
    note_type           varchar(24) NOT NULL DEFAULT 'general'
                        CHECK (note_type IN ('general', 'service', 'complaint', 'preference', 'risk', 'other')),
    visibility          varchar(20) NOT NULL DEFAULT 'internal'
                        CHECK (visibility IN ('internal', 'restricted')),
    note_text           text NOT NULL,
    created_by_user_id  uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    redacted_at         timestamptz,
    redaction_reason    text,
    CONSTRAINT customer_notes_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_notes_text_not_blank CHECK (btrim(note_text) <> ''),
    CONSTRAINT customer_notes_redaction_consistent CHECK ((redacted_at IS NULL) = (redaction_reason IS NULL))
);

CREATE INDEX ix_customer_notes_customer_time
    ON customers.customer_notes (tenant_id, customer_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 11. Etiquetas manuales
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_tags (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tag_code        varchar(50) NOT NULL,
    name            varchar(100) NOT NULL,
    description     text,
    color_code      varchar(12),
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_tags_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_tags_code_unique UNIQUE (tenant_id, tag_code),
    CONSTRAINT customer_tags_code_not_blank CHECK (btrim(tag_code) <> ''),
    CONSTRAINT customer_tags_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT customer_tags_color_format CHECK (color_code IS NULL OR color_code ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE TABLE customers.customer_tag_assignments (
    tenant_id       uuid NOT NULL,
    customer_id     uuid NOT NULL,
    tag_id          uuid NOT NULL,
    assigned_by_user_id uuid,
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, customer_id, tag_id),
    CONSTRAINT customer_tag_assignments_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_tag_assignments_tag_fk FOREIGN KEY (tenant_id, tag_id)
        REFERENCES customers.customer_tags (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_customer_tag_assignments_tag
    ON customers.customer_tag_assignments (tenant_id, tag_id, customer_id);

-- ---------------------------------------------------------------------------
-- 12. Segmentos de clientes. La ejecucion de reglas vive en application.
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_segments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    segment_code        varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    segment_type        varchar(20) NOT NULL DEFAULT 'manual'
                        CHECK (segment_type IN ('manual', 'rule_based')),
    criteria            jsonb NOT NULL DEFAULT '{}'::jsonb,
    refresh_policy      varchar(20) NOT NULL DEFAULT 'on_demand'
                        CHECK (refresh_policy IN ('on_demand', 'scheduled', 'event_driven')),
    status              varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'inactive', 'archived')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_segments_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_segments_code_unique UNIQUE (tenant_id, segment_code),
    CONSTRAINT customer_segments_criteria_object CHECK (jsonb_typeof(criteria) = 'object'),
    CONSTRAINT customer_segments_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE customers.customer_segment_members (
    tenant_id       uuid NOT NULL,
    segment_id      uuid NOT NULL,
    customer_id     uuid NOT NULL,
    membership_source varchar(20) NOT NULL DEFAULT 'manual'
                      CHECK (membership_source IN ('manual', 'rule', 'import', 'event')),
    added_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, segment_id, customer_id),
    CONSTRAINT customer_segment_members_segment_fk FOREIGN KEY (tenant_id, segment_id)
        REFERENCES customers.customer_segments (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_segment_members_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_customer_segment_members_customer
    ON customers.customer_segment_members (tenant_id, customer_id, segment_id);

-- ---------------------------------------------------------------------------
-- 13. Programas de fidelizacion
-- ---------------------------------------------------------------------------

CREATE TABLE customers.loyalty_programs (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    program_code            varchar(50) NOT NULL,
    name                    varchar(140) NOT NULL,
    description             text,
    points_name             varchar(40) NOT NULL DEFAULT 'Puntos',
    earn_rate               numeric(12,6) NOT NULL DEFAULT 1 CHECK (earn_rate > 0),
    minimum_redemption      integer NOT NULL DEFAULT 1 CHECK (minimum_redemption > 0),
    points_expire_after_days integer CHECK (points_expire_after_days IS NULL OR points_expire_after_days > 0),
    starts_at               timestamptz,
    ends_at                 timestamptz,
    status                  varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft', 'active', 'paused', 'ended', 'archived')),
    rules                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT loyalty_programs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT loyalty_programs_code_unique UNIQUE (tenant_id, program_code),
    CONSTRAINT loyalty_programs_date_range CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at),
    CONSTRAINT loyalty_programs_rules_object CHECK (jsonb_typeof(rules) = 'object')
);

CREATE TABLE customers.loyalty_tiers (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    program_id          uuid NOT NULL,
    tier_code           varchar(40) NOT NULL,
    name                varchar(100) NOT NULL,
    minimum_lifetime_points bigint NOT NULL DEFAULT 0 CHECK (minimum_lifetime_points >= 0),
    earn_multiplier     numeric(10,4) NOT NULL DEFAULT 1 CHECK (earn_multiplier > 0),
    benefits            jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort_order          integer NOT NULL DEFAULT 0,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT loyalty_tiers_program_fk FOREIGN KEY (tenant_id, program_id)
        REFERENCES customers.loyalty_programs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_tiers_tenant_program_id_unique UNIQUE (tenant_id, program_id, id),
    CONSTRAINT loyalty_tiers_code_unique UNIQUE (tenant_id, program_id, tier_code),
    CONSTRAINT loyalty_tiers_benefits_object CHECK (jsonb_typeof(benefits) = 'object')
);

CREATE INDEX ix_loyalty_tiers_threshold
    ON customers.loyalty_tiers (tenant_id, program_id, minimum_lifetime_points)
    WHERE is_active;

CREATE TABLE customers.loyalty_accounts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    program_id              uuid NOT NULL,
    customer_id             uuid NOT NULL,
    account_number          varchar(80) NOT NULL,
    account_status          varchar(20) NOT NULL DEFAULT 'active'
                            CHECK (account_status IN ('active', 'suspended', 'closed')),
    current_tier_id         uuid,
    points_balance          bigint NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    lifetime_points_earned  bigint NOT NULL DEFAULT 0 CHECK (lifetime_points_earned >= 0),
    lifetime_points_redeemed bigint NOT NULL DEFAULT 0 CHECK (lifetime_points_redeemed >= 0),
    joined_at               timestamptz NOT NULL DEFAULT now(),
    last_activity_at        timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT loyalty_accounts_program_fk FOREIGN KEY (tenant_id, program_id)
        REFERENCES customers.loyalty_programs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_accounts_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_accounts_tier_fk FOREIGN KEY (tenant_id, program_id, current_tier_id)
        REFERENCES customers.loyalty_tiers (tenant_id, program_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_accounts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT loyalty_accounts_tenant_program_id_unique UNIQUE (tenant_id, program_id, id),
    CONSTRAINT loyalty_accounts_program_customer_unique UNIQUE (tenant_id, program_id, customer_id),
    CONSTRAINT loyalty_accounts_number_unique UNIQUE (tenant_id, account_number)
);

CREATE INDEX ix_loyalty_accounts_customer
    ON customers.loyalty_accounts (tenant_id, customer_id, account_status);

-- ---------------------------------------------------------------------------
-- 14. Libro append-only de puntos. Toda correccion usa un asiento compensatorio.
-- ---------------------------------------------------------------------------

CREATE TABLE customers.loyalty_ledger (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    loyalty_account_id  uuid NOT NULL,
    entry_type          varchar(20) NOT NULL
                        CHECK (entry_type IN ('earn', 'redeem', 'expire', 'adjustment', 'refund', 'reversal')),
    points_delta        bigint NOT NULL CHECK (points_delta <> 0),
    balance_after       bigint NOT NULL CHECK (balance_after >= 0),
    reference_type      varchar(40),
    reference_id        uuid,
    idempotency_key     varchar(160) NOT NULL,
    description         varchar(300),
    expires_at          timestamptz,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    created_by_user_id  uuid,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT loyalty_ledger_account_fk FOREIGN KEY (tenant_id, loyalty_account_id)
        REFERENCES customers.loyalty_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_ledger_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT loyalty_ledger_idempotency_unique UNIQUE (tenant_id, loyalty_account_id, idempotency_key),
    CONSTRAINT loyalty_ledger_idempotency_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT loyalty_ledger_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT loyalty_ledger_type_sign CHECK (
        (entry_type IN ('earn', 'refund') AND points_delta > 0)
        OR (entry_type IN ('redeem', 'expire') AND points_delta < 0)
        OR entry_type IN ('adjustment', 'reversal')
    )
);

CREATE INDEX ix_loyalty_ledger_account_time
    ON customers.loyalty_ledger (tenant_id, loyalty_account_id, occurred_at DESC);
CREATE INDEX ix_loyalty_ledger_reference
    ON customers.loyalty_ledger (tenant_id, reference_type, reference_id)
    WHERE reference_id IS NOT NULL;
CREATE INDEX ix_loyalty_ledger_expiration
    ON customers.loyalty_ledger (tenant_id, expires_at)
    WHERE expires_at IS NOT NULL AND entry_type = 'earn';

-- ---------------------------------------------------------------------------
-- 15. Recompensas y canjes
-- ---------------------------------------------------------------------------

CREATE TABLE customers.loyalty_rewards (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    program_id          uuid NOT NULL,
    reward_code         varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    reward_type         varchar(24) NOT NULL
                        CHECK (reward_type IN ('discount', 'free_item', 'voucher', 'benefit', 'other')),
    points_cost         bigint NOT NULL CHECK (points_cost > 0),
    reward_value        jsonb NOT NULL DEFAULT '{}'::jsonb,
    starts_at           timestamptz,
    ends_at             timestamptz,
    redemption_limit    integer CHECK (redemption_limit IS NULL OR redemption_limit > 0),
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT loyalty_rewards_program_fk FOREIGN KEY (tenant_id, program_id)
        REFERENCES customers.loyalty_programs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_rewards_tenant_program_id_unique UNIQUE (tenant_id, program_id, id),
    CONSTRAINT loyalty_rewards_code_unique UNIQUE (tenant_id, program_id, reward_code),
    CONSTRAINT loyalty_rewards_value_object CHECK (jsonb_typeof(reward_value) = 'object'),
    CONSTRAINT loyalty_rewards_date_range CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE customers.loyalty_redemptions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    program_id          uuid NOT NULL,
    loyalty_account_id  uuid NOT NULL,
    reward_id           uuid NOT NULL,
    redemption_code     varchar(100) NOT NULL,
    points_spent        bigint NOT NULL CHECK (points_spent > 0),
    status              varchar(20) NOT NULL DEFAULT 'reserved'
                        CHECK (status IN ('reserved', 'issued', 'fulfilled', 'cancelled', 'expired')),
    source_sale_id      uuid,
    reserved_at         timestamptz NOT NULL DEFAULT now(),
    issued_at           timestamptz,
    fulfilled_at        timestamptz,
    expires_at          timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT loyalty_redemptions_account_fk FOREIGN KEY (tenant_id, program_id, loyalty_account_id)
        REFERENCES customers.loyalty_accounts (tenant_id, program_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_redemptions_reward_fk FOREIGN KEY (tenant_id, program_id, reward_id)
        REFERENCES customers.loyalty_rewards (tenant_id, program_id, id) ON DELETE RESTRICT,
    CONSTRAINT loyalty_redemptions_code_unique UNIQUE (tenant_id, redemption_code),
    CONSTRAINT loyalty_redemptions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT loyalty_redemptions_issued_consistent CHECK (
        status NOT IN ('issued', 'fulfilled') OR issued_at IS NOT NULL
    ),
    CONSTRAINT loyalty_redemptions_fulfilled_consistent CHECK (
        (status = 'fulfilled' AND fulfilled_at IS NOT NULL)
        OR (status <> 'fulfilled' AND fulfilled_at IS NULL)
    ),
    CONSTRAINT loyalty_redemptions_expired_consistent CHECK (
        status <> 'expired' OR expires_at IS NOT NULL
    )
);

CREATE INDEX ix_loyalty_redemptions_account_status
    ON customers.loyalty_redemptions (tenant_id, loyalty_account_id, status, reserved_at DESC);

-- ---------------------------------------------------------------------------
-- 16. Referidos. La recompensa se acredita mediante el ledger, no aqui.
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_referrals (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    referrer_customer_id    uuid NOT NULL,
    referred_customer_id    uuid NOT NULL,
    referral_code           varchar(80) NOT NULL,
    referral_status         varchar(20) NOT NULL DEFAULT 'pending'
                            CHECK (referral_status IN ('pending', 'qualified', 'rewarded', 'rejected', 'expired')),
    source_reference        varchar(160),
    qualified_at            timestamptz,
    rewarded_at             timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_referrals_referrer_fk FOREIGN KEY (tenant_id, referrer_customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_referrals_referred_fk FOREIGN KEY (tenant_id, referred_customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_referrals_not_self CHECK (referrer_customer_id <> referred_customer_id),
    CONSTRAINT customer_referrals_code_unique UNIQUE (tenant_id, referral_code),
    CONSTRAINT customer_referrals_referred_unique UNIQUE (tenant_id, referred_customer_id),
    CONSTRAINT customer_referrals_qualified_consistent CHECK (
        referral_status NOT IN ('qualified', 'rewarded') OR qualified_at IS NOT NULL
    ),
    CONSTRAINT customer_referrals_rewarded_consistent CHECK (
        referral_status <> 'rewarded' OR rewarded_at IS NOT NULL
    )
);

-- ---------------------------------------------------------------------------
-- 17. Historial de fusiones de clientes
-- ---------------------------------------------------------------------------

CREATE TABLE customers.customer_merge_history (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    source_customer_id      uuid NOT NULL,
    destination_customer_id uuid NOT NULL,
    merge_reason            text NOT NULL,
    source_snapshot         jsonb NOT NULL DEFAULT '{}'::jsonb,
    merged_by_user_id       uuid,
    merged_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_merge_history_source_fk FOREIGN KEY (tenant_id, source_customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_merge_history_destination_fk FOREIGN KEY (tenant_id, destination_customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_merge_history_not_self CHECK (source_customer_id <> destination_customer_id),
    CONSTRAINT customer_merge_history_snapshot_object CHECK (jsonb_typeof(source_snapshot) = 'object'),
    CONSTRAINT customer_merge_history_source_unique UNIQUE (tenant_id, source_customer_id)
);

CREATE INDEX ix_customer_merge_history_destination
    ON customers.customer_merge_history (tenant_id, destination_customer_id, merged_at DESC);

-- ---------------------------------------------------------------------------
-- 18. Solicitudes de privacidad y derechos del titular
-- ---------------------------------------------------------------------------

CREATE TABLE customers.privacy_requests (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    customer_id             uuid NOT NULL,
    request_type            varchar(24) NOT NULL
                            CHECK (request_type IN ('access', 'copy', 'correction', 'deletion', 'portability', 'opt_out', 'other')),
    request_status          varchar(20) NOT NULL DEFAULT 'received'
                            CHECK (request_status IN ('received', 'verifying', 'in_progress', 'completed', 'rejected', 'cancelled')),
    requested_at            timestamptz NOT NULL DEFAULT now(),
    due_at                  timestamptz,
    completed_at            timestamptz,
    resolution_reference    varchar(300),
    resolution_notes        text,
    handled_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT privacy_requests_customer_fk FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers.customers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT privacy_requests_due_after_requested CHECK (due_at IS NULL OR due_at >= requested_at),
    CONSTRAINT privacy_requests_terminal_consistent CHECK (
        (request_status IN ('completed', 'rejected', 'cancelled') AND completed_at IS NOT NULL)
        OR (request_status NOT IN ('completed', 'rejected', 'cancelled') AND completed_at IS NULL)
    )
);

CREATE INDEX ix_privacy_requests_tenant_status
    ON customers.privacy_requests (tenant_id, request_status, requested_at);
CREATE INDEX ix_privacy_requests_customer
    ON customers.privacy_requests (tenant_id, customer_id, requested_at DESC);

-- ---------------------------------------------------------------------------
-- 19. Inbox de eventos procesados
-- ---------------------------------------------------------------------------

CREATE TABLE customers.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_name       varchar(120) NOT NULL,
    event_id            uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    processed_at        timestamptz NOT NULL DEFAULT now(),
    result_reference    uuid,
    CONSTRAINT customers_processed_events_unique UNIQUE (tenant_id, consumer_name, event_id)
);

CREATE INDEX ix_customers_processed_events_time
    ON customers.processed_events (tenant_id, processed_at DESC);

-- ---------------------------------------------------------------------------
-- 20. Outbox transaccional
-- ---------------------------------------------------------------------------

CREATE TABLE customers.event_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type      varchar(100) NOT NULL,
    aggregate_id        uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    event_version       integer NOT NULL DEFAULT 1 CHECK (event_version > 0),
    payload             jsonb NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    available_at        timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    attempt_count       integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error          text,
    CONSTRAINT customers_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX ix_customers_event_outbox_pending
    ON customers.event_outbox (available_at, occurred_at)
    WHERE published_at IS NULL;
CREATE INDEX ix_customers_event_outbox_aggregate
    ON customers.event_outbox (tenant_id, aggregate_type, aggregate_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 21. Idempotencia de comandos/API
-- ---------------------------------------------------------------------------

CREATE TABLE customers.idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    idempotency_key     varchar(160) NOT NULL,
    operation_scope     varchar(120) NOT NULL,
    request_fingerprint bytea NOT NULL,
    response_status     integer,
    response_body       jsonb,
    resource_id         uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,
    CONSTRAINT customers_idempotency_unique UNIQUE (tenant_id, operation_scope, idempotency_key),
    CONSTRAINT customers_idempotency_fingerprint_nonempty CHECK (octet_length(request_fingerprint) >= 16),
    CONSTRAINT customers_idempotency_response_object CHECK (response_body IS NULL OR jsonb_typeof(response_body) = 'object'),
    CONSTRAINT customers_idempotency_expiration CHECK (expires_at > created_at)
);

CREATE INDEX ix_customers_idempotency_expiration
    ON customers.idempotency_records (expires_at);

-- ---------------------------------------------------------------------------
-- 22. Triggers: updated_at, tenant inmutable y registros append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    tbl text;
    updated_tables text[] := ARRAY[
        'tenant_settings', 'customers', 'customer_profiles', 'customer_business_profiles',
        'customer_contact_points', 'customer_addresses', 'customer_company_assignments', 'customer_preferences',
        'customer_tags', 'customer_segments', 'loyalty_programs',
        'loyalty_tiers', 'loyalty_accounts', 'loyalty_rewards', 'loyalty_redemptions',
        'customer_referrals', 'privacy_requests'
    ];
    tenant_tables text[] := ARRAY[
        'tenant_settings', 'customers', 'customer_profiles', 'customer_business_profiles', 'customer_contact_points',
        'customer_addresses', 'customer_company_assignments', 'customer_preferences',
        'customer_consents', 'customer_notes', 'customer_tags', 'customer_tag_assignments',
        'customer_segments', 'customer_segment_members', 'loyalty_programs', 'loyalty_tiers',
        'loyalty_accounts', 'loyalty_ledger', 'loyalty_rewards', 'loyalty_redemptions',
        'customer_referrals', 'customer_merge_history', 'privacy_requests', 'processed_events',
        'event_outbox', 'idempotency_records'
    ];
    immutable_tables text[] := ARRAY[
        'customer_consents', 'loyalty_ledger', 'customer_merge_history', 'processed_events'
    ];
BEGIN
    FOREACH tbl IN ARRAY updated_tables LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON customers.%I FOR EACH ROW EXECUTE FUNCTION customers.set_updated_at()',
            'trg_' || tbl || '_updated_at', tbl
        );
    END LOOP;

    FOREACH tbl IN ARRAY tenant_tables LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON customers.%I FOR EACH ROW EXECUTE FUNCTION customers.prevent_tenant_change()',
            'trg_' || tbl || '_prevent_tenant_change', tbl
        );
    END LOOP;

    FOREACH tbl IN ARRAY immutable_tables LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON customers.%I FOR EACH ROW EXECUTE FUNCTION customers.prevent_append_only_mutation()',
            'trg_' || tbl || '_append_only', tbl
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_customers_prevent_merge_cycle
BEFORE INSERT OR UPDATE OF merged_into_customer_id ON customers.customers
FOR EACH ROW EXECUTE FUNCTION customers.prevent_customer_merge_cycle();

CREATE TRIGGER trg_customer_profiles_type_guard
BEFORE INSERT OR UPDATE OF customer_id ON customers.customer_profiles
FOR EACH ROW EXECUTE FUNCTION customers.ensure_profile_customer_type();

CREATE TRIGGER trg_customer_business_profiles_type_guard
BEFORE INSERT OR UPDATE OF customer_id, billing_email_contact_id ON customers.customer_business_profiles
FOR EACH ROW EXECUTE FUNCTION customers.ensure_profile_customer_type();

CREATE TRIGGER trg_customers_prevent_profile_type_change
BEFORE UPDATE OF customer_type ON customers.customers
FOR EACH ROW EXECUTE FUNCTION customers.prevent_customer_type_change_with_profile();

-- ---------------------------------------------------------------------------
-- 23. RLS: todas las tablas con tenant_id quedan aisladas por tenant.
-- El backend debe establecer app.tenant_id desde un contexto autenticado.
-- RLS no sustituye permisos de usuario ni controles de sucursal.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    tbl text;
    tenant_tables text[] := ARRAY[
        'tenant_settings', 'customers', 'customer_profiles', 'customer_business_profiles',
        'customer_contact_points', 'customer_addresses', 'customer_company_assignments',
        'customer_preferences', 'customer_consents', 'customer_notes', 'customer_tags',
        'customer_tag_assignments', 'customer_segments', 'customer_segment_members',
        'loyalty_programs', 'loyalty_tiers', 'loyalty_accounts', 'loyalty_ledger',
        'loyalty_rewards', 'loyalty_redemptions', 'customer_referrals', 'customer_merge_history',
        'privacy_requests', 'processed_events', 'event_outbox', 'idempotency_records'
    ];
BEGIN
    FOREACH tbl IN ARRAY tenant_tables LOOP
        EXECUTE format('ALTER TABLE customers.%I ENABLE ROW LEVEL SECURITY', tbl);
        EXECUTE format('ALTER TABLE customers.%I FORCE ROW LEVEL SECURITY', tbl);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON customers.%I USING (tenant_id = customers.current_tenant_id()) WITH CHECK (tenant_id = customers.current_tenant_id())',
            tbl
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 24. Generacion transaccional de codigos de cliente
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION customers.next_customer_code(p_tenant_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_prefix varchar(12);
    v_number bigint;
BEGIN
    IF p_tenant_id IS NULL OR customers.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado debe coincidir con app.tenant_id autenticado';
    END IF;

    INSERT INTO customers.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    UPDATE customers.tenant_settings
       SET next_customer_number = next_customer_number + 1
     WHERE tenant_id = p_tenant_id
     RETURNING customer_code_prefix, next_customer_number - 1
          INTO v_prefix, v_number;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No fue posible reservar el siguiente codigo de cliente';
    END IF;

    RETURN v_prefix || '-' || lpad(v_number::text, 8, '0');
END;
$$;

-- ---------------------------------------------------------------------------
-- 25. Inicializacion idempotente por tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION customers.initialize_tenant_customers(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tenant_id IS NULL OR customers.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado debe coincidir con app.tenant_id autenticado';
    END IF;

    INSERT INTO customers.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION customers.initialize_tenant_customers(uuid) IS
'Inicializa la configuracion de Customers para el tenant autenticado. No crea clientes ni programas de fidelizacion automaticamente.';

-- Permisos a registrar en identity.permissions (Identity es propietario):
--   customers.profiles.read / customers.profiles.manage
--   customers.business_profiles.read / customers.business_profiles.manage
--   customers.contacts.read / customers.contacts.manage
--   customers.addresses.read / customers.addresses.manage
--   customers.consents.read / customers.consents.manage
--   customers.notes.read / customers.notes.manage
--   customers.segments.read / customers.segments.manage
--   customers.loyalty.read / customers.loyalty.manage
--   customers.privacy.read / customers.privacy.manage
--   customers.merge
--   customers.referrals.read / customers.referrals.manage
-- Aplicar estos permisos además de customers.read/manage para endpoints de
-- datos sensibles; el permiso general no concede acceso a PII, consentimientos
-- ni solicitudes de privacidad.
-- El modulo comercial correspondiente en Platform es 'customers_loyalty'.

COMMIT;

-- ============================================================================
-- FIN MODULO 12 - CUSTOMERS
--
-- Notas de implementacion obligatorias:
-- 1. app.tenant_id debe asignarse con SET LOCAL dentro de cada transaccion,
--    usando un tenant obtenido de una sesion autenticada; nunca desde el body.
-- 2. Los valores de contacto/direccion se cifran en application usando KMS/Vault;
--    value_fingerprint debe ser HMAC con clave gestionada, no SHA simple.
-- 3. No almacenar PAN/CVV ni datos de pago. Payments es el propietario de pagos.
-- 4. El backend debe comprobar permisos y scope de company_id/branch_id; RLS aqui
--    garantiza tenant isolation, no autorizacion granular por sucursal.
-- 5. Genere customer_code llamando customers.next_customer_code(tenant_id)
--    dentro de una transaccion y con app.tenant_id autenticado.
-- 6. Los saldos de fidelizacion se actualizan en una transaccion de application:
--    SELECT ... FOR UPDATE en loyalty_accounts, insertar loyalty_ledger y
--    actualizar balance/lifetime counters; rollback si cualquier paso falla.
-- 7. Los eventos se insertan en event_outbox dentro de la misma transaccion de
--    negocio; el publicador reintenta con backoff y consumidores usan Inbox.
-- 8. customer_id en Sales es una referencia logica UUID. Sales y Customers se
--    integran mediante contratos/eventos; no se agrega FK cruzada entre modulos.
-- 9. Customer merge debe migrar referencias de forma transaccional y conservar
--    source/destination e historial; no borrar fisicamente clientes fusionados.
-- ============================================================================
