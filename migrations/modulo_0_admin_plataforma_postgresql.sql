-- ============================================================================
-- POS SaaS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 0: ADMINISTRACION CENTRAL DE LA PLATAFORMA (SUPERADMIN)
-- Motor: PostgreSQL 15+ recomendado
--
-- Alcance:
--   * Identidades y permisos de administradores de la plataforma.
--   * Registro central de tenants (cuentas/clientes SaaS).
--   * Planes, suscripciones, módulos y límites contratados.
--   * Dominios, aprovisionamiento, soporte, facturación SaaS y auditoría.
--
-- Fuera del alcance de este módulo:
--   * Datos legales/operativos de la empresa y sus sucursales.
--   * Usuarios y roles de cada empresa cliente.
--   * Productos, ventas, cajas e inventario.
--
-- El Módulo 1 creará sus tablas propias (por ejemplo, organization.companies
-- y organization.branches) y las relacionará con platform.tenants.id.
-- platform.tenants representa la cuenta SaaS; NO sustituye el perfil legal
-- de empresa que será propiedad del Módulo 1.
--
-- Seguridad:
--   * password_hash debe contener un hash Argon2id calculado por la aplicación.
--   * Nunca almacenar contraseñas, refresh tokens ni secretos en texto plano.
--   * Los secretos globales se guardan en un gestor externo; aquí solo su referencia.
--   * No se crea un superadministrador con contraseña predeterminada.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS platform;

COMMENT ON SCHEMA platform IS
'Plano de control SaaS: superadministradores, tenants, planes, suscripciones y auditoría.';

-- ---------------------------------------------------------------------------
-- Funciones comunes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION platform.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION platform.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'platform.audit_logs es inmutable: no se permite UPDATE ni DELETE';
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Administradores de la plataforma (identidades separadas de los clientes)
-- ---------------------------------------------------------------------------

CREATE TABLE platform.admins (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email               varchar(320) NOT NULL,
    display_name        varchar(160) NOT NULL,
    password_hash       text NOT NULL,
    status              varchar(20) NOT NULL DEFAULT 'invited'
                        CHECK (status IN ('invited', 'active', 'locked', 'disabled')),
    mfa_required        boolean NOT NULL DEFAULT true,
    mfa_enabled         boolean NOT NULL DEFAULT false,
    last_login_at       timestamptz,
    password_changed_at timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT admins_email_not_blank CHECK (btrim(email) <> ''),
    CONSTRAINT admins_display_name_not_blank CHECK (btrim(display_name) <> '')
);

CREATE UNIQUE INDEX uq_platform_admins_email_active
    ON platform.admins (lower(email))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_platform_admins_status
    ON platform.admins (status)
    WHERE deleted_at IS NULL;

CREATE TABLE platform.roles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        varchar(80) NOT NULL UNIQUE,
    name        varchar(120) NOT NULL,
    description text,
    is_system   boolean NOT NULL DEFAULT false,
    is_active   boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT roles_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT roles_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE platform.permissions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        varchar(120) NOT NULL UNIQUE,
    description text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_code_not_blank CHECK (btrim(code) <> '')
);

CREATE TABLE platform.role_permissions (
    role_id       uuid NOT NULL REFERENCES platform.roles(id) ON DELETE RESTRICT,
    permission_id uuid NOT NULL REFERENCES platform.permissions(id) ON DELETE RESTRICT,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE platform.admin_role_assignments (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id               uuid NOT NULL REFERENCES platform.admins(id) ON DELETE RESTRICT,
    role_id                uuid NOT NULL REFERENCES platform.roles(id) ON DELETE RESTRICT,
    assigned_by_admin_id   uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    assigned_at            timestamptz NOT NULL DEFAULT now(),
    revoked_at             timestamptz,
    revoked_by_admin_id    uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    CONSTRAINT admin_role_assignment_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at)
);

CREATE UNIQUE INDEX uq_active_admin_role_assignment
    ON platform.admin_role_assignments (admin_id, role_id)
    WHERE revoked_at IS NULL;

CREATE INDEX ix_admin_role_assignments_admin
    ON platform.admin_role_assignments (admin_id, revoked_at);

CREATE TABLE platform.admin_sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id            uuid NOT NULL REFERENCES platform.admins(id) ON DELETE RESTRICT,
    refresh_token_hash  text NOT NULL UNIQUE,
    ip_address          inet,
    user_agent          text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    last_seen_at        timestamptz,
    expires_at          timestamptz NOT NULL,
    revoked_at          timestamptz,
    CONSTRAINT admin_session_expiration CHECK (expires_at > created_at),
    CONSTRAINT admin_session_revocation CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

CREATE INDEX ix_admin_sessions_admin_active
    ON platform.admin_sessions (admin_id, expires_at)
    WHERE revoked_at IS NULL;

-- Factores MFA. Los secretos TOTP deben cifrarse en la aplicación con una
-- clave administrada por KMS/Vault; nunca guardar el secreto descifrado.
CREATE TABLE platform.admin_mfa_factors (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id          uuid NOT NULL REFERENCES platform.admins(id) ON DELETE RESTRICT,
    factor_type       varchar(20) NOT NULL CHECK (factor_type IN ('totp', 'webauthn')),
    label             varchar(120),
    secret_ciphertext bytea,
    credential_id     text,
    public_key        bytea,
    metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,
    verified_at       timestamptz,
    last_used_at      timestamptz,
    revoked_at        timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT admin_mfa_factor_material CHECK (
        (factor_type = 'totp' AND secret_ciphertext IS NOT NULL)
        OR
        (factor_type = 'webauthn' AND credential_id IS NOT NULL AND public_key IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_admin_webauthn_credential
    ON platform.admin_mfa_factors (credential_id)
    WHERE factor_type = 'webauthn' AND revoked_at IS NULL;

CREATE INDEX ix_admin_mfa_factors_admin_active
    ON platform.admin_mfa_factors (admin_id, factor_type)
    WHERE revoked_at IS NULL;

-- Los códigos de recuperación se almacenan como hashes, nunca en texto plano.
CREATE TABLE platform.admin_recovery_codes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id    uuid NOT NULL REFERENCES platform.admins(id) ON DELETE RESTRICT,
    code_hash   text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    used_at     timestamptz,
    CONSTRAINT recovery_code_hash_not_blank CHECK (btrim(code_hash) <> '')
);

CREATE INDEX ix_admin_recovery_codes_admin_unused
    ON platform.admin_recovery_codes (admin_id)
    WHERE used_at IS NULL;

CREATE TABLE platform.admin_auth_events (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id       uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    email_attempted varchar(320),
    event_type     varchar(40) NOT NULL
                   CHECK (event_type IN ('login_success', 'login_failure', 'logout', 'mfa_success', 'mfa_failure', 'password_changed', 'session_revoked', 'account_locked')),
    ip_address     inet,
    user_agent     text,
    details        jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_admin_auth_events_admin_time
    ON platform.admin_auth_events (admin_id, occurred_at DESC);

CREATE INDEX ix_admin_auth_events_email_time
    ON platform.admin_auth_events (lower(email_attempted), occurred_at DESC)
    WHERE email_attempted IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. Registro central de tenants (cuentas SaaS)
-- ---------------------------------------------------------------------------

CREATE TABLE platform.tenants (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_code           varchar(40) NOT NULL UNIQUE,
    slug                  varchar(100) NOT NULL UNIQUE,
    display_name          varchar(180) NOT NULL,
    primary_contact_email varchar(320) NOT NULL,
    status                varchar(20) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'provisioning', 'active', 'suspended', 'closed')),
    default_locale        varchar(20) NOT NULL DEFAULT 'es-CO',
    timezone              varchar(80) NOT NULL DEFAULT 'UTC',
    region_code           varchar(10),
    created_by_admin_id   uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    status_reason         text,
    activated_at          timestamptz,
    suspended_at          timestamptz,
    closed_at             timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tenants_code_not_blank CHECK (btrim(tenant_code) <> ''),
    CONSTRAINT tenants_slug_not_blank CHECK (btrim(slug) <> ''),
    CONSTRAINT tenants_display_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT tenants_contact_email_not_blank CHECK (btrim(primary_contact_email) <> '')
);

CREATE INDEX ix_tenants_status_created
    ON platform.tenants (status, created_at DESC);

CREATE INDEX ix_tenants_contact_email
    ON platform.tenants (lower(primary_contact_email));

CREATE TABLE platform.tenant_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    old_status          varchar(20),
    new_status          varchar(20) NOT NULL
                        CHECK (new_status IN ('pending', 'provisioning', 'active', 'suspended', 'closed')),
    reason              text,
    changed_by_admin_id uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    changed_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_tenant_status_history_tenant_time
    ON platform.tenant_status_history (tenant_id, changed_at DESC);

CREATE TABLE platform.tenant_domains (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    domain        varchar(253) NOT NULL,
    status        varchar(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'verified', 'disabled')),
    is_primary    boolean NOT NULL DEFAULT false,
    verified_at   timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tenant_domain_not_blank CHECK (btrim(domain) <> '')
);

CREATE UNIQUE INDEX uq_tenant_domains_domain
    ON platform.tenant_domains (lower(domain));

CREATE UNIQUE INDEX uq_tenant_primary_domain
    ON platform.tenant_domains (tenant_id)
    WHERE is_primary = true AND status = 'verified';

CREATE INDEX ix_tenant_domains_tenant
    ON platform.tenant_domains (tenant_id, status);

-- ---------------------------------------------------------------------------
-- 3. Catálogo de planes, módulos y límites
-- ---------------------------------------------------------------------------

CREATE TABLE platform.plans (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             varchar(60) NOT NULL UNIQUE,
    name             varchar(120) NOT NULL,
    description      text,
    billing_interval varchar(20) NOT NULL
                     CHECK (billing_interval IN ('monthly', 'yearly', 'one_time')),
    price_amount     numeric(14,2) NOT NULL DEFAULT 0 CHECK (price_amount >= 0),
    currency         char(3) NOT NULL DEFAULT 'COP',
    trial_days       integer NOT NULL DEFAULT 0 CHECK (trial_days >= 0),
    is_active        boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT plans_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT plans_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT plans_currency_upper CHECK (currency = upper(currency))
);

CREATE INDEX ix_plans_active
    ON platform.plans (is_active, name);

CREATE TABLE platform.modules (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code         varchar(80) NOT NULL UNIQUE,
    name         varchar(120) NOT NULL,
    description  text,
    is_core      boolean NOT NULL DEFAULT false,
    is_available boolean NOT NULL DEFAULT true,
    sort_order   integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT modules_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT modules_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE platform.module_dependencies (
    module_id          uuid NOT NULL REFERENCES platform.modules(id) ON DELETE RESTRICT,
    requires_module_id uuid NOT NULL REFERENCES platform.modules(id) ON DELETE RESTRICT,
    PRIMARY KEY (module_id, requires_module_id),
    CONSTRAINT module_cannot_require_itself CHECK (module_id <> requires_module_id)
);

CREATE TABLE platform.plan_modules (
    plan_id     uuid NOT NULL REFERENCES platform.plans(id) ON DELETE RESTRICT,
    module_id   uuid NOT NULL REFERENCES platform.modules(id) ON DELETE RESTRICT,
    is_enabled  boolean NOT NULL DEFAULT true,
    settings    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (plan_id, module_id)
);

CREATE TABLE platform.plan_limits (
    plan_id     uuid NOT NULL REFERENCES platform.plans(id) ON DELETE RESTRICT,
    limit_code  varchar(80) NOT NULL,
    limit_value bigint,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (plan_id, limit_code),
    CONSTRAINT plan_limit_non_negative CHECK (limit_value IS NULL OR limit_value >= 0),
    CONSTRAINT plan_limit_code_not_blank CHECK (btrim(limit_code) <> '')
);

-- Anulación específica de un módulo para un tenant.
-- enabled_override NULL = heredar lo definido en el plan.
CREATE TABLE platform.tenant_module_overrides (
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    module_id         uuid NOT NULL REFERENCES platform.modules(id) ON DELETE RESTRICT,
    enabled_override  boolean,
    reason            text NOT NULL,
    changed_by_admin_id uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    expires_at        timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, module_id),
    CONSTRAINT tenant_module_override_reason CHECK (btrim(reason) <> '')
);

CREATE INDEX ix_tenant_module_overrides_expiration
    ON platform.tenant_module_overrides (expires_at)
    WHERE expires_at IS NOT NULL;

-- Anulación individual de límites.
-- Si existe una fila y limit_value es NULL, el límite queda ilimitado.
CREATE TABLE platform.tenant_limit_overrides (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    limit_code          varchar(80) NOT NULL,
    limit_value         bigint,
    reason              text NOT NULL,
    changed_by_admin_id uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    expires_at          timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, limit_code),
    CONSTRAINT tenant_limit_override_non_negative CHECK (limit_value IS NULL OR limit_value >= 0),
    CONSTRAINT tenant_limit_override_reason CHECK (btrim(reason) <> '')
);

-- ---------------------------------------------------------------------------
-- 4. Suscripciones e historial
-- ---------------------------------------------------------------------------

CREATE TABLE platform.subscriptions (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    plan_id               uuid NOT NULL REFERENCES platform.plans(id) ON DELETE RESTRICT,
    status                varchar(20) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'trialing', 'active', 'past_due', 'paused', 'cancelled', 'expired')),
    current_period_start  timestamptz,
    current_period_end    timestamptz,
    trial_ends_at         timestamptz,
    grace_until           timestamptz,
    cancel_at_period_end  boolean NOT NULL DEFAULT false,
    cancelled_at          timestamptz,
    external_provider     varchar(60),
    external_customer_ref varchar(180),
    external_subscription_ref varchar(180),
    metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT subscription_period_valid CHECK (
        current_period_start IS NULL OR current_period_end IS NULL OR current_period_end > current_period_start
    )
);

-- Una sola suscripción vigente por tenant. Las suscripciones históricas se conservan.
CREATE UNIQUE INDEX uq_tenant_current_subscription
    ON platform.subscriptions (tenant_id)
    WHERE status IN ('trialing', 'active', 'past_due', 'paused');

CREATE INDEX ix_subscriptions_tenant_status
    ON platform.subscriptions (tenant_id, status, created_at DESC);

CREATE INDEX ix_subscriptions_period_end
    ON platform.subscriptions (current_period_end)
    WHERE status IN ('trialing', 'active', 'past_due');

CREATE TABLE platform.subscription_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     uuid NOT NULL REFERENCES platform.subscriptions(id) ON DELETE RESTRICT,
    event_code          varchar(80) NOT NULL,
    old_status          varchar(20),
    new_status          varchar(20),
    old_plan_id         uuid REFERENCES platform.plans(id) ON DELETE SET NULL,
    new_plan_id         uuid REFERENCES platform.plans(id) ON DELETE SET NULL,
    actor_admin_id      uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    reason              text,
    payload             jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT subscription_event_code_not_blank CHECK (btrim(event_code) <> '')
);

CREATE INDEX ix_subscription_events_subscription_time
    ON platform.subscription_events (subscription_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 5. Límites efectivos (planes + excepciones por tenant)
-- ---------------------------------------------------------------------------

CREATE VIEW platform.v_tenant_effective_limits AS
WITH current_subscriptions AS (
    SELECT DISTINCT ON (s.tenant_id)
           s.tenant_id, s.plan_id, s.status, s.grace_until, s.trial_ends_at
    FROM platform.subscriptions s
    WHERE s.status IN ('trialing', 'active', 'past_due')
    ORDER BY s.tenant_id, s.created_at DESC
), limit_keys AS (
    SELECT cs.tenant_id, pl.limit_code
    FROM current_subscriptions cs
    JOIN platform.plan_limits pl ON pl.plan_id = cs.plan_id
    UNION
    SELECT tlo.tenant_id, tlo.limit_code
    FROM platform.tenant_limit_overrides tlo
    WHERE tlo.expires_at IS NULL OR tlo.expires_at > now()
)
SELECT
    lk.tenant_id,
    lk.limit_code,
    CASE
        WHEN tlo.tenant_id IS NOT NULL THEN tlo.limit_value
        ELSE pl.limit_value
    END AS effective_limit,
    CASE
        WHEN tlo.tenant_id IS NOT NULL THEN 'tenant_override'
        ELSE 'plan'
    END AS source
FROM limit_keys lk
LEFT JOIN current_subscriptions cs ON cs.tenant_id = lk.tenant_id
LEFT JOIN platform.plan_limits pl ON pl.plan_id = cs.plan_id AND pl.limit_code = lk.limit_code
LEFT JOIN platform.tenant_limit_overrides tlo
       ON tlo.tenant_id = lk.tenant_id
      AND tlo.limit_code = lk.limit_code
      AND (tlo.expires_at IS NULL OR tlo.expires_at > now());

COMMENT ON VIEW platform.v_tenant_effective_limits IS
'Limites contratados por tenant. effective_limit NULL significa ilimitado.';

-- ---------------------------------------------------------------------------
-- 6. Módulos habilitados efectivos por tenant
-- ---------------------------------------------------------------------------

CREATE VIEW platform.v_tenant_effective_modules AS
WITH current_subscriptions AS (
    SELECT DISTINCT ON (s.tenant_id)
           s.id, s.tenant_id, s.plan_id, s.status, s.grace_until, s.trial_ends_at
    FROM platform.subscriptions s
    WHERE s.status IN ('trialing', 'active', 'past_due')
    ORDER BY s.tenant_id, s.created_at DESC
)
SELECT
    t.id AS tenant_id,
    m.id AS module_id,
    m.code AS module_code,
    m.name AS module_name,
    CASE
        WHEN t.status <> 'active' THEN false
        WHEN NOT m.is_available THEN false
        WHEN cs.id IS NULL THEN false
        WHEN cs.status = 'past_due' AND (cs.grace_until IS NULL OR cs.grace_until <= now()) THEN false
        WHEN cs.status = 'trialing' AND cs.trial_ends_at IS NOT NULL AND cs.trial_ends_at <= now() THEN false
        WHEN m.is_core THEN true
        ELSE COALESCE(tmo.enabled_override, pm.is_enabled, false)
    END AS is_enabled,
    cs.id AS subscription_id,
    CASE
        WHEN tmo.tenant_id IS NOT NULL
         AND (tmo.expires_at IS NULL OR tmo.expires_at > now()) THEN 'tenant_override'
        WHEN pm.plan_id IS NOT NULL THEN 'plan'
        ELSE 'not_included'
    END AS source
FROM platform.tenants t
CROSS JOIN platform.modules m
LEFT JOIN current_subscriptions cs ON cs.tenant_id = t.id
LEFT JOIN platform.plan_modules pm
       ON pm.plan_id = cs.plan_id AND pm.module_id = m.id
LEFT JOIN platform.tenant_module_overrides tmo
       ON tmo.tenant_id = t.id
      AND tmo.module_id = m.id
      AND (tmo.expires_at IS NULL OR tmo.expires_at > now());

COMMENT ON VIEW platform.v_tenant_effective_modules IS
'Módulos habilitados efectivamente para cada tenant, combinando plan y excepciones administrativas.';

-- ---------------------------------------------------------------------------
-- 7. Configuración global de la plataforma
-- ---------------------------------------------------------------------------

CREATE TABLE platform.settings (
    setting_key         varchar(120) PRIMARY KEY,
    setting_value       jsonb,
    description         text,
    is_public           boolean NOT NULL DEFAULT false,
    is_secret_reference boolean NOT NULL DEFAULT false,
    secret_reference    text,
    updated_by_admin_id uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settings_key_not_blank CHECK (btrim(setting_key) <> ''),
    CONSTRAINT settings_secret_storage CHECK (
        (is_secret_reference = true AND setting_value IS NULL AND secret_reference IS NOT NULL)
        OR
        (is_secret_reference = false AND setting_value IS NOT NULL AND secret_reference IS NULL)
    )
);

-- ---------------------------------------------------------------------------
-- 8. Acceso de soporte a empresas (acceso temporal y auditable)
-- ---------------------------------------------------------------------------

CREATE TABLE platform.support_access_grants (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    requested_by_admin_id    uuid NOT NULL REFERENCES platform.admins(id) ON DELETE RESTRICT,
    approved_by_admin_id     uuid REFERENCES platform.admins(id) ON DELETE RESTRICT,
    access_mode              varchar(20) NOT NULL
                             CHECK (access_mode IN ('read_only', 'read_write')),
    status                   varchar(20) NOT NULL DEFAULT 'requested'
                             CHECK (status IN ('requested', 'approved', 'denied', 'revoked', 'expired')),
    reason                   text NOT NULL,
    requested_at             timestamptz NOT NULL DEFAULT now(),
    starts_at                timestamptz,
    expires_at               timestamptz,
    revoked_at               timestamptz,
    revoked_by_admin_id      uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    CONSTRAINT support_grant_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT support_grant_time_valid CHECK (
        starts_at IS NULL OR expires_at IS NULL OR expires_at > starts_at
    ),
    CONSTRAINT support_grant_approval_valid CHECK (
        approved_by_admin_id IS NULL OR approved_by_admin_id <> requested_by_admin_id
    )
);

CREATE INDEX ix_support_grants_tenant_status
    ON platform.support_access_grants (tenant_id, status, requested_at DESC);

CREATE INDEX ix_support_grants_expiration
    ON platform.support_access_grants (expires_at)
    WHERE status = 'approved';

-- ---------------------------------------------------------------------------
-- 9. Aprovisionamiento y ciclo de vida del tenant
-- ---------------------------------------------------------------------------

CREATE TABLE platform.provisioning_jobs (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation           varchar(40) NOT NULL
                        CHECK (operation IN ('create_tenant', 'activate_tenant', 'suspend_tenant', 'close_tenant', 'provision_modules')),
    status              varchar(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')),
    attempts            integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    requested_by_admin_id uuid REFERENCES platform.admins(id) ON DELETE SET NULL,
    payload             jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_message       text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    started_at          timestamptz,
    finished_at         timestamptz,
    CONSTRAINT provisioning_job_dates CHECK (
        finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at
    )
);

CREATE INDEX ix_provisioning_jobs_status_created
    ON platform.provisioning_jobs (status, created_at);

CREATE INDEX ix_provisioning_jobs_tenant
    ON platform.provisioning_jobs (tenant_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 10. Facturación de la suscripción SaaS (no es la caja del POS cliente)
-- ---------------------------------------------------------------------------

CREATE TABLE platform.invoices (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    subscription_id  uuid REFERENCES platform.subscriptions(id) ON DELETE RESTRICT,
    invoice_number    varchar(80) NOT NULL UNIQUE,
    status            varchar(20) NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'open', 'paid', 'overdue', 'void', 'uncollectible')),
    currency          char(3) NOT NULL DEFAULT 'COP',
    subtotal_amount   numeric(14,2) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    tax_amount        numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount      numeric(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    issued_at         timestamptz,
    due_at            timestamptz,
    paid_at           timestamptz,
    period_start      timestamptz,
    period_end        timestamptz,
    notes             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT invoice_total_consistent CHECK (total_amount = subtotal_amount + tax_amount),
    CONSTRAINT invoice_period_valid CHECK (period_start IS NULL OR period_end IS NULL OR period_end > period_start),
    CONSTRAINT invoice_currency_upper CHECK (currency = upper(currency))
);

CREATE INDEX ix_invoices_tenant_date
    ON platform.invoices (tenant_id, created_at DESC);

CREATE INDEX ix_invoices_status_due
    ON platform.invoices (status, due_at);

CREATE TABLE platform.invoice_items (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id       uuid NOT NULL REFERENCES platform.invoices(id) ON DELETE RESTRICT,
    description      varchar(240) NOT NULL,
    quantity         numeric(12,3) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_amount      numeric(14,2) NOT NULL CHECK (unit_amount >= 0),
    line_total       numeric(14,2) NOT NULL CHECK (line_total >= 0),
    metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT invoice_item_description_not_blank CHECK (btrim(description) <> '')
);

CREATE INDEX ix_invoice_items_invoice
    ON platform.invoice_items (invoice_id);

CREATE TABLE platform.billing_payments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id          uuid NOT NULL REFERENCES platform.invoices(id) ON DELETE RESTRICT,
    provider            varchar(60) NOT NULL,
    provider_reference  varchar(180),
    status              varchar(20) NOT NULL DEFAULT 'initiated'
                        CHECK (status IN ('initiated', 'succeeded', 'failed', 'refunded', 'cancelled')),
    amount              numeric(14,2) NOT NULL CHECK (amount >= 0),
    currency            char(3) NOT NULL DEFAULT 'COP',
    paid_at             timestamptz,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_payment_currency_upper CHECK (currency = upper(currency))
);

CREATE UNIQUE INDEX uq_billing_provider_reference
    ON platform.billing_payments (provider, provider_reference)
    WHERE provider_reference IS NOT NULL;

CREATE INDEX ix_billing_payments_invoice
    ON platform.billing_payments (invoice_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 11. Auditoría central de la plataforma (inmutable desde SQL)
-- ---------------------------------------------------------------------------

CREATE TABLE platform.audit_logs (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    actor_type      varchar(20) NOT NULL DEFAULT 'platform_admin'
                    CHECK (actor_type IN ('platform_admin', 'system', 'service')),
    actor_admin_id  uuid REFERENCES platform.admins(id) ON DELETE RESTRICT,
    actor_service   varchar(120),
    action          varchar(120) NOT NULL,
    resource_type   varchar(120) NOT NULL,
    resource_id     varchar(180),
    request_id      uuid,
    ip_address      inet,
    user_agent      text,
    before_data     jsonb,
    after_data      jsonb,
    metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_action_not_blank CHECK (btrim(action) <> ''),
    CONSTRAINT audit_resource_not_blank CHECK (btrim(resource_type) <> ''),
    CONSTRAINT audit_actor_valid CHECK (
        (actor_type = 'platform_admin' AND actor_admin_id IS NOT NULL)
        OR (actor_type IN ('system', 'service'))
    )
);

CREATE INDEX ix_platform_audit_tenant_time
    ON platform.audit_logs (tenant_id, occurred_at DESC);

CREATE INDEX ix_platform_audit_actor_time
    ON platform.audit_logs (actor_admin_id, occurred_at DESC);

CREATE INDEX ix_platform_audit_resource
    ON platform.audit_logs (resource_type, resource_id, occurred_at DESC);

CREATE INDEX ix_platform_audit_request
    ON platform.audit_logs (request_id)
    WHERE request_id IS NOT NULL;

CREATE TRIGGER trg_platform_audit_immutable
BEFORE UPDATE OR DELETE ON platform.audit_logs
FOR EACH ROW EXECUTE FUNCTION platform.prevent_audit_log_mutation();

-- ---------------------------------------------------------------------------
-- 12. Índices y triggers updated_at
-- ---------------------------------------------------------------------------

CREATE TRIGGER trg_admins_updated_at
BEFORE UPDATE ON platform.admins
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_roles_updated_at
BEFORE UPDATE ON platform.roles
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_tenants_updated_at
BEFORE UPDATE ON platform.tenants
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_tenant_domains_updated_at
BEFORE UPDATE ON platform.tenant_domains
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_plans_updated_at
BEFORE UPDATE ON platform.plans
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_modules_updated_at
BEFORE UPDATE ON platform.modules
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_plan_modules_updated_at
BEFORE UPDATE ON platform.plan_modules
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_plan_limits_updated_at
BEFORE UPDATE ON platform.plan_limits
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_tenant_module_overrides_updated_at
BEFORE UPDATE ON platform.tenant_module_overrides
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_tenant_limit_overrides_updated_at
BEFORE UPDATE ON platform.tenant_limit_overrides
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_subscriptions_updated_at
BEFORE UPDATE ON platform.subscriptions
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_settings_updated_at
BEFORE UPDATE ON platform.settings
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_invoices_updated_at
BEFORE UPDATE ON platform.invoices
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TRIGGER trg_billing_payments_updated_at
BEFORE UPDATE ON platform.billing_payments
FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- ---------------------------------------------------------------------------
-- 13. Datos iniciales: permisos y roles del panel Superadmin
-- ---------------------------------------------------------------------------

INSERT INTO platform.permissions (code, description) VALUES
    ('dashboard.read', 'Consultar el panel general de la plataforma'),
    ('tenants.read', 'Consultar las cuentas/tenants registrados'),
    ('tenants.create', 'Registrar nuevas cuentas/tenants'),
    ('tenants.update', 'Editar datos generales de una cuenta/tenant'),
    ('tenants.suspend', 'Suspender cuentas/tenants'),
    ('tenants.activate', 'Activar o reactivar cuentas/tenants'),
    ('tenants.close', 'Cerrar cuentas/tenants'),
    ('plans.read', 'Consultar planes comerciales'),
    ('plans.manage', 'Crear y modificar planes comerciales'),
    ('subscriptions.read', 'Consultar suscripciones'),
    ('subscriptions.manage', 'Administrar suscripciones'),
    ('modules.read', 'Consultar el catálogo de módulos'),
    ('modules.manage', 'Administrar disponibilidad y módulos contratados'),
    ('admins.read', 'Consultar administradores de plataforma'),
    ('admins.manage', 'Crear, modificar y asignar roles a administradores'),
    ('audit.read', 'Consultar auditoría de la plataforma'),
    ('support.request', 'Solicitar acceso temporal de soporte'),
    ('support.approve', 'Aprobar o denegar accesos de soporte'),
    ('support.revoke', 'Revocar accesos temporales de soporte'),
    ('settings.read', 'Consultar configuración global'),
    ('settings.manage', 'Modificar configuración global'),
    ('billing.read', 'Consultar facturas y pagos SaaS'),
    ('billing.manage', 'Administrar facturas y pagos SaaS'),
    ('provisioning.read', 'Consultar trabajos de aprovisionamiento'),
    ('provisioning.manage', 'Gestionar trabajos de aprovisionamiento'),
    ('domains.manage', 'Administrar dominios personalizados')
ON CONFLICT (code) DO NOTHING;

INSERT INTO platform.roles (code, name, description, is_system) VALUES
    ('platform_owner', 'Propietario de plataforma', 'Control total de la plataforma SaaS', true),
    ('platform_admin', 'Administrador de plataforma', 'Administración general sin gestionar propietarios', true),
    ('support_agent', 'Agente de soporte', 'Soporte limitado y temporal a tenants', true),
    ('billing_admin', 'Administrador de facturación', 'Gestión de planes, suscripciones y facturación SaaS', true),
    ('platform_auditor', 'Auditor de plataforma', 'Acceso de solo lectura a información de auditoría', true)
ON CONFLICT (code) DO NOTHING;

-- Propietario: todos los permisos.
INSERT INTO platform.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM platform.roles r
CROSS JOIN platform.permissions p
WHERE r.code = 'platform_owner'
ON CONFLICT DO NOTHING;

-- Administrador: permisos operativos, excluyendo la administración de admins,
-- cambios de configuración global y aprobación/revocación de soporte.
INSERT INTO platform.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM platform.roles r
JOIN platform.permissions p ON p.code IN (
    'dashboard.read', 'tenants.read', 'tenants.create', 'tenants.update',
    'tenants.suspend', 'tenants.activate', 'plans.read', 'plans.manage',
    'subscriptions.read', 'subscriptions.manage', 'modules.read', 'modules.manage',
    'audit.read', 'support.request', 'settings.read', 'billing.read', 'billing.manage',
    'provisioning.read', 'provisioning.manage', 'domains.manage'
)
WHERE r.code = 'platform_admin'
ON CONFLICT DO NOTHING;

-- Soporte: lectura de tenants y solicitud de acceso temporal; no concede por sí solo acceso.
INSERT INTO platform.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM platform.roles r
JOIN platform.permissions p ON p.code IN (
    'dashboard.read', 'tenants.read', 'support.request'
)
WHERE r.code = 'support_agent'
ON CONFLICT DO NOTHING;

-- Facturación.
INSERT INTO platform.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM platform.roles r
JOIN platform.permissions p ON p.code IN (
    'dashboard.read', 'tenants.read', 'plans.read', 'plans.manage',
    'subscriptions.read', 'subscriptions.manage', 'billing.read', 'billing.manage'
)
WHERE r.code = 'billing_admin'
ON CONFLICT DO NOTHING;

-- Auditor: lectura, sin permisos de modificación.
INSERT INTO platform.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM platform.roles r
JOIN platform.permissions p ON p.code IN (
    'dashboard.read', 'tenants.read', 'plans.read', 'subscriptions.read',
    'audit.read', 'provisioning.read', 'billing.read'
)
WHERE r.code = 'platform_auditor'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 14. Catálogo inicial de módulos comerciales del POS
-- ---------------------------------------------------------------------------

UPDATE platform.modules
   SET code = 'reporting',
       name = 'Reporting',
       description = 'Plantillas, generacion, exportacion y distribucion programada de informes'
 WHERE code = 'reports_audit'
   AND NOT EXISTS (SELECT 1 FROM platform.modules WHERE code = 'reporting');

INSERT INTO platform.modules (code, name, description, is_core, is_available, sort_order) VALUES
    ('company_multibranch', 'Empresa y multisucursal', 'Configuración de la empresa, establecimientos y sucursales', true, true, 1),
    ('users_security', 'Usuarios y seguridad', 'Usuarios, roles, permisos y acceso por sucursal', true, true, 2),
    ('product_catalog', 'Catálogo de productos', 'Categorías, productos, variantes, unidades, impuestos y precios', false, true, 3),
    ('inventory', 'Inventario', 'Bodegas, existencias, movimientos, ajustes, conteos y transferencias', false, true, 4),
    ('procurement', 'Compras y proveedores', 'Proveedores, sourcing, órdenes de compra, recepciones y facturas', false, true, 5),
    ('menu_production', 'Menú, recetas y producción', 'Ingredientes, recetas, modificadores, preparación y consumo', false, true, 6),
    ('pos_sales', 'POS y ventas', 'Pedidos, órdenes, ventas, descuentos y anulaciones', false, true, 7),
    ('payments', 'Pagos', 'Metodos de pago, autorizaciones, capturas, reembolsos y liquidaciones', false, true, 8),
    ('cash', 'Caja', 'Turnos, apertura y cierre de caja, arqueos y movimientos de efectivo', false, true, 9),
    ('customers_loyalty', 'Clientes y fidelización', 'Clientes, historial, puntos, segmentos y beneficios de fidelización', false, true, 10),
    ('workforce', 'Personal y turnos', 'Expedientes laborales, horarios, turnos, asistencia y ausencias', false, true, 11),
    ('finance', 'Finanzas y contabilidad', 'Libros, cuentas por cobrar/pagar, bancos, impuestos y conciliaciones', false, true, 12),
    ('billing', 'Facturación fiscal', 'Documentos fiscales, emisión y transmisión a autoridades por empresa y sucursal', false, true, 13),
    ('integrations', 'Integraciones', 'Conectores, credenciales, webhooks y sincronización con servicios externos', false, true, 14),
    ('automation', 'Automatización', 'Workflows, disparadores, aprobaciones y ejecución automatizada de procesos', false, true, 15),
    ('reporting', 'Reporting', 'Plantillas, generacion, exportacion y distribucion programada de informes', false, true, 16),
    ('analytics', 'Analítica', 'Modelos analíticos, métricas semánticas y dashboards empresariales', false, true, 17),
    ('audit', 'Auditoría operativa', 'Historial central, integridad, retención y control de acceso a auditoría', true, true, 18)
ON CONFLICT (code) DO NOTHING;

-- Dependencias funcionales recomendadas. La aplicación debe validar que un
-- módulo no se habilite si falta un módulo requerido.
INSERT INTO platform.module_dependencies (module_id, requires_module_id)
SELECT m.id, required.id
FROM (VALUES
    ('inventory', 'product_catalog'),
    ('procurement', 'inventory'),
    ('menu_production', 'product_catalog'),
    ('menu_production', 'inventory'),
    ('pos_sales', 'product_catalog'),
    ('pos_sales', 'payments'),
    ('cash', 'pos_sales'),
    ('cash', 'payments'),
    ('customers_loyalty', 'pos_sales'),
    ('workforce', 'company_multibranch'),
    ('workforce', 'users_security'),
    ('finance', 'company_multibranch'),
    ('finance', 'users_security'),
    ('billing', 'company_multibranch'),
    ('billing', 'users_security'),
    ('billing', 'pos_sales'),
    ('billing', 'finance'),
    ('integrations', 'company_multibranch'),
    ('integrations', 'users_security'),
    ('automation', 'company_multibranch'),
    ('automation', 'users_security'),
    ('reporting', 'company_multibranch'),
    ('reporting', 'users_security'),
    ('reporting', 'analytics'),
    ('analytics', 'company_multibranch'),
    ('analytics', 'users_security'),
    ('analytics', 'pos_sales'),
    ('audit', 'company_multibranch'),
    ('audit', 'users_security')
) AS deps(module_code, required_code)
JOIN platform.modules m ON m.code = deps.module_code
JOIN platform.modules required ON required.code = deps.required_code
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 15. Comentarios de propiedad y reglas de integración
-- ---------------------------------------------------------------------------

COMMENT ON TABLE platform.tenants IS
'Cuenta SaaS registrada en la plataforma. El perfil legal de la empresa y sus sucursales pertenecen al Módulo 1.';

COMMENT ON COLUMN platform.admins.password_hash IS
'Hash de contraseña Argon2id generado por la aplicación. Nunca guardar texto plano.';

COMMENT ON COLUMN platform.admin_sessions.refresh_token_hash IS
'Hash del refresh token. Nunca almacenar el token original.';

COMMENT ON COLUMN platform.tenant_module_overrides.enabled_override IS
'NULL hereda el plan; TRUE habilita; FALSE deshabilita. El módulo core no debe poder deshabilitarse.';

COMMENT ON COLUMN platform.plan_limits.limit_value IS
'NULL significa ilimitado. Ejemplos de limit_code: max_users, max_branches, max_products, max_monthly_sales.';

COMMENT ON COLUMN platform.settings.secret_reference IS
'Referencia a un secreto guardado en Vault/KMS o gestor equivalente; no almacenar el secreto aquí.';

COMMIT;

-- ============================================================================
-- BOOTSTRAP DEL PRIMER SUPERADMIN (EJECUTAR DESPUES DE CREAR HASH ARGON2ID)
-- ============================================================================
-- 1) Desde la aplicación/CLI genera un hash Argon2id seguro para la contraseña.
-- 2) Inserta el administrador usando ese hash:
--
-- INSERT INTO platform.admins (email, display_name, password_hash, status,
--                              mfa_required, mfa_enabled, password_changed_at)
-- VALUES ('admin@tudominio.com', 'Administrador principal', '<HASH_ARGON2ID>',
--         'active', true, false, now())
-- RETURNING id;
--
-- 3) Asigna el rol de propietario al ID devuelto:
--
-- INSERT INTO platform.admin_role_assignments (admin_id, role_id)
-- SELECT '<UUID_DEL_ADMIN>'::uuid, id
-- FROM platform.roles
-- WHERE code = 'platform_owner';
--
-- IMPORTANTE: activar MFA antes de habilitar el acceso operativo.
-- ============================================================================
