-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 10: PAYMENTS (COBROS, TRANSACCIONES, CAPTURAS Y REEMBOLSOS)
-- Ubicacion del crate: crates/modules/payments
-- Motor objetivo: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants)
--   * Los modulos Sales, Cash, Finance, Customers e Integrations se conectan
--     mediante contratos publicos; no se crean FK fisicas hacia ellos.
--
-- RESPONSABILIDAD DE PAYMENTS:
--   * Configuracion de cuentas de proveedores de pago y metodos de pago.
--   * Sesiones de cobro, intents, intentos y transacciones aprobadas.
--   * Autorizaciones, capturas, anulaciones y reembolsos monetarios.
--   * Referencias tokenizadas de medios de pago (nunca PAN/CVV).
--   * Webhooks de proveedores, disputas y liquidaciones de procesadores.
--   * Idempotencia, Inbox y Outbox para integracion entre modulos/servicios.
--
-- FUERA DE ALCANCE:
--   * Pedidos, checks, ventas y devoluciones comerciales: sales.
--   * Apertura/cierre de caja, arqueos y movimientos de cajon: cash.
--   * Libro contable, cuentas por cobrar/pagar y conciliacion bancaria general:
--     finance.
--   * Clientes y datos maestros del cliente: customers.
--   * Credenciales/secretos de proveedores: KMS/Vault externo; aqui solo se
--     guardan referencias a secretos.
--   * Terminales/dispositivos fisicos: integrations/workforce.
--
-- LIMITES ENTRE MODULOS:
--   * Payments solo crea FK fisica a platform.tenants y a su propio schema.
--   * sale_id, order_id, sales_return_id, customer_id, company_id, branch_id,
--     user_id, terminal_id, cash_session_id y finance references son UUID
--     logicos validados por contratos/ports del modulo propietario.
--   * No se almacena PAN completo, CVV, PIN, track data ni credenciales de
--     proveedores. Usar token_reference y secret_ref opacos administrados por
--     un vault/token provider compatible con PCI DSS.
--   * El modulo Cash consume los eventos de cobros cash para registrar sus
--     movimientos de caja; Payments conserva la transaccion de pago.
--   * Finance consume eventos de cobro, reembolso y liquidacion para el mayor.
--
-- AISLAMIENTO:
--   * Todas las tablas tenant-scoped incluyen tenant_id y RLS + FORCE RLS.
--   * Cada transaccion autenticada ejecuta SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant se deriva de la sesion verificada; nunca confiar en el body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--
-- INSTALACION:
--   * Ejecutar despues de Platform. Los otros modulos pueden instalarse antes
--     o despues porque Payments no crea FK fisicas hacia ellos.
--   * No ejecutar sobre una base con el schema payments existente sin migracion.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS payments;

COMMENT ON SCHEMA payments IS
'Procesamiento y registro de pagos, autorizaciones, capturas, reembolsos, webhooks y liquidaciones de proveedores. No administra ventas, cajas ni contabilidad.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION payments.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION payments.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION payments.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Payments';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION payments.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre un evento compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION payments.guard_payment_transaction_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF ROW(NEW.tenant_id, NEW.payment_intent_id, NEW.payment_attempt_id,
           NEW.provider_account_id, NEW.transaction_type,
           NEW.provider_transaction_reference, NEW.authorization_code,
           NEW.amount, NEW.currency, NEW.card_brand_snapshot,
           NEW.card_last4_snapshot, NEW.method_code_snapshot, NEW.approved_at,
           NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.tenant_id, OLD.payment_intent_id, OLD.payment_attempt_id,
           OLD.provider_account_id, OLD.transaction_type,
           OLD.provider_transaction_reference, OLD.authorization_code,
           OLD.amount, OLD.currency, OLD.card_brand_snapshot,
           OLD.card_last4_snapshot, OLD.method_code_snapshot, OLD.approved_at,
           OLD.created_at) THEN
        RAISE EXCEPTION 'Los datos financieros base de una transaccion son inmutables';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion del modulo por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE payments.tenant_settings (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_currency            char(3) NOT NULL DEFAULT 'COP',
    allow_manual_capture        boolean NOT NULL DEFAULT true,
    require_idempotency_key     boolean NOT NULL DEFAULT true,
    refund_requires_approval    boolean NOT NULL DEFAULT true,
    max_refund_days             integer NOT NULL DEFAULT 90 CHECK (max_refund_days BETWEEN 0 AND 3650),
    webhook_max_attempts       smallint NOT NULL DEFAULT 12 CHECK (webhook_max_attempts BETWEEN 1 AND 100),
    settings                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_settings_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT payments_settings_json_object CHECK (jsonb_typeof(settings) = 'object'),
    CONSTRAINT payments_settings_tenant_unique UNIQUE (tenant_id),
    CONSTRAINT payments_settings_tenant_id_unique UNIQUE (tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- 2. Cuentas de proveedores de pago y asignacion de sucursales
-- ---------------------------------------------------------------------------

CREATE TABLE payments.provider_accounts (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid,
    provider_code               varchar(60) NOT NULL,
    account_code                varchar(80) NOT NULL,
    display_name                varchar(160) NOT NULL,
    environment                 varchar(12) NOT NULL DEFAULT 'test'
                                CHECK (environment IN ('test', 'live')),
    merchant_account_reference  varchar(180),
    credential_secret_ref       varchar(500) NOT NULL,
    webhook_secret_ref          varchar(500),
    account_status              varchar(20) NOT NULL DEFAULT 'pending'
                                CHECK (account_status IN ('pending', 'active', 'suspended', 'disabled', 'error')),
    supported_currencies        char(3)[] NOT NULL DEFAULT ARRAY['COP']::char(3)[],
    capabilities                jsonb NOT NULL DEFAULT '{}'::jsonb,
    safe_configuration          jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_verified_at            timestamptz,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT provider_accounts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT provider_accounts_code_unique UNIQUE (tenant_id, provider_code, account_code),
    CONSTRAINT provider_accounts_provider_not_blank CHECK (btrim(provider_code) <> ''),
    CONSTRAINT provider_accounts_account_not_blank CHECK (btrim(account_code) <> ''),
    CONSTRAINT provider_accounts_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT provider_accounts_secret_ref_not_blank CHECK (btrim(credential_secret_ref) <> ''),
    CONSTRAINT provider_accounts_currencies_nonempty CHECK (cardinality(supported_currencies) > 0),
    CONSTRAINT provider_accounts_json_objects CHECK (
        jsonb_typeof(capabilities) = 'object' AND jsonb_typeof(safe_configuration) = 'object'
    )
);

CREATE INDEX ix_provider_accounts_status
    ON payments.provider_accounts (tenant_id, account_status, provider_code);
CREATE INDEX ix_provider_accounts_company
    ON payments.provider_accounts (tenant_id, company_id, account_status);

CREATE TABLE payments.provider_account_branches (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_account_id uuid NOT NULL,
    branch_id           uuid NOT NULL,
    is_default          boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT provider_account_branches_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT provider_account_branches_unique UNIQUE (tenant_id, provider_account_id, branch_id),
    CONSTRAINT provider_account_branches_account_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_provider_account_branch_default
    ON payments.provider_account_branches (tenant_id, branch_id)
    WHERE is_default = true;
CREATE INDEX ix_provider_account_branches_branch
    ON payments.provider_account_branches (tenant_id, branch_id);

-- ---------------------------------------------------------------------------
-- 3. Metodos de pago y vinculo con proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_methods (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid,
    branch_id           uuid,
    scope_type          varchar(12) NOT NULL DEFAULT 'tenant'
                        CHECK (scope_type IN ('tenant', 'company', 'branch')),
    method_code         varchar(50) NOT NULL,
    display_name        varchar(120) NOT NULL,
    method_family       varchar(24) NOT NULL
                        CHECK (method_family IN ('cash', 'card', 'bank_transfer', 'digital_wallet', 'voucher', 'gift_card', 'credit', 'other')),
    entry_mode          varchar(20) NOT NULL DEFAULT 'any'
                        CHECK (entry_mode IN ('any', 'present', 'not_present', 'manual', 'external')),
    requires_provider   boolean NOT NULL DEFAULT false,
    supports_refunds    boolean NOT NULL DEFAULT true,
    supports_partial_refunds boolean NOT NULL DEFAULT true,
    is_active           boolean NOT NULL DEFAULT true,
    sort_order          integer NOT NULL DEFAULT 0,
    configuration       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT payment_methods_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_methods_scope_shape CHECK (
        (scope_type = 'tenant' AND company_id IS NULL AND branch_id IS NULL) OR
        (scope_type = 'company' AND company_id IS NOT NULL AND branch_id IS NULL) OR
        (scope_type = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL)
    ),
    CONSTRAINT payment_methods_code_not_blank CHECK (btrim(method_code) <> ''),
    CONSTRAINT payment_methods_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT payment_methods_provider_shape CHECK (requires_provider = false OR method_family <> 'cash'),
    CONSTRAINT payment_methods_configuration_object CHECK (jsonb_typeof(configuration) = 'object')
);

CREATE UNIQUE INDEX uq_payment_methods_scope_code
    ON payments.payment_methods (tenant_id, scope_type, COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(branch_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(method_code))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_payment_methods_active_scope
    ON payments.payment_methods (tenant_id, scope_type, company_id, branch_id, is_active, sort_order)
    WHERE deleted_at IS NULL;

CREATE TABLE payments.payment_method_provider_accounts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_method_id   uuid NOT NULL,
    provider_account_id uuid NOT NULL,
    provider_method_code varchar(100),
    priority            smallint NOT NULL DEFAULT 1 CHECK (priority > 0),
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT method_provider_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT method_provider_pair_unique UNIQUE (tenant_id, payment_method_id, provider_account_id),
    CONSTRAINT method_provider_method_fk FOREIGN KEY (tenant_id, payment_method_id)
        REFERENCES payments.payment_methods (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT method_provider_account_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_method_provider_active
    ON payments.payment_method_provider_accounts (tenant_id, payment_method_id, is_active, priority);

-- ---------------------------------------------------------------------------
-- 4. Referencias tokenizadas de medios de pago del cliente
-- ---------------------------------------------------------------------------

CREATE TABLE payments.customer_payment_tokens (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    customer_id                 uuid NOT NULL,
    provider_account_id         uuid NOT NULL,
    provider_token_reference    varchar(240) NOT NULL,
    token_type                  varchar(24) NOT NULL
                                CHECK (token_type IN ('card', 'bank_account', 'wallet', 'other')),
    card_brand                  varchar(40),
    card_last4                  char(4),
    card_exp_month              smallint CHECK (card_exp_month IS NULL OR card_exp_month BETWEEN 1 AND 12),
    card_exp_year               smallint CHECK (card_exp_year IS NULL OR card_exp_year BETWEEN 2000 AND 2200),
    cardholder_name             varchar(160),
    token_status                varchar(16) NOT NULL DEFAULT 'active'
                                CHECK (token_status IN ('active', 'expired', 'revoked', 'failed')),
    is_default                  boolean NOT NULL DEFAULT false,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    revoked_at                  timestamptz,
    CONSTRAINT customer_payment_tokens_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT customer_payment_tokens_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT customer_payment_tokens_ref_not_blank CHECK (btrim(provider_token_reference) <> ''),
    CONSTRAINT customer_payment_tokens_last4_shape CHECK (card_last4 IS NULL OR card_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT customer_payment_tokens_revoked_shape CHECK (
        (token_status = 'revoked' AND revoked_at IS NOT NULL) OR
        (token_status <> 'revoked' AND revoked_at IS NULL)
    )
);

CREATE UNIQUE INDEX uq_customer_provider_token
    ON payments.customer_payment_tokens (tenant_id, provider_account_id, provider_token_reference);
CREATE UNIQUE INDEX uq_customer_default_payment_token
    ON payments.customer_payment_tokens (tenant_id, customer_id, token_type)
    WHERE is_default = true AND token_status = 'active';
CREATE INDEX ix_customer_payment_tokens_customer
    ON payments.customer_payment_tokens (tenant_id, customer_id, token_status);

-- ---------------------------------------------------------------------------
-- 5. Sesiones de cobro: agregan uno o varios metodos (split tender)
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_sessions (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    session_number          varchar(80) NOT NULL,
    sale_id                 uuid,
    order_id                uuid,
    customer_id             uuid,
    currency                char(3) NOT NULL,
    amount_due              numeric(19,4) NOT NULL CHECK (amount_due > 0),
    session_status          varchar(20) NOT NULL DEFAULT 'open'
                            CHECK (session_status IN ('open', 'partially_paid', 'paid', 'cancelled', 'expired', 'failed')),
    expires_at              timestamptz,
    opened_by_user_id       uuid,
    completed_at            timestamptz,
    cancelled_at            timestamptz,
    cancellation_reason     text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_sessions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_sessions_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT payment_sessions_tenant_company_branch_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT payment_sessions_number_unique UNIQUE (tenant_id, branch_id, session_number),
    CONSTRAINT payment_sessions_sale_or_order CHECK (sale_id IS NOT NULL OR order_id IS NOT NULL),
    CONSTRAINT payment_sessions_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_sessions_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT payment_sessions_completed_shape CHECK (
        (session_status <> 'paid') OR completed_at IS NOT NULL
    ),
    CONSTRAINT payment_sessions_cancelled_shape CHECK (
        (session_status <> 'cancelled') OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL)
    )
);

CREATE INDEX ix_payment_sessions_branch_status
    ON payments.payment_sessions (tenant_id, branch_id, session_status, created_at DESC);
CREATE INDEX ix_payment_sessions_sale
    ON payments.payment_sessions (tenant_id, sale_id)
    WHERE sale_id IS NOT NULL;
CREATE INDEX ix_payment_sessions_order
    ON payments.payment_sessions (tenant_id, order_id)
    WHERE order_id IS NOT NULL;

CREATE UNIQUE INDEX uq_payment_session_active_sale
    ON payments.payment_sessions (tenant_id, sale_id)
    WHERE sale_id IS NOT NULL AND session_status IN ('open', 'partially_paid');
CREATE UNIQUE INDEX uq_payment_session_active_order
    ON payments.payment_sessions (tenant_id, order_id)
    WHERE order_id IS NOT NULL AND session_status IN ('open', 'partially_paid');

-- ---------------------------------------------------------------------------
-- 6. Intents e intentos de comunicacion con la pasarela
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_intents (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_session_id      uuid NOT NULL,
    payment_method_id       uuid NOT NULL,
    provider_account_id     uuid,
    customer_payment_token_id uuid,
    intent_number           varchar(80) NOT NULL,
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    capture_mode            varchar(12) NOT NULL DEFAULT 'automatic'
                            CHECK (capture_mode IN ('automatic', 'manual')),
    intent_status           varchar(24) NOT NULL DEFAULT 'created'
                            CHECK (intent_status IN ('created', 'requires_action', 'processing', 'authorized', 'partially_captured', 'captured', 'failed', 'cancelled', 'expired', 'partially_refunded', 'refunded')),
    provider_intent_reference varchar(240),
    description             varchar(240),
    idempotency_key         varchar(255) NOT NULL,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    expires_at              timestamptz,
    CONSTRAINT payment_intents_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_intents_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT payment_intents_tenant_session_id_unique UNIQUE (tenant_id, payment_session_id, id),
    CONSTRAINT payment_intents_number_unique UNIQUE (tenant_id, intent_number),
    CONSTRAINT payment_intents_idempotency_unique UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT payment_intents_session_fk FOREIGN KEY (tenant_id, payment_session_id, currency)
        REFERENCES payments.payment_sessions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_intents_method_fk FOREIGN KEY (tenant_id, payment_method_id)
        REFERENCES payments.payment_methods (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_intents_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_intents_token_fk FOREIGN KEY (tenant_id, customer_payment_token_id)
        REFERENCES payments.customer_payment_tokens (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_intents_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_intents_idempotency_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT payment_intents_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT payment_intents_expiration_shape CHECK (
        expires_at IS NULL OR expires_at > created_at
    )
);

CREATE INDEX ix_payment_intents_session_status
    ON payments.payment_intents (tenant_id, payment_session_id, intent_status, created_at);
CREATE INDEX ix_payment_intents_provider_reference
    ON payments.payment_intents (tenant_id, provider_account_id, provider_intent_reference)
    WHERE provider_intent_reference IS NOT NULL;

CREATE TABLE payments.payment_attempts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_intent_id       uuid NOT NULL,
    provider_account_id     uuid,
    attempt_number          smallint NOT NULL CHECK (attempt_number > 0),
    attempt_status          varchar(20) NOT NULL DEFAULT 'started'
                            CHECK (attempt_status IN ('started', 'pending', 'requires_action', 'succeeded', 'failed', 'cancelled', 'timed_out')),
    provider_request_id     varchar(240),
    provider_payment_reference varchar(240),
    request_idempotency_key varchar(255) NOT NULL,
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    response_code           varchar(100),
    failure_code            varchar(100),
    failure_message         text,
    safe_response           jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at              timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_attempts_tenant_intent_id_unique UNIQUE (tenant_id, payment_intent_id, id),
    CONSTRAINT payment_attempts_tenant_intent_currency_id_unique
        UNIQUE (tenant_id, payment_intent_id, id, currency),
    CONSTRAINT payment_attempts_number_unique UNIQUE (tenant_id, payment_intent_id, attempt_number),
    CONSTRAINT payment_attempts_idempotency_unique UNIQUE (tenant_id, request_idempotency_key),
    CONSTRAINT payment_attempts_intent_fk FOREIGN KEY (tenant_id, payment_intent_id, currency)
        REFERENCES payments.payment_intents (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_attempts_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_attempts_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_attempts_idempotency_not_blank CHECK (btrim(request_idempotency_key) <> ''),
    CONSTRAINT payment_attempts_response_object CHECK (jsonb_typeof(safe_response) = 'object'),
    CONSTRAINT payment_attempts_completed_shape CHECK (
        (attempt_status IN ('started', 'pending', 'requires_action') AND completed_at IS NULL) OR
        (attempt_status IN ('succeeded', 'failed', 'cancelled', 'timed_out') AND completed_at IS NOT NULL)
    )
);

CREATE INDEX ix_payment_attempts_intent
    ON payments.payment_attempts (tenant_id, payment_intent_id, attempt_number DESC);

-- ---------------------------------------------------------------------------
-- 7. Libro de transacciones aprobadas/autorizadas
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_transactions (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_intent_id       uuid NOT NULL,
    payment_attempt_id      uuid,
    provider_account_id     uuid,
    transaction_type        varchar(16) NOT NULL
                            CHECK (transaction_type IN ('sale', 'authorization', 'adjustment')),
    transaction_status      varchar(24) NOT NULL
                            CHECK (transaction_status IN ('authorized', 'captured', 'partially_captured', 'partially_refunded', 'refunded', 'voided')),
    provider_transaction_reference varchar(240),
    authorization_code      varchar(120),
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    card_brand_snapshot     varchar(40),
    card_last4_snapshot     char(4),
    method_code_snapshot    varchar(50) NOT NULL,
    approved_at             timestamptz,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_transactions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_transactions_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT payment_transactions_tenant_intent_id_unique UNIQUE (tenant_id, payment_intent_id, id),
    CONSTRAINT payment_transactions_intent_fk FOREIGN KEY (tenant_id, payment_intent_id, currency)
        REFERENCES payments.payment_intents (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_transactions_attempt_fk
        FOREIGN KEY (tenant_id, payment_intent_id, payment_attempt_id, currency)
        REFERENCES payments.payment_attempts (tenant_id, payment_intent_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_transactions_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_transactions_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_transactions_last4_shape CHECK (card_last4_snapshot IS NULL OR card_last4_snapshot ~ '^[0-9]{4}$'),
    CONSTRAINT payment_transactions_method_not_blank CHECK (btrim(method_code_snapshot) <> ''),
    CONSTRAINT payment_transactions_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT payment_transactions_approved_shape CHECK (approved_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_payment_transaction_attempt
    ON payments.payment_transactions (tenant_id, payment_attempt_id)
    WHERE payment_attempt_id IS NOT NULL;
CREATE UNIQUE INDEX uq_payment_provider_transaction_reference
    ON payments.payment_transactions (tenant_id, provider_account_id, provider_transaction_reference)
    WHERE provider_account_id IS NOT NULL AND provider_transaction_reference IS NOT NULL;
CREATE INDEX ix_payment_transactions_intent
    ON payments.payment_transactions (tenant_id, payment_intent_id, created_at);
CREATE INDEX ix_payment_transactions_status_date
    ON payments.payment_transactions (tenant_id, transaction_status, created_at DESC);

-- ---------------------------------------------------------------------------
-- 8. Capturas de fondos (una autorizacion puede tener varias capturas)
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_captures (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_transaction_id  uuid NOT NULL,
    capture_number          smallint NOT NULL CHECK (capture_number > 0),
    capture_status           varchar(16) NOT NULL DEFAULT 'pending'
                            CHECK (capture_status IN ('pending', 'succeeded', 'failed', 'reversed')),
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    provider_capture_reference varchar(240),
    idempotency_key         varchar(255) NOT NULL,
    requested_at            timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    failure_code            varchar(100),
    failure_message         text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_captures_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_captures_number_unique UNIQUE (tenant_id, payment_transaction_id, capture_number),
    CONSTRAINT payment_captures_idempotency_unique UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT payment_captures_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id, currency)
        REFERENCES payments.payment_transactions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_captures_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_captures_idempotency_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT payment_captures_completed_shape CHECK (
        (capture_status = 'pending' AND completed_at IS NULL) OR
        (capture_status <> 'pending' AND completed_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_payment_provider_capture_reference
    ON payments.payment_captures (tenant_id, provider_capture_reference)
    WHERE provider_capture_reference IS NOT NULL;
CREATE INDEX ix_payment_captures_transaction_status
    ON payments.payment_captures (tenant_id, payment_transaction_id, capture_status);

-- ---------------------------------------------------------------------------
-- 9. Reembolsos y sus intentos
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_refunds (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_transaction_id  uuid NOT NULL,
    payment_session_id      uuid,
    sales_return_id         uuid,
    refund_number           varchar(80) NOT NULL,
    refund_status           varchar(20) NOT NULL DEFAULT 'requested'
                            CHECK (refund_status IN ('requested', 'pending', 'succeeded', 'failed', 'rejected', 'cancelled')),
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    reason_code             varchar(60),
    reason                  text NOT NULL,
    requested_by_user_id    uuid,
    approved_by_user_id     uuid,
    requested_at            timestamptz NOT NULL DEFAULT now(),
    approved_at             timestamptz,
    completed_at            timestamptz,
    provider_refund_reference varchar(240),
    idempotency_key         varchar(255) NOT NULL,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_refunds_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_refunds_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT payment_refunds_number_unique UNIQUE (tenant_id, refund_number),
    CONSTRAINT payment_refunds_idempotency_unique UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT payment_refunds_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id, currency)
        REFERENCES payments.payment_transactions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_refunds_session_fk
        FOREIGN KEY (tenant_id, payment_session_id, currency)
        REFERENCES payments.payment_sessions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_refunds_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_refunds_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT payment_refunds_idempotency_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT payment_refunds_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT payment_refunds_approval_shape CHECK (
        approved_at IS NOT NULL OR refund_status IN ('requested', 'rejected', 'cancelled')
    ),
    CONSTRAINT payment_refunds_approval_actor_shape CHECK (
        (approved_at IS NULL) = (approved_by_user_id IS NULL)
    ),
    CONSTRAINT payment_refunds_completed_shape CHECK (
        (refund_status IN ('succeeded', 'failed', 'rejected', 'cancelled') AND completed_at IS NOT NULL) OR
        (refund_status IN ('requested', 'pending') AND completed_at IS NULL)
    )
);

CREATE UNIQUE INDEX uq_payment_provider_refund_reference
    ON payments.payment_refunds (tenant_id, provider_refund_reference)
    WHERE provider_refund_reference IS NOT NULL;
CREATE INDEX ix_payment_refunds_transaction_status
    ON payments.payment_refunds (tenant_id, payment_transaction_id, refund_status, requested_at DESC);
CREATE INDEX ix_payment_refunds_sales_return
    ON payments.payment_refunds (tenant_id, sales_return_id)
    WHERE sales_return_id IS NOT NULL;

CREATE TABLE payments.payment_refund_attempts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_refund_id       uuid NOT NULL,
    provider_account_id     uuid,
    attempt_number          smallint NOT NULL CHECK (attempt_number > 0),
    attempt_status          varchar(16) NOT NULL DEFAULT 'started'
                            CHECK (attempt_status IN ('started', 'pending', 'succeeded', 'failed', 'timed_out')),
    provider_request_id     varchar(240),
    provider_refund_reference varchar(240),
    request_idempotency_key varchar(255) NOT NULL,
    response_code           varchar(100),
    failure_code            varchar(100),
    failure_message         text,
    safe_response           jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at              timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_refund_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_refund_attempts_number_unique UNIQUE (tenant_id, payment_refund_id, attempt_number),
    CONSTRAINT payment_refund_attempts_idempotency_unique UNIQUE (tenant_id, request_idempotency_key),
    CONSTRAINT payment_refund_attempts_refund_fk FOREIGN KEY (tenant_id, payment_refund_id)
        REFERENCES payments.payment_refunds (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_refund_attempts_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_refund_attempts_response_object CHECK (jsonb_typeof(safe_response) = 'object'),
    CONSTRAINT payment_refund_attempts_completed_shape CHECK (
        (attempt_status IN ('started', 'pending') AND completed_at IS NULL) OR
        (attempt_status IN ('succeeded', 'failed', 'timed_out') AND completed_at IS NOT NULL)
    )
);

CREATE INDEX ix_payment_refund_attempts_refund
    ON payments.payment_refund_attempts (tenant_id, payment_refund_id, attempt_number DESC);

-- ---------------------------------------------------------------------------
-- 10. Anulaciones de autorizaciones (void)
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_voids (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_transaction_id  uuid NOT NULL,
    void_status             varchar(16) NOT NULL DEFAULT 'requested'
                            CHECK (void_status IN ('requested', 'pending', 'succeeded', 'failed')),
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    reason                  text NOT NULL,
    provider_void_reference varchar(240),
    idempotency_key         varchar(255) NOT NULL,
    requested_by_user_id    uuid,
    requested_at            timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    failure_code            varchar(100),
    failure_message         text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_voids_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_voids_transaction_unique UNIQUE (tenant_id, payment_transaction_id),
    CONSTRAINT payment_voids_idempotency_unique UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT payment_voids_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id, currency)
        REFERENCES payments.payment_transactions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_voids_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_voids_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT payment_voids_completed_shape CHECK (
        (void_status IN ('requested', 'pending') AND completed_at IS NULL) OR
        (void_status IN ('succeeded', 'failed') AND completed_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_payment_provider_void_reference
    ON payments.payment_voids (tenant_id, provider_void_reference)
    WHERE provider_void_reference IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 11. Disputas / contracargos
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_disputes (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_transaction_id  uuid NOT NULL,
    provider_account_id     uuid NOT NULL,
    provider_dispute_reference varchar(240) NOT NULL,
    dispute_status          varchar(20) NOT NULL DEFAULT 'open'
                            CHECK (dispute_status IN ('open', 'evidence_required', 'under_review', 'won', 'lost', 'accepted', 'closed')),
    dispute_reason_code     varchar(80),
    dispute_reason          text,
    amount                  numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                char(3) NOT NULL,
    response_due_at         timestamptz,
    evidence_submitted_at   timestamptz,
    resolved_at             timestamptz,
    provider_payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_disputes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_disputes_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT payment_disputes_provider_ref_unique UNIQUE (tenant_id, provider_account_id, provider_dispute_reference),
    CONSTRAINT payment_disputes_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id, currency)
        REFERENCES payments.payment_transactions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT payment_disputes_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_disputes_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payment_disputes_provider_payload_object CHECK (jsonb_typeof(provider_payload) = 'object'),
    CONSTRAINT payment_disputes_resolved_shape CHECK (
        (dispute_status IN ('won', 'lost', 'accepted', 'closed') AND resolved_at IS NOT NULL) OR
        (dispute_status IN ('open', 'evidence_required', 'under_review') AND resolved_at IS NULL)
    )
);

CREATE INDEX ix_payment_disputes_due
    ON payments.payment_disputes (tenant_id, dispute_status, response_due_at)
    WHERE response_due_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 12. Historiales de estados
-- ---------------------------------------------------------------------------

CREATE TABLE payments.payment_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_intent_id   uuid NOT NULL,
    old_status          varchar(24),
    new_status          varchar(24) NOT NULL,
    change_reason       text,
    actor_user_id       uuid,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT payment_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_status_history_intent_fk FOREIGN KEY (tenant_id, payment_intent_id)
        REFERENCES payments.payment_intents (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_status_history_status_shape CHECK (
        new_status IN ('created', 'requires_action', 'processing', 'authorized',
                       'partially_captured', 'captured', 'failed', 'cancelled',
                       'expired', 'partially_refunded', 'refunded')
        AND (old_status IS NULL OR old_status IN (
            'created', 'requires_action', 'processing', 'authorized',
            'partially_captured', 'captured', 'failed', 'cancelled',
            'expired', 'partially_refunded', 'refunded'
        ))
    ),
    CONSTRAINT payment_status_history_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX ix_payment_status_history_intent
    ON payments.payment_status_history (tenant_id, payment_intent_id, occurred_at DESC);

CREATE TABLE payments.payment_transaction_status_history (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_transaction_id  uuid NOT NULL,
    old_status              varchar(24),
    new_status              varchar(24) NOT NULL
                            CHECK (new_status IN ('authorized', 'captured', 'partially_captured',
                                'partially_refunded', 'refunded', 'voided')),
    change_reason           text,
    actor_user_id           uuid,
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT payment_transaction_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payment_transaction_status_history_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id)
        REFERENCES payments.payment_transactions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT payment_transaction_status_history_old_status_check
        CHECK (old_status IS NULL OR old_status IN ('authorized', 'captured',
            'partially_captured', 'partially_refunded', 'refunded', 'voided')),
    CONSTRAINT payment_transaction_status_history_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX ix_payment_transaction_status_history
    ON payments.payment_transaction_status_history
       (tenant_id, payment_transaction_id, occurred_at DESC);

CREATE TABLE payments.refund_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payment_refund_id   uuid NOT NULL,
    old_status          varchar(20),
    new_status          varchar(20) NOT NULL,
    change_reason       text,
    actor_user_id       uuid,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT refund_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT refund_status_history_refund_fk FOREIGN KEY (tenant_id, payment_refund_id)
        REFERENCES payments.payment_refunds (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT refund_status_history_status_shape CHECK (
        new_status IN ('requested', 'pending', 'succeeded', 'failed', 'rejected', 'cancelled')
        AND (old_status IS NULL OR old_status IN (
            'requested', 'pending', 'succeeded', 'failed', 'rejected', 'cancelled'
        ))
    ),
    CONSTRAINT refund_status_history_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX ix_refund_status_history_refund
    ON payments.refund_status_history (tenant_id, payment_refund_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 13. Webhooks de proveedores (inbox externo)
-- ---------------------------------------------------------------------------

CREATE TABLE payments.provider_webhook_events (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_account_id     uuid NOT NULL,
    provider_event_reference varchar(240) NOT NULL,
    event_type              varchar(160) NOT NULL,
    signature_valid         boolean NOT NULL DEFAULT false,
    processing_status       varchar(18) NOT NULL DEFAULT 'received'
                            CHECK (processing_status IN ('received', 'verified', 'processing', 'processed', 'ignored', 'failed')),
    safe_payload            jsonb NOT NULL,
    received_at             timestamptz NOT NULL DEFAULT now(),
    processed_at            timestamptz,
    processing_attempts     smallint NOT NULL DEFAULT 0 CHECK (processing_attempts >= 0),
    last_error              text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT provider_webhook_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT provider_webhook_events_provider_event_unique UNIQUE (tenant_id, provider_account_id, provider_event_reference),
    CONSTRAINT provider_webhook_events_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT provider_webhook_events_event_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT provider_webhook_events_payload_object CHECK (jsonb_typeof(safe_payload) = 'object'),
    CONSTRAINT provider_webhook_events_processed_shape CHECK (
        (processing_status = 'processed' AND processed_at IS NOT NULL) OR
        (processing_status <> 'processed')
    )
);

CREATE INDEX ix_provider_webhook_events_pending
    ON payments.provider_webhook_events (tenant_id, processing_status, received_at)
    WHERE processing_status IN ('received', 'verified', 'failed');

-- ---------------------------------------------------------------------------
-- 14. Liquidaciones de proveedores (no sustituye conciliacion bancaria Finance)
-- ---------------------------------------------------------------------------

CREATE TABLE payments.settlement_batches (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_account_id     uuid NOT NULL,
    settlement_reference    varchar(240) NOT NULL,
    settlement_status       varchar(20) NOT NULL DEFAULT 'received'
                            CHECK (settlement_status IN ('received', 'processing', 'reconciled', 'discrepancy', 'cancelled')),
    currency                char(3) NOT NULL,
    gross_amount            numeric(19,4) NOT NULL DEFAULT 0 CHECK (gross_amount >= 0),
    fee_amount              numeric(19,4) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
    adjustment_amount       numeric(19,4) NOT NULL DEFAULT 0,
    net_amount              numeric(19,4) NOT NULL DEFAULT 0,
    settlement_date         date NOT NULL,
    provider_payout_reference varchar(240),
    received_at             timestamptz NOT NULL DEFAULT now(),
    reconciled_at           timestamptz,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlement_batches_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT settlement_batches_tenant_id_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT settlement_batches_provider_ref_unique UNIQUE (tenant_id, provider_account_id, settlement_reference),
    CONSTRAINT settlement_batches_provider_fk FOREIGN KEY (tenant_id, provider_account_id)
        REFERENCES payments.provider_accounts (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT settlement_batches_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT settlement_batches_net_consistent CHECK (net_amount = gross_amount - fee_amount + adjustment_amount),
    CONSTRAINT settlement_batches_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT settlement_batches_reconciled_shape CHECK (
        (settlement_status = 'reconciled' AND reconciled_at IS NOT NULL) OR
        (settlement_status <> 'reconciled')
    )
);

CREATE INDEX ix_settlement_batches_provider_date
    ON payments.settlement_batches (tenant_id, provider_account_id, settlement_date DESC, settlement_status);

CREATE TABLE payments.settlement_batch_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    settlement_batch_id     uuid NOT NULL,
    payment_transaction_id  uuid,
    payment_refund_id       uuid,
    payment_dispute_id      uuid,
    line_type               varchar(16) NOT NULL
                            CHECK (line_type IN ('payment', 'refund', 'fee', 'adjustment', 'chargeback')),
    provider_line_reference varchar(240),
    gross_amount            numeric(19,4) NOT NULL DEFAULT 0,
    fee_amount              numeric(19,4) NOT NULL DEFAULT 0,
    net_amount              numeric(19,4) NOT NULL,
    currency                char(3) NOT NULL,
    line_description       text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlement_batch_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT settlement_batch_lines_batch_fk
        FOREIGN KEY (tenant_id, settlement_batch_id, currency)
        REFERENCES payments.settlement_batches (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT settlement_batch_lines_transaction_fk
        FOREIGN KEY (tenant_id, payment_transaction_id, currency)
        REFERENCES payments.payment_transactions (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT settlement_batch_lines_refund_fk
        FOREIGN KEY (tenant_id, payment_refund_id, currency)
        REFERENCES payments.payment_refunds (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT settlement_batch_lines_dispute_fk
        FOREIGN KEY (tenant_id, payment_dispute_id, currency)
        REFERENCES payments.payment_disputes (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT settlement_batch_lines_source_shape CHECK (
        (line_type = 'payment' AND payment_transaction_id IS NOT NULL
            AND payment_refund_id IS NULL AND payment_dispute_id IS NULL) OR
        (line_type = 'refund' AND payment_refund_id IS NOT NULL
            AND payment_transaction_id IS NULL AND payment_dispute_id IS NULL) OR
        (line_type = 'chargeback' AND payment_dispute_id IS NOT NULL
            AND payment_transaction_id IS NULL AND payment_refund_id IS NULL) OR
        (line_type IN ('fee', 'adjustment') AND payment_transaction_id IS NULL
            AND payment_refund_id IS NULL AND payment_dispute_id IS NULL)
    ),
    CONSTRAINT settlement_batch_lines_net_consistent CHECK (net_amount = gross_amount - fee_amount),
    CONSTRAINT settlement_batch_lines_currency_upper CHECK (currency = upper(currency))
);

CREATE INDEX ix_settlement_batch_lines_batch
    ON payments.settlement_batch_lines (tenant_id, settlement_batch_id);
CREATE INDEX ix_settlement_batch_lines_transaction
    ON payments.settlement_batch_lines (tenant_id, payment_transaction_id)
    WHERE payment_transaction_id IS NOT NULL;
CREATE INDEX ix_settlement_batch_lines_dispute
    ON payments.settlement_batch_lines (tenant_id, payment_dispute_id)
    WHERE payment_dispute_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 15. Idempotencia, Inbox y Outbox para integracion asincrona
-- ---------------------------------------------------------------------------

CREATE TABLE payments.idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_code      varchar(100) NOT NULL,
    idempotency_key     varchar(255) NOT NULL,
    request_hash        char(64) NOT NULL,
    processing_status   varchar(20) NOT NULL DEFAULT 'in_progress'
                        CHECK (processing_status IN ('in_progress', 'succeeded', 'failed')),
    resource_type       varchar(80),
    resource_id         uuid,
    response_status     smallint CHECK (response_status IS NULL OR response_status BETWEEN 100 AND 599),
    error_code          varchar(100),
    expires_at          timestamptz NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_idempotency_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payments_idempotency_scope_unique UNIQUE (tenant_id, operation_code, idempotency_key),
    CONSTRAINT payments_idempotency_operation_not_blank CHECK (btrim(operation_code) <> ''),
    CONSTRAINT payments_idempotency_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT payments_idempotency_hash_shape CHECK (request_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT payments_idempotency_expiration CHECK (expires_at > created_at),
    CONSTRAINT payments_idempotency_success_shape CHECK (
        processing_status <> 'succeeded' OR
        (resource_type IS NOT NULL AND resource_id IS NOT NULL AND response_status IS NOT NULL)
    )
);

CREATE INDEX ix_payments_idempotency_expiration
    ON payments.idempotency_records (expires_at);

CREATE TABLE payments.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_name       varchar(120) NOT NULL,
    event_id            uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    processing_status   varchar(16) NOT NULL DEFAULT 'processing'
                        CHECK (processing_status IN ('processing', 'processed', 'failed', 'ignored')),
    received_at         timestamptz NOT NULL DEFAULT now(),
    processed_at        timestamptz,
    error_message       text,
    CONSTRAINT payments_processed_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payments_processed_events_unique UNIQUE (tenant_id, consumer_name, event_id),
    CONSTRAINT payments_processed_events_consumer_not_blank CHECK (btrim(consumer_name) <> ''),
    CONSTRAINT payments_processed_events_type_not_blank CHECK (btrim(event_type) <> '')
);

CREATE INDEX ix_payments_processed_events_status
    ON payments.processed_events (tenant_id, processing_status, received_at);

CREATE TABLE payments.event_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type      varchar(100) NOT NULL,
    aggregate_id        uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    event_version       smallint NOT NULL DEFAULT 1 CHECK (event_version > 0),
    payload             jsonb NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    available_at        timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    publish_status      varchar(16) NOT NULL DEFAULT 'pending'
                        CHECK (publish_status IN ('pending', 'publishing', 'published', 'retry', 'dead_letter')),
    publish_attempts    integer NOT NULL DEFAULT 0 CHECK (publish_attempts >= 0),
    last_error          text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_event_outbox_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT payments_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT payments_event_outbox_published_shape CHECK (
        (publish_status = 'published' AND published_at IS NOT NULL) OR
        (publish_status <> 'published')
    )
);

CREATE INDEX ix_payments_event_outbox_pending
    ON payments.event_outbox (available_at, created_at)
    WHERE publish_status IN ('pending', 'retry');
CREATE INDEX ix_payments_event_outbox_aggregate
    ON payments.event_outbox (tenant_id, aggregate_type, aggregate_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 16. Triggers: updated_at, tenant inmutable y registros append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_accounts', 'payment_methods',
        'payment_method_provider_accounts', 'customer_payment_tokens',
        'payment_sessions', 'payment_intents', 'payment_attempts',
        'payment_captures', 'payment_refunds', 'payment_refund_attempts',
        'payment_voids', 'payment_disputes', 'provider_webhook_events',
        'settlement_batches', 'idempotency_records', 'event_outbox'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON payments.%I FOR EACH ROW EXECUTE FUNCTION payments.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_accounts', 'provider_account_branches',
        'payment_methods', 'payment_method_provider_accounts',
        'customer_payment_tokens', 'payment_sessions', 'payment_intents',
        'payment_attempts', 'payment_transactions', 'payment_captures',
        'payment_refunds', 'payment_refund_attempts', 'payment_voids',
        'payment_disputes', 'payment_status_history', 'refund_status_history',
        'payment_transaction_status_history',
        'provider_webhook_events', 'settlement_batches', 'settlement_batch_lines',
        'processed_events', 'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON payments.%I FOR EACH ROW EXECUTE FUNCTION payments.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

-- Los datos base de una transaccion son inmutables, pero transaction_status
-- puede avanzar (authorized -> captured -> partially_refunded/refunded/voided).
-- Los cambios quedan trazados en payment_status_history o en los registros
-- de captura/reembolso/anulacion. La fila financiera no puede borrarse.
CREATE TRIGGER trg_payment_transactions_guard_update
BEFORE UPDATE ON payments.payment_transactions
FOR EACH ROW EXECUTE FUNCTION payments.guard_payment_transaction_update();

CREATE TRIGGER trg_payment_transactions_no_delete
BEFORE DELETE ON payments.payment_transactions
FOR EACH ROW EXECUTE FUNCTION payments.prevent_append_only_mutation();

-- Historiales y lineas de liquidacion son append-only.
DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'payment_status_history', 'payment_transaction_status_history',
        'refund_status_history', 'settlement_batch_lines'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON payments.%I FOR EACH ROW EXECUTE FUNCTION payments.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 17. Row Level Security: todas las tablas aisladas por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_accounts', 'provider_account_branches',
        'payment_methods', 'payment_method_provider_accounts',
        'customer_payment_tokens', 'payment_sessions', 'payment_intents',
        'payment_attempts', 'payment_transactions', 'payment_captures',
        'payment_refunds', 'payment_refund_attempts', 'payment_voids',
        'payment_disputes', 'payment_status_history',
        'payment_transaction_status_history', 'refund_status_history',
        'provider_webhook_events', 'settlement_batches', 'settlement_batch_lines',
        'processed_events', 'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE payments.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE payments.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON payments.%I USING (tenant_id = payments.current_tenant_id()) WITH CHECK (tenant_id = payments.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 18. Inicializacion idempotente de metodos base por tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION payments.initialize_tenant_payments(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF payments.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO payments.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO payments.payment_methods (
        tenant_id, scope_type, method_code, display_name, method_family,
        entry_mode, requires_provider, supports_refunds, supports_partial_refunds,
        is_active, sort_order
    ) VALUES
        (p_tenant_id, 'tenant', 'cash', 'Efectivo', 'cash', 'manual', false, true, true, true, 10),
        (p_tenant_id, 'tenant', 'card_present', 'Tarjeta presencial', 'card', 'present', true, true, true, true, 20),
        (p_tenant_id, 'tenant', 'card_not_present', 'Tarjeta no presencial', 'card', 'not_present', true, true, true, true, 30),
        (p_tenant_id, 'tenant', 'bank_transfer', 'Transferencia bancaria', 'bank_transfer', 'external', false, true, false, true, 40),
        (p_tenant_id, 'tenant', 'digital_wallet', 'Billetera digital', 'digital_wallet', 'external', true, true, true, true, 50),
        (p_tenant_id, 'tenant', 'voucher', 'Vale', 'voucher', 'manual', false, false, false, true, 60),
        (p_tenant_id, 'tenant', 'gift_card', 'Tarjeta regalo', 'gift_card', 'manual', false, true, true, true, 70)
    ON CONFLICT DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 19. Comentarios de propiedad, PCI y contratos
-- ---------------------------------------------------------------------------

COMMENT ON TABLE payments.provider_accounts IS
'Configuracion no secreta de una cuenta de pasarela. credential_secret_ref y webhook_secret_ref son referencias opacas a KMS/Vault; nunca guardar secretos en claro.';
COMMENT ON TABLE payments.payment_methods IS
'Catalogo de medios de pago del tenant. Cash registra la operacion de caja; Finance contabiliza los efectos financieros.';
COMMENT ON TABLE payments.customer_payment_tokens IS
'Tokens opacos de proveedores. No almacenar PAN completo, CVV, PIN, track data ni datos sensibles de autenticacion.';
COMMENT ON TABLE payments.payment_sessions IS
'Sesion de cobro asociada a sale_id u order_id logicos. Permite dividir el pago entre varios intents/metodos (split tender).';
COMMENT ON TABLE payments.payment_intents IS
'Intencion de cobrar un monto y moneda con un metodo. Puede tener varios intentos tecnicos ante un proveedor.';
COMMENT ON TABLE payments.payment_transactions IS
'Libro inmutable de operaciones aprobadas/autorizadas. Los errores tecnicos viven en payment_attempts; el estado avanza con trazabilidad en payment_transaction_status_history.';
COMMENT ON TABLE payments.payment_captures IS
'Capturas de una autorizacion. La suma de capturas exitosas no debe superar la autorizacion; validarlo transaccionalmente en application con bloqueo de fila.';
COMMENT ON TABLE payments.payment_refunds IS
'Solicitud y resultado monetario del reembolso. sales_return_id es referencia logica a Sales; no FK cruzada.';
COMMENT ON TABLE payments.settlement_batches IS
'Liquidaciones reportadas por el proveedor de pagos; no sustituye la conciliacion bancaria/contable propiedad de Finance.';
COMMENT ON TABLE payments.provider_webhook_events IS
'Inbox de webhooks. safe_payload debe estar depurado; verificar firma, tenant, cuenta y event id antes de procesar.';
COMMENT ON TABLE payments.event_outbox IS
'Eventos de Payments publicados despues del commit. El worker debe reclamar filas con SELECT ... FOR UPDATE SKIP LOCKED.';

-- Permisos que deben registrarse en identity.permissions (Identity es propietario):
--   payments.methods.read / payments.methods.manage
--   payments.providers.read / payments.providers.manage
--   payments.sessions.read / payments.sessions.create / payments.sessions.cancel
--   payments.intents.read / payments.intents.create
--   payments.transactions.read / payments.transactions.capture / payments.transactions.void
--   payments.refunds.read / payments.refunds.create / payments.refunds.approve
--   payments.disputes.read / payments.disputes.manage
--   payments.settlements.read / payments.settlements.reconcile
--   payments.tokens.manage
-- La aplicacion valida tambien el plan/modulo 'payments' y el alcance del
-- usuario sobre company_id/branch_id. RLS solo garantiza aislamiento por tenant.
--
-- Eventos sugeridos para crates/contracts/events:
--   payments.payment_session_created.v1
--   payments.payment_authorized.v1
--   payments.payment_captured.v1
--   payments.payment_failed.v1
--   payments.payment_voided.v1
--   payments.refund_requested.v1
--   payments.refund_succeeded.v1
--   payments.refund_failed.v1
--   payments.dispute_opened.v1
--   payments.settlement_reconciled.v1
-- Consumidores:
--   Sales: estado de cobro del check/venta y estado del flujo de reembolso.
--   Cash: registro de entradas/salidas en caja y cierres de turno (incluido efectivo).
--   Finance: asientos contables, comisiones, liquidaciones y conciliacion.
--   Customers: actualizacion de historial de pago si aplica.
--
-- IMPORTANTE:
--   * La suma de capturas/reembolsos y el estado de la sesion se validan en
--     application bajo transacciones y bloqueos; un CHECK SQL no puede validar
--     sumas concurrentes entre varias filas.
--   * Una respuesta HTTP del proveedor no basta: verificar webhooks y consultar
--     estado remoto ante timeouts ambiguos antes de reintentar operaciones.
--   * El sistema debe usar TLS, validar firmas, proteger secretos y aplicar
--     controles PCI DSS segun el flujo y proveedor elegido.
--
-- Ejemplo de contexto RLS e inicializacion:
-- BEGIN;
-- SET LOCAL app.tenant_id = 'UUID_DEL_TENANT_AUTORIZADO';
-- SELECT payments.initialize_tenant_payments('UUID_DEL_TENANT_AUTORIZADO'::uuid);
-- COMMIT;
-- ============================================================================

COMMIT;
