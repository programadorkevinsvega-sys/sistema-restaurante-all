-- ============================================================================
-- POS SAAS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 2: IDENTITY / USUARIOS, IDENTIDAD, ROLES Y SEGURIDAD
-- Motor: PostgreSQL 15+
--
-- REQUIERE EJECUTAR PREVIAMENTE, EN LA MISMA BASE DE DATOS:
--   1) modulo_0_admin_plataforma_postgresql.sql
--   2) modulo_1_organization_postgresql.sql
--
-- RESPONSABILIDAD DE ESTE MODULO
--   * Identidades y cuentas de usuarios pertenecientes a cada tenant.
--   * Credenciales de contrasena, sesiones y cierre/revocacion de sesiones.
--   * MFA (TOTP/WebAuthn), codigos de recuperacion.
--   * Roles por tenant, catalogo de permisos y asignaciones con alcance
--     tenant / company / branch.
--   * Invitaciones, verificacion de correo y recuperacion de contrasena.
--   * Proveedores de identidad externos OIDC y vinculacion de identidades.
--   * Preferencias de usuario, politicas de autenticacion y eventos de seguridad.
--
-- NO ES RESPONSABILIDAD DE ESTE MODULO
--   * Superadministradores de la plataforma: pertenecen a platform.admins
--     (Modulo 0). No se duplican esas identidades ni sus roles.
--   * Empresas, establecimientos y sucursales: pertenecen a organization
--     (Modulo 1). Este modulo solo referencia sus UUID para limitar accesos.
--   * Empleados, contratos, nomina o gestion humana: no son cuentas de acceso.
--   * Permisos de negocio internos de otros modulos: aqui solo se registra el
--     catalogo de codigos y asignaciones; la regla de negocio vive en cada modulo.
--
-- DECISIONES DE IDENTIDAD
--   * Una cuenta de usuario pertenece a un tenant. El mismo correo puede existir
--     en tenants distintos como identidades independientes.
--   * Un usuario puede recibir varios roles en distintos alcances.
--   * El alcance tenant cubre todo el tenant; company cubre esa empresa y sus
--     sucursales; branch cubre solo esa sucursal.
--   * La API/backend debe resolver el alcance efectivo y verificar permisos.
--   * La base de datos no interpreta JWT ni confia en tenant_id enviado por el
--     navegador. El backend fija app.tenant_id tras autenticar/autorizar.
--
-- SEGURIDAD
--   * password_hash: Argon2id generado por la aplicacion; nunca texto plano.
--   * refresh_token_hash, token_hash y recovery code hashes: solo hashes.
--   * Secretos TOTP y secretos OIDC: cifrados/gestionados por KMS o Vault;
--     en esta base solo se guarda ciphertext o una referencia al secreto.
--   * Access JWT de corta duracion se emite en la aplicacion; no se persiste aqui.
--   * RLS usa SET LOCAL app.tenant_id dentro de CADA transaccion autenticada.
--   * El rol runtime no debe ser superusuario, propietario de tablas ni BYPASSRLS.
--
-- IMPORTANTE SOBRE EL BOOTSTRAP
--   * Esta migracion crea catalogo global de permisos y una funcion para
--     inicializar roles predeterminados en un tenant.
--   * Al crear un tenant, el servicio de aprovisionamiento debe establecer
--     SET LOCAL app.tenant_id = '<tenant-uuid>' y llamar
--     SELECT identity.initialize_tenant_identity('<tenant-uuid>');
--   * Para tenants existentes, ejecutar esa misma llamada por tenant desde una
--     transaccion autenticada con su contexto. No se crea ningun usuario ni
--     contrasena predeterminada.
--
-- EJECUCION
--   Ejecutar una sola vez despues de Modulos 0 y 1. Script transaccionado.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS identity;

COMMENT ON SCHEMA identity IS
'Identidad y seguridad de usuarios de cada tenant. Las identidades del superadmin pertenecen a platform.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION identity.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION identity.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION identity.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id de un registro de identity';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION identity.prevent_security_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Los eventos de seguridad de identity son append-only';
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Usuarios de cada tenant
-- ---------------------------------------------------------------------------

CREATE TABLE identity.users (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    user_code             varchar(40) NOT NULL,
    email                 varchar(320) NOT NULL,
    username              varchar(80),
    full_name             varchar(180) NOT NULL,
    display_name          varchar(120),
    phone_country_code    varchar(8),
    phone_number          varchar(40),
    status                varchar(20) NOT NULL DEFAULT 'invited'
                          CHECK (status IN ('invited', 'active', 'locked', 'disabled', 'archived')),
    email_verified_at     timestamptz,
    phone_verified_at     timestamptz,
    last_login_at         timestamptz,
    last_failed_login_at  timestamptz,
    failed_login_count    integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
    locked_until          timestamptz,
    must_change_password  boolean NOT NULL DEFAULT false,
    metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    deleted_at            timestamptz,
    CONSTRAINT users_code_not_blank CHECK (btrim(user_code) <> ''),
    CONSTRAINT users_email_not_blank CHECK (btrim(email) <> ''),
    CONSTRAINT users_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT users_username_not_blank CHECK (username IS NULL OR btrim(username) <> ''),
    CONSTRAINT users_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT users_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_identity_users_email_per_tenant
    ON identity.users (tenant_id, lower(email))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_identity_users_username_per_tenant
    ON identity.users (tenant_id, lower(username))
    WHERE username IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX uq_identity_users_code_per_tenant
    ON identity.users (tenant_id, lower(user_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_identity_users_tenant_status
    ON identity.users (tenant_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_identity_users_tenant_name
    ON identity.users (tenant_id, lower(full_name))
    WHERE deleted_at IS NULL;

COMMENT ON TABLE identity.users IS
'Cuenta de acceso de una persona dentro de un tenant. No es la tabla de superadministradores ni un expediente laboral.';
COMMENT ON COLUMN identity.users.email IS
'Correo de inicio de sesion/contacto. Se aplica unicidad sin distinguir mayusculas dentro de cada tenant.';

-- ---------------------------------------------------------------------------
-- 2. Credenciales de contrasena y prevencion de reutilizacion
-- ---------------------------------------------------------------------------

CREATE TABLE identity.password_credentials (
    tenant_id              uuid NOT NULL,
    user_id                uuid NOT NULL,
    password_hash          text NOT NULL,
    password_algorithm     varchar(30) NOT NULL DEFAULT 'argon2id'
                           CHECK (password_algorithm IN ('argon2id')),
    password_changed_at    timestamptz NOT NULL DEFAULT now(),
    password_expires_at    timestamptz,
    must_change_password   boolean NOT NULL DEFAULT false,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, user_id),
    CONSTRAINT password_hash_not_blank CHECK (btrim(password_hash) <> ''),
    CONSTRAINT password_credentials_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE identity.password_history (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    user_id         uuid NOT NULL,
    password_hash   text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT password_history_hash_not_blank CHECK (btrim(password_hash) <> ''),
    CONSTRAINT password_history_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_password_history_user_time
    ON identity.password_history (tenant_id, user_id, created_at DESC);

COMMENT ON COLUMN identity.password_credentials.password_hash IS
'Hash Argon2id producido por la aplicacion. Nunca guardar la contrasena original.';
COMMENT ON TABLE identity.password_history IS
'Historial opcional de hashes para impedir reutilizacion; aplicar retencion limitada desde la politica del tenant.';

-- ---------------------------------------------------------------------------
-- 3. Politicas de autenticacion por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE identity.tenant_auth_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    allow_password_auth             boolean NOT NULL DEFAULT true,
    allow_oidc_auth                 boolean NOT NULL DEFAULT false,
    require_email_verification      boolean NOT NULL DEFAULT true,
    require_mfa_for_all_users       boolean NOT NULL DEFAULT false,
    require_mfa_for_privileged      boolean NOT NULL DEFAULT true,
    password_min_length             smallint NOT NULL DEFAULT 12,
    password_max_age_days           integer,
    password_history_count          smallint NOT NULL DEFAULT 5,
    max_failed_attempts             smallint NOT NULL DEFAULT 8,
    lockout_duration_seconds        integer NOT NULL DEFAULT 900,
    session_idle_timeout_minutes    integer NOT NULL DEFAULT 720,
    session_absolute_timeout_hours  integer NOT NULL DEFAULT 168,
    max_active_sessions_per_user    smallint NOT NULL DEFAULT 10,
    allowed_email_domains            text[] NOT NULL DEFAULT ARRAY[]::text[],
    metadata                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    updated_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT auth_password_min_length CHECK (password_min_length BETWEEN 8 AND 128),
    CONSTRAINT auth_password_max_age CHECK (password_max_age_days IS NULL OR password_max_age_days BETWEEN 1 AND 3650),
    CONSTRAINT auth_password_history CHECK (password_history_count BETWEEN 0 AND 24),
    CONSTRAINT auth_failed_attempts CHECK (max_failed_attempts BETWEEN 3 AND 50),
    CONSTRAINT auth_lockout_duration CHECK (lockout_duration_seconds BETWEEN 60 AND 604800),
    CONSTRAINT auth_idle_timeout CHECK (session_idle_timeout_minutes BETWEEN 5 AND 10080),
    CONSTRAINT auth_absolute_timeout CHECK (session_absolute_timeout_hours BETWEEN 1 AND 2160),
    CONSTRAINT auth_max_sessions CHECK (max_active_sessions_per_user BETWEEN 1 AND 100),
    CONSTRAINT auth_domains_nonblank CHECK (array_position(allowed_email_domains, '') IS NULL),
    CONSTRAINT auth_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT auth_at_least_one_method CHECK (allow_password_auth OR allow_oidc_auth)
);

COMMENT ON TABLE identity.tenant_auth_settings IS
'Politicas de autenticacion del tenant. Los limites tambien deben aplicarse en el backend y en el proveedor de identidad.';

-- ---------------------------------------------------------------------------
-- 4. Catalogo global de permisos y roles por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE identity.permissions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code            varchar(140) NOT NULL UNIQUE,
    module_code     varchar(80) NOT NULL,
    name            varchar(140) NOT NULL,
    description     text NOT NULL,
    is_sensitive    boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT permissions_code_lowercase CHECK (code = lower(code)),
    CONSTRAINT permissions_module_not_blank CHECK (btrim(module_code) <> ''),
    CONSTRAINT permissions_name_not_blank CHECK (btrim(name) <> '')
);

CREATE INDEX ix_identity_permissions_module
    ON identity.permissions (module_code, code);

CREATE TABLE identity.roles (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    code            varchar(80) NOT NULL,
    name            varchar(120) NOT NULL,
    description     text,
    is_system       boolean NOT NULL DEFAULT false,
    is_active       boolean NOT NULL DEFAULT true,
    created_by_id   uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz,
    CONSTRAINT roles_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT roles_code_lowercase CHECK (code = lower(code)),
    CONSTRAINT roles_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT roles_tenant_code_unique UNIQUE (tenant_id, code),
    CONSTRAINT roles_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT roles_created_by_fk
        FOREIGN KEY (tenant_id, created_by_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_identity_roles_tenant_active
    ON identity.roles (tenant_id, is_active)
    WHERE deleted_at IS NULL;

CREATE TABLE identity.role_permissions (
    tenant_id       uuid NOT NULL,
    role_id         uuid NOT NULL,
    permission_id   uuid NOT NULL REFERENCES identity.permissions(id) ON DELETE RESTRICT,
    granted_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, role_id, permission_id),
    CONSTRAINT role_permissions_role_fk
        FOREIGN KEY (tenant_id, role_id)
        REFERENCES identity.roles (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_role_permissions_permission
    ON identity.role_permissions (permission_id, tenant_id);

COMMENT ON TABLE identity.permissions IS
'Catalogo global e inmutable por tenant de codigos de permiso. Los permisos efectivos se asignan a roles tenant-scoped.';
COMMENT ON TABLE identity.roles IS
'Roles privados de cada tenant. Los roles de platform.admins pertenecen exclusivamente al Modulo 0.';

-- ---------------------------------------------------------------------------
-- 5. Asignaciones de roles con alcance tenant / company / branch
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_role_assignments (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL,
    user_id               uuid NOT NULL,
    role_id               uuid NOT NULL,
    scope_type            varchar(20) NOT NULL
                          CHECK (scope_type IN ('tenant', 'company', 'branch')),
    company_id            uuid,
    branch_id             uuid,
    assigned_by_user_id   uuid,
    assigned_at           timestamptz NOT NULL DEFAULT now(),
    expires_at            timestamptz,
    revoked_at            timestamptz,
    revoked_by_user_id    uuid,
    reason                text,
    CONSTRAINT user_role_scope_shape CHECK (
        (scope_type = 'tenant' AND company_id IS NULL AND branch_id IS NULL)
        OR (scope_type = 'company' AND company_id IS NOT NULL AND branch_id IS NULL)
        OR (scope_type = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL)
    ),
    CONSTRAINT user_role_assignment_dates CHECK (expires_at IS NULL OR expires_at > assigned_at),
    CONSTRAINT user_role_revocation_dates CHECK (revoked_at IS NULL OR revoked_at >= assigned_at),
    CONSTRAINT user_role_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT user_role_role_fk
        FOREIGN KEY (tenant_id, role_id)
        REFERENCES identity.roles (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT user_role_assigned_by_fk
        FOREIGN KEY (tenant_id, assigned_by_user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT user_role_revoked_by_fk
        FOREIGN KEY (tenant_id, revoked_by_user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT user_role_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT user_role_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_user_tenant_role_active
    ON identity.user_role_assignments (tenant_id, user_id, role_id)
    WHERE scope_type = 'tenant' AND revoked_at IS NULL;

CREATE UNIQUE INDEX uq_user_company_role_active
    ON identity.user_role_assignments (tenant_id, user_id, role_id, company_id)
    WHERE scope_type = 'company' AND revoked_at IS NULL;

CREATE UNIQUE INDEX uq_user_branch_role_active
    ON identity.user_role_assignments (tenant_id, user_id, role_id, branch_id)
    WHERE scope_type = 'branch' AND revoked_at IS NULL;

CREATE INDEX ix_user_role_assignments_user
    ON identity.user_role_assignments (tenant_id, user_id, revoked_at, expires_at);

CREATE INDEX ix_user_role_assignments_role_scope
    ON identity.user_role_assignments (tenant_id, role_id, scope_type, company_id, branch_id)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE identity.user_role_assignments IS
'Asignacion autorizada de roles. tenant scope aplica a todo el tenant; company scope a la empresa y sus sucursales; branch scope solo a la sucursal indicada.';

-- ---------------------------------------------------------------------------
-- 6. Sesiones de usuarios
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_sessions (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL,
    user_id               uuid NOT NULL,
    refresh_token_hash    text NOT NULL UNIQUE,
    token_family_id       uuid NOT NULL DEFAULT gen_random_uuid(),
    ip_address            inet,
    user_agent            text,
    device_name           varchar(160),
    mfa_verified_at       timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    last_seen_at          timestamptz,
    expires_at            timestamptz NOT NULL,
    revoked_at            timestamptz,
    revoke_reason         varchar(120),
    CONSTRAINT user_session_token_hash_not_blank CHECK (btrim(refresh_token_hash) <> ''),
    CONSTRAINT user_session_expiration CHECK (expires_at > created_at),
    CONSTRAINT user_session_revocation CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT user_session_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_user_sessions_user_active
    ON identity.user_sessions (tenant_id, user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE INDEX ix_user_sessions_token_family
    ON identity.user_sessions (token_family_id);

-- ---------------------------------------------------------------------------
-- 7. MFA: TOTP / WebAuthn y codigos de recuperacion
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_mfa_factors (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL,
    user_id           uuid NOT NULL,
    factor_type       varchar(20) NOT NULL CHECK (factor_type IN ('totp', 'webauthn')),
    label             varchar(120),
    secret_ciphertext bytea,
    credential_id     text,
    public_key        bytea,
    sign_count        bigint NOT NULL DEFAULT 0 CHECK (sign_count >= 0),
    metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,
    verified_at       timestamptz,
    last_used_at      timestamptz,
    revoked_at        timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_mfa_factor_material CHECK (
        (factor_type = 'totp' AND secret_ciphertext IS NOT NULL
         AND credential_id IS NULL AND public_key IS NULL)
        OR
        (factor_type = 'webauthn' AND credential_id IS NOT NULL AND public_key IS NOT NULL
         AND secret_ciphertext IS NULL)
    ),
    CONSTRAINT user_mfa_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT user_mfa_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_user_webauthn_credential
    ON identity.user_mfa_factors (credential_id)
    WHERE factor_type = 'webauthn' AND revoked_at IS NULL;

CREATE INDEX ix_user_mfa_factors_user_active
    ON identity.user_mfa_factors (tenant_id, user_id, factor_type)
    WHERE revoked_at IS NULL;

CREATE TABLE identity.user_recovery_codes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   uuid NOT NULL,
    user_id     uuid NOT NULL,
    code_hash   text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    used_at     timestamptz,
    CONSTRAINT user_recovery_code_hash_not_blank CHECK (btrim(code_hash) <> ''),
    CONSTRAINT user_recovery_codes_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_user_recovery_codes_unused
    ON identity.user_recovery_codes (tenant_id, user_id)
    WHERE used_at IS NULL;

-- ---------------------------------------------------------------------------
-- 8. Invitaciones de usuarios
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_invitations (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    email                 varchar(320) NOT NULL,
    full_name             varchar(180),
    invitation_token_hash text NOT NULL UNIQUE,
    invited_role_id       uuid,
    scope_type            varchar(20) NOT NULL DEFAULT 'tenant'
                          CHECK (scope_type IN ('tenant', 'company', 'branch')),
    company_id            uuid,
    branch_id             uuid,
    invited_by_user_id    uuid,
    status                varchar(20) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    created_at            timestamptz NOT NULL DEFAULT now(),
    expires_at            timestamptz NOT NULL,
    accepted_at           timestamptz,
    revoked_at            timestamptz,
    CONSTRAINT invitation_email_not_blank CHECK (btrim(email) <> ''),
    CONSTRAINT invitation_token_not_blank CHECK (btrim(invitation_token_hash) <> ''),
    CONSTRAINT invitation_scope_shape CHECK (
        (scope_type = 'tenant' AND company_id IS NULL AND branch_id IS NULL)
        OR (scope_type = 'company' AND company_id IS NOT NULL AND branch_id IS NULL)
        OR (scope_type = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL)
    ),
    CONSTRAINT invitation_expiration CHECK (expires_at > created_at),
    CONSTRAINT invitation_terminal_dates CHECK (
        (status = 'accepted' AND accepted_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'revoked' AND revoked_at IS NOT NULL AND accepted_at IS NULL)
        OR (status IN ('pending', 'expired') AND accepted_at IS NULL AND revoked_at IS NULL)
    ),
    CONSTRAINT invitation_role_fk
        FOREIGN KEY (tenant_id, invited_role_id)
        REFERENCES identity.roles (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT invitation_inviter_fk
        FOREIGN KEY (tenant_id, invited_by_user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT invitation_company_fk
        FOREIGN KEY (tenant_id, company_id)
        REFERENCES organization.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT invitation_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id)
        REFERENCES organization.branches (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_pending_invitation_email_tenant
    ON identity.user_invitations (tenant_id, lower(email))
    WHERE status = 'pending';

CREATE INDEX ix_user_invitations_tenant_status
    ON identity.user_invitations (tenant_id, status, created_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Recuperacion de contrasena y verificacion de correo
-- ---------------------------------------------------------------------------

CREATE TABLE identity.password_reset_tokens (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    user_id         uuid NOT NULL,
    token_hash      text NOT NULL UNIQUE,
    created_at      timestamptz NOT NULL DEFAULT now(),
    expires_at      timestamptz NOT NULL,
    used_at         timestamptz,
    requested_ip    inet,
    CONSTRAINT password_reset_token_not_blank CHECK (btrim(token_hash) <> ''),
    CONSTRAINT password_reset_expiration CHECK (expires_at > created_at),
    CONSTRAINT password_reset_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_password_reset_active
    ON identity.password_reset_tokens (tenant_id, user_id, expires_at)
    WHERE used_at IS NULL;

CREATE TABLE identity.email_verification_tokens (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    user_id         uuid NOT NULL,
    token_hash      text NOT NULL UNIQUE,
    created_at      timestamptz NOT NULL DEFAULT now(),
    expires_at      timestamptz NOT NULL,
    verified_at     timestamptz,
    CONSTRAINT email_verification_token_not_blank CHECK (btrim(token_hash) <> ''),
    CONSTRAINT email_verification_expiration CHECK (expires_at > created_at),
    CONSTRAINT email_verification_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_email_verification_active
    ON identity.email_verification_tokens (tenant_id, user_id, expires_at)
    WHERE verified_at IS NULL;

-- ---------------------------------------------------------------------------
-- 10. Proveedores OIDC y vinculos de identidad externa
-- ---------------------------------------------------------------------------

CREATE TABLE identity.identity_providers (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_code            varchar(60) NOT NULL,
    display_name             varchar(120) NOT NULL,
    protocol                 varchar(20) NOT NULL DEFAULT 'oidc'
                             CHECK (protocol IN ('oidc')),
    issuer_url               text NOT NULL,
    client_id                varchar(255) NOT NULL,
    client_secret_reference  text,
    scopes                   text[] NOT NULL DEFAULT ARRAY['openid', 'email', 'profile']::text[],
    is_enabled               boolean NOT NULL DEFAULT false,
    jit_provisioning         boolean NOT NULL DEFAULT false,
    trusted_email_claim      boolean NOT NULL DEFAULT false,
    configuration            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT identity_provider_code_not_blank CHECK (btrim(provider_code) <> ''),
    CONSTRAINT identity_provider_code_lowercase CHECK (provider_code = lower(provider_code)),
    CONSTRAINT identity_provider_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT identity_provider_issuer_not_blank CHECK (btrim(issuer_url) <> ''),
    CONSTRAINT identity_provider_client_not_blank CHECK (btrim(client_id) <> ''),
    CONSTRAINT identity_provider_configuration_object CHECK (jsonb_typeof(configuration) = 'object'),
    CONSTRAINT identity_provider_tenant_code_unique UNIQUE (tenant_id, provider_code),
    CONSTRAINT identity_provider_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_identity_providers_tenant_enabled
    ON identity.identity_providers (tenant_id, is_enabled);

CREATE TABLE identity.external_identity_links (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL,
    user_id               uuid NOT NULL,
    identity_provider_id  uuid NOT NULL,
    subject               varchar(255) NOT NULL,
    email_at_provider     varchar(320),
    linked_at             timestamptz NOT NULL DEFAULT now(),
    last_login_at         timestamptz,
    metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT external_identity_subject_not_blank CHECK (btrim(subject) <> ''),
    CONSTRAINT external_identity_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT external_identity_provider_subject_unique UNIQUE (tenant_id, identity_provider_id, subject),
    CONSTRAINT external_identity_user_provider_unique UNIQUE (tenant_id, user_id, identity_provider_id),
    CONSTRAINT external_identity_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT external_identity_provider_fk
        FOREIGN KEY (tenant_id, identity_provider_id)
        REFERENCES identity.identity_providers (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_external_identity_user
    ON identity.external_identity_links (tenant_id, user_id);

COMMENT ON COLUMN identity.identity_providers.client_secret_reference IS
'Ruta/referencia de secreto en KMS/Vault. Nunca guardar el client_secret en texto plano en PostgreSQL.';

-- ---------------------------------------------------------------------------
-- 11. Preferencias de usuario
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_preferences (
    tenant_id       uuid NOT NULL,
    user_id         uuid NOT NULL,
    locale          varchar(20) NOT NULL DEFAULT 'es-CO',
    timezone        varchar(80) NOT NULL DEFAULT 'America/Bogota',
    preferences     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, user_id),
    CONSTRAINT user_preferences_object CHECK (jsonb_typeof(preferences) = 'object'),
    CONSTRAINT user_preferences_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 12. Eventos de autenticacion y cambios de estado
-- ---------------------------------------------------------------------------

CREATE TABLE identity.user_auth_events (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    user_id           uuid,
    email_attempted   varchar(320),
    event_type        varchar(50) NOT NULL CHECK (event_type IN (
        'login_success', 'login_failure', 'logout', 'refresh_success',
        'refresh_failure', 'mfa_success', 'mfa_failure', 'password_changed',
        'password_reset_requested', 'password_reset_completed',
        'email_verified', 'invitation_accepted', 'session_revoked',
        'account_locked', 'account_unlocked', 'external_login_success',
        'external_login_failure', 'permission_denied'
    )),
    ip_address        inet,
    user_agent        text,
    request_id        varchar(100),
    details           jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_auth_event_details_object CHECK (jsonb_typeof(details) = 'object'),
    CONSTRAINT user_auth_event_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_user_auth_events_user_time
    ON identity.user_auth_events (tenant_id, user_id, occurred_at DESC);

CREATE INDEX ix_user_auth_events_type_time
    ON identity.user_auth_events (tenant_id, event_type, occurred_at DESC);

CREATE INDEX ix_user_auth_events_email_time
    ON identity.user_auth_events (tenant_id, lower(email_attempted), occurred_at DESC)
    WHERE email_attempted IS NOT NULL;

CREATE TABLE identity.user_status_history (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL,
    user_id         uuid NOT NULL,
    old_status      varchar(20),
    new_status      varchar(20) NOT NULL
                    CHECK (new_status IN ('invited', 'active', 'locked', 'disabled', 'archived')),
    reason          text,
    actor_type      varchar(20) NOT NULL DEFAULT 'system'
                    CHECK (actor_type IN ('tenant_user', 'platform_admin', 'system', 'service')),
    actor_id        uuid,
    changed_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_status_history_actor CHECK (
        (actor_type IN ('tenant_user', 'platform_admin') AND actor_id IS NOT NULL)
        OR actor_type IN ('system', 'service')
    ),
    CONSTRAINT user_status_history_user_fk
        FOREIGN KEY (tenant_id, user_id)
        REFERENCES identity.users (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_user_status_history_user_time
    ON identity.user_status_history (tenant_id, user_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- 13. Indices adicionales para claves foraneas y consultas frecuentes
-- ---------------------------------------------------------------------------

CREATE INDEX ix_password_credentials_user
    ON identity.password_credentials (tenant_id, user_id);

CREATE INDEX ix_password_reset_tokens_expiration
    ON identity.password_reset_tokens (expires_at)
    WHERE used_at IS NULL;

CREATE INDEX ix_email_verification_tokens_expiration
    ON identity.email_verification_tokens (expires_at)
    WHERE verified_at IS NULL;

CREATE INDEX ix_user_invitations_expiration
    ON identity.user_invitations (expires_at)
    WHERE status = 'pending';

-- ---------------------------------------------------------------------------
-- 14. Triggers updated_at y proteccion de tenant_id
-- ---------------------------------------------------------------------------

CREATE TRIGGER trg_identity_users_updated_at
BEFORE UPDATE ON identity.users
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

CREATE TRIGGER trg_identity_password_credentials_updated_at
BEFORE UPDATE ON identity.password_credentials
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

CREATE TRIGGER trg_identity_tenant_auth_settings_updated_at
BEFORE UPDATE ON identity.tenant_auth_settings
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

CREATE TRIGGER trg_identity_roles_updated_at
BEFORE UPDATE ON identity.roles
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

CREATE TRIGGER trg_identity_identity_providers_updated_at
BEFORE UPDATE ON identity.identity_providers
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

CREATE TRIGGER trg_identity_user_preferences_updated_at
BEFORE UPDATE ON identity.user_preferences
FOR EACH ROW EXECUTE FUNCTION identity.set_updated_at();

DO $$
DECLARE
    table_name text;
    table_names text[] := ARRAY[
        'users', 'password_credentials', 'password_history', 'tenant_auth_settings',
        'roles', 'role_permissions', 'user_role_assignments', 'user_sessions',
        'user_mfa_factors', 'user_recovery_codes', 'user_invitations',
        'password_reset_tokens', 'email_verification_tokens', 'identity_providers',
        'external_identity_links', 'user_preferences', 'user_auth_events',
        'user_status_history'
    ];
BEGIN
    FOREACH table_name IN ARRAY table_names LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON identity.%I FOR EACH ROW EXECUTE FUNCTION identity.prevent_tenant_change()',
            'trg_' || table_name || '_prevent_tenant_change', table_name
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_user_auth_events_append_only
BEFORE UPDATE OR DELETE ON identity.user_auth_events
FOR EACH ROW EXECUTE FUNCTION identity.prevent_security_event_mutation();

CREATE TRIGGER trg_user_status_history_append_only
BEFORE UPDATE OR DELETE ON identity.user_status_history
FOR EACH ROW EXECUTE FUNCTION identity.prevent_security_event_mutation();

-- ---------------------------------------------------------------------------
-- 15. Row Level Security: todas las tablas con tenant_id
-- ---------------------------------------------------------------------------
-- La aplicacion debe abrir una transaccion y ejecutar:
--   SET LOCAL app.tenant_id = '<uuid-del-tenant-autorizado>';
-- El valor debe derivarse de la sesion autenticada y de las autorizaciones del
-- backend; nunca debe confiarse directamente en un tenant_id del cliente HTTP.
-- identity.permissions es un catalogo global y por eso no tiene tenant_id/RLS.

DO $$
DECLARE
    table_name text;
    table_names text[] := ARRAY[
        'users', 'password_credentials', 'password_history', 'tenant_auth_settings',
        'roles', 'role_permissions', 'user_role_assignments', 'user_sessions',
        'user_mfa_factors', 'user_recovery_codes', 'user_invitations',
        'password_reset_tokens', 'email_verification_tokens', 'identity_providers',
        'external_identity_links', 'user_preferences', 'user_auth_events',
        'user_status_history'
    ];
BEGIN
    FOREACH table_name IN ARRAY table_names LOOP
        EXECUTE format('ALTER TABLE identity.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE identity.%I FORCE ROW LEVEL SECURITY', table_name);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON identity.%I USING (tenant_id = identity.current_tenant_id()) WITH CHECK (tenant_id = identity.current_tenant_id())',
            table_name
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 16. Catalogo global de permisos
-- ---------------------------------------------------------------------------

INSERT INTO identity.permissions (code, module_code, name, description, is_sensitive) VALUES
    ('dashboard.read', 'platform_app', 'Consultar panel', 'Consultar el panel de la empresa/tenant.', false),
    ('profile.read', 'identity', 'Consultar perfil', 'Consultar perfiles de usuarios.', false),
    ('profile.update', 'identity', 'Actualizar perfil', 'Actualizar el perfil propio.', false),
    ('users.read', 'identity', 'Consultar usuarios', 'Consultar usuarios del alcance autorizado.', false),
    ('users.invite', 'identity', 'Invitar usuarios', 'Enviar invitaciones de acceso.', true),
    ('users.create', 'identity', 'Crear usuarios', 'Crear usuarios dentro del alcance autorizado.', true),
    ('users.update', 'identity', 'Actualizar usuarios', 'Actualizar datos y estado de usuarios.', true),
    ('users.disable', 'identity', 'Deshabilitar usuarios', 'Deshabilitar o bloquear cuentas de usuarios.', true),
    ('roles.read', 'identity', 'Consultar roles', 'Consultar roles y permisos.', false),
    ('roles.manage', 'identity', 'Administrar roles', 'Crear roles y asignar permisos.', true),
    ('companies.read', 'organization', 'Consultar empresas', 'Consultar empresas del tenant.', false),
    ('companies.manage', 'organization', 'Administrar empresas', 'Administrar datos de empresas.', true),
    ('branches.read', 'organization', 'Consultar sucursales', 'Consultar sucursales autorizadas.', false),
    ('branches.manage', 'organization', 'Administrar sucursales', 'Administrar sucursales autorizadas.', true),
    ('catalog.read', 'catalog', 'Consultar catalogo', 'Consultar productos, categorias y precios.', false),
    ('catalog.manage', 'catalog', 'Administrar catalogo', 'Crear y modificar catalogo de productos.', true),
    ('inventory.read', 'inventory', 'Consultar inventario', 'Consultar existencias y movimientos.', false),
    ('inventory.manage', 'inventory', 'Administrar inventario', 'Registrar movimientos y administrar inventario.', true),
    ('inventory.adjust', 'inventory', 'Ajustar inventario', 'Realizar ajustes autorizados de existencias.', true),
    ('inventory.transfer', 'inventory', 'Transferir inventario', 'Solicitar, aprobar y recibir transferencias.', true),
    ('procurement.suppliers.read', 'procurement', 'Consultar proveedores', 'Consultar proveedores y sus perfiles comerciales autorizados.', false),
    ('procurement.suppliers.create', 'procurement', 'Crear proveedores', 'Registrar proveedores nuevos.', true),
    ('procurement.suppliers.update', 'procurement', 'Actualizar proveedores', 'Modificar perfiles de proveedores.', true),
    ('procurement.suppliers.approve', 'procurement', 'Aprobar proveedores', 'Aprobar proveedores homologados.', true),
    ('procurement.suppliers.suspend', 'procurement', 'Suspender proveedores', 'Suspender o bloquear proveedores.', true),
    ('procurement.suppliers.documents.manage', 'procurement', 'Administrar documentos de proveedores', 'Cargar, verificar y administrar documentos de homologacion.', true),
    ('procurement.suppliers.evaluate', 'procurement', 'Evaluar proveedores', 'Registrar evaluaciones de proveedores.', true),
    ('procurement.suppliers.categories.manage', 'procurement', 'Administrar categorias de proveedores', 'Crear y mantener categorias de proveedores.', true),
    ('procurement.suppliers.branch_profiles.manage', 'procurement', 'Administrar proveedores por sucursal', 'Configurar disponibilidad, preferencia y exclusividad de proveedores por sucursal.', true),
    ('procurement.sourcing.read', 'procurement', 'Consultar procesos de cotizacion', 'Consultar solicitudes de cotizacion y ofertas.', false),
    ('procurement.sourcing.create', 'procurement', 'Crear procesos de cotizacion', 'Crear solicitudes de informacion, cotizacion o propuesta.', true),
    ('procurement.sourcing.publish', 'procurement', 'Publicar procesos de cotizacion', 'Invitar proveedores y publicar solicitudes.', true),
    ('procurement.sourcing.cancel', 'procurement', 'Cancelar procesos de cotizacion', 'Cancelar procesos de cotizacion.', true),
    ('procurement.quotes.read', 'procurement', 'Consultar cotizaciones', 'Consultar cotizaciones recibidas.', false),
    ('procurement.quotes.submit', 'procurement', 'Enviar cotizaciones', 'Enviar o modificar cotizaciones como proveedor autorizado.', true),
    ('procurement.quotes.evaluate', 'procurement', 'Evaluar cotizaciones', 'Comparar y evaluar ofertas recibidas.', true),
    ('procurement.quotes.award', 'procurement', 'Adjudicar cotizaciones', 'Adjudicar una cotizacion aprobada.', true),
    ('procurement.agreements.read', 'procurement', 'Consultar acuerdos comerciales', 'Consultar acuerdos marco y listas de precios.', false),
    ('procurement.agreements.manage', 'procurement', 'Administrar acuerdos comerciales', 'Crear y administrar acuerdos comerciales.', true),
    ('procurement.requests.read', 'procurement', 'Consultar solicitudes de compra', 'Consultar solicitudes de compra del alcance autorizado.', false),
    ('procurement.requests.create', 'procurement', 'Crear solicitudes de compra', 'Crear solicitudes de compra por sucursal o centralizadas.', true),
    ('procurement.requests.approve', 'procurement', 'Aprobar solicitudes de compra', 'Aprobar solicitudes dentro de los limites autorizados.', true),
    ('procurement.requests.reject', 'procurement', 'Rechazar solicitudes de compra', 'Rechazar solicitudes indicando el motivo.', true),
    ('procurement.orders.read', 'procurement', 'Consultar ordenes de compra', 'Consultar ordenes de compra autorizadas.', false),
    ('procurement.orders.create', 'procurement', 'Crear ordenes de compra', 'Crear ordenes de compra para proveedores aprobados.', true),
    ('procurement.orders.approve', 'procurement', 'Aprobar ordenes de compra', 'Aprobar compromisos de compra dentro de los limites.', true),
    ('procurement.orders.issue', 'procurement', 'Emitir ordenes de compra', 'Emitir ordenes de compra aprobadas.', true),
    ('procurement.orders.cancel', 'procurement', 'Cancelar ordenes de compra', 'Cancelar ordenes de compra con motivo.', true),
    ('procurement.orders.schedule.manage', 'procurement', 'Administrar entregas programadas', 'Crear y actualizar entregas programadas de ordenes de compra.', true),
    ('procurement.receipts.read', 'procurement', 'Consultar recepciones', 'Consultar recepciones y discrepancias.', false),
    ('procurement.receipts.create', 'procurement', 'Registrar recepciones', 'Registrar mercancia recibida y discrepancias.', true),
    ('procurement.receipts.post', 'procurement', 'Confirmar recepciones', 'Confirmar recepciones y solicitar su registro en Inventory.', true),
    ('procurement.receipts.inspect', 'procurement', 'Inspeccionar recepciones', 'Registrar inspecciones de cantidad, calidad, temperatura y empaque.', true),
    ('procurement.receipts.discrepancies.manage', 'procurement', 'Gestionar discrepancias de recepcion', 'Resolver diferencias detectadas durante la recepcion.', true),
    ('procurement.returns.read', 'procurement', 'Consultar devoluciones a proveedores', 'Consultar devoluciones y sus estados.', false),
    ('procurement.returns.create', 'procurement', 'Crear devoluciones a proveedores', 'Solicitar devoluciones de mercancia a proveedores.', true),
    ('procurement.returns.approve', 'procurement', 'Aprobar devoluciones a proveedores', 'Aprobar devoluciones antes de su despacho.', true),
    ('procurement.returns.complete', 'procurement', 'Completar devoluciones a proveedores', 'Confirmar despacho y movimiento de inventario de una devolucion.', true),
    ('procurement.documents.manage', 'procurement', 'Administrar documentos de compras', 'Cargar y administrar documentos de solicitudes, ordenes, recepciones y devoluciones.', true),
    ('procurement.settings.manage', 'procurement', 'Administrar configuracion de compras', 'Configurar aprobaciones, tolerancias de recepcion y politicas operativas de Procurement.', true),
    ('procurement.invoices.read', 'procurement', 'Consultar facturas de proveedor', 'Consultar facturas y estado de conciliacion.', false),
    ('procurement.invoices.create', 'procurement', 'Registrar facturas de proveedor', 'Registrar facturas recibidas de proveedores.', true),
    ('procurement.invoices.match', 'procurement', 'Conciliar facturas de proveedor', 'Conciliar factura, orden y recepcion.', true),
    ('procurement.invoices.approve', 'procurement', 'Aprobar facturas de proveedor', 'Aprobar facturas conciliadas para cuentas por pagar.', true),
    ('production.read', 'production', 'Consultar produccion', 'Consultar recetas, ordenes y resultados de produccion.', false),
    ('production.recipes.read', 'production', 'Consultar recetas', 'Consultar recetas y versiones dentro del alcance autorizado.', false),
    ('production.recipes.create', 'production', 'Crear recetas', 'Crear recetas y versiones borrador.', true),
    ('production.recipes.update', 'production', 'Actualizar recetas', 'Modificar recetas y versiones borrador.', true),
    ('production.recipes.publish', 'production', 'Publicar recetas', 'Aprobar y publicar versiones de receta.', true),
    ('production.recipes.retire', 'production', 'Retirar recetas', 'Retirar versiones activas de receta.', true),
    ('production.orders.read', 'production', 'Consultar ordenes de produccion', 'Consultar ordenes y lotes de produccion autorizados.', false),
    ('production.orders.create', 'production', 'Crear ordenes de produccion', 'Crear y planificar ordenes de produccion.', true),
    ('production.orders.approve', 'production', 'Aprobar ordenes de produccion', 'Aprobar ordenes dentro del alcance autorizado.', true),
    ('production.orders.release', 'production', 'Liberar ordenes de produccion', 'Liberar ordenes aprobadas para ejecucion.', true),
    ('production.orders.pause', 'production', 'Pausar ordenes de produccion', 'Pausar o reanudar ordenes en ejecucion.', true),
    ('production.orders.complete', 'production', 'Completar ordenes de produccion', 'Completar ordenes con resultados registrados.', true),
    ('production.materials.plan', 'production', 'Planificar materiales', 'Planificar materiales requeridos por una orden.', true),
    ('production.materials.issue', 'production', 'Emitir materiales a produccion', 'Solicitar a Inventory la emision de materiales.', true),
    ('production.materials.return', 'production', 'Devolver materiales de produccion', 'Solicitar a Inventory la devolucion de materiales.', true),
    ('production.outputs.report', 'production', 'Reportar productos producidos', 'Registrar resultados de produccion para recibir en Inventory.', true),
    ('production.waste.report', 'production', 'Reportar mermas de produccion', 'Registrar mermas y solicitar sus movimientos a Inventory.', true),
    ('production.quality.read', 'production', 'Consultar calidad de produccion', 'Consultar especificaciones e inspecciones de calidad.', false),
    ('production.quality.inspect', 'production', 'Inspeccionar calidad', 'Registrar inspecciones y resultados de calidad.', true),
    ('production.quality.release', 'production', 'Liberar productos inspeccionados', 'Aprobar lotes que cumplan los controles de calidad.', true),
    ('production.work_centers.manage', 'production', 'Administrar centros de trabajo', 'Configurar centros de trabajo de produccion.', true),
    ('production.routings.manage', 'production', 'Administrar rutas de produccion', 'Configurar rutas y operaciones de produccion.', true),
    ('sales.read', 'sales', 'Consultar ventas', 'Consultar pedidos y ventas.', false),
    ('sales.create', 'sales', 'Registrar ventas', 'Registrar pedidos y ventas.', false),
    ('sales.discount', 'sales', 'Aplicar descuentos', 'Aplicar descuentos dentro de los limites autorizados.', true),
    ('sales.void', 'sales', 'Anular ventas', 'Anular ventas segun las reglas del negocio.', true),
    ('cash.read', 'cash', 'Consultar caja', 'Consultar turnos y movimientos de caja.', false),
    ('cash.open', 'cash', 'Abrir caja', 'Abrir turnos de caja.', true),
    ('cash.close', 'cash', 'Cerrar caja', 'Cerrar turnos y declarar diferencias.', true),
    ('cash.manage', 'cash', 'Administrar caja', 'Administrar cajas y movimientos manuales.', true),
    ('cash.registers.read', 'cash', 'Consultar cajas', 'Consultar cajas registradoras del alcance autorizado.', false),
    ('cash.registers.manage', 'cash', 'Administrar cajas', 'Crear y configurar cajas registradoras.', true),
    ('cash.sessions.read', 'cash', 'Consultar turnos de caja', 'Consultar sesiones y responsables de caja.', false),
    ('cash.sessions.open', 'cash', 'Abrir turnos de caja', 'Abrir una sesion de caja y declarar el fondo inicial.', true),
    ('cash.sessions.close', 'cash', 'Cerrar turnos de caja', 'Iniciar y completar el cierre de una sesion de caja.', true),
    ('cash.sessions.cancel', 'cash', 'Cancelar turnos de caja', 'Cancelar una sesion de caja con motivo.', true),
    ('cash.sessions.assign_cashier', 'cash', 'Asignar cajeros', 'Asignar o retirar cajeros de una sesion.', true),
    ('cash.movements.read', 'cash', 'Consultar movimientos de efectivo', 'Consultar el libro de movimientos del cajon.', false),
    ('cash.movements.create', 'cash', 'Registrar movimientos de efectivo', 'Registrar entradas, salidas y ajustes autorizados.', true),
    ('cash.movements.reverse', 'cash', 'Revertir movimientos de efectivo', 'Revertir movimientos mediante registros compensatorios.', true),
    ('cash.expenses.read', 'cash', 'Consultar gastos menores', 'Consultar gastos menores pagados desde caja.', false),
    ('cash.expenses.create', 'cash', 'Registrar gastos menores', 'Crear solicitudes de gastos menores de caja.', true),
    ('cash.expenses.approve', 'cash', 'Aprobar gastos menores', 'Aprobar gastos menores sujetos a autorizacion.', true),
    ('cash.expenses.pay', 'cash', 'Pagar gastos menores', 'Pagar gastos menores aprobados con efectivo.', true),
    ('cash.counts.read', 'cash', 'Consultar arqueos', 'Consultar conteos y arqueos de caja.', false),
    ('cash.counts.create', 'cash', 'Crear arqueos', 'Registrar conteos de efectivo por denominacion.', true),
    ('cash.counts.submit', 'cash', 'Enviar arqueos', 'Enviar un conteo para revision o cierre.', true),
    ('cash.counts.approve', 'cash', 'Aprobar arqueos', 'Aprobar arqueos y diferencias de efectivo.', true),
    ('cash.reconciliations.read', 'cash', 'Consultar conciliaciones de caja', 'Consultar conciliaciones de efectivo por turno.', false),
    ('cash.reconciliations.approve', 'cash', 'Aprobar conciliaciones de caja', 'Aprobar conciliaciones y diferencias de turno.', true),
    ('cash.transfers.read', 'cash', 'Consultar traslados de caja', 'Consultar traslados entre cajas.', false),
    ('cash.transfers.create', 'cash', 'Solicitar traslados de caja', 'Solicitar traslados de efectivo entre cajas.', true),
    ('cash.transfers.approve', 'cash', 'Aprobar traslados de caja', 'Aprobar traslados de efectivo solicitados.', true),
    ('cash.transfers.post', 'cash', 'Registrar traslados de caja', 'Confirmar traslados aprobados con movimientos compensados.', true),
    ('cash.safes.read', 'cash', 'Consultar cajas fuertes', 'Consultar cajas fuertes y sus movimientos.', false),
    ('cash.safes.manage', 'cash', 'Administrar cajas fuertes', 'Crear y configurar cajas fuertes.', true),
    ('cash.safes.move', 'cash', 'Mover efectivo a cajas fuertes', 'Registrar movimientos autorizados hacia o desde cajas fuertes.', true),
    ('cash.drawer_events.read', 'cash', 'Consultar eventos de gaveta', 'Consultar eventos operativos de apertura de gaveta.', false),
    ('payments.read', 'payments', 'Consultar pagos', 'Consultar pagos y reembolsos.', false),
    ('payments.refund', 'payments', 'Procesar reembolsos', 'Solicitar o procesar reembolsos.', true),
    ('payments.methods.read', 'payments', 'Consultar medios de pago', 'Consultar medios de pago habilitados en el alcance autorizado.', false),
    ('payments.methods.manage', 'payments', 'Administrar medios de pago', 'Crear y configurar medios de pago por empresa o sucursal.', true),
    ('payments.providers.read', 'payments', 'Consultar proveedores de pago', 'Consultar cuentas y estado de proveedores de pago.', false),
    ('payments.providers.manage', 'payments', 'Administrar proveedores de pago', 'Configurar cuentas y referencias a secretos de proveedores.', true),
    ('payments.sessions.read', 'payments', 'Consultar sesiones de cobro', 'Consultar sesiones de cobro del alcance autorizado.', false),
    ('payments.sessions.create', 'payments', 'Crear sesiones de cobro', 'Iniciar una sesion para cobrar una cuenta.', true),
    ('payments.sessions.cancel', 'payments', 'Cancelar sesiones de cobro', 'Cancelar una sesion de cobro abierta con motivo.', true),
    ('payments.intents.read', 'payments', 'Consultar intents de pago', 'Consultar intents y su estado.', false),
    ('payments.intents.create', 'payments', 'Crear intents de pago', 'Solicitar autorizacion o cobro a un proveedor.', true),
    ('payments.transactions.read', 'payments', 'Consultar transacciones de pago', 'Consultar transacciones, capturas y anulaciones.', false),
    ('payments.transactions.capture', 'payments', 'Capturar pagos', 'Capturar fondos previamente autorizados.', true),
    ('payments.transactions.void', 'payments', 'Anular autorizaciones', 'Anular autorizaciones de pago vigentes.', true),
    ('payments.refunds.read', 'payments', 'Consultar reembolsos', 'Consultar solicitudes e intentos de reembolso.', false),
    ('payments.refunds.create', 'payments', 'Solicitar reembolsos', 'Solicitar reembolsos vinculados a una transaccion original.', true),
    ('payments.refunds.approve', 'payments', 'Aprobar reembolsos', 'Aprobar reembolsos segun limites y politicas.', true),
    ('payments.disputes.read', 'payments', 'Consultar disputas de pago', 'Consultar contracargos y sus vencimientos.', false),
    ('payments.disputes.manage', 'payments', 'Gestionar disputas de pago', 'Preparar evidencias y responder disputas de pago.', true),
    ('payments.settlements.read', 'payments', 'Consultar liquidaciones', 'Consultar lotes de liquidacion de proveedores.', false),
    ('payments.settlements.reconcile', 'payments', 'Conciliar liquidaciones', 'Conciliar liquidaciones reportadas por proveedores de pago.', true),
    ('payments.tokens.manage', 'payments', 'Administrar tokens de pago', 'Vincular o revocar referencias tokenizadas de medios de pago.', true),
    ('customers.read', 'customers', 'Consultar clientes', 'Consultar datos basicos de clientes.', false),
    ('customers.manage', 'customers', 'Administrar clientes', 'Crear y modificar datos basicos de clientes.', true),
    ('customers.profiles.read', 'customers', 'Consultar perfiles de clientes', 'Consultar perfiles personales del alcance autorizado.', true),
    ('customers.profiles.manage', 'customers', 'Administrar perfiles de clientes', 'Crear y modificar perfiles personales.', true),
    ('customers.business_profiles.read', 'customers', 'Consultar perfiles empresariales', 'Consultar perfiles fiscales y empresariales.', true),
    ('customers.business_profiles.manage', 'customers', 'Administrar perfiles empresariales', 'Crear y modificar perfiles fiscales y empresariales.', true),
    ('customers.contacts.read', 'customers', 'Consultar contactos de clientes', 'Acceder a datos de contacto descifrados y enmascarados.', true),
    ('customers.contacts.manage', 'customers', 'Administrar contactos de clientes', 'Crear, verificar, desactivar y modificar contactos.', true),
    ('customers.addresses.read', 'customers', 'Consultar direcciones de clientes', 'Acceder a direcciones descifradas del alcance autorizado.', true),
    ('customers.addresses.manage', 'customers', 'Administrar direcciones de clientes', 'Crear y modificar direcciones de clientes.', true),
    ('customers.consents.read', 'customers', 'Consultar consentimientos', 'Consultar consentimientos y su evidencia.', true),
    ('customers.consents.manage', 'customers', 'Administrar consentimientos', 'Registrar o revocar consentimientos de clientes.', true),
    ('customers.notes.read', 'customers', 'Consultar notas de clientes', 'Consultar notas internas segun su nivel de visibilidad.', true),
    ('customers.notes.manage', 'customers', 'Administrar notas de clientes', 'Crear o redactar notas internas de clientes.', true),
    ('customers.segments.read', 'customers', 'Consultar segmentos', 'Consultar segmentos y sus integrantes autorizados.', true),
    ('customers.segments.manage', 'customers', 'Administrar segmentos', 'Crear segmentos y administrar su composicion.', true),
    ('customers.loyalty.read', 'customers', 'Consultar fidelizacion', 'Consultar cuentas, puntos, recompensas y canjes.', false),
    ('customers.loyalty.manage', 'customers', 'Administrar fidelizacion', 'Acreditar, canjear y corregir puntos mediante el ledger.', true),
    ('customers.privacy.read', 'customers', 'Consultar solicitudes de privacidad', 'Consultar solicitudes de derechos de titulares.', true),
    ('customers.privacy.manage', 'customers', 'Administrar solicitudes de privacidad', 'Verificar y resolver solicitudes de privacidad.', true),
    ('customers.merge', 'customers', 'Fusionar clientes', 'Fusionar registros duplicados conservando trazabilidad.', true),
    ('customers.referrals.read', 'customers', 'Consultar referidos', 'Consultar referencias entre clientes.', true),
    ('customers.referrals.manage', 'customers', 'Administrar referidos', 'Gestionar estados y recompensas de referidos.', true),
    ('workforce.employees.read', 'workforce', 'Consultar empleados', 'Consultar datos laborales basicos dentro del alcance autorizado.', false),
    ('workforce.employees.manage', 'workforce', 'Administrar empleados', 'Crear y actualizar expedientes laborales.', true),
    ('workforce.profiles.read', 'workforce', 'Consultar perfiles laborales', 'Consultar datos personales protegidos del empleado.', true),
    ('workforce.profiles.manage', 'workforce', 'Administrar perfiles laborales', 'Administrar datos personales protegidos del empleado.', true),
    ('workforce.contacts.read', 'workforce', 'Consultar contactos laborales', 'Consultar contactos personales cifrados del empleado.', true),
    ('workforce.contacts.manage', 'workforce', 'Administrar contactos laborales', 'Administrar contactos personales cifrados del empleado.', true),
    ('workforce.documents.read', 'workforce', 'Consultar documentos laborales', 'Consultar metadatos de documentos laborales privados.', true),
    ('workforce.documents.manage', 'workforce', 'Administrar documentos laborales', 'Administrar documentos laborales privados.', true),
    ('workforce.employment.read', 'workforce', 'Consultar vinculaciones laborales', 'Consultar contratos y vinculaciones laborales.', true),
    ('workforce.employment.manage', 'workforce', 'Administrar vinculaciones laborales', 'Crear y actualizar contratos y vinculaciones laborales.', true),
    ('workforce.compensation.read', 'workforce', 'Consultar compensaciones', 'Consultar condiciones de remuneracion confidenciales.', true),
    ('workforce.compensation.manage', 'workforce', 'Administrar compensaciones', 'Administrar condiciones de remuneracion confidenciales.', true),
    ('workforce.schedules.read', 'workforce', 'Consultar horarios', 'Consultar plantillas y horarios de trabajo.', false),
    ('workforce.schedules.manage', 'workforce', 'Administrar horarios', 'Crear y actualizar plantillas de horarios.', true),
    ('workforce.shifts.read', 'workforce', 'Consultar turnos', 'Consultar turnos asignados dentro del alcance autorizado.', false),
    ('workforce.shifts.manage', 'workforce', 'Administrar turnos', 'Crear, modificar y cancelar turnos.', true),
    ('workforce.shifts.assign', 'workforce', 'Asignar turnos', 'Asignar empleados a turnos y sucursales autorizadas.', true),
    ('workforce.attendance.read', 'workforce', 'Consultar asistencia', 'Consultar marcaciones, asistencia y ajustes.', true),
    ('workforce.attendance.record', 'workforce', 'Registrar asistencia', 'Registrar marcaciones y asistencia manual.', true),
    ('workforce.attendance.adjust', 'workforce', 'Solicitar ajustes de asistencia', 'Solicitar correcciones de asistencia.', true),
    ('workforce.attendance.approve', 'workforce', 'Aprobar asistencia', 'Aprobar o rechazar asistencia y ajustes.', true),
    ('workforce.leave.read', 'workforce', 'Consultar ausencias', 'Consultar solicitudes y decisiones de ausencia.', true),
    ('workforce.leave.request', 'workforce', 'Solicitar ausencias', 'Crear y retirar solicitudes propias de ausencia.', true),
    ('workforce.leave.approve', 'workforce', 'Resolver ausencias', 'Aprobar o rechazar solicitudes de ausencia.', true),
    ('workforce.certifications.read', 'workforce', 'Consultar certificaciones', 'Consultar certificaciones laborales y vencimientos.', false),
    ('workforce.certifications.manage', 'workforce', 'Administrar certificaciones', 'Registrar y verificar certificaciones laborales.', true),
    ('workforce.training.read', 'workforce', 'Consultar formacion', 'Consultar formaciones y resultados laborales.', false),
    ('workforce.training.manage', 'workforce', 'Administrar formacion', 'Registrar formaciones y resultados laborales.', true),
    ('workforce.identity_links.manage', 'workforce', 'Vincular cuentas laborales', 'Vincular o revocar una cuenta Identity de un empleado.', true),
    ('finance.books.read', 'finance', 'Consultar libros contables', 'Consultar libros y moneda funcional del alcance autorizado.', false),
    ('finance.books.manage', 'finance', 'Administrar libros contables', 'Crear y configurar libros contables.', true),
    ('finance.periods.read', 'finance', 'Consultar periodos contables', 'Consultar ejercicios, periodos y cierres.', false),
    ('finance.periods.manage', 'finance', 'Administrar periodos contables', 'Crear y configurar ejercicios y periodos.', true),
    ('finance.periods.close', 'finance', 'Cerrar periodos contables', 'Cerrar o bloquear periodos contables.', true),
    ('finance.periods.reopen', 'finance', 'Reabrir periodos contables', 'Reabrir periodos cerrados mediante autorizacion.', true),
    ('finance.accounts.read', 'finance', 'Consultar plan de cuentas', 'Consultar cuentas, mapeos y centros de costos.', false),
    ('finance.accounts.manage', 'finance', 'Administrar plan de cuentas', 'Administrar cuentas, mapeos y centros de costos.', true),
    ('finance.journals.read', 'finance', 'Consultar asientos', 'Consultar asientos y lineas contables.', true),
    ('finance.journals.create', 'finance', 'Crear asientos', 'Crear asientos contables en borrador.', true),
    ('finance.journals.approve', 'finance', 'Aprobar asientos', 'Aprobar asientos pendientes de contabilizacion.', true),
    ('finance.journals.post', 'finance', 'Contabilizar asientos', 'Contabilizar asientos balanceados en periodos abiertos.', true),
    ('finance.journals.reverse', 'finance', 'Revertir asientos', 'Crear y contabilizar asientos de reverso.', true),
    ('finance.receivables.read', 'finance', 'Consultar cuentas por cobrar', 'Consultar saldos, vencimientos y aplicaciones.', true),
    ('finance.receivables.manage', 'finance', 'Administrar cuentas por cobrar', 'Crear y actualizar documentos por cobrar.', true),
    ('finance.receivables.apply', 'finance', 'Aplicar cobros', 'Aplicar pagos externos a cuentas por cobrar.', true),
    ('finance.receivables.adjust', 'finance', 'Ajustar cuentas por cobrar', 'Registrar ajustes y castigos de cuentas por cobrar.', true),
    ('finance.payables.read', 'finance', 'Consultar cuentas por pagar', 'Consultar saldos, vencimientos y aplicaciones.', true),
    ('finance.payables.manage', 'finance', 'Administrar cuentas por pagar', 'Crear y actualizar documentos por pagar.', true),
    ('finance.payables.apply', 'finance', 'Aplicar desembolsos', 'Aplicar desembolsos externos a cuentas por pagar.', true),
    ('finance.payables.adjust', 'finance', 'Ajustar cuentas por pagar', 'Registrar ajustes de cuentas por pagar.', true),
    ('finance.banks.read', 'finance', 'Consultar bancos', 'Consultar cuentas bancarias, extractos y conciliaciones.', true),
    ('finance.banks.manage', 'finance', 'Administrar bancos', 'Administrar cuentas bancarias e importaciones de extractos.', true),
    ('finance.banks.reconcile', 'finance', 'Conciliar bancos', 'Crear, revisar y aprobar conciliaciones bancarias.', true),
    ('finance.taxes.read', 'finance', 'Consultar impuestos', 'Consultar impuestos, periodos y declaraciones.', true),
    ('finance.taxes.manage', 'finance', 'Administrar impuestos', 'Administrar categorias y tarifas tributarias.', true),
    ('finance.taxes.file', 'finance', 'Gestionar declaraciones tributarias', 'Preparar y registrar declaraciones tributarias.', true),
    ('finance.reports.read', 'finance', 'Consultar reportes financieros', 'Consultar estados financieros y resultados autorizados.', true),
    ('billing.documents.read', 'billing', 'Consultar documentos fiscales', 'Consultar documentos fiscales y datos legales de clientes.', true),
    ('billing.documents.create', 'billing', 'Crear documentos fiscales', 'Crear borradores de documentos fiscales desde operaciones autorizadas.', true),
    ('billing.documents.issue', 'billing', 'Emitir documentos fiscales', 'Asignar consecutivo y emitir documentos fiscales.', true),
    ('billing.documents.cancel', 'billing', 'Cancelar documentos fiscales', 'Cancelar o anular documentos fiscales con motivo y trazabilidad.', true),
    ('billing.configuration.manage', 'billing', 'Administrar configuracion fiscal', 'Administrar emisores, tipos documentales, autorizaciones y series.', true),
    ('billing.submissions.read', 'billing', 'Consultar transmisiones fiscales', 'Consultar intentos y respuestas de transmision fiscal.', true),
    ('billing.submissions.manage', 'billing', 'Gestionar transmisiones fiscales', 'Enviar, reintentar y resolver transmisiones fiscales.', true),
    ('billing.artifacts.read', 'billing', 'Consultar artefactos fiscales', 'Consultar referencias a XML, UBL, PDF y soportes fiscales.', true),
    ('billing.deliveries.manage', 'billing', 'Gestionar entrega de documentos', 'Enviar documentos fiscales a sus destinatarios.', true),
    ('automation.workflows.read', 'automation', 'Consultar workflows', 'Consultar definiciones y versiones de workflows autorizados.', true),
    ('automation.workflows.manage', 'automation', 'Administrar workflows', 'Crear y editar borradores de workflows.', true),
    ('automation.workflows.publish', 'automation', 'Publicar workflows', 'Validar y publicar versiones de workflows.', true),
    ('automation.runs.read', 'automation', 'Consultar ejecuciones', 'Consultar ejecuciones, pasos y errores de workflows.', true),
    ('automation.runs.manage', 'automation', 'Administrar ejecuciones', 'Cancelar y reintentar ejecuciones autorizadas.', true),
    ('automation.approvals.read', 'automation', 'Consultar aprobaciones', 'Consultar solicitudes de aprobacion pendientes e historicas.', true),
    ('automation.approvals.decide', 'automation', 'Resolver aprobaciones', 'Aprobar o rechazar acciones de workflows asignadas.', true),
    ('automation.actions.manage', 'automation', 'Administrar acciones permitidas', 'Configurar acciones declarativas habilitadas para workflows.', true),
    ('automation.settings.manage', 'automation', 'Administrar automatizacion', 'Administrar limites y configuracion de Automation.', true),
    ('automation.audit.read', 'automation', 'Consultar auditoria de automatizacion', 'Consultar auditoria de cambios y ejecuciones de workflows.', true),
    ('integrations.catalog.read', 'integrations', 'Consultar conectores', 'Consultar proveedores y capacidades de integracion disponibles.', false),
    ('integrations.catalog.manage', 'integrations', 'Administrar conectores', 'Administrar conectores personalizados habilitados para el tenant.', true),
    ('integrations.connections.read', 'integrations', 'Consultar conexiones', 'Consultar conexiones externas y su estado.', true),
    ('integrations.connections.manage', 'integrations', 'Administrar conexiones', 'Crear, configurar, conectar y desactivar integraciones.', true),
    ('integrations.credentials.manage', 'integrations', 'Administrar referencias de credenciales', 'Crear, rotar y revocar referencias a secretos externos.', true),
    ('integrations.webhooks.read', 'integrations', 'Consultar webhooks', 'Consultar endpoints, eventos y entregas de webhooks.', true),
    ('integrations.webhooks.manage', 'integrations', 'Administrar webhooks', 'Configurar endpoints entrantes y destinos salientes.', true),
    ('integrations.deliveries.read', 'integrations', 'Consultar entregas', 'Consultar entregas externas, intentos y resultados.', true),
    ('integrations.deliveries.manage', 'integrations', 'Administrar entregas', 'Reintentar o cancelar entregas externas autorizadas.', true),
    ('integrations.sync.read', 'integrations', 'Consultar sincronizaciones', 'Consultar trabajos, cursores y ejecuciones de sincronizacion.', true),
    ('integrations.sync.manage', 'integrations', 'Administrar sincronizaciones', 'Configurar, iniciar y detener trabajos de sincronizacion.', true),
    ('integrations.logs.read', 'integrations', 'Consultar logs de integracion', 'Consultar logs tecnicos previamente redactados.', true),
    ('integrations.audit.read', 'integrations', 'Consultar auditoria de integraciones', 'Consultar cambios y acciones de administracion de integraciones.', true),
    ('analytics.dashboards.read', 'analytics', 'Consultar dashboards', 'Consultar dashboards y resultados analiticos dentro del alcance autorizado.', false),
    ('analytics.dashboards.manage', 'analytics', 'Administrar dashboards', 'Crear y configurar dashboards dentro del alcance autorizado.', true),
    ('analytics.metrics.read', 'analytics', 'Consultar metricas', 'Consultar el catalogo semantico de metricas disponibles.', false),
    ('analytics.metrics.manage', 'analytics', 'Administrar metricas', 'Crear y configurar definiciones semanticas de metricas.', true),
    ('analytics.data.read', 'analytics', 'Consultar datos analiticos', 'Consultar modelos y agregados analiticos dentro del alcance autorizado.', true),
    ('analytics.refresh.manage', 'analytics', 'Administrar refrescos analiticos', 'Configurar y ejecutar refrescos de modelos analiticos autorizados.', true),
    ('analytics.audit.read', 'analytics', 'Consultar auditoria analitica', 'Consultar la auditoria de consultas analiticas.', true),
    ('audit.events.read', 'audit', 'Consultar eventos de auditoria', 'Consultar eventos operativos dentro del alcance y clasificaciones autorizados.', true),
    ('audit.integrity.verify', 'audit', 'Verificar integridad', 'Verificar hashes y continuidad de las cadenas de auditoria.', true),
    ('audit.exports.request', 'audit', 'Solicitar exportaciones', 'Solicitar exportaciones de auditoria con motivo y filtros autorizados.', true),
    ('audit.exports.approve', 'audit', 'Aprobar exportaciones', 'Aprobar o rechazar exportaciones de auditoria sensibles.', true),
    ('audit.retention.manage', 'audit', 'Administrar retencion', 'Administrar politicas y ejecuciones de retencion y archivo.', true),
    ('audit.legal_holds.manage', 'audit', 'Administrar legal holds', 'Crear, aprobar, liberar y consultar retenciones legales.', true),
    ('audit.access.manage', 'audit', 'Administrar accesos de auditoria', 'Administrar politicas y concesiones de acceso a auditoria.', true),
    ('audit.access.read', 'audit', 'Consultar accesos de auditoria', 'Consultar accesos, consultas y denegaciones sobre Audit.', true),
    ('audit.alerts.read', 'audit', 'Consultar alertas de auditoria', 'Consultar alertas de seguridad y sus estados.', true),
    ('audit.alerts.manage', 'audit', 'Administrar alertas', 'Configurar reglas y resolver alertas de seguridad.', true),
    ('audit.redaction.manage', 'audit', 'Administrar redaccion', 'Administrar politicas de redaccion de eventos y evidencias.', true),
    ('audit.settings.manage', 'audit', 'Administrar configuracion de auditoria', 'Administrar fuentes, catalogos y configuracion del tenant.', true),
    ('audit.evidence.manage', 'audit', 'Administrar evidencias', 'Asociar referencias de evidencia externa a eventos de auditoria.', true),
    ('reports.read', 'reporting', 'Consultar informes', 'Consultar informes autorizados dentro del alcance asignado.', false),
    ('reports.generate', 'reporting', 'Generar informes', 'Solicitar la generacion de informes autorizados.', false),
    ('reports.export', 'reporting', 'Exportar informes', 'Descargar informes en formatos autorizados.', false),
    ('reports.definitions.manage', 'reporting', 'Administrar definiciones', 'Crear y configurar definiciones, parametros y secciones de informes.', true),
    ('reports.templates.manage', 'reporting', 'Administrar plantillas', 'Crear, versionar y publicar plantillas de informes.', true),
    ('reports.schedules.manage', 'reporting', 'Administrar programaciones', 'Crear, pausar y administrar informes programados.', true),
    ('reports.distribution.manage', 'reporting', 'Administrar distribucion', 'Configurar destinatarios y canales de entrega de informes.', true),
    ('reports.approvals.decide', 'reporting', 'Resolver aprobaciones', 'Aprobar o rechazar solicitudes de informes protegidos.', true),
    ('reports.access.manage', 'reporting', 'Administrar accesos', 'Administrar politicas y concesiones de acceso a informes.', true),
    ('audit.read', 'audit', 'Consultar auditoria', 'Consultar la trazabilidad del tenant.', true),
    ('settings.read', 'settings', 'Consultar configuracion', 'Consultar configuracion de empresa/sucursal.', false),
    ('settings.manage', 'settings', 'Administrar configuracion', 'Modificar configuracion de empresa/sucursal.', true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 17. Funcion de aprovisionamiento de roles y politicas por tenant
-- ---------------------------------------------------------------------------
-- Debe invocarse con SET LOCAL app.tenant_id igual a p_tenant_id.
-- No es SECURITY DEFINER: las politicas RLS siguen aplicandose al caller.

CREATE OR REPLACE FUNCTION identity.initialize_tenant_identity(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tenant_id IS NULL OR identity.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El contexto app.tenant_id debe coincidir con el tenant a inicializar';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM platform.tenants t WHERE t.id = p_tenant_id) THEN
        RAISE EXCEPTION 'El tenant % no existe', p_tenant_id;
    END IF;

    INSERT INTO identity.tenant_auth_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO identity.roles (tenant_id, code, name, description, is_system)
    VALUES
        (p_tenant_id, 'tenant_owner', 'Propietario del tenant', 'Control total de la operacion del tenant.', true),
        (p_tenant_id, 'company_admin', 'Administrador de empresa', 'Administracion de una empresa y sus sucursales asignadas.', true),
        (p_tenant_id, 'branch_manager', 'Administrador de sucursal', 'Administracion operativa de una sucursal.', true),
        (p_tenant_id, 'workforce_manager', 'Administrador de personal', 'Administracion laboral y de personal dentro del alcance autorizado.', true),
        (p_tenant_id, 'finance_manager', 'Administrador financiero', 'Administracion contable, bancaria y tributaria dentro del alcance autorizado.', true),
        (p_tenant_id, 'billing_manager', 'Administrador de facturacion fiscal', 'Administracion de documentos y configuracion fiscal dentro del alcance autorizado.', true),
        (p_tenant_id, 'automation_manager', 'Administrador de automatizacion', 'Administracion de workflows, acciones y ejecuciones dentro del alcance autorizado.', true),
        (p_tenant_id, 'integrations_manager', 'Administrador de integraciones', 'Administracion de conexiones, credenciales, webhooks y sincronizaciones dentro del alcance autorizado.', true),
        (p_tenant_id, 'analytics_manager', 'Administrador de analitica', 'Administracion de metricas y dashboards empresariales dentro del alcance autorizado.', true),
        (p_tenant_id, 'reporting_manager', 'Administrador de Reporting', 'Administracion de definiciones, plantillas, exportaciones y distribucion de informes.', true),
        (p_tenant_id, 'audit_manager', 'Administrador de auditoria', 'Administracion de politicas, retencion, alertas y exportaciones de auditoria.', true),
        (p_tenant_id, 'auditor', 'Auditor', 'Consulta de eventos y verificacion de integridad dentro del alcance autorizado.', true),
        (p_tenant_id, 'security_auditor', 'Auditor de seguridad', 'Consulta de auditoria y accesos de seguridad con clasificaciones autorizadas.', true),
        (p_tenant_id, 'cashier', 'Cajero', 'Registro de ventas y operaciones de caja autorizadas.', true),
        (p_tenant_id, 'inventory_manager', 'Administrador de inventario', 'Gestion de existencias, ajustes y transferencias.', true),
        (p_tenant_id, 'viewer', 'Solo lectura', 'Consulta de informacion permitida en el alcance asignado.', true)
    ON CONFLICT (tenant_id, code) DO NOTHING;

    -- Propietario del tenant: todos los permisos existentes del catalogo.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    CROSS JOIN identity.permissions p
    WHERE r.tenant_id = p_tenant_id
      AND r.code = 'tenant_owner'
    ON CONFLICT DO NOTHING;

    -- Administrador de empresa: administracion funcional sin permisos de auditoria
    -- sensible ni de creacion/administracion de roles.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'dashboard.read', 'profile.read', 'profile.update', 'users.read',
        'users.invite', 'users.create', 'users.update', 'users.disable',
        'roles.read', 'companies.read', 'companies.manage', 'branches.read',
        'branches.manage', 'catalog.read', 'catalog.manage', 'inventory.read',
        'inventory.manage', 'inventory.adjust', 'inventory.transfer',
        'procurement.suppliers.read', 'procurement.suppliers.create',
        'procurement.suppliers.update', 'procurement.suppliers.approve',
        'procurement.suppliers.suspend', 'procurement.suppliers.documents.manage',
        'procurement.suppliers.evaluate', 'procurement.suppliers.categories.manage',
        'procurement.suppliers.branch_profiles.manage',
        'procurement.sourcing.read', 'procurement.sourcing.create',
        'procurement.sourcing.publish', 'procurement.sourcing.cancel',
        'procurement.quotes.read', 'procurement.quotes.submit',
        'procurement.quotes.evaluate', 'procurement.quotes.award',
        'procurement.agreements.read', 'procurement.agreements.manage',
        'procurement.requests.read', 'procurement.requests.create',
        'procurement.requests.approve', 'procurement.requests.reject',
        'procurement.orders.read', 'procurement.orders.create',
        'procurement.orders.approve', 'procurement.orders.issue',
        'procurement.orders.cancel', 'procurement.orders.schedule.manage',
        'procurement.receipts.read', 'procurement.receipts.create',
        'procurement.receipts.post', 'procurement.receipts.inspect',
        'procurement.receipts.discrepancies.manage', 'procurement.returns.read',
        'procurement.returns.create', 'procurement.returns.approve',
        'procurement.returns.complete', 'procurement.documents.manage',
        'procurement.settings.manage',
        'procurement.invoices.read', 'procurement.invoices.create',
        'procurement.invoices.match', 'procurement.invoices.approve',
        'production.read', 'production.recipes.read', 'production.recipes.create',
        'production.recipes.update', 'production.recipes.publish', 'production.recipes.retire',
        'production.orders.read', 'production.orders.create', 'production.orders.approve',
        'production.orders.release', 'production.orders.pause', 'production.orders.complete',
        'production.materials.plan', 'production.materials.issue', 'production.materials.return',
        'production.outputs.report', 'production.waste.report', 'production.quality.read',
        'production.quality.inspect', 'production.quality.release',
        'production.work_centers.manage', 'production.routings.manage',
        'sales.read', 'sales.create', 'sales.discount',
        'sales.void', 'cash.read', 'cash.open', 'cash.close', 'cash.manage',
        'cash.registers.read', 'cash.registers.manage',
        'cash.sessions.read', 'cash.sessions.open', 'cash.sessions.close',
        'cash.sessions.cancel', 'cash.sessions.assign_cashier',
        'cash.movements.read', 'cash.movements.create', 'cash.movements.reverse',
        'cash.expenses.read', 'cash.expenses.create', 'cash.expenses.approve', 'cash.expenses.pay',
        'cash.counts.read', 'cash.counts.create', 'cash.counts.submit', 'cash.counts.approve',
        'cash.reconciliations.read', 'cash.reconciliations.approve',
        'cash.transfers.read', 'cash.transfers.create', 'cash.transfers.approve', 'cash.transfers.post',
        'cash.safes.read', 'cash.safes.manage', 'cash.safes.move', 'cash.drawer_events.read',
        'payments.read', 'payments.refund',
        'payments.methods.read', 'payments.methods.manage',
        'payments.providers.read', 'payments.providers.manage',
        'payments.sessions.read', 'payments.sessions.create', 'payments.sessions.cancel',
        'payments.intents.read', 'payments.intents.create',
        'payments.transactions.read', 'payments.transactions.capture',
        'payments.transactions.void', 'payments.refunds.read',
        'payments.refunds.create', 'payments.refunds.approve',
        'payments.disputes.read', 'payments.disputes.manage',
        'payments.settlements.read', 'payments.settlements.reconcile',
        'payments.tokens.manage', 'customers.read', 'customers.manage',
        'customers.profiles.read', 'customers.profiles.manage',
        'customers.business_profiles.read', 'customers.business_profiles.manage',
        'customers.contacts.read', 'customers.contacts.manage',
        'customers.addresses.read', 'customers.addresses.manage',
        'customers.consents.read', 'customers.consents.manage',
        'customers.notes.read', 'customers.notes.manage',
        'customers.segments.read', 'customers.segments.manage',
        'customers.loyalty.read', 'customers.loyalty.manage',
        'customers.privacy.read', 'customers.privacy.manage', 'customers.merge',
        'customers.referrals.read', 'customers.referrals.manage',
        'workforce.employees.read', 'workforce.employees.manage',
        'workforce.employment.read', 'workforce.employment.manage',
        'workforce.schedules.read', 'workforce.schedules.manage',
        'workforce.shifts.read', 'workforce.shifts.manage', 'workforce.shifts.assign',
        'workforce.attendance.read', 'workforce.attendance.record',
        'workforce.attendance.adjust', 'workforce.attendance.approve',
        'workforce.leave.read', 'workforce.leave.request', 'workforce.leave.approve',
        'workforce.certifications.read', 'workforce.certifications.manage',
        'workforce.training.read', 'workforce.training.manage',
        'billing.documents.read', 'billing.documents.create', 'billing.documents.issue',
        'billing.documents.cancel', 'billing.configuration.manage',
        'billing.submissions.read', 'billing.submissions.manage',
        'billing.artifacts.read', 'billing.deliveries.manage',
        'automation.workflows.read', 'automation.workflows.manage',
        'automation.workflows.publish', 'automation.runs.read',
        'automation.runs.manage', 'automation.approvals.read',
        'automation.approvals.decide', 'automation.actions.manage',
        'automation.settings.manage', 'automation.audit.read',
        'integrations.catalog.read', 'integrations.catalog.manage',
        'integrations.connections.read', 'integrations.connections.manage',
        'integrations.credentials.manage', 'integrations.webhooks.read',
        'integrations.webhooks.manage', 'integrations.deliveries.read',
        'integrations.deliveries.manage', 'integrations.sync.read',
        'integrations.sync.manage', 'integrations.logs.read',
        'integrations.audit.read',
        'analytics.dashboards.read', 'analytics.dashboards.manage',
        'analytics.metrics.read', 'analytics.metrics.manage', 'analytics.data.read',
        'reports.read', 'reports.generate', 'reports.export',
        'reports.definitions.manage', 'reports.templates.manage',
        'reports.schedules.manage', 'reports.distribution.manage',
        'reports.approvals.decide', 'reports.access.manage',
        'settings.read', 'settings.manage'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'company_admin'
    ON CONFLICT DO NOTHING;

    -- Administrador de sucursal: operaciones del local, sin administrar el tenant.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'dashboard.read', 'profile.read', 'profile.update', 'users.read',
        'branches.read', 'catalog.read', 'inventory.read', 'inventory.manage',
        'inventory.adjust', 'inventory.transfer',
        'procurement.suppliers.read', 'procurement.requests.read',
        'procurement.requests.create', 'procurement.orders.read',
        'procurement.orders.create', 'procurement.orders.schedule.manage',
        'procurement.receipts.read', 'procurement.receipts.create',
        'procurement.receipts.inspect', 'procurement.receipts.discrepancies.manage',
        'procurement.returns.read', 'procurement.returns.create',
        'procurement.documents.manage',
        'production.read', 'production.recipes.read', 'production.recipes.create',
        'production.recipes.update', 'production.orders.read', 'production.orders.create',
        'production.orders.approve', 'production.orders.release', 'production.orders.pause',
        'production.orders.complete', 'production.materials.plan', 'production.materials.issue',
        'production.materials.return', 'production.outputs.report', 'production.waste.report',
        'production.quality.read', 'production.quality.inspect', 'production.quality.release',
        'production.work_centers.manage', 'production.routings.manage',
        'sales.read', 'sales.create',
        'sales.discount', 'sales.void', 'cash.read', 'cash.open', 'cash.close',
        'cash.manage', 'cash.registers.read', 'cash.registers.manage',
        'cash.sessions.read', 'cash.sessions.open', 'cash.sessions.close',
        'cash.sessions.cancel', 'cash.sessions.assign_cashier',
        'cash.movements.read', 'cash.movements.create', 'cash.movements.reverse',
        'cash.expenses.read', 'cash.expenses.create', 'cash.expenses.approve', 'cash.expenses.pay',
        'cash.counts.read', 'cash.counts.create', 'cash.counts.submit', 'cash.counts.approve',
        'cash.reconciliations.read', 'cash.reconciliations.approve',
        'cash.transfers.read', 'cash.transfers.create', 'cash.transfers.approve', 'cash.transfers.post',
        'cash.safes.read', 'cash.safes.manage', 'cash.safes.move', 'cash.drawer_events.read',
        'payments.read', 'payments.refund',
        'payments.methods.read', 'payments.methods.manage', 'payments.providers.read',
        'payments.sessions.read', 'payments.sessions.create', 'payments.sessions.cancel',
        'payments.intents.read', 'payments.intents.create',
        'payments.transactions.read', 'payments.transactions.capture',
        'payments.transactions.void', 'payments.refunds.read', 'payments.refunds.create',
        'payments.disputes.read', 'customers.read',
        'customers.manage', 'customers.profiles.read', 'customers.profiles.manage',
        'customers.business_profiles.read', 'customers.contacts.read', 'customers.contacts.manage',
        'customers.addresses.read', 'customers.addresses.manage',
        'customers.consents.read', 'customers.consents.manage',
        'customers.notes.read', 'customers.notes.manage',
        'customers.segments.read', 'customers.segments.manage',
        'customers.loyalty.read', 'customers.loyalty.manage',
        'customers.referrals.read', 'customers.referrals.manage',
        'workforce.employees.read',
        'workforce.schedules.read', 'workforce.schedules.manage',
        'workforce.shifts.read', 'workforce.shifts.manage', 'workforce.shifts.assign',
        'workforce.attendance.read', 'workforce.attendance.record',
        'workforce.attendance.adjust', 'workforce.attendance.approve',
        'workforce.leave.read', 'workforce.leave.approve',
        'workforce.certifications.read', 'workforce.training.read',
        'billing.documents.read', 'billing.documents.create', 'billing.documents.issue',
        'billing.submissions.read', 'billing.artifacts.read',
        'automation.workflows.read', 'automation.runs.read',
        'automation.runs.manage', 'automation.approvals.read',
        'automation.approvals.decide',
        'integrations.catalog.read', 'integrations.connections.read',
        'integrations.connections.manage', 'integrations.webhooks.read',
        'integrations.deliveries.read', 'integrations.sync.read',
        'analytics.dashboards.read', 'analytics.metrics.read', 'analytics.data.read',
        'reports.read', 'reports.generate', 'reports.export',
        'reports.schedules.manage', 'settings.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'branch_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador de Analytics: acceso completo a metricas, dashboards y auditoria analitica.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'analytics.dashboards.read', 'analytics.dashboards.manage',
        'analytics.metrics.read', 'analytics.metrics.manage',
        'analytics.data.read', 'analytics.refresh.manage', 'analytics.audit.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'analytics_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador de Reporting: control completo de informes, sujeto a alcance y aprobaciones.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'reports.read', 'reports.generate', 'reports.export',
        'reports.definitions.manage', 'reports.templates.manage',
        'reports.schedules.manage', 'reports.distribution.manage',
        'reports.approvals.decide', 'reports.access.manage'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'reporting_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador de Audit: configuracion, proteccion, consulta y exportacion.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'audit.read', 'audit.events.read', 'audit.integrity.verify',
        'audit.exports.request', 'audit.exports.approve', 'audit.retention.manage',
        'audit.legal_holds.manage', 'audit.access.manage', 'audit.access.read',
        'audit.alerts.read', 'audit.alerts.manage', 'audit.redaction.manage',
        'audit.settings.manage', 'audit.evidence.manage'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'audit_manager'
    ON CONFLICT DO NOTHING;

    -- Auditor: consulta de operaciones ordinarias, sin acceso privilegiado de seguridad.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'audit.read', 'audit.events.read', 'audit.integrity.verify', 'audit.exports.request'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'auditor'
    ON CONFLICT DO NOTHING;

    -- Auditor de seguridad: acceso ampliado controlado además por las access_policies de Audit.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'audit.read', 'audit.events.read', 'audit.integrity.verify',
        'audit.exports.request', 'audit.access.read', 'audit.alerts.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'security_auditor'
    ON CONFLICT DO NOTHING;

    -- Administrador de personal: acceso laboral, con permisos sensibles explicitos.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'workforce.employees.read', 'workforce.employees.manage',
        'workforce.profiles.read', 'workforce.profiles.manage',
        'workforce.contacts.read', 'workforce.contacts.manage',
        'workforce.documents.read', 'workforce.documents.manage',
        'workforce.employment.read', 'workforce.employment.manage',
        'workforce.compensation.read', 'workforce.compensation.manage',
        'workforce.schedules.read', 'workforce.schedules.manage',
        'workforce.shifts.read', 'workforce.shifts.manage', 'workforce.shifts.assign',
        'workforce.attendance.read', 'workforce.attendance.record',
        'workforce.attendance.adjust', 'workforce.attendance.approve',
        'workforce.leave.read', 'workforce.leave.request', 'workforce.leave.approve',
        'workforce.certifications.read', 'workforce.certifications.manage',
        'workforce.training.read', 'workforce.training.manage',
        'workforce.identity_links.manage'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'workforce_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador financiero: permisos financieros explicitos y aislados.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'finance.books.read', 'finance.books.manage',
        'finance.periods.read', 'finance.periods.manage',
        'finance.periods.close', 'finance.periods.reopen',
        'finance.accounts.read', 'finance.accounts.manage',
        'finance.journals.read', 'finance.journals.create',
        'finance.journals.approve', 'finance.journals.post', 'finance.journals.reverse',
        'finance.receivables.read', 'finance.receivables.manage',
        'finance.receivables.apply', 'finance.receivables.adjust',
        'finance.payables.read', 'finance.payables.manage',
        'finance.payables.apply', 'finance.payables.adjust',
        'finance.banks.read', 'finance.banks.manage', 'finance.banks.reconcile',
        'finance.taxes.read', 'finance.taxes.manage', 'finance.taxes.file',
        'finance.reports.read', 'reports.read', 'reports.generate', 'reports.export'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'finance_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador fiscal: permisos completos, independientes de billing SaaS.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'billing.documents.read', 'billing.documents.create', 'billing.documents.issue',
        'billing.documents.cancel', 'billing.configuration.manage',
        'billing.submissions.read', 'billing.submissions.manage',
        'billing.artifacts.read', 'billing.deliveries.manage'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'billing_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador de Automation: administracion completa de workflows y ejecuciones.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'automation.workflows.read', 'automation.workflows.manage',
        'automation.workflows.publish', 'automation.runs.read',
        'automation.runs.manage', 'automation.approvals.read',
        'automation.approvals.decide', 'automation.actions.manage',
        'automation.settings.manage', 'automation.audit.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'automation_manager'
    ON CONFLICT DO NOTHING;

    -- Administrador de Integrations: acceso completo a conectores y transporte externo.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'integrations.catalog.read', 'integrations.catalog.manage',
        'integrations.connections.read', 'integrations.connections.manage',
        'integrations.credentials.manage', 'integrations.webhooks.read',
        'integrations.webhooks.manage', 'integrations.deliveries.read',
        'integrations.deliveries.manage', 'integrations.sync.read',
        'integrations.sync.manage', 'integrations.logs.read',
        'integrations.audit.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'integrations_manager'
    ON CONFLICT DO NOTHING;

    -- Cajero: venta, clientes y caja dentro del alcance de sucursal asignado.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'profile.read', 'profile.update', 'catalog.read', 'sales.read',
        'sales.create', 'customers.read', 'customers.manage',
        'customers.contacts.read', 'customers.contacts.manage',
        'customers.addresses.read', 'customers.consents.read', 'customers.consents.manage',
        'customers.loyalty.read', 'customers.loyalty.manage', 'cash.read',
        'cash.open', 'cash.close', 'cash.registers.read',
        'cash.sessions.read', 'cash.sessions.open', 'cash.sessions.close',
        'cash.movements.read', 'cash.movements.create',
        'cash.expenses.read', 'cash.expenses.create', 'cash.expenses.pay',
        'cash.counts.read', 'cash.counts.create', 'cash.counts.submit',
        'payments.read',
        'payments.methods.read', 'payments.sessions.read', 'payments.sessions.create',
        'payments.sessions.cancel', 'payments.intents.read', 'payments.intents.create',
        'payments.transactions.read', 'payments.transactions.capture',
        'payments.refunds.create',
        'billing.documents.read', 'billing.documents.create', 'billing.documents.issue',
        'billing.artifacts.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'cashier'
    ON CONFLICT DO NOTHING;

    -- Administrador de inventario.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'profile.read', 'catalog.read', 'inventory.read', 'inventory.manage',
        'inventory.adjust', 'inventory.transfer', 'procurement.suppliers.read',
        'procurement.orders.read', 'procurement.receipts.read',
        'procurement.receipts.create', 'procurement.receipts.post',
        'procurement.receipts.inspect', 'procurement.receipts.discrepancies.manage',
        'procurement.returns.read', 'procurement.returns.create',
        'procurement.returns.complete', 'procurement.documents.manage',
        'reports.read', 'reports.generate', 'reports.export'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'inventory_manager'
    ON CONFLICT DO NOTHING;

    -- Solo lectura.
    INSERT INTO identity.role_permissions (tenant_id, role_id, permission_id)
    SELECT p_tenant_id, r.id, p.id
    FROM identity.roles r
    JOIN identity.permissions p ON p.code IN (
        'dashboard.read', 'profile.read', 'users.read', 'roles.read',
        'companies.read', 'branches.read', 'catalog.read', 'inventory.read',
        'procurement.suppliers.read', 'procurement.sourcing.read',
        'procurement.quotes.read', 'procurement.agreements.read',
        'procurement.requests.read', 'procurement.orders.read',
        'procurement.receipts.read', 'procurement.returns.read',
        'procurement.invoices.read',
        'production.read', 'production.recipes.read', 'production.orders.read',
        'production.quality.read', 'sales.read', 'cash.read',
        'cash.registers.read', 'cash.sessions.read', 'cash.movements.read',
        'cash.expenses.read', 'cash.counts.read', 'cash.reconciliations.read',
        'cash.transfers.read', 'cash.safes.read', 'cash.drawer_events.read',
        'payments.read', 'payments.methods.read', 'payments.sessions.read',
        'payments.intents.read', 'payments.transactions.read', 'payments.refunds.read',
        'customers.read', 'workforce.employees.read', 'workforce.schedules.read',
        'workforce.shifts.read', 'analytics.dashboards.read',
        'analytics.metrics.read', 'analytics.data.read', 'reports.read', 'settings.read'
    )
    WHERE r.tenant_id = p_tenant_id AND r.code = 'viewer'
    ON CONFLICT DO NOTHING;
END;
$$;

COMMENT ON FUNCTION identity.initialize_tenant_identity(uuid) IS
'Inicializa politicas de autenticacion y roles base. Llamar desde el aprovisionador con SET LOCAL app.tenant_id del mismo tenant.';

-- ---------------------------------------------------------------------------
-- 18. Comentarios de integracion y limites entre modulos
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN identity.user_role_assignments.company_id IS
'UUID de organization.companies. Se usa solo para asignaciones con scope company o branch.';
COMMENT ON COLUMN identity.user_role_assignments.branch_id IS
'UUID de organization.branches. Una asignacion branch se limita a esa sucursal.';
COMMENT ON COLUMN identity.user_status_history.actor_id IS
'UUID del actor; referencia polimorfica para evitar FK circular con el actor que ejecuta la operacion.';
COMMENT ON COLUMN identity.user_invitations.invitation_token_hash IS
'Hash de un token aleatorio de un solo uso; el token original se envia al invitado y no se almacena.';
COMMENT ON COLUMN identity.user_sessions.refresh_token_hash IS
'Hash del refresh token rotatorio. El access token JWT de corta duracion no se almacena en esta tabla.';

COMMIT;

-- ============================================================================
-- EJEMPLO DE USO POST-INSTALACION (NO EJECUTAR SIN REEMPLAZAR EL UUID)
-- ============================================================================
-- El contexto debe establecerse dentro de la misma transaccion que usa la app:
--
-- BEGIN;
-- SET LOCAL app.tenant_id = '00000000-0000-0000-0000-000000000000';
-- SELECT identity.initialize_tenant_identity(
--     '00000000-0000-0000-0000-000000000000'::uuid
-- );
-- COMMIT;
--
-- EJEMPLO DE ALTA DE USUARIO (la aplicacion debe generar password_hash Argon2id):
--
-- BEGIN;
-- SET LOCAL app.tenant_id = '<TENANT_UUID>';
-- WITH new_user AS (
--   INSERT INTO identity.users (tenant_id, user_code, email, full_name, status)
--   VALUES ('<TENANT_UUID>', 'USR-0001', 'usuario@empresa.com', 'Usuario Ejemplo', 'active')
--   RETURNING tenant_id, id
-- )
-- INSERT INTO identity.password_credentials (tenant_id, user_id, password_hash)
-- SELECT tenant_id, id, '<ARGON2ID_HASH_GENERADO_EN_LA_APLICACION>'
-- FROM new_user;
-- COMMIT;
--
-- EJEMPLO DE ASIGNACION DEL ROL CAJERO A UNA SUCURSAL:
-- BEGIN;
-- SET LOCAL app.tenant_id = '<TENANT_UUID>';
-- INSERT INTO identity.user_role_assignments
--   (tenant_id, user_id, role_id, scope_type, company_id, branch_id)
-- SELECT '<TENANT_UUID>', '<USER_UUID>', r.id, 'branch', '<COMPANY_UUID>', '<BRANCH_UUID>'
-- FROM identity.roles r
-- WHERE r.tenant_id = '<TENANT_UUID>' AND r.code = 'cashier';
-- COMMIT;
--
-- REGLAS OPERATIVAS OBLIGATORIAS:
--   1) Validar en backend que el usuario autenticado puede asignar ese rol/alcance.
--   2) No confiar en tenant_id, company_id ni branch_id enviados por el cliente.
--   3) Evaluar expiracion/revocacion de user_role_assignments en cada autorizacion.
--   4) Las asignaciones tenant/company/branch se combinan; no asumir que una
--      asignacion de rol por si sola constituye un login autorizado.
--   5) Rotar refresh tokens y revocar toda la token_family ante reutilizacion.
--   6) Aplicar rate limiting fuera de PostgreSQL y registrar intentos relevantes.
--   7) Las operaciones sensibles (asignar roles, desactivar MFA, reembolsar,
--      anular ventas) deben exigir permisos y, segun politica, MFA reciente.
--   8) Conceder al rol runtime solo los permisos SQL necesarios. No otorgar
--      BYPASSRLS, SUPERUSER ni propiedad de tablas.
-- ============================================================================
