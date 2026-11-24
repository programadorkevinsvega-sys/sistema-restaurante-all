-- ============================================================================
-- RESTAURANT-OS / POS SaaS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO: ORGANIZATION
-- Ubicacion de codigo: crates/modules/organization
-- Motor: PostgreSQL 15+
--
-- RESPONSABILIDAD
--   * Empresas legales/comerciales pertenecientes a un tenant.
--   * Ubicaciones normalizadas.
--   * Establecimientos comerciales/legales.
--   * Sucursales operativas del POS.
--   * Areas fisicas y mesas del pack de restaurantes.
--   * Estaciones fisicas utilizadas por capacidades operativas.
--   * Contactos, perfiles fiscales generales y documentos corporativos.
--   * Horarios y configuraciones de empresa/sucursal.
--   * Historial de estados organizacionales.
--
-- DEPENDENCIAS
--   * Requiere platform.tenants (Modulo 0), que es el registro canonico
--     de cuentas SaaS. No vuelve a crear tenants.
--   * No crea ni consulta tablas internas de identity, sales, inventory,
--     procurement, workforce ni otros modulos de negocio.
--   * actor_id y updated_by_id son referencias logicas UUID; la identidad
--     del actor se valida en la capa de aplicacion mediante contratos.
--
-- IMPORTANTE SOBRE LOS ARCHIVOS ANTERIORES
--   Este archivo es el Modulo 1 definitivo de ORGANIZATION.
--   Si una instalacion anterior ejecutó una copia con otro nombre,
--   NO volver a ejecutar este archivo sobre esa base sin revisar
--   las migraciones y objetos ya existentes.
--
-- AISLAMIENTO
--   * Todas las tablas tenant-scoped incluyen tenant_id.
--   * Las FK compuestas impiden relaciones cruzadas entre tenants y empresas.
--   * RLS usa SET LOCAL app.tenant_id dentro de cada transaccion.
--   * El rol de runtime no debe ser propietario, superusuario ni BYPASSRLS.
--   * El tenant se obtiene de la sesion autenticada; nunca se confia en un
--     tenant_id arbitrario enviado por el cliente.
--
-- EJECUCION PARA UNA INSTALACION NUEVA
--   1. modulo_0_admin_plataforma_postgresql.sql
--   2. modulo_1_organization_postgresql.sql
--   3. modulo_2_identity_usuarios_seguridad_postgresql.sql (la version actual
--      contiene FK hacia organization.companies/branches, por eso requiere
--      que organization exista antes; se debe desacoplar en la siguiente
--      revision para cumplir independencia estricta entre modulos).
--
-- Este script esta transaccionado. Ejecutar una sola vez en una base nueva.
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS organization;

COMMENT ON SCHEMA organization IS
'Perfil legal y estructura organizacional de cada tenant: empresas, establecimientos, sucursales y ubicaciones.';

-- ---------------------------------------------------------------------------
-- 0. Funcion comun para mantener updated_at
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Ubicaciones normalizadas
-- ---------------------------------------------------------------------------

CREATE TABLE organization.locations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    label               varchar(120),
    address_line_1      varchar(240) NOT NULL,
    address_line_2      varchar(240),
    neighborhood        varchar(120),
    city                varchar(120) NOT NULL,
    municipality_code   varchar(30),
    region              varchar(120),
    region_code         varchar(30),
    postal_code         varchar(24),
    country_code        char(2) NOT NULL DEFAULT 'CO',
    latitude            numeric(10,7),
    longitude           numeric(10,7),
    delivery_notes      text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT locations_address_not_blank CHECK (btrim(address_line_1) <> ''),
    CONSTRAINT locations_city_not_blank CHECK (btrim(city) <> ''),
    CONSTRAINT locations_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT locations_latitude_range CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT locations_longitude_range CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT locations_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_locations_tenant_city
    ON organization.locations (tenant_id, country_code, region, city);

-- ---------------------------------------------------------------------------
-- 2. Empresas / entidades legales dentro de un tenant
-- ---------------------------------------------------------------------------

CREATE TABLE organization.companies (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_code            varchar(40) NOT NULL,
    legal_name              varchar(200) NOT NULL,
    trade_name              varchar(200),
    entity_type             varchar(30) NOT NULL
                            CHECK (entity_type IN ('natural_person', 'legal_entity', 'nonprofit', 'government', 'other')),
    legal_form              varchar(80),
    tax_country_code        char(2) NOT NULL DEFAULT 'CO',
    tax_identifier_type     varchar(40),
    tax_identifier          varchar(80),
    tax_verification_digit  varchar(4),
    industry_code           varchar(40),
    industry_description    varchar(180),
    registered_location_id  uuid,
    website_url             text,
    default_locale          varchar(20) NOT NULL DEFAULT 'es-CO',
    default_timezone        varchar(80) NOT NULL DEFAULT 'America/Bogota',
    default_currency        char(3) NOT NULL DEFAULT 'COP',
    status                  varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft', 'active', 'suspended', 'closed')),
    is_primary              boolean NOT NULL DEFAULT false,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz,
    CONSTRAINT companies_code_not_blank CHECK (btrim(company_code) <> ''),
    CONSTRAINT companies_legal_name_not_blank CHECK (btrim(legal_name) <> ''),
    CONSTRAINT companies_tax_country_upper CHECK (tax_country_code = upper(tax_country_code)),
    CONSTRAINT companies_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT companies_tax_identifier_pair CHECK (
        (tax_identifier IS NULL AND tax_identifier_type IS NULL)
        OR
        (tax_identifier IS NOT NULL AND tax_identifier_type IS NOT NULL
         AND btrim(tax_identifier) <> '' AND btrim(tax_identifier_type) <> '')
    ),
    CONSTRAINT companies_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT companies_location_same_tenant_fk
        FOREIGN KEY (tenant_id, registered_location_id)
        REFERENCES organization.locations (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_companies_code_per_tenant
    ON organization.companies (tenant_id, lower(company_code))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_companies_tax_identifier_per_tenant
    ON organization.companies (
        tenant_id,
        tax_country_code,
        tax_identifier_type,
        upper(regexp_replace(tax_identifier, '[^A-Za-z0-9]', '', 'g'))
    )
    WHERE tax_identifier IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX uq_companies_primary_per_tenant
    ON organization.companies (tenant_id)
    WHERE is_primary = true AND deleted_at IS NULL;

CREATE INDEX ix_companies_tenant_status
    ON organization.companies (tenant_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_companies_legal_name
    ON organization.companies (tenant_id, lower(legal_name))
    WHERE deleted_at IS NULL;

COMMENT ON TABLE organization.companies IS
'Entidad legal/comercial del cliente. No representa el tenant SaaS; se relaciona con platform.tenants mediante tenant_id.';
COMMENT ON COLUMN organization.companies.tax_identifier IS
'Identificacion tributaria de la entidad. Para Colombia puede ser NIT; el tipo y el digito de verificacion se guardan por separado.';

-- ---------------------------------------------------------------------------
-- 3. Contactos de la empresa
-- ---------------------------------------------------------------------------

CREATE TABLE organization.company_contacts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    contact_type        varchar(30) NOT NULL
                        CHECK (contact_type IN ('legal', 'administrative', 'billing', 'operations', 'sales', 'technical', 'other')),
    full_name           varchar(160) NOT NULL,
    job_title           varchar(120),
    email               varchar(320),
    phone_country_code  varchar(8),
    phone_number        varchar(40),
    is_primary          boolean NOT NULL DEFAULT false,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT company_contacts_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT company_contacts_email_not_blank CHECK (email IS NULL OR btrim(email) <> ''),
    CONSTRAINT company_contacts_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_company_primary_contact_type
    ON organization.company_contacts (tenant_id, company_id, contact_type)
    WHERE is_primary = true AND deleted_at IS NULL;

CREATE INDEX ix_company_contacts_company
    ON organization.company_contacts (tenant_id, company_id, contact_type)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Perfil fiscal general de la empresa (sin reglas de impuestos de productos)
-- ---------------------------------------------------------------------------

CREATE TABLE organization.company_tax_profiles (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL,
    company_id                  uuid NOT NULL,
    country_code                char(2) NOT NULL,
    tax_regime_code             varchar(60),
    taxpayer_category           varchar(60),
    fiscal_responsibilities     jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_tax_withholding_agent    boolean NOT NULL DEFAULT false,
    electronic_invoicing_status varchar(30) NOT NULL DEFAULT 'not_configured'
                                CHECK (electronic_invoicing_status IN ('not_configured', 'pending', 'enabled', 'disabled')),
    tax_authority_name          varchar(120),
    tax_registration_reference  varchar(160),
    effective_from              date,
    effective_until             date,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT company_tax_profiles_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT company_tax_profiles_responsibilities_array CHECK (jsonb_typeof(fiscal_responsibilities) = 'array'),
    CONSTRAINT company_tax_profiles_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT company_tax_profiles_dates CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until >= effective_from),
    CONSTRAINT company_tax_profiles_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT company_tax_profiles_company_country_unique UNIQUE (tenant_id, company_id, country_code)
);

CREATE INDEX ix_company_tax_profiles_company
    ON organization.company_tax_profiles (tenant_id, company_id);

COMMENT ON TABLE organization.company_tax_profiles IS
'Perfil tributario general de la entidad. La configuracion de impuestos de productos y transacciones pertenece a modulos fiscales/ventas posteriores.';

-- ---------------------------------------------------------------------------
-- 5. Marcas comerciales de una empresa
-- ---------------------------------------------------------------------------

CREATE TABLE organization.brands (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    brand_code          varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    website_url         text,
    logo_object_key     text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT brands_code_not_blank CHECK (btrim(brand_code) <> ''),
    CONSTRAINT brands_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT brands_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT brands_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT brands_tenant_company_id_unique UNIQUE (tenant_id, company_id, id)
);

CREATE UNIQUE INDEX uq_brands_code_per_company
    ON organization.brands (tenant_id, company_id, lower(brand_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_brands_company_active
    ON organization.brands (tenant_id, company_id, is_active)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 6. Establecimientos comerciales/legales pertenecientes a una empresa
-- ---------------------------------------------------------------------------

CREATE TABLE organization.establishments (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL,
    company_id                  uuid NOT NULL,
    establishment_code          varchar(40) NOT NULL,
    name                        varchar(180) NOT NULL,
    establishment_type          varchar(30) NOT NULL DEFAULT 'commercial'
                                CHECK (establishment_type IN ('commercial', 'service', 'manufacturing', 'office', 'other')),
    commercial_registration_no  varchar(100),
    chamber_of_commerce         varchar(160),
    registration_date           date,
    last_renewal_date           date,
    location_id                 uuid,
    status                      varchar(20) NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'inactive', 'closed')),
    opened_on                   date,
    closed_on                   date,
    notes                       text,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz,
    CONSTRAINT establishments_code_not_blank CHECK (btrim(establishment_code) <> ''),
    CONSTRAINT establishments_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT establishments_dates CHECK (closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on),
    CONSTRAINT establishments_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT establishments_location_fk
        FOREIGN KEY (tenant_id, location_id)
        REFERENCES organization.locations (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT establishments_tenant_company_id_unique UNIQUE (tenant_id, company_id, id)
);

CREATE UNIQUE INDEX uq_establishment_code_per_company
    ON organization.establishments (tenant_id, company_id, lower(establishment_code))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_establishment_registration_per_company
    ON organization.establishments (tenant_id, company_id, commercial_registration_no)
    WHERE commercial_registration_no IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX ix_establishments_company_status
    ON organization.establishments (tenant_id, company_id, status)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 7. Sucursales operativas del POS
-- ---------------------------------------------------------------------------

CREATE TABLE organization.branches (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    fiscal_company_id   uuid,
    brand_id            uuid NOT NULL,
    establishment_id    uuid,
    location_id         uuid,
    branch_code         varchar(40) NOT NULL,
    name                varchar(180) NOT NULL,
    branch_type         varchar(30) NOT NULL DEFAULT 'store'
                        CHECK (branch_type IN ('store', 'restaurant', 'office', 'kiosk', 'online', 'other')),
    status              varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('draft', 'active', 'temporarily_closed', 'suspended', 'closed')),
    email               varchar(320),
    phone_country_code  varchar(8),
    phone_number        varchar(40),
    timezone            varchar(80) NOT NULL DEFAULT 'America/Bogota',
    locale              varchar(20) NOT NULL DEFAULT 'es-CO',
    currency            char(3) NOT NULL DEFAULT 'COP',
    is_primary          boolean NOT NULL DEFAULT false,
    opened_at           date,
    closed_at           date,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT branches_code_not_blank CHECK (btrim(branch_code) <> ''),
    CONSTRAINT branches_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT branches_email_not_blank CHECK (email IS NULL OR btrim(email) <> ''),
    CONSTRAINT branches_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT branches_dates CHECK (closed_at IS NULL OR opened_at IS NULL OR closed_at >= opened_at),
    CONSTRAINT branches_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT branches_brand_same_company_fk
        FOREIGN KEY (tenant_id, company_id, brand_id)
        REFERENCES organization.brands (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT branches_fiscal_company_same_tenant_fk
        FOREIGN KEY (tenant_id, fiscal_company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT branches_establishment_same_company_fk
        FOREIGN KEY (tenant_id, company_id, establishment_id)
        REFERENCES organization.establishments (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT branches_location_same_tenant_fk
        FOREIGN KEY (tenant_id, location_id)
        REFERENCES organization.locations (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT branches_tenant_company_id_unique UNIQUE (tenant_id, company_id, id)
);

CREATE UNIQUE INDEX uq_branch_code_per_company
    ON organization.branches (tenant_id, company_id, lower(branch_code))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_primary_branch_per_company
    ON organization.branches (tenant_id, company_id)
    WHERE is_primary = true AND deleted_at IS NULL;

CREATE INDEX ix_branches_tenant_company_status
    ON organization.branches (tenant_id, company_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_branches_establishment
    ON organization.branches (tenant_id, company_id, establishment_id)
    WHERE establishment_id IS NOT NULL;

CREATE INDEX ix_branches_brand
    ON organization.branches (tenant_id, brand_id)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE organization.branches IS
'Unidad operativa del POS. Debe resolver una marca y una empresa fiscal efectiva; bodegas y cajas pertenecen a sus modulos.';
COMMENT ON COLUMN organization.branches.brand_id IS
'Marca comercial operada por la sucursal. Debe pertenecer a la misma empresa y tenant.';
COMMENT ON COLUMN organization.branches.fiscal_company_id IS
'Empresa legal efectiva para documentos fiscales de la sucursal. Puede ser distinta de company_id cuando se autorice una relacion fiscal propia.';

-- ---------------------------------------------------------------------------
-- 8. Areas fisicas y mesas del pack de restaurantes
-- ---------------------------------------------------------------------------
-- La configuracion fisica pertenece a ORGANIZATION. La ocupacion, reservas
-- y asignaciones temporales de mesas pertenecen a SALES.

CREATE TABLE organization.dining_areas (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    area_code       varchar(40) NOT NULL,
    name            varchar(120) NOT NULL,
    description     text,
    floor_name      varchar(80),
    display_order   integer NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz,
    CONSTRAINT dining_areas_code_not_blank CHECK (btrim(area_code) <> ''),
    CONSTRAINT dining_areas_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT dining_areas_scope_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT dining_areas_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, id)
);

CREATE UNIQUE INDEX uq_dining_areas_code_per_branch
    ON organization.dining_areas (tenant_id, branch_id, lower(area_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_dining_areas_branch_active
    ON organization.dining_areas (tenant_id, branch_id, is_active, display_order)
    WHERE deleted_at IS NULL;

CREATE TABLE organization.dining_tables (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    area_id         uuid NOT NULL,
    table_code      varchar(40) NOT NULL,
    name            varchar(100) NOT NULL,
    capacity        smallint NOT NULL DEFAULT 2 CHECK (capacity > 0),
    shape           varchar(20) NOT NULL DEFAULT 'rectangle'
                    CHECK (shape IN ('rectangle', 'square', 'circle', 'oval', 'custom')),
    position_x      numeric(10,3),
    position_y      numeric(10,3),
    rotation_degrees smallint NOT NULL DEFAULT 0
                    CHECK (rotation_degrees BETWEEN 0 AND 359),
    display_order   integer NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz,
    CONSTRAINT dining_tables_code_not_blank CHECK (btrim(table_code) <> ''),
    CONSTRAINT dining_tables_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT dining_tables_position_pair CHECK (
        (position_x IS NULL AND position_y IS NULL)
        OR (position_x IS NOT NULL AND position_y IS NOT NULL)
    ),
    CONSTRAINT dining_tables_area_same_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id, area_id)
        REFERENCES organization.dining_areas (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT dining_tables_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, id)
);

CREATE UNIQUE INDEX uq_dining_tables_code_per_branch
    ON organization.dining_tables (tenant_id, branch_id, lower(table_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_dining_tables_area_active
    ON organization.dining_tables (tenant_id, branch_id, area_id, is_active, display_order)
    WHERE deleted_at IS NULL;

CREATE TABLE organization.stations (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    station_code    varchar(40) NOT NULL,
    name            varchar(120) NOT NULL,
    station_type    varchar(30) NOT NULL DEFAULT 'prep'
                    CHECK (station_type IN ('hot_line', 'cold_line', 'grill', 'fryer', 'bar', 'dessert', 'prep', 'expo', 'packing', 'other')),
    description     text,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz,
    CONSTRAINT stations_code_not_blank CHECK (btrim(station_code) <> ''),
    CONSTRAINT stations_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT stations_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT stations_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, id)
);

CREATE UNIQUE INDEX uq_stations_code_per_branch
    ON organization.stations (tenant_id, branch_id, lower(station_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_stations_branch_active
    ON organization.stations (tenant_id, branch_id, is_active, station_type)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE organization.dining_areas IS
'Areas fisicas configurables de una sucursal del pack de restaurantes. La ocupacion de cada area no se almacena aqui.';
COMMENT ON TABLE organization.dining_tables IS
'Mesas fisicas y su posicion en el plano de una sucursal. Su ocupacion, reservas y asignacion a pedidos pertenecen a SALES.';
COMMENT ON COLUMN organization.dining_tables.is_active IS
'Indica si la mesa puede ofrecerse para nuevas operaciones; no representa su estado de ocupacion.';
COMMENT ON TABLE organization.stations IS
'Estaciones fisicas de una sucursal. Cada modulo operativo mantiene su propia configuracion y flujo de trabajo.';

-- ---------------------------------------------------------------------------
-- 9. Contactos de sucursal
-- ---------------------------------------------------------------------------

CREATE TABLE organization.branch_contacts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    contact_type        varchar(30) NOT NULL
                        CHECK (contact_type IN ('manager', 'administrative', 'billing', 'operations', 'technical', 'emergency', 'other')),
    full_name           varchar(160) NOT NULL,
    job_title           varchar(120),
    email               varchar(320),
    phone_country_code  varchar(8),
    phone_number        varchar(40),
    is_primary          boolean NOT NULL DEFAULT false,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT branch_contacts_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT branch_contacts_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_branch_primary_contact_type
    ON organization.branch_contacts (tenant_id, branch_id, contact_type)
    WHERE is_primary = true AND deleted_at IS NULL;

CREATE INDEX ix_branch_contacts_branch
    ON organization.branch_contacts (tenant_id, branch_id, contact_type)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 10. Horarios de atencion por sucursal
--    weekday_iso: 1 = lunes ... 7 = domingo.
--    Permite varios periodos por dia (por ejemplo, jornada partida).
-- ---------------------------------------------------------------------------

CREATE TABLE organization.branch_business_hours (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    weekday_iso     smallint NOT NULL CHECK (weekday_iso BETWEEN 1 AND 7),
    period_no       smallint NOT NULL DEFAULT 1 CHECK (period_no BETWEEN 1 AND 4),
    is_closed       boolean NOT NULL DEFAULT false,
    opens_at        time without time zone,
    closes_at       time without time zone,
    closes_next_day boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT branch_hours_period_valid CHECK (
        (is_closed = true AND opens_at IS NULL AND closes_at IS NULL AND closes_next_day = false)
        OR
        (is_closed = false AND opens_at IS NOT NULL AND closes_at IS NOT NULL AND (
            (closes_next_day = false AND closes_at > opens_at)
            OR
            (closes_next_day = true AND closes_at < opens_at)
        ))
    ),
    CONSTRAINT branch_hours_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT branch_hours_unique_period UNIQUE (tenant_id, branch_id, weekday_iso, period_no)
);

CREATE INDEX ix_branch_business_hours_branch_day
    ON organization.branch_business_hours (tenant_id, branch_id, weekday_iso, period_no);

-- ---------------------------------------------------------------------------
-- 11. Configuracion de empresa y sucursal (sin secretos)
-- ---------------------------------------------------------------------------

CREATE TABLE organization.company_settings (
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    setting_key     varchar(120) NOT NULL,
    setting_value   jsonb NOT NULL,
    description     text,
    updated_by_id   uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, company_id, setting_key),
    CONSTRAINT company_settings_key_not_blank CHECK (btrim(setting_key) <> ''),
    CONSTRAINT company_settings_value_object_or_scalar CHECK (jsonb_typeof(setting_value) IS NOT NULL),
    CONSTRAINT company_settings_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE organization.branch_settings (
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    setting_key     varchar(120) NOT NULL,
    setting_value   jsonb NOT NULL,
    description     text,
    updated_by_id   uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, branch_id, setting_key),
    CONSTRAINT branch_settings_key_not_blank CHECK (btrim(setting_key) <> ''),
    CONSTRAINT branch_settings_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE organization.company_settings IS
'Preferencias configurables de la empresa. No guardar contrasenas, tokens, claves privadas ni secretos.';
COMMENT ON TABLE organization.branch_settings IS
'Preferencias configurables de una sucursal. No guardar secretos ni duplicar configuraciones propias de otros modulos.';

-- ---------------------------------------------------------------------------
-- 12. Documentos corporativos (metadatos; los archivos viven en object storage)
-- ---------------------------------------------------------------------------

CREATE TABLE organization.company_documents (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    document_type       varchar(50) NOT NULL,
    document_number     varchar(120),
    file_name           varchar(255) NOT NULL,
    content_type        varchar(120),
    file_size_bytes     bigint CHECK (file_size_bytes IS NULL OR file_size_bytes > 0),
    checksum_sha256     char(64),
    storage_provider    varchar(40) NOT NULL,
    storage_object_key  text NOT NULL,
    issued_on           date,
    expires_on          date,
    uploaded_by_id      uuid,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT company_documents_type_not_blank CHECK (btrim(document_type) <> ''),
    CONSTRAINT company_documents_filename_not_blank CHECK (btrim(file_name) <> ''),
    CONSTRAINT company_documents_storage_key_not_blank CHECK (btrim(storage_object_key) <> ''),
    CONSTRAINT company_documents_checksum_hex CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT company_documents_dates CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on),
    CONSTRAINT company_documents_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT company_documents_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_company_document_object
    ON organization.company_documents (storage_provider, storage_object_key)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_company_documents_company_type
    ON organization.company_documents (tenant_id, company_id, document_type)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 13. Historial de estados (historial funcional; auditoria transversal en el modulo audit)
--    actor_id es una referencia polimorfica: no crea dependencia con Modulo 2.
-- ---------------------------------------------------------------------------

CREATE TABLE organization.company_status_history (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    old_status      varchar(20),
    new_status      varchar(20) NOT NULL CHECK (new_status IN ('draft', 'active', 'suspended', 'closed')),
    reason          text,
    actor_type      varchar(20) NOT NULL DEFAULT 'system'
                    CHECK (actor_type IN ('tenant_user', 'platform_admin', 'system', 'service')),
    actor_id        uuid,
    changed_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT company_status_history_actor CHECK (
        (actor_type IN ('tenant_user', 'platform_admin') AND actor_id IS NOT NULL)
        OR actor_type IN ('system', 'service')
    ),
    CONSTRAINT company_status_history_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_company_status_history_time
    ON organization.company_status_history (tenant_id, company_id, changed_at DESC);

CREATE TABLE organization.establishment_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    company_id          uuid NOT NULL,
    establishment_id    uuid NOT NULL,
    old_status          varchar(20),
    new_status          varchar(20) NOT NULL CHECK (new_status IN ('active', 'inactive', 'closed')),
    reason              text,
    actor_type          varchar(20) NOT NULL DEFAULT 'system'
                        CHECK (actor_type IN ('tenant_user', 'platform_admin', 'system', 'service')),
    actor_id            uuid,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT establishment_status_history_actor CHECK (
        (actor_type IN ('tenant_user', 'platform_admin') AND actor_id IS NOT NULL)
        OR actor_type IN ('system', 'service')
    ),
    CONSTRAINT establishment_status_history_establishment_fk
        FOREIGN KEY (tenant_id, company_id, establishment_id)
        REFERENCES organization.establishments (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_establishment_status_history_time
    ON organization.establishment_status_history (tenant_id, establishment_id, changed_at DESC);

CREATE TABLE organization.branch_status_history (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    company_id      uuid NOT NULL,
    branch_id       uuid NOT NULL,
    old_status      varchar(30),
    new_status      varchar(30) NOT NULL CHECK (new_status IN ('draft', 'active', 'temporarily_closed', 'suspended', 'closed')),
    reason          text,
    actor_type      varchar(20) NOT NULL DEFAULT 'system'
                    CHECK (actor_type IN ('tenant_user', 'platform_admin', 'system', 'service')),
    actor_id        uuid,
    changed_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT branch_status_history_actor CHECK (
        (actor_type IN ('tenant_user', 'platform_admin') AND actor_id IS NOT NULL)
        OR actor_type IN ('system', 'service')
    ),
    CONSTRAINT branch_status_history_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_branch_status_history_time
    ON organization.branch_status_history (tenant_id, branch_id, changed_at DESC);

COMMENT ON COLUMN organization.company_status_history.actor_id IS
'UUID del principal que realizo el cambio. Referencia polimorfica deliberada para no acoplar este modulo a usuarios (Modulo 2) ni a admins (Modulo 0).';

-- ---------------------------------------------------------------------------
-- 14. Triggers updated_at
-- ---------------------------------------------------------------------------

CREATE TRIGGER trg_locations_updated_at
BEFORE UPDATE ON organization.locations
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_companies_updated_at
BEFORE UPDATE ON organization.companies
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_company_contacts_updated_at
BEFORE UPDATE ON organization.company_contacts
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_company_tax_profiles_updated_at
BEFORE UPDATE ON organization.company_tax_profiles
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_brands_updated_at
BEFORE UPDATE ON organization.brands
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_establishments_updated_at
BEFORE UPDATE ON organization.establishments
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_branches_updated_at
BEFORE UPDATE ON organization.branches
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_dining_areas_updated_at
BEFORE UPDATE ON organization.dining_areas
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_dining_tables_updated_at
BEFORE UPDATE ON organization.dining_tables
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_stations_updated_at
BEFORE UPDATE ON organization.stations
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_branch_contacts_updated_at
BEFORE UPDATE ON organization.branch_contacts
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_branch_business_hours_updated_at
BEFORE UPDATE ON organization.branch_business_hours
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_company_settings_updated_at
BEFORE UPDATE ON organization.company_settings
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

CREATE TRIGGER trg_branch_settings_updated_at
BEFORE UPDATE ON organization.branch_settings
FOR EACH ROW EXECUTE FUNCTION organization.set_updated_at();

-- ---------------------------------------------------------------------------
-- 15. Row Level Security: aislamiento por tenant
-- ---------------------------------------------------------------------------
-- El middleware/backend debe establecer SET LOCAL app.tenant_id dentro de la
-- transaccion autenticada antes de consultar estas tablas.
-- No crear el rol de aplicacion como propietario de tablas ni darle BYPASSRLS.

DO $$
DECLARE
    table_name text;
    table_names text[] := ARRAY[
        'locations',
        'companies',
        'brands',
        'company_contacts',
        'company_tax_profiles',
        'establishments',
        'branches',
        'dining_areas',
        'dining_tables',
        'stations',
        'branch_contacts',
        'branch_business_hours',
        'company_settings',
        'branch_settings',
        'company_documents',
        'company_status_history',
        'establishment_status_history',
        'branch_status_history'
    ];
BEGIN
    FOREACH table_name IN ARRAY table_names LOOP
        EXECUTE format('ALTER TABLE organization.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE organization.%I FORCE ROW LEVEL SECURITY', table_name);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON organization.%I USING (tenant_id = NULLIF(current_setting(''app.tenant_id'', true), '''')::uuid) WITH CHECK (tenant_id = NULLIF(current_setting(''app.tenant_id'', true), '''')::uuid)',
            table_name
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 16. Comentarios de limites entre modulos
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN organization.companies.tenant_id IS
'Identificador del tenant SaaS propietario, referenciado desde platform.tenants. No se debe aceptar directamente desde el cliente sin validacion de identidad.';

COMMENT ON COLUMN organization.branches.establishment_id IS
'Referencia opcional a un establecimiento comercial/legal de la misma empresa. Una sucursal operativa puede existir sin un registro de establecimiento asociado.';

COMMENT ON COLUMN organization.company_settings.updated_by_id IS
'UUID del usuario/administrador que modifico la configuracion. Referencia logica hasta que el modulo identity defina su contrato publico.';

COMMENT ON COLUMN organization.branch_settings.updated_by_id IS
'UUID del usuario/administrador que modifico la configuracion. Referencia logica; este modulo no depende de las tablas del Modulo 2.';

COMMENT ON TABLE organization.branch_business_hours IS
'Horario comercial de la sucursal; no representa turnos de empleados ni disponibilidad de cajas.';

COMMIT;

-- ============================================================================
-- EJEMPLO DE CONTEXTO TENANT (NO EJECUTAR COMO PARTE DE LA INSTALACION)
-- ============================================================================
-- Ejecutar las consultas de negocio dentro de una transaccion y establecer
-- el tenant autorizado en esa misma transaccion:
--
-- BEGIN;
-- SET LOCAL app.tenant_id = 'UUID-REAL-DEL-TENANT';
-- SELECT id, company_code, legal_name
-- FROM organization.companies
-- WHERE deleted_at IS NULL;
-- COMMIT;
--
-- IMPORTANTE:
-- 1) El tenant debe obtenerse desde la sesion autenticada del backend.
-- 2) SET LOCAL debe ejecutarse en cada transaccion/conexion reutilizada.
-- 3) Para tareas de Superadmin entre tenants, usar un servicio/rol separado,
--    con permisos minimos, aprobacion y auditoria; no desactivar RLS para el
--    rol normal de la aplicacion.
-- 4) company_id y branch_id no sustituyen tenant_id: siempre validar ambos.
-- ============================================================================
