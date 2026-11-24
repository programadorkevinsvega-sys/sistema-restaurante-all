-- ============================================================================
-- RESTAURANT-OS - POS SAAS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 18: ANALYTICS (MODELOS ANALITICOS, KPI Y DASHBOARDS)
-- Numeracion tecnica de migraciones; requisitos.md enumera Analytics como modulo funcional 17.
-- Ubicacion del crate: crates/modules/analytics
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD
--   * Almacenar modelos analiticos derivados de eventos/contratos publicados.
--   * Mantener dimensiones historicas (SCD tipo 2) y hechos de negocio.
--   * Exponer catalogo semantico de metricas y dashboards configurables.
--   * Mantener agregados diarios por sucursal, producto, empleado y cohortes.
--   * Controlar ingesta, checkpoints, refrescos y auditoria de consultas.
--
-- FUERA DE ALCANCE / PROPIETARIO ES OTRO MODULO
--   * Ventas, productos, existencias, pagos, compras, contabilidad y RRHH son
--     propiedad de Sales, Catalog, Inventory, Payments, Purchasing, Finance y
--     Workforce. Analytics solo conserva snapshots/modelos de lectura derivados.
--   * Plantillas de informes, exportaciones y distribucion programada: reporting.
--   * Orquestacion de workflows: automation.
--   * Transporte de webhooks/APIs externas: integrations.
--   * No se consulta ni modifica directamente tablas privadas de otros modulos.
--
-- DEPENDENCIAS Y ARQUITECTURA
--   * Unica FK externa: platform.tenants(id), referencia canonica del tenant.
--   * company_id, branch_id, product_id, customer_id, employee_id, sale_id y
--     demas IDs de origen son UUID logicos, validados por contratos/eventos.
--   * Los hechos son snapshots analiticos, no registros transaccionales fuente.
--   * Las dimensiones usan versionado SCD tipo 2 para conservar historia.
--   * Los dashboards usan definiciones semanticas JSON; la app NO debe ejecutar
--     SQL arbitrario enviado por el cliente.
--
-- SEGURIDAD
--   * Todas las tablas tenant-scoped tienen tenant_id, RLS y FORCE RLS.
--   * La app establece SET LOCAL app.tenant_id en cada transaccion.
--   * El tenant se obtiene del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * La app valida permisos y alcance por empresa/sucursal ademas del aislamiento RLS por tenant.
--   * Evitar copiar PII innecesaria a los hechos; usar IDs pseudonimizados.
--   * No almacenar payloads crudos con secretos, tarjetas, CVV o documentos
--     personales. Ingerir eventos normalizados y redactados.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * El catalogo comercial analytics se registra en modulo_0_admin_plataforma_postgresql.sql.
--   * Los permisos y el rol analytics_manager se registran en modulo_2_identity_usuarios_seguridad_postgresql.sql.
--   * No ejecutar sobre un schema analytics ya existente; usar migraciones
--     versionadas para cambios posteriores.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS
'Modelos analiticos de solo lectura, hechos, dimensiones, metricas, dashboards y agregados. No es la fuente transaccional de los modulos operativos.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION analytics.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Analytics';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una correccion o una nueva version',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.validate_dimension_period()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.valid_to IS NOT NULL AND NEW.valid_to <= NEW.valid_from THEN
        RAISE EXCEPTION 'valid_to debe ser posterior a valid_from';
    END IF;
    IF NEW.is_current AND NEW.valid_to IS NOT NULL THEN
        RAISE EXCEPTION 'Una version vigente no puede tener valid_to';
    END IF;
    IF NOT NEW.is_current AND NEW.valid_to IS NULL THEN
        RAISE EXCEPTION 'Una version historica debe tener valid_to';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.protect_dimension_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Las dimensiones historicas son inmutables; cierre la version vigente';
    END IF;
    IF NOT OLD.is_current
       OR NEW.is_current
       OR NEW.valid_to IS NULL
       OR (to_jsonb(NEW) - ARRAY['is_current', 'valid_to']) IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['is_current', 'valid_to']) THEN
        RAISE EXCEPTION 'Una version SCD2 solo puede cerrarse una vez sin cambiar sus atributos';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION analytics.validate_event_inbox_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_transition_allowed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'pending' OR NEW.attempts <> 0
           OR NEW.locked_at IS NOT NULL OR NEW.locked_by IS NOT NULL
           OR NEW.processed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Los eventos deben ingresar en estado pending y sin lease';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' OR OLD.status IN ('processed', 'dead_letter') THEN
        RAISE EXCEPTION 'Los eventos procesados o enviados a dead letter son inmutables';
    END IF;
    IF (to_jsonb(NEW) - ARRAY[
        'status', 'attempts', 'available_at', 'locked_at', 'locked_by',
        'processed_at', 'last_error_code', 'last_error_message'
    ]) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY[
        'status', 'attempts', 'available_at', 'locked_at', 'locked_by',
        'processed_at', 'last_error_code', 'last_error_message'
    ]) THEN
        RAISE EXCEPTION 'El contenido recibido del evento es inmutable';
    END IF;
    IF NEW.attempts < OLD.attempts THEN
        RAISE EXCEPTION 'El contador de intentos no puede disminuir';
    END IF;
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;

    v_transition_allowed := CASE OLD.status
        WHEN 'pending' THEN NEW.status IN ('processing', 'dead_letter')
        WHEN 'processing' THEN NEW.status IN ('pending', 'processed', 'failed', 'dead_letter')
        WHEN 'failed' THEN NEW.status IN ('pending', 'processing', 'dead_letter')
        ELSE false
    END;
    IF NOT v_transition_allowed THEN
        RAISE EXCEPTION 'Transicion de evento no permitida: % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion y catalogo semantico
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    is_enabled                      boolean NOT NULL DEFAULT true,
    reporting_timezone              varchar(64) NOT NULL DEFAULT 'America/Bogota',
    default_currency_code           char(3) NOT NULL DEFAULT 'COP',
    data_retention_days             integer NOT NULL DEFAULT 730,
    pii_minimization_enabled        boolean NOT NULL DEFAULT true,
    dashboard_cache_ttl_seconds    integer NOT NULL DEFAULT 300,
    max_dashboard_widgets           smallint NOT NULL DEFAULT 24,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT analytics_timezone_not_blank CHECK (length(trim(reporting_timezone)) > 0),
    CONSTRAINT analytics_currency_format CHECK (default_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT analytics_retention_positive CHECK (data_retention_days BETWEEN 1 AND 36500),
    CONSTRAINT analytics_cache_ttl_range CHECK (dashboard_cache_ttl_seconds BETWEEN 0 AND 86400),
    CONSTRAINT analytics_widget_limit_range CHECK (max_dashboard_widgets BETWEEN 1 AND 100),
    CONSTRAINT analytics_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TABLE analytics.metric_definitions (
    metric_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    metric_code                     varchar(100) NOT NULL,
    display_name                    varchar(160) NOT NULL,
    description                     text,
    category                        varchar(60) NOT NULL,
    source_model                    varchar(100) NOT NULL,
    measure_type                    varchar(30) NOT NULL,
    aggregation                     varchar(30) NOT NULL,
    formula                         jsonb NOT NULL,
    allowed_dimensions              text[] NOT NULL DEFAULT ARRAY[]::text[],
    format_options                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_system                       boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_metric_code UNIQUE (tenant_id, metric_code),
    CONSTRAINT uq_analytics_metric_tenant_id UNIQUE (tenant_id, metric_id),
    CONSTRAINT analytics_metric_type_check CHECK (measure_type IN ('money','integer','decimal','percentage','duration','boolean')),
    CONSTRAINT analytics_metric_aggregation_check CHECK (aggregation IN ('sum','count','count_distinct','avg','min','max','ratio','derived')),
    CONSTRAINT analytics_metric_formula_object CHECK (jsonb_typeof(formula) = 'object'),
    CONSTRAINT analytics_metric_code_not_blank CHECK (length(trim(metric_code)) > 0),
    CONSTRAINT analytics_metric_name_not_blank CHECK (length(trim(display_name)) > 0)
);

CREATE TABLE analytics.dashboard_definitions (
    dashboard_id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    dashboard_code                  varchar(100) NOT NULL,
    name                            varchar(160) NOT NULL,
    description                     text,
    audience                        varchar(30) NOT NULL DEFAULT 'tenant',
    company_id                      uuid,
    branch_id                       uuid,
    layout_config                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    default_filters                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_default                      boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    created_by_user_id              uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dashboard_code UNIQUE (tenant_id, dashboard_code),
    CONSTRAINT uq_analytics_dashboard_tenant_id UNIQUE (tenant_id, dashboard_id),
    CONSTRAINT analytics_dashboard_audience_check CHECK (audience IN ('tenant','company','branch','personal')),
    CONSTRAINT analytics_dashboard_scope_check CHECK (
        (audience = 'tenant' AND company_id IS NULL AND branch_id IS NULL) OR
        (audience = 'company' AND company_id IS NOT NULL AND branch_id IS NULL) OR
        (audience = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL) OR
        (audience = 'personal' AND created_by_user_id IS NOT NULL)
    ),
    CONSTRAINT analytics_dashboard_layout_object CHECK (jsonb_typeof(layout_config) = 'object'),
    CONSTRAINT analytics_dashboard_filters_object CHECK (jsonb_typeof(default_filters) = 'object')
);

CREATE TABLE analytics.dashboard_widgets (
    widget_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    dashboard_id                    uuid NOT NULL,
    widget_code                     varchar(100) NOT NULL,
    title                           varchar(160) NOT NULL,
    visualization                   varchar(30) NOT NULL,
    metric_codes                    text[] NOT NULL DEFAULT ARRAY[]::text[],
    dimension_codes                 text[] NOT NULL DEFAULT ARRAY[]::text[],
    query_config                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    position_x                      smallint NOT NULL DEFAULT 0,
    position_y                      smallint NOT NULL DEFAULT 0,
    width_units                     smallint NOT NULL DEFAULT 6,
    height_units                    smallint NOT NULL DEFAULT 4,
    refresh_interval_seconds        integer,
    is_visible                      boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_analytics_widget_dashboard FOREIGN KEY (tenant_id, dashboard_id)
        REFERENCES analytics.dashboard_definitions(tenant_id, dashboard_id) ON DELETE CASCADE,
    CONSTRAINT uq_analytics_widget_code UNIQUE (tenant_id, dashboard_id, widget_code),
    CONSTRAINT analytics_widget_visualization_check CHECK (visualization IN ('number','line','bar','stacked_bar','area','pie','table','heatmap','funnel')),
    CONSTRAINT analytics_widget_dimensions_check CHECK (width_units BETWEEN 1 AND 12 AND height_units BETWEEN 1 AND 20),
    CONSTRAINT analytics_widget_refresh_check CHECK (refresh_interval_seconds IS NULL OR refresh_interval_seconds BETWEEN 30 AND 86400),
    CONSTRAINT analytics_widget_query_object CHECK (jsonb_typeof(query_config) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Ingesta de eventos y checkpoints
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.ingestion_checkpoints (
    checkpoint_id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module                   varchar(80) NOT NULL,
    event_type                      varchar(160) NOT NULL,
    partition_key                   varchar(160) NOT NULL DEFAULT 'default',
    last_event_cursor               varchar(500),
    last_event_occurred_at          timestamptz,
    last_event_id                   uuid,
    checkpoint_data                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_checkpoint UNIQUE (tenant_id, source_module, event_type, partition_key)
);

CREATE TABLE analytics.event_inbox (
    inbox_id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module                   varchar(80) NOT NULL,
    event_id                        uuid NOT NULL,
    event_type                      varchar(160) NOT NULL,
    event_version                   smallint NOT NULL DEFAULT 1,
    occurred_at                     timestamptz NOT NULL,
    received_at                     timestamptz NOT NULL DEFAULT now(),
    payload_hash                    char(64) NOT NULL,
    normalized_payload              jsonb NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'pending',
    attempts                        integer NOT NULL DEFAULT 0,
    available_at                    timestamptz NOT NULL DEFAULT now(),
    locked_at                       timestamptz,
    locked_by                       varchar(160),
    processed_at                    timestamptz,
    last_error_code                 varchar(100),
    last_error_message              varchar(1000),
    CONSTRAINT uq_analytics_inbox_event UNIQUE (tenant_id, source_module, event_id),
    CONSTRAINT uq_analytics_inbox_tenant_id UNIQUE (tenant_id, inbox_id),
    CONSTRAINT analytics_inbox_version_positive CHECK (event_version > 0),
    CONSTRAINT analytics_inbox_hash_format CHECK (payload_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT analytics_inbox_status_check CHECK (status IN ('pending','processing','processed','failed','dead_letter')),
    CONSTRAINT analytics_inbox_attempts_nonnegative CHECK (attempts >= 0),
    CONSTRAINT analytics_inbox_payload_object CHECK (jsonb_typeof(normalized_payload) = 'object'),
    CONSTRAINT analytics_inbox_processing_fields CHECK (
        (status = 'processing' AND locked_at IS NOT NULL AND NULLIF(btrim(locked_by), '') IS NOT NULL AND processed_at IS NULL)
        OR
        (status <> 'processing' AND locked_at IS NULL AND locked_by IS NULL)
    ),
    CONSTRAINT analytics_inbox_processed_fields CHECK (
        (status = 'processed') = (processed_at IS NOT NULL)
    )
);

CREATE TABLE analytics.processed_events (
    processed_event_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module                   varchar(80) NOT NULL,
    event_id                        uuid NOT NULL,
    event_type                      varchar(160) NOT NULL,
    processed_at                    timestamptz NOT NULL DEFAULT now(),
    result_reference                uuid,
    result_summary                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_analytics_processed_event UNIQUE (tenant_id, source_module, event_id),
    CONSTRAINT analytics_processed_result_object CHECK (jsonb_typeof(result_summary) = 'object')
);

-- ---------------------------------------------------------------------------
-- 3. Dimensiones historicas (SCD tipo 2)
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.dim_companies (
    dimension_version_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    company_code                    varchar(80),
    company_name                    varchar(200) NOT NULL,
    legal_name                      varchar(240),
    country_code                    char(2),
    industry_code                   varchar(40),
    status                          varchar(30),
    valid_from                      timestamptz NOT NULL,
    valid_to                        timestamptz,
    is_current                      boolean NOT NULL DEFAULT true,
    source_event_id                 uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dim_company_version UNIQUE (tenant_id, company_id, dimension_version_id),
    CONSTRAINT analytics_dim_company_period CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_analytics_dim_company_current ON analytics.dim_companies (tenant_id, company_id) WHERE is_current;

CREATE TABLE analytics.dim_branches (
    dimension_version_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    branch_id                       uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_code                     varchar(80),
    branch_name                     varchar(200) NOT NULL,
    city                            varchar(120),
    region                          varchar(120),
    country_code                    char(2),
    timezone                        varchar(64),
    status                          varchar(30),
    valid_from                      timestamptz NOT NULL,
    valid_to                        timestamptz,
    is_current                      boolean NOT NULL DEFAULT true,
    source_event_id                 uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dim_branch_version UNIQUE (tenant_id, branch_id, dimension_version_id),
    CONSTRAINT analytics_dim_branch_period CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_analytics_dim_branch_current ON analytics.dim_branches (tenant_id, branch_id) WHERE is_current;

CREATE TABLE analytics.dim_products (
    dimension_version_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id                      uuid NOT NULL,
    sku                             varchar(100),
    product_name                    varchar(240) NOT NULL,
    category_id                     uuid,
    category_name                   varchar(160),
    brand_name                      varchar(160),
    product_type                    varchar(40),
    is_trackable                    boolean NOT NULL DEFAULT true,
    status                          varchar(30),
    valid_from                      timestamptz NOT NULL,
    valid_to                        timestamptz,
    is_current                      boolean NOT NULL DEFAULT true,
    source_event_id                 uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dim_product_version UNIQUE (tenant_id, product_id, dimension_version_id),
    CONSTRAINT analytics_dim_product_period CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_analytics_dim_product_current ON analytics.dim_products (tenant_id, product_id) WHERE is_current;

CREATE TABLE analytics.dim_customers (
    dimension_version_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    customer_id                     uuid NOT NULL,
    customer_code                   varchar(100),
    customer_type                   varchar(30),
    segment_code                    varchar(100),
    loyalty_tier_code               varchar(80),
    acquisition_channel              varchar(80),
    lifecycle_status                varchar(30),
    country_code                    char(2),
    valid_from                      timestamptz NOT NULL,
    valid_to                        timestamptz,
    is_current                      boolean NOT NULL DEFAULT true,
    source_event_id                 uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dim_customer_version UNIQUE (tenant_id, customer_id, dimension_version_id),
    CONSTRAINT analytics_dim_customer_period CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_analytics_dim_customer_current ON analytics.dim_customers (tenant_id, customer_id) WHERE is_current;

CREATE TABLE analytics.dim_employees (
    dimension_version_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id                     uuid NOT NULL,
    employee_code                   varchar(100),
    job_position_code               varchar(100),
    job_position_name               varchar(160),
    department_code                 varchar(100),
    department_name                 varchar(160),
    employment_type_code            varchar(60),
    status                          varchar(30),
    valid_from                      timestamptz NOT NULL,
    valid_to                        timestamptz,
    is_current                      boolean NOT NULL DEFAULT true,
    source_event_id                 uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_dim_employee_version UNIQUE (tenant_id, employee_id, dimension_version_id),
    CONSTRAINT analytics_dim_employee_period CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE UNIQUE INDEX uq_analytics_dim_employee_current ON analytics.dim_employees (tenant_id, employee_id) WHERE is_current;

-- ---------------------------------------------------------------------------
-- 4. Hechos analiticos: snapshots derivados de eventos de dominio
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.fact_sales (
    fact_sale_id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_sale_id                  uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    source_revision                 integer NOT NULL DEFAULT 1,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    customer_id                     uuid,
    cashier_user_id                 uuid,
    business_date                   date NOT NULL,
    sold_at                         timestamptz NOT NULL,
    currency_code                   char(3) NOT NULL,
    channel                         varchar(40),
    fulfillment_type                varchar(40),
    sale_status                     varchar(30) NOT NULL,
    items_count                     integer NOT NULL DEFAULT 0,
    subtotal_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    discount_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount                      numeric(20,6) NOT NULL DEFAULT 0,
    total_amount                    numeric(20,6) NOT NULL DEFAULT 0,
    refunded_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    net_amount                      numeric(20,6) NOT NULL DEFAULT 0,
    source_schema_version           integer NOT NULL DEFAULT 1,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_sale_revision UNIQUE (tenant_id, source_sale_id, source_revision),
    CONSTRAINT uq_analytics_fact_sale_tenant_id UNIQUE (tenant_id, fact_sale_id),
    CONSTRAINT analytics_fact_sale_amounts CHECK (
        subtotal_amount >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND
        total_amount >= 0 AND refunded_amount >= 0 AND net_amount >= 0
    ),
    CONSTRAINT analytics_fact_sale_counts CHECK (items_count >= 0 AND source_revision > 0 AND source_schema_version > 0),
    CONSTRAINT analytics_fact_sale_currency CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.fact_sale_lines (
    fact_sale_line_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    fact_sale_id                    uuid NOT NULL,
    source_sale_line_id             uuid NOT NULL,
    source_revision                 integer NOT NULL DEFAULT 1,
    product_id                      uuid,
    sku_snapshot                    varchar(100),
    product_name_snapshot           varchar(240) NOT NULL,
    category_id                     uuid,
    category_name_snapshot          varchar(160),
    quantity                        numeric(20,6) NOT NULL,
    unit_price                      numeric(20,6) NOT NULL,
    discount_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount                      numeric(20,6) NOT NULL DEFAULT 0,
    line_total                      numeric(20,6) NOT NULL,
    unit_cost_snapshot              numeric(20,6),
    gross_margin_snapshot           numeric(20,6),
    currency_code                   char(3) NOT NULL,
    business_date                   date NOT NULL,
    branch_id                       uuid NOT NULL,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_analytics_fact_sale_line_sale FOREIGN KEY (tenant_id, fact_sale_id)
        REFERENCES analytics.fact_sales(tenant_id, fact_sale_id) ON DELETE RESTRICT,
    CONSTRAINT uq_analytics_fact_sale_line_source UNIQUE (tenant_id, source_sale_line_id, source_revision),
    CONSTRAINT analytics_fact_sale_line_revision CHECK (source_revision > 0),
    CONSTRAINT analytics_fact_sale_line_amounts CHECK (
        quantity > 0 AND unit_price >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND line_total >= 0
    ),
    CONSTRAINT analytics_fact_sale_line_cost CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0),
    CONSTRAINT analytics_fact_sale_line_currency CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.fact_payments (
    fact_payment_id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_payment_transaction_id  uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    source_revision                 integer NOT NULL DEFAULT 1,
    source_sale_id                  uuid,
    company_id                      uuid NOT NULL,
    branch_id                       uuid,
    business_date                   date NOT NULL,
    occurred_at                     timestamptz NOT NULL,
    payment_method_code             varchar(60),
    provider_code                   varchar(80),
    transaction_status              varchar(30) NOT NULL,
    amount                          numeric(20,6) NOT NULL,
    fee_amount                      numeric(20,6) NOT NULL DEFAULT 0,
    currency_code                   char(3) NOT NULL,
    source_schema_version           integer NOT NULL DEFAULT 1,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_payment_revision UNIQUE (tenant_id, source_payment_transaction_id, source_revision),
    CONSTRAINT analytics_fact_payment_amounts CHECK (
        amount >= 0 AND fee_amount >= 0 AND source_revision > 0 AND source_schema_version > 0
    ),
    CONSTRAINT analytics_fact_payment_currency CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.fact_inventory_movements (
    fact_inventory_movement_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_movement_id              uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    warehouse_id                    uuid,
    product_id                      uuid NOT NULL,
    movement_type                   varchar(50) NOT NULL,
    quantity_delta                  numeric(20,6) NOT NULL,
    unit_cost_snapshot              numeric(20,6),
    total_cost_snapshot              numeric(20,6),
    currency_code                   char(3),
    business_date                   date NOT NULL,
    occurred_at                     timestamptz NOT NULL,
    source_reference_id             uuid,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_inventory_source UNIQUE (tenant_id, source_movement_id),
    CONSTRAINT analytics_fact_inventory_cost CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0),
    CONSTRAINT analytics_fact_inventory_total_cost CHECK (total_cost_snapshot IS NULL OR total_cost_snapshot >= 0),
    CONSTRAINT analytics_fact_inventory_currency CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.fact_purchase_receipts (
    fact_purchase_receipt_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_receipt_id               uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    supplier_id                     uuid,
    purchase_order_id               uuid,
    business_date                   date NOT NULL,
    received_at                     timestamptz NOT NULL,
    accepted_lines_count            integer NOT NULL DEFAULT 0,
    rejected_lines_count            integer NOT NULL DEFAULT 0,
    accepted_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    rejected_amount                 numeric(20,6) NOT NULL DEFAULT 0,
    currency_code                   char(3) NOT NULL,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_purchase_receipt UNIQUE (tenant_id, source_receipt_id),
    CONSTRAINT analytics_fact_purchase_counts CHECK (accepted_lines_count >= 0 AND rejected_lines_count >= 0),
    CONSTRAINT analytics_fact_purchase_amounts CHECK (accepted_amount >= 0 AND rejected_amount >= 0),
    CONSTRAINT analytics_fact_purchase_currency CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.fact_production_batches (
    fact_production_batch_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_production_batch_id      uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    recipe_id                       uuid,
    recipe_version_id               uuid,
    planned_quantity                numeric(20,6) NOT NULL,
    actual_quantity                 numeric(20,6) NOT NULL,
    waste_quantity                  numeric(20,6) NOT NULL DEFAULT 0,
    yield_percentage                numeric(9,4),
    business_date                   date NOT NULL,
    started_at                      timestamptz,
    completed_at                    timestamptz,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_production_batch UNIQUE (tenant_id, source_production_batch_id),
    CONSTRAINT analytics_fact_production_quantities CHECK (planned_quantity >= 0 AND actual_quantity >= 0 AND waste_quantity >= 0),
    CONSTRAINT analytics_fact_production_yield CHECK (yield_percentage IS NULL OR yield_percentage BETWEEN 0 AND 1000),
    CONSTRAINT analytics_fact_production_time CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE analytics.fact_kitchen_tickets (
    fact_kitchen_ticket_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_ticket_id                uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    source_order_id                 uuid,
    business_date                   date NOT NULL,
    received_at                     timestamptz NOT NULL,
    started_at                      timestamptz,
    ready_at                        timestamptz,
    dispatched_at                   timestamptz,
    ticket_status                   varchar(30) NOT NULL,
    items_count                     integer NOT NULL DEFAULT 0,
    preparation_seconds             integer,
    lateness_seconds                integer NOT NULL DEFAULT 0,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_kitchen_ticket UNIQUE (tenant_id, source_ticket_id),
    CONSTRAINT analytics_fact_kitchen_counts CHECK (items_count >= 0 AND lateness_seconds >= 0),
    CONSTRAINT analytics_fact_kitchen_durations CHECK (preparation_seconds IS NULL OR preparation_seconds >= 0),
    CONSTRAINT analytics_fact_kitchen_time_order CHECK (
        (started_at IS NULL OR started_at >= received_at) AND
        (ready_at IS NULL OR started_at IS NULL OR ready_at >= started_at) AND
        (dispatched_at IS NULL OR ready_at IS NULL OR dispatched_at >= ready_at)
    )
);

CREATE TABLE analytics.fact_workforce_attendance (
    fact_attendance_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_attendance_id            uuid NOT NULL,
    source_event_id                 uuid NOT NULL,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    employee_id                     uuid NOT NULL,
    business_date                   date NOT NULL,
    scheduled_minutes               integer NOT NULL DEFAULT 0,
    worked_minutes                  integer NOT NULL DEFAULT 0,
    late_minutes                    integer NOT NULL DEFAULT 0,
    overtime_minutes                integer NOT NULL DEFAULT 0,
    absence_minutes                 integer NOT NULL DEFAULT 0,
    attendance_status               varchar(30) NOT NULL,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_attendance UNIQUE (tenant_id, source_attendance_id),
    CONSTRAINT analytics_fact_attendance_minutes CHECK (
        scheduled_minutes >= 0 AND worked_minutes >= 0 AND late_minutes >= 0 AND
        overtime_minutes >= 0 AND absence_minutes >= 0
    )
);

CREATE TABLE analytics.fact_customer_activity (
    fact_customer_activity_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_event_id                 uuid NOT NULL,
    customer_id                     uuid,
    company_id                      uuid,
    branch_id                       uuid,
    activity_type                   varchar(60) NOT NULL,
    channel                         varchar(60),
    occurred_at                     timestamptz NOT NULL,
    business_date                   date NOT NULL,
    monetary_value                  numeric(20,6),
    currency_code                   char(3),
    attributes                      jsonb NOT NULL DEFAULT '{}'::jsonb,
    ingested_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_fact_customer_activity UNIQUE (tenant_id, source_event_id),
    CONSTRAINT analytics_fact_customer_activity_value CHECK (monetary_value IS NULL OR monetary_value >= 0),
    CONSTRAINT analytics_fact_customer_activity_currency CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT analytics_fact_customer_activity_attributes CHECK (jsonb_typeof(attributes) = 'object')
);

-- ---------------------------------------------------------------------------
-- 5. Agregados y cohortes
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.agg_branch_daily (
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    business_date                   date NOT NULL,
    currency_code                   char(3) NOT NULL,
    sales_count                     bigint NOT NULL DEFAULT 0,
    orders_count                    bigint NOT NULL DEFAULT 0,
    units_sold                      numeric(20,6) NOT NULL DEFAULT 0,
    gross_revenue                   numeric(20,6) NOT NULL DEFAULT 0,
    discounts                       numeric(20,6) NOT NULL DEFAULT 0,
    taxes                           numeric(20,6) NOT NULL DEFAULT 0,
    refunds                         numeric(20,6) NOT NULL DEFAULT 0,
    net_revenue                     numeric(20,6) NOT NULL DEFAULT 0,
    payment_fees                    numeric(20,6) NOT NULL DEFAULT 0,
    estimated_cost                 numeric(20,6),
    estimated_gross_profit          numeric(20,6),
    average_ticket                  numeric(20,6) NOT NULL DEFAULT 0,
    voided_sales_count              bigint NOT NULL DEFAULT 0,
    refreshed_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_analytics_agg_branch_daily PRIMARY KEY (tenant_id, company_id, branch_id, business_date, currency_code),
    CONSTRAINT analytics_agg_branch_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT analytics_agg_branch_counts CHECK (sales_count >= 0 AND orders_count >= 0 AND voided_sales_count >= 0),
    CONSTRAINT analytics_agg_branch_amounts CHECK (
        gross_revenue >= 0 AND discounts >= 0 AND taxes >= 0 AND refunds >= 0
        AND payment_fees >= 0 AND average_ticket >= 0
        AND (estimated_cost IS NULL OR estimated_cost >= 0)
    )
);

CREATE TABLE analytics.agg_product_daily (
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    product_id                      uuid NOT NULL,
    business_date                   date NOT NULL,
    currency_code                   char(3) NOT NULL,
    units_sold                      numeric(20,6) NOT NULL DEFAULT 0,
    gross_revenue                   numeric(20,6) NOT NULL DEFAULT 0,
    discounts                       numeric(20,6) NOT NULL DEFAULT 0,
    net_revenue                     numeric(20,6) NOT NULL DEFAULT 0,
    estimated_cost                  numeric(20,6),
    estimated_gross_profit          numeric(20,6),
    transactions_count              bigint NOT NULL DEFAULT 0,
    refreshed_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_analytics_agg_product_daily PRIMARY KEY (tenant_id, company_id, branch_id, product_id, business_date, currency_code),
    CONSTRAINT analytics_agg_product_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT analytics_agg_product_values CHECK (
        units_sold >= 0 AND gross_revenue >= 0 AND discounts >= 0 AND transactions_count >= 0
        AND (estimated_cost IS NULL OR estimated_cost >= 0)
    )
);

CREATE TABLE analytics.agg_employee_daily (
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    branch_id                       uuid NOT NULL,
    employee_id                     uuid NOT NULL,
    business_date                   date NOT NULL,
    shifts_count                    integer NOT NULL DEFAULT 0,
    scheduled_minutes               integer NOT NULL DEFAULT 0,
    worked_minutes                  integer NOT NULL DEFAULT 0,
    late_minutes                    integer NOT NULL DEFAULT 0,
    overtime_minutes                integer NOT NULL DEFAULT 0,
    absence_minutes                 integer NOT NULL DEFAULT 0,
    sales_attributed_count          bigint NOT NULL DEFAULT 0,
    sales_attributed_amount         numeric(20,6),
    currency_code                   char(3),
    refreshed_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_analytics_agg_employee_daily PRIMARY KEY (tenant_id, company_id, branch_id, employee_id, business_date),
    CONSTRAINT analytics_agg_employee_values CHECK (
        shifts_count >= 0 AND scheduled_minutes >= 0 AND worked_minutes >= 0 AND late_minutes >= 0 AND
        overtime_minutes >= 0 AND absence_minutes >= 0 AND sales_attributed_count >= 0
    ),
    CONSTRAINT analytics_agg_employee_currency CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$')
);

CREATE TABLE analytics.agg_customer_cohorts_monthly (
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                      uuid NOT NULL,
    cohort_month                    date NOT NULL,
    activity_month                  date NOT NULL,
    currency_code                   char(3) NOT NULL,
    acquired_customers              bigint NOT NULL DEFAULT 0,
    active_customers                bigint NOT NULL DEFAULT 0,
    repeat_customers                bigint NOT NULL DEFAULT 0,
    orders_count                    bigint NOT NULL DEFAULT 0,
    net_revenue                     numeric(20,6) NOT NULL DEFAULT 0,
    refreshed_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_analytics_customer_cohort_monthly PRIMARY KEY (tenant_id, company_id, cohort_month, activity_month, currency_code),
    CONSTRAINT analytics_customer_cohort_months CHECK (
        date_trunc('month', cohort_month)::date = cohort_month AND
        date_trunc('month', activity_month)::date = activity_month AND activity_month >= cohort_month
    ),
    CONSTRAINT analytics_customer_cohort_values CHECK (
        acquired_customers >= 0 AND active_customers >= 0 AND repeat_customers >= 0 AND orders_count >= 0 AND net_revenue >= 0
    ),
    CONSTRAINT analytics_customer_cohort_currency CHECK (currency_code ~ '^[A-Z]{3}$')
);

-- ---------------------------------------------------------------------------
-- 6. Refresco de modelos y auditoria analitica
-- ---------------------------------------------------------------------------

CREATE TABLE analytics.refresh_jobs (
    refresh_job_id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    job_code                        varchar(100) NOT NULL,
    display_name                    varchar(160) NOT NULL,
    model_name                      varchar(120) NOT NULL,
    refresh_strategy                varchar(20) NOT NULL DEFAULT 'incremental',
    schedule_expression             varchar(120),
    timezone                        varchar(64) NOT NULL DEFAULT 'America/Bogota',
    parameters                      jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_enabled                      boolean NOT NULL DEFAULT true,
    next_run_at                     timestamptz,
    last_run_at                     timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_analytics_refresh_job_code UNIQUE (tenant_id, job_code),
    CONSTRAINT uq_analytics_refresh_job_tenant_id UNIQUE (tenant_id, refresh_job_id),
    CONSTRAINT analytics_refresh_strategy CHECK (refresh_strategy IN ('full','incremental','partition')),
    CONSTRAINT analytics_refresh_parameters_object CHECK (jsonb_typeof(parameters) = 'object')
);

CREATE TABLE analytics.refresh_job_runs (
    refresh_job_run_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    refresh_job_id                  uuid NOT NULL,
    run_number                      bigint NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'queued',
    started_at                      timestamptz,
    completed_at                    timestamptz,
    rows_read                       bigint NOT NULL DEFAULT 0,
    rows_inserted                   bigint NOT NULL DEFAULT 0,
    rows_updated                    bigint NOT NULL DEFAULT 0,
    rows_rejected                   bigint NOT NULL DEFAULT 0,
    checkpoint_before               jsonb NOT NULL DEFAULT '{}'::jsonb,
    checkpoint_after                jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_code                      varchar(100),
    error_message                   varchar(1200),
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_analytics_refresh_run_job FOREIGN KEY (tenant_id, refresh_job_id)
        REFERENCES analytics.refresh_jobs(tenant_id, refresh_job_id) ON DELETE RESTRICT,
    CONSTRAINT uq_analytics_refresh_run_number UNIQUE (tenant_id, refresh_job_id, run_number),
    CONSTRAINT analytics_refresh_run_status CHECK (status IN ('queued','running','succeeded','failed','cancelled')),
    CONSTRAINT analytics_refresh_run_counts CHECK (rows_read >= 0 AND rows_inserted >= 0 AND rows_updated >= 0 AND rows_rejected >= 0),
    CONSTRAINT analytics_refresh_run_time CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT analytics_refresh_run_lifecycle CHECK (
        (status = 'queued' AND started_at IS NULL AND completed_at IS NULL)
        OR (status = 'running' AND started_at IS NOT NULL AND completed_at IS NULL)
        OR (status IN ('succeeded','failed','cancelled') AND started_at IS NOT NULL AND completed_at IS NOT NULL)
    ),
    CONSTRAINT analytics_refresh_run_checkpoint_objects CHECK (jsonb_typeof(checkpoint_before) = 'object' AND jsonb_typeof(checkpoint_after) = 'object')
);

CREATE TABLE analytics.query_audit_logs (
    query_audit_id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    actor_user_id                   uuid,
    company_id                      uuid,
    branch_id                       uuid,
    dashboard_id                   uuid,
    widget_id                       uuid,
    semantic_query_code             varchar(120) NOT NULL,
    query_fingerprint               char(64) NOT NULL,
    filters_hash                    char(64),
    executed_at                     timestamptz NOT NULL DEFAULT now(),
    duration_ms                     integer NOT NULL,
    rows_returned                   integer NOT NULL DEFAULT 0,
    cache_hit                       boolean NOT NULL DEFAULT false,
    outcome                         varchar(20) NOT NULL DEFAULT 'succeeded',
    error_code                      varchar(100),
    CONSTRAINT analytics_query_audit_fingerprint CHECK (query_fingerprint ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT analytics_query_audit_filters_hash CHECK (filters_hash IS NULL OR filters_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT analytics_query_audit_duration CHECK (duration_ms >= 0 AND rows_returned >= 0),
    CONSTRAINT analytics_query_audit_outcome CHECK (outcome IN ('succeeded','failed','denied','timeout'))
);

-- ---------------------------------------------------------------------------
-- 7. Indices operativos y analiticos
-- ---------------------------------------------------------------------------

CREATE INDEX ix_analytics_metric_category ON analytics.metric_definitions (tenant_id, category, is_active);
CREATE INDEX ix_analytics_dashboards_scope ON analytics.dashboard_definitions (tenant_id, audience, company_id, branch_id, is_active);
CREATE INDEX ix_analytics_widgets_dashboard_position ON analytics.dashboard_widgets (tenant_id, dashboard_id, position_y, position_x);
CREATE INDEX ix_analytics_inbox_pending ON analytics.event_inbox (tenant_id, available_at, received_at) WHERE status IN ('pending','failed');
CREATE INDEX ix_analytics_inbox_lease ON analytics.event_inbox (locked_at) WHERE status = 'processing';
CREATE INDEX ix_analytics_checkpoint_source ON analytics.ingestion_checkpoints (tenant_id, source_module, event_type);
CREATE INDEX ix_analytics_processed_events_recent ON analytics.processed_events (tenant_id, processed_at DESC);
CREATE INDEX ix_analytics_dim_branch_company ON analytics.dim_branches (tenant_id, company_id, is_current);
CREATE INDEX ix_analytics_dim_product_category ON analytics.dim_products (tenant_id, category_id, is_current);
CREATE INDEX ix_analytics_fact_sales_branch_date ON analytics.fact_sales (tenant_id, company_id, branch_id, business_date DESC);
CREATE INDEX ix_analytics_fact_sales_customer_date ON analytics.fact_sales (tenant_id, customer_id, business_date DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX ix_analytics_fact_sales_status_date ON analytics.fact_sales (tenant_id, sale_status, business_date DESC);
CREATE INDEX ix_analytics_fact_sale_lines_product_date ON analytics.fact_sale_lines (tenant_id, product_id, business_date DESC) WHERE product_id IS NOT NULL;
CREATE INDEX ix_analytics_fact_payments_date_method ON analytics.fact_payments (tenant_id, business_date DESC, payment_method_code);
CREATE INDEX ix_analytics_fact_inventory_product_date ON analytics.fact_inventory_movements (tenant_id, branch_id, product_id, business_date DESC);
CREATE INDEX ix_analytics_fact_purchase_branch_date ON analytics.fact_purchase_receipts (tenant_id, branch_id, business_date DESC);
CREATE INDEX ix_analytics_fact_production_branch_date ON analytics.fact_production_batches (tenant_id, branch_id, business_date DESC);
CREATE INDEX ix_analytics_fact_kitchen_branch_date ON analytics.fact_kitchen_tickets (tenant_id, branch_id, business_date DESC);
CREATE INDEX ix_analytics_fact_attendance_employee_date ON analytics.fact_workforce_attendance (tenant_id, employee_id, business_date DESC);
CREATE INDEX ix_analytics_fact_customer_activity_customer ON analytics.fact_customer_activity (tenant_id, customer_id, occurred_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX ix_analytics_agg_branch_date ON analytics.agg_branch_daily (tenant_id, business_date DESC, branch_id);
CREATE INDEX ix_analytics_agg_product_date ON analytics.agg_product_daily (tenant_id, product_id, business_date DESC);
CREATE INDEX ix_analytics_agg_employee_date ON analytics.agg_employee_daily (tenant_id, employee_id, business_date DESC);
CREATE INDEX ix_analytics_cohorts_month ON analytics.agg_customer_cohorts_monthly (tenant_id, company_id, cohort_month, activity_month);
CREATE INDEX ix_analytics_refresh_jobs_due ON analytics.refresh_jobs (tenant_id, next_run_at) WHERE is_enabled;
CREATE INDEX ix_analytics_refresh_runs_recent ON analytics.refresh_job_runs (tenant_id, refresh_job_id, created_at DESC);
CREATE INDEX ix_analytics_query_audit_recent ON analytics.query_audit_logs (tenant_id, executed_at DESC);
CREATE INDEX ix_analytics_query_audit_actor ON analytics.query_audit_logs (tenant_id, actor_user_id, executed_at DESC) WHERE actor_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Triggers de integridad, versionado e inmutabilidad
-- ---------------------------------------------------------------------------

CREATE TRIGGER trg_analytics_dim_company_period
BEFORE INSERT OR UPDATE ON analytics.dim_companies
FOR EACH ROW EXECUTE FUNCTION analytics.validate_dimension_period();
CREATE TRIGGER trg_analytics_dim_branch_period
BEFORE INSERT OR UPDATE ON analytics.dim_branches
FOR EACH ROW EXECUTE FUNCTION analytics.validate_dimension_period();
CREATE TRIGGER trg_analytics_dim_product_period
BEFORE INSERT OR UPDATE ON analytics.dim_products
FOR EACH ROW EXECUTE FUNCTION analytics.validate_dimension_period();
CREATE TRIGGER trg_analytics_dim_customer_period
BEFORE INSERT OR UPDATE ON analytics.dim_customers
FOR EACH ROW EXECUTE FUNCTION analytics.validate_dimension_period();
CREATE TRIGGER trg_analytics_dim_employee_period
BEFORE INSERT OR UPDATE ON analytics.dim_employees
FOR EACH ROW EXECUTE FUNCTION analytics.validate_dimension_period();

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'dim_companies', 'dim_branches', 'dim_products', 'dim_customers', 'dim_employees'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON analytics.%I FOR EACH ROW EXECUTE FUNCTION analytics.protect_dimension_history()',
            'trg_' || v_table || '_history', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_analytics_event_inbox_state
BEFORE INSERT OR UPDATE OR DELETE ON analytics.event_inbox
FOR EACH ROW EXECUTE FUNCTION analytics.validate_event_inbox_mutation();

CREATE TRIGGER trg_analytics_processed_events_immutable
BEFORE UPDATE OR DELETE ON analytics.processed_events
FOR EACH ROW EXECUTE FUNCTION analytics.prevent_append_only_mutation();
CREATE TRIGGER trg_analytics_query_audit_immutable
BEFORE UPDATE OR DELETE ON analytics.query_audit_logs
FOR EACH ROW EXECUTE FUNCTION analytics.prevent_append_only_mutation();

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'fact_sales','fact_sale_lines','fact_payments','fact_inventory_movements',
        'fact_purchase_receipts','fact_production_batches','fact_kitchen_tickets',
        'fact_workforce_attendance','fact_customer_activity'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON analytics.%I FOR EACH ROW EXECUTE FUNCTION analytics.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Inicializacion por tenant y metricas semanticas predeterminadas
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analytics.initialize_tenant_analytics(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM analytics.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO analytics.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO analytics.metric_definitions (
        tenant_id, metric_code, display_name, description, category,
        source_model, measure_type, aggregation, formula, allowed_dimensions,
        is_system, is_active
    ) VALUES
    (p_tenant_id, 'sales_gross_revenue', 'Ventas brutas', 'Importe bruto de ventas antes de descuentos y devoluciones.', 'sales', 'fact_sales', 'money', 'sum',
     '{"field":"subtotal_amount","filter":{"sale_status":["completed"]}}'::jsonb,
     ARRAY['company','branch','business_date','channel','currency'], true, true),
    (p_tenant_id, 'sales_net_revenue', 'Ventas netas', 'Importe neto después de descuentos y devoluciones.', 'sales', 'fact_sales', 'money', 'sum',
     '{"field":"net_amount","filter":{"sale_status":["completed"]}}'::jsonb,
     ARRAY['company','branch','business_date','channel','currency'], true, true),
    (p_tenant_id, 'sales_count', 'Cantidad de ventas', 'Número de ventas completadas.', 'sales', 'fact_sales', 'integer', 'count',
     '{"field":"fact_sale_id","filter":{"sale_status":["completed"]}}'::jsonb,
     ARRAY['company','branch','business_date','channel'], true, true),
    (p_tenant_id, 'average_ticket', 'Ticket promedio', 'Ventas netas divididas por cantidad de ventas.', 'sales', 'fact_sales', 'money', 'ratio',
     '{"numerator":"sales_net_revenue","denominator":"sales_count"}'::jsonb,
     ARRAY['company','branch','business_date','channel','currency'], true, true),
    (p_tenant_id, 'units_sold', 'Unidades vendidas', 'Unidades netas vendidas.', 'sales', 'fact_sale_lines', 'decimal', 'sum',
     '{"field":"quantity"}'::jsonb,
     ARRAY['company','branch','product','category','business_date'], true, true),
    (p_tenant_id, 'inventory_movement_count', 'Movimientos de inventario', 'Cantidad de movimientos de inventario recibidos.', 'inventory', 'fact_inventory_movements', 'integer', 'count',
     '{"field":"fact_inventory_movement_id"}'::jsonb,
     ARRAY['company','branch','product','movement_type','business_date'], true, true),
    (p_tenant_id, 'kitchen_avg_preparation_seconds', 'Tiempo promedio de preparación', 'Promedio de tiempo de preparación de comandas.', 'kitchen', 'fact_kitchen_tickets', 'duration', 'avg',
     '{"field":"preparation_seconds","filter":{"ticket_status":["ready","dispatched"]}}'::jsonb,
     ARRAY['company','branch','business_date'], true, true),
    (p_tenant_id, 'workforce_worked_minutes', 'Minutos trabajados', 'Minutos de asistencia registrados.', 'workforce', 'fact_workforce_attendance', 'integer', 'sum',
     '{"field":"worked_minutes"}'::jsonb,
     ARRAY['company','branch','employee','business_date'], true, true)
    ON CONFLICT (tenant_id, metric_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Triggers updated_at y proteccion tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','metric_definitions','dashboard_definitions','dashboard_widgets',
        'ingestion_checkpoints','refresh_jobs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON analytics.%I FOR EACH ROW EXECUTE FUNCTION analytics.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','metric_definitions','dashboard_definitions','dashboard_widgets','ingestion_checkpoints',
        'event_inbox','processed_events','dim_companies','dim_branches','dim_products',
        'dim_customers','dim_employees','fact_sales','fact_sale_lines','fact_payments',
        'fact_inventory_movements','fact_purchase_receipts','fact_production_batches',
        'fact_kitchen_tickets','fact_workforce_attendance','fact_customer_activity',
        'agg_branch_daily','agg_product_daily','agg_employee_daily','agg_customer_cohorts_monthly',
        'refresh_jobs','refresh_job_runs','query_audit_logs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON analytics.%I FOR EACH ROW EXECUTE FUNCTION analytics.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. RLS: todas las tablas se aislan por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','metric_definitions','dashboard_definitions','dashboard_widgets',
        'ingestion_checkpoints','event_inbox','processed_events','dim_companies',
        'dim_branches','dim_products','dim_customers','dim_employees','fact_sales',
        'fact_sale_lines','fact_payments','fact_inventory_movements','fact_purchase_receipts',
        'fact_production_batches','fact_kitchen_tickets','fact_workforce_attendance',
        'fact_customer_activity','agg_branch_daily','agg_product_daily','agg_employee_daily',
        'agg_customer_cohorts_monthly','refresh_jobs','refresh_job_runs','query_audit_logs'
    ] LOOP
        EXECUTE format('ALTER TABLE analytics.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE analytics.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON analytics.%I USING (tenant_id = analytics.current_tenant_id()) WITH CHECK (tenant_id = analytics.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Comentarios de propiedad y uso
-- ---------------------------------------------------------------------------

COMMENT ON TABLE analytics.event_inbox IS
'Inbox de eventos de dominio normalizados. El consumidor valida version, tenant y esquema antes de proyectar hechos analiticos.';
COMMENT ON TABLE analytics.dim_branches IS
'Dimension SCD tipo 2 de sucursales. Conserva los atributos historicos recibidos mediante contratos de Organization.';
COMMENT ON TABLE analytics.dim_products IS
'Dimension SCD tipo 2 de productos. Sus atributos son snapshots analiticos; Catalog sigue siendo la fuente maestra.';
COMMENT ON TABLE analytics.fact_sales IS
'Hechos analiticos derivados de eventos Sales. No reemplazan ni modifican la venta transaccional original.';
COMMENT ON TABLE analytics.fact_payments IS
'Hechos analiticos de pagos. Payments conserva las transacciones financieras originales.';
COMMENT ON TABLE analytics.fact_inventory_movements IS
'Hechos analiticos de movimientos. Inventory conserva el libro oficial de existencias.';
COMMENT ON TABLE analytics.agg_branch_daily IS
'Agregado diario por empresa, sucursal, fecha y moneda. Es una proyeccion reconstruible desde los hechos.';
COMMENT ON TABLE analytics.metric_definitions IS
'Catalogo semantico de metricas. formula es una definicion declarativa; no debe contener ni ejecutar SQL arbitrario.';
COMMENT ON TABLE analytics.query_audit_logs IS
'Auditoria append-only de consultas semanticas; no almacenar SQL literal, PII ni valores sensibles de filtros.';
COMMENT ON FUNCTION analytics.initialize_tenant_analytics(uuid) IS
'Inicializa la configuracion y las metricas de sistema para el tenant autenticado.';

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 18: ANALYTICS
-- ============================================================================
