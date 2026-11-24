-- ============================================================================
-- RESTAURANT-OS - POS SAAS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 17: INTEGRATIONS (CONECTORES Y COMUNICACIONES EXTERNAS)
-- Numeracion tecnica de migraciones; requisitos.md enumera Integrations como modulo funcional 15.
-- Ubicacion del crate: crates/modules/integrations
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD
--   * Catalogo por tenant de proveedores/conectores externos habilitados.
--   * Conexiones, cuentas externas, permisos/scopes y salud de integraciones.
--   * Referencias a credenciales almacenadas en KMS/Vault/Secret Manager.
--   * Flujos OAuth y callbacks, sin guardar access/refresh tokens en claro.
--   * Recepcion y entrega tecnica de webhooks.
--   * Entregas salientes a sistemas externos, con reintentos e idempotencia.
--   * Sincronizaciones, cursores e identificadores externos.
--   * Registro tecnico de llamadas API, rate limits, Inbox, Outbox y auditoria.
--
-- FUERA DE ALCANCE / PROPIETARIO ES OTRO MODULO
--   * Reglas y orquestacion de workflows: automation.
--   * Reglas de negocio de pagos, cuentas de pasarela, autorizaciones, capturas,
--     reembolsos y webhooks normalizados de pago: payments.
--   * Facturas, documentos fiscales, envios tributarios y eventos fiscales
--     normalizados: billing.
--   * Inventario, ventas, compras, clientes, contabilidad y usuarios: sus
--     respectivos modulos propietarios.
--   * Los secretos reales, tokens OAuth y claves privadas se guardan fuera de
--     PostgreSQL en KMS/Vault/Secret Manager. Esta base guarda solo referencias.
--
-- DISTINCION DE WEBHOOKS
--   * Integrations conserva la recepcion/entrega tecnica HTTP, firma verificada,
--     hash, intentos y resultado de transporte.
--   * Payments y Billing pueden mantener sus propios registros normalizados de
--     eventos de negocio del proveedor. No se sustituyen desde este modulo.
--   * La aplicacion debe eliminar/redactar PII, cookies, autorizaciones y
--     secretos antes de persistir headers o payloads.
--
-- DEPENDENCIAS Y ARQUITECTURA
--   * Unica FK externa: platform.tenants(id), referencia canonica del tenant.
--   * No hay FK fisicas a identity, organization, sales, payments, billing,
--     automation, finance ni otros modulos de negocio.
--   * company_id, branch_id, actor_id y source_document_id son UUID logicos;
--     validar permisos/propiedad con contratos publicos y el contexto autenticado.
--   * Automation decide CUANDO llamar una integracion; Integrations ejecuta la
--     comunicacion externa usando adaptadores. Ningun modulo consulta sus tablas.
--   * Payments conserva sus propias cuentas de pasarela; Integrations no crea
--     una segunda configuracion de cuentas para adquirentes de pago.
--
-- SEGURIDAD
--   * Todas las tablas tenant-scoped tienen tenant_id, RLS y FORCE RLS.
--   * La app establece SET LOCAL app.tenant_id dentro de cada transaccion.
--   * El tenant se deriva del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * Nunca almacenar passwords, client_secret, API keys, tokens ni private keys.
--   * No registrar headers Authorization, cookies, PAN/CVV ni payloads sensibles.
--   * Validar URLs de destino contra SSRF: bloquear loopback, link-local, RFC1918,
--     metadata cloud, esquemas no HTTP(S), redirects inseguros y DNS rebinding.
--   * Verificar firma de webhook antes de procesar y utilizar timestamp/nonce para
--     limitar replay. La verificacion criptografica se implementa en Rust.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * El catalogo comercial integrations se registra en modulo_0_admin_plataforma_postgresql.sql.
--   * No ejecutar sobre un schema integrations ya existente; usar migraciones
--     versionadas para cambios posteriores.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS integrations;

COMMENT ON SCHEMA integrations IS
'Conexiones externas, credenciales por referencia, webhooks, entregas, sincronizaciones y adaptadores. Automation orquesta; Integrations transporta.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION integrations.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION integrations.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Integrations';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre un nuevo evento',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion general por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    is_enabled                      boolean NOT NULL DEFAULT true,
    default_timeout_ms              integer NOT NULL DEFAULT 15000,
    default_max_attempts            smallint NOT NULL DEFAULT 5,
    default_backoff_seconds         integer NOT NULL DEFAULT 30,
    max_payload_bytes               integer NOT NULL DEFAULT 1048576,
    webhook_clock_skew_seconds      integer NOT NULL DEFAULT 300,
    api_log_retention_days          integer NOT NULL DEFAULT 30,
    webhook_retention_days          integer NOT NULL DEFAULT 90,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integrations_tenant_timeout_positive CHECK (default_timeout_ms BETWEEN 100 AND 300000),
    CONSTRAINT integrations_tenant_attempts_range CHECK (default_max_attempts BETWEEN 1 AND 20),
    CONSTRAINT integrations_tenant_backoff_nonnegative CHECK (default_backoff_seconds >= 0),
    CONSTRAINT integrations_tenant_payload_range CHECK (max_payload_bytes BETWEEN 1024 AND 10485760),
    CONSTRAINT integrations_tenant_clock_skew_range CHECK (webhook_clock_skew_seconds BETWEEN 0 AND 3600),
    CONSTRAINT integrations_tenant_api_retention_range CHECK (api_log_retention_days BETWEEN 1 AND 365),
    CONSTRAINT integrations_tenant_webhook_retention_range CHECK (webhook_retention_days BETWEEN 1 AND 730),
    CONSTRAINT integrations_tenant_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Catalogo de proveedores/conectores habilitados por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.provider_catalog (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_code                   varchar(100) NOT NULL,
    display_name                    varchar(180) NOT NULL,
    category                        varchar(40) NOT NULL,
    description                     text,
    website_url                     text,
    auth_type                       varchar(30) NOT NULL,
    supported_capabilities          text[] NOT NULL DEFAULT ARRAY[]::text[],
    config_schema                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    documentation_url               text,
    is_enabled                      boolean NOT NULL DEFAULT true,
    is_system                       boolean NOT NULL DEFAULT false,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT provider_catalog_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT provider_catalog_code_unique UNIQUE (tenant_id, provider_code),
    CONSTRAINT provider_catalog_code_not_blank CHECK (btrim(provider_code) <> ''),
    CONSTRAINT provider_catalog_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT provider_catalog_category_valid CHECK (category IN (
        'messaging', 'email', 'fiscal', 'accounting', 'crm', 'ecommerce',
        'delivery', 'storage', 'analytics', 'identity', 'other'
    )),
    CONSTRAINT provider_catalog_auth_valid CHECK (auth_type IN (
        'none', 'api_key', 'oauth2', 'basic_ref', 'mtls', 'signed_jwt', 'custom'
    )),
    CONSTRAINT provider_catalog_schema_object CHECK (jsonb_typeof(config_schema) = 'object'),
    CONSTRAINT provider_catalog_url_scheme CHECK (
        website_url IS NULL OR website_url ~* '^https?://'
    ),
    CONSTRAINT provider_catalog_docs_url_scheme CHECK (
        documentation_url IS NULL OR documentation_url ~* '^https?://'
    )
);
CREATE INDEX ix_integrations_provider_catalog_category
    ON integrations.provider_catalog (tenant_id, category, is_enabled);

-- ---------------------------------------------------------------------------
-- 3. Referencias a secretos externos (nunca el secreto en si)
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.credential_references (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    credential_code                 varchar(120) NOT NULL,
    secret_manager                  varchar(30) NOT NULL,
    secret_reference                text NOT NULL,
    key_version                     varchar(80),
    credential_kind                 varchar(40) NOT NULL,
    expires_at                      timestamptz,
    last_rotated_at                 timestamptz,
    status                          varchar(20) NOT NULL DEFAULT 'active',
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT credential_references_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT credential_references_code_unique UNIQUE (tenant_id, credential_code),
    CONSTRAINT credential_references_code_not_blank CHECK (btrim(credential_code) <> ''),
    CONSTRAINT credential_references_secret_ref_not_blank CHECK (btrim(secret_reference) <> ''),
    CONSTRAINT credential_references_manager_valid CHECK (secret_manager IN ('aws_secrets_manager', 'aws_kms', 'azure_key_vault', 'gcp_secret_manager', 'hashicorp_vault', 'external_kms', 'other')),
    CONSTRAINT credential_references_kind_valid CHECK (credential_kind IN ('api_key', 'client_secret', 'oauth_access_token', 'oauth_refresh_token', 'signing_key', 'certificate', 'private_key', 'basic_auth', 'other')),
    CONSTRAINT credential_references_status_valid CHECK (status IN ('active', 'rotating', 'expired', 'revoked', 'disabled')),
    CONSTRAINT credential_references_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX ix_integrations_credential_status_expiry
    ON integrations.credential_references (tenant_id, status, expires_at);

-- ---------------------------------------------------------------------------
-- 4. Instancias conectadas de proveedores
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.integration_connections (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_id                     uuid NOT NULL,
    connection_code                 varchar(120) NOT NULL,
    display_name                    varchar(180) NOT NULL,
    company_id                      uuid,
    branch_id                       uuid,
    credential_reference_id         uuid,
    environment                     varchar(20) NOT NULL DEFAULT 'production',
    status                          varchar(24) NOT NULL DEFAULT 'draft',
    external_account_id             varchar(220),
    config                          jsonb NOT NULL DEFAULT '{}'::jsonb,
    connected_at                    timestamptz,
    disconnected_at                 timestamptz,
    last_success_at                 timestamptz,
    last_error_at                   timestamptz,
    last_error_code                 varchar(100),
    last_error_summary              text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integration_connections_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integration_connections_provider_scope_unique UNIQUE (tenant_id, id, provider_id),
    CONSTRAINT integration_connections_code_unique UNIQUE (tenant_id, connection_code),
    CONSTRAINT integration_connections_provider_fk FOREIGN KEY (tenant_id, provider_id)
        REFERENCES integrations.provider_catalog (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT integration_connections_credential_fk FOREIGN KEY (tenant_id, credential_reference_id)
        REFERENCES integrations.credential_references (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT integration_connections_code_not_blank CHECK (btrim(connection_code) <> ''),
    CONSTRAINT integration_connections_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT integration_connections_environment_valid CHECK (environment IN ('sandbox', 'staging', 'production')),
    CONSTRAINT integration_connections_status_valid CHECK (status IN ('draft', 'pending_auth', 'connected', 'degraded', 'disconnected', 'error', 'disabled')),
    CONSTRAINT integration_connections_config_object CHECK (jsonb_typeof(config) = 'object'),
    CONSTRAINT integration_connections_not_disconnected_before_connected CHECK (disconnected_at IS NULL OR connected_at IS NULL OR disconnected_at >= connected_at),
    CONSTRAINT integration_connections_connected_shape CHECK (
        status NOT IN ('connected', 'degraded') OR (connected_at IS NOT NULL AND disconnected_at IS NULL)
    ),
    CONSTRAINT integration_connections_disconnected_shape CHECK (
        status <> 'disconnected' OR (connected_at IS NOT NULL AND disconnected_at IS NOT NULL)
    )
);
CREATE INDEX ix_integrations_connections_provider_status
    ON integrations.integration_connections (tenant_id, provider_id, status);
CREATE INDEX ix_integrations_connections_company_branch
    ON integrations.integration_connections (tenant_id, company_id, branch_id)
    WHERE status <> 'disabled';

-- ---------------------------------------------------------------------------
-- 5. Cuentas externas asociadas a una conexion
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.integration_accounts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    external_account_id             varchar(220) NOT NULL,
    external_account_name           varchar(180),
    account_type                    varchar(80),
    account_metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_primary                      boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    linked_at                       timestamptz NOT NULL DEFAULT now(),
    unlinked_at                     timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integration_accounts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integration_accounts_integration_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT integration_accounts_external_unique UNIQUE (tenant_id, integration_id, external_account_id),
    CONSTRAINT integration_accounts_external_id_not_blank CHECK (btrim(external_account_id) <> ''),
    CONSTRAINT integration_accounts_metadata_object CHECK (jsonb_typeof(account_metadata) = 'object'),
    CONSTRAINT integration_accounts_unlinked_order CHECK (unlinked_at IS NULL OR unlinked_at >= linked_at)
);
CREATE INDEX ix_integrations_accounts_active
    ON integrations.integration_accounts (tenant_id, integration_id, is_active, is_primary);
CREATE UNIQUE INDEX uq_integrations_primary_account
    ON integrations.integration_accounts (tenant_id, integration_id)
    WHERE is_active AND is_primary;

-- ---------------------------------------------------------------------------
-- 6. Scopes/permisos OAuth concedidos
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.integration_scopes (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    scope_code                      varchar(180) NOT NULL,
    granted                         boolean NOT NULL DEFAULT false,
    granted_at                      timestamptz,
    revoked_at                      timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integration_scopes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integration_scopes_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT integration_scopes_code_unique UNIQUE (tenant_id, integration_id, scope_code),
    CONSTRAINT integration_scopes_code_not_blank CHECK (btrim(scope_code) <> ''),
    CONSTRAINT integration_scopes_revocation_order CHECK (revoked_at IS NULL OR granted_at IS NULL OR revoked_at >= granted_at),
    CONSTRAINT integration_scopes_grant_shape CHECK (
        (granted AND granted_at IS NOT NULL AND revoked_at IS NULL)
        OR (NOT granted AND (revoked_at IS NULL OR granted_at IS NOT NULL))
    )
);

-- ---------------------------------------------------------------------------
-- 7. Estado OAuth de un solo uso (state_hash, nunca state en claro)
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.oauth_authorization_states (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    provider_id                     uuid NOT NULL,
    integration_id                  uuid,
    state_hash                      char(64) NOT NULL,
    redirect_uri                    text NOT NULL,
    requested_scopes                text[] NOT NULL DEFAULT ARRAY[]::text[],
    pkce_challenge                   text,
    initiated_by_user_id            uuid,
    expires_at                      timestamptz NOT NULL,
    consumed_at                     timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT oauth_authorization_states_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT oauth_authorization_states_provider_fk FOREIGN KEY (tenant_id, provider_id)
        REFERENCES integrations.provider_catalog (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT oauth_authorization_states_connection_fk FOREIGN KEY (tenant_id, integration_id, provider_id)
        REFERENCES integrations.integration_connections (tenant_id, id, provider_id) ON DELETE RESTRICT,
    CONSTRAINT oauth_authorization_states_hash_unique UNIQUE (tenant_id, state_hash),
    CONSTRAINT oauth_authorization_states_hash_format CHECK (state_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT oauth_authorization_states_redirect_https CHECK (redirect_uri ~* '^https://'),
    CONSTRAINT oauth_authorization_states_expiry CHECK (expires_at > created_at)
);
CREATE INDEX ix_integrations_oauth_pending
    ON integrations.oauth_authorization_states (tenant_id, expires_at)
    WHERE consumed_at IS NULL;

-- ---------------------------------------------------------------------------
-- 8. Pruebas de salud de conexiones
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.integration_health_checks (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    checked_at                      timestamptz NOT NULL DEFAULT now(),
    status                          varchar(20) NOT NULL,
    latency_ms                      integer,
    response_code                   varchar(100),
    error_summary                   text,
    diagnostics                     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integration_health_checks_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integration_health_checks_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT integration_health_checks_status_valid CHECK (status IN ('healthy', 'degraded', 'unhealthy', 'unknown')),
    CONSTRAINT integration_health_checks_latency_nonnegative CHECK (latency_ms IS NULL OR latency_ms >= 0),
    CONSTRAINT integration_health_checks_diagnostics_object CHECK (jsonb_typeof(diagnostics) = 'object')
);
CREATE INDEX ix_integrations_health_latest
    ON integrations.integration_health_checks (tenant_id, integration_id, checked_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Endpoints entrantes de webhook
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.inbound_webhook_endpoints (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    endpoint_code                   varchar(120) NOT NULL,
    path_token_hash                 char(64) NOT NULL,
    signing_credential_reference_id uuid,
    signature_algorithm             varchar(30) NOT NULL DEFAULT 'hmac_sha256',
    allowed_event_types              text[] NOT NULL DEFAULT ARRAY[]::text[],
    allowed_source_cidrs             text[] NOT NULL DEFAULT ARRAY[]::text[],
    is_enabled                      boolean NOT NULL DEFAULT true,
    last_received_at                timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inbound_webhook_endpoints_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inbound_webhook_endpoints_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT inbound_webhook_endpoints_credential_fk FOREIGN KEY (tenant_id, signing_credential_reference_id)
        REFERENCES integrations.credential_references (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT inbound_webhook_endpoints_code_unique UNIQUE (tenant_id, endpoint_code),
    CONSTRAINT inbound_webhook_endpoints_path_unique UNIQUE (tenant_id, path_token_hash),
    CONSTRAINT inbound_webhook_endpoints_code_not_blank CHECK (btrim(endpoint_code) <> ''),
    CONSTRAINT inbound_webhook_endpoints_path_hash_format CHECK (path_token_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT inbound_webhook_endpoints_signature_valid CHECK (signature_algorithm IN ('hmac_sha256', 'hmac_sha512', 'ed25519', 'rsa_sha256', 'provider_managed'))
);

-- ---------------------------------------------------------------------------
-- 10. Recepciones tecnicas de webhooks
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.inbound_webhook_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    endpoint_id                     uuid NOT NULL,
    provider_event_id               varchar(240),
    event_type                      varchar(180) NOT NULL,
    payload_hash                    char(64) NOT NULL,
    signature_nonce_hash            char(64),
    payload                         jsonb NOT NULL,
    sanitized_headers               jsonb NOT NULL DEFAULT '{}'::jsonb,
    signature_valid                 boolean NOT NULL,
    signature_checked_at            timestamptz,
    received_at                     timestamptz NOT NULL DEFAULT now(),
    processing_status               varchar(24) NOT NULL DEFAULT 'received',
    routed_module                   varchar(80),
    routed_event_id                 uuid,
    processed_at                    timestamptz,
    rejection_reason                varchar(240),
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inbound_webhook_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inbound_webhook_events_endpoint_fk FOREIGN KEY (tenant_id, endpoint_id)
        REFERENCES integrations.inbound_webhook_endpoints (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT inbound_webhook_events_payload_hash_format CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT inbound_webhook_events_nonce_hash_format CHECK (signature_nonce_hash IS NULL OR signature_nonce_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT inbound_webhook_events_type_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT inbound_webhook_events_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT inbound_webhook_events_headers_object CHECK (jsonb_typeof(sanitized_headers) = 'object'),
    CONSTRAINT inbound_webhook_events_headers_redacted CHECK (
        NOT (sanitized_headers ?| ARRAY['authorization', 'Authorization', 'cookie', 'Cookie', 'set-cookie', 'Set-Cookie'])
    ),
    CONSTRAINT inbound_webhook_events_status_valid CHECK (processing_status IN ('received', 'verified', 'rejected', 'queued', 'processed', 'failed', 'ignored')),
    CONSTRAINT inbound_webhook_events_verified_shape CHECK (
        NOT signature_valid OR signature_checked_at IS NOT NULL
    ),
    CONSTRAINT inbound_webhook_events_routing_requires_signature CHECK (
        processing_status NOT IN ('verified', 'queued', 'processed') OR signature_valid
    ),
    CONSTRAINT inbound_webhook_events_processed_shape CHECK (
        (processing_status = 'processed') = (processed_at IS NOT NULL)
    ),
    CONSTRAINT inbound_webhook_events_rejection_reason CHECK (
        processing_status <> 'rejected' OR NULLIF(btrim(rejection_reason), '') IS NOT NULL
    )
);
CREATE UNIQUE INDEX uq_integrations_inbound_provider_event
    ON integrations.inbound_webhook_events (tenant_id, endpoint_id, provider_event_id)
    WHERE provider_event_id IS NOT NULL;
CREATE UNIQUE INDEX uq_integrations_inbound_nonce
    ON integrations.inbound_webhook_events (tenant_id, endpoint_id, signature_nonce_hash)
    WHERE signature_nonce_hash IS NOT NULL;
CREATE INDEX ix_integrations_inbound_webhook_pending
    ON integrations.inbound_webhook_events (tenant_id, processing_status, received_at)
    WHERE processing_status IN ('received', 'verified', 'queued', 'failed');

-- ---------------------------------------------------------------------------
-- 11. Intentos de procesamiento/entrega de webhook entrante
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.inbound_webhook_attempts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    webhook_event_id                uuid NOT NULL,
    attempt_number                  smallint NOT NULL,
    status                          varchar(20) NOT NULL,
    started_at                      timestamptz NOT NULL DEFAULT now(),
    completed_at                    timestamptz,
    response_code                   varchar(100),
    error_code                      varchar(100),
    error_summary                   text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inbound_webhook_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inbound_webhook_attempts_event_fk FOREIGN KEY (tenant_id, webhook_event_id)
        REFERENCES integrations.inbound_webhook_events (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT inbound_webhook_attempts_number_unique UNIQUE (tenant_id, webhook_event_id, attempt_number),
    CONSTRAINT inbound_webhook_attempts_number_positive CHECK (attempt_number > 0),
    CONSTRAINT inbound_webhook_attempts_status_valid CHECK (status IN ('running', 'succeeded', 'retryable_error', 'permanent_error')),
    CONSTRAINT inbound_webhook_attempts_time_order CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT inbound_webhook_attempts_completion_shape CHECK (
        (status = 'running' AND completed_at IS NULL)
        OR (status <> 'running' AND completed_at IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------------
-- 12. Destinos externos para webhooks/mensajes salientes
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.outbound_webhook_destinations (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    destination_code                varchar(120) NOT NULL,
    destination_url                 text NOT NULL,
    signing_credential_reference_id uuid,
    subscribed_event_types          text[] NOT NULL DEFAULT ARRAY[]::text[],
    custom_headers                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    timeout_ms                      integer NOT NULL DEFAULT 15000,
    max_attempts                    smallint NOT NULL DEFAULT 5,
    status                          varchar(20) NOT NULL DEFAULT 'active',
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT outbound_destinations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT outbound_destinations_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT outbound_destinations_credential_fk FOREIGN KEY (tenant_id, signing_credential_reference_id)
        REFERENCES integrations.credential_references (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT outbound_destinations_code_unique UNIQUE (tenant_id, destination_code),
    CONSTRAINT outbound_destinations_code_not_blank CHECK (btrim(destination_code) <> ''),
    CONSTRAINT outbound_destinations_https CHECK (destination_url ~* '^https://'),
    CONSTRAINT outbound_destinations_no_userinfo CHECK (destination_url !~* '^https://[^/]*@'),
    CONSTRAINT outbound_destinations_timeout_range CHECK (timeout_ms BETWEEN 100 AND 300000),
    CONSTRAINT outbound_destinations_attempts_range CHECK (max_attempts BETWEEN 1 AND 20),
    CONSTRAINT outbound_destinations_status_valid CHECK (status IN ('active', 'paused', 'disabled', 'invalid')),
    CONSTRAINT outbound_destinations_headers_object CHECK (jsonb_typeof(custom_headers) = 'object'),
    CONSTRAINT outbound_destinations_headers_no_credentials CHECK (
        NOT (custom_headers ?| ARRAY['authorization', 'Authorization', 'cookie', 'Cookie', 'proxy-authorization', 'Proxy-Authorization'])
    )
);

-- ---------------------------------------------------------------------------
-- 13. Entregas salientes
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.outbound_deliveries (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    destination_id                  uuid NOT NULL,
    source_module                   varchar(80),
    source_event_id                 uuid,
    event_type                      varchar(180) NOT NULL,
    idempotency_key                 varchar(220) NOT NULL,
    payload                         jsonb NOT NULL,
    payload_hash                    char(64) NOT NULL,
    request_hash                    char(64) NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'pending',
    attempts_count                  integer NOT NULL DEFAULT 0,
    max_attempts                    smallint NOT NULL DEFAULT 5,
    available_at                    timestamptz NOT NULL DEFAULT now(),
    locked_at                       timestamptz,
    lock_owner                      varchar(160),
    lease_expires_at                timestamptz,
    delivered_at                    timestamptz,
    last_error_code                 varchar(100),
    last_error_summary              text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT outbound_deliveries_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT outbound_deliveries_destination_fk FOREIGN KEY (tenant_id, destination_id)
        REFERENCES integrations.outbound_webhook_destinations (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT outbound_deliveries_idempotency_unique UNIQUE (tenant_id, destination_id, idempotency_key),
    CONSTRAINT outbound_deliveries_event_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT outbound_deliveries_idempotency_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT outbound_deliveries_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT outbound_deliveries_payload_hash_format CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT outbound_deliveries_request_hash_format CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT outbound_deliveries_status_valid CHECK (status IN ('pending', 'processing', 'delivered', 'retry_wait', 'failed', 'cancelled', 'dead_letter')),
    CONSTRAINT outbound_deliveries_attempts_valid CHECK (attempts_count >= 0 AND max_attempts BETWEEN 1 AND 20),
    CONSTRAINT outbound_deliveries_processing_lease CHECK (
        (status <> 'processing' AND locked_at IS NULL AND lock_owner IS NULL AND lease_expires_at IS NULL)
        OR
        (status = 'processing' AND locked_at IS NOT NULL AND NULLIF(btrim(lock_owner), '') IS NOT NULL AND lease_expires_at IS NOT NULL)
    ),
    CONSTRAINT outbound_deliveries_lease_order CHECK (lease_expires_at IS NULL OR lease_expires_at > locked_at),
    CONSTRAINT outbound_deliveries_delivered_status CHECK ((status = 'delivered') = (delivered_at IS NOT NULL))
);
CREATE INDEX ix_integrations_outbound_delivery_queue
    ON integrations.outbound_deliveries (tenant_id, available_at, created_at)
    WHERE status IN ('pending', 'retry_wait');
CREATE INDEX ix_integrations_outbound_delivery_lease
    ON integrations.outbound_deliveries (tenant_id, lease_expires_at)
    WHERE status = 'processing';

-- ---------------------------------------------------------------------------
-- 14. Intentos de entregas salientes
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.outbound_delivery_attempts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    delivery_id                     uuid NOT NULL,
    attempt_number                  smallint NOT NULL,
    started_at                      timestamptz NOT NULL DEFAULT now(),
    completed_at                    timestamptz,
    http_status                     smallint,
    response_headers                jsonb NOT NULL DEFAULT '{}'::jsonb,
    response_body_excerpt           text,
    duration_ms                     integer,
    outcome                         varchar(24) NOT NULL,
    error_code                      varchar(100),
    error_summary                   text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT outbound_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT outbound_attempts_delivery_fk FOREIGN KEY (tenant_id, delivery_id)
        REFERENCES integrations.outbound_deliveries (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT outbound_attempts_number_unique UNIQUE (tenant_id, delivery_id, attempt_number),
    CONSTRAINT outbound_attempts_number_positive CHECK (attempt_number > 0),
    CONSTRAINT outbound_attempts_http_range CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    CONSTRAINT outbound_attempts_duration_nonnegative CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT outbound_attempts_outcome_valid CHECK (outcome IN ('succeeded', 'retryable_error', 'permanent_error', 'timeout', 'cancelled')),
    CONSTRAINT outbound_attempts_headers_object CHECK (jsonb_typeof(response_headers) = 'object'),
    CONSTRAINT outbound_attempts_time_order CHECK (completed_at IS NOT NULL AND completed_at >= started_at)
);

-- ---------------------------------------------------------------------------
-- 15. Definicion de trabajos de sincronizacion
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.sync_jobs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    job_code                        varchar(120) NOT NULL,
    display_name                    varchar(180) NOT NULL,
    direction                       varchar(20) NOT NULL,
    resource_type                   varchar(100) NOT NULL,
    schedule_expression             varchar(160),
    timezone_name                   varchar(80) NOT NULL DEFAULT 'UTC',
    config                          jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_enabled                      boolean NOT NULL DEFAULT true,
    next_run_at                     timestamptz,
    last_run_at                     timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sync_jobs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sync_jobs_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sync_jobs_code_unique UNIQUE (tenant_id, integration_id, job_code),
    CONSTRAINT sync_jobs_code_not_blank CHECK (btrim(job_code) <> ''),
    CONSTRAINT sync_jobs_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT sync_jobs_direction_valid CHECK (direction IN ('inbound', 'outbound', 'bidirectional')),
    CONSTRAINT sync_jobs_resource_not_blank CHECK (btrim(resource_type) <> ''),
    CONSTRAINT sync_jobs_config_object CHECK (jsonb_typeof(config) = 'object')
);
CREATE INDEX ix_integrations_sync_jobs_due
    ON integrations.sync_jobs (tenant_id, next_run_at)
    WHERE is_enabled = true;

-- ---------------------------------------------------------------------------
-- 16. Ejecuciones de sincronizacion
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.sync_runs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sync_job_id                     uuid NOT NULL,
    run_number                      integer NOT NULL,
    status                          varchar(24) NOT NULL DEFAULT 'queued',
    started_at                      timestamptz,
    completed_at                    timestamptz,
    records_read                    integer NOT NULL DEFAULT 0,
    records_created                 integer NOT NULL DEFAULT 0,
    records_updated                 integer NOT NULL DEFAULT 0,
    records_skipped                 integer NOT NULL DEFAULT 0,
    records_failed                  integer NOT NULL DEFAULT 0,
    cursor_before                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    cursor_after                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    summary                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_code                      varchar(100),
    error_summary                   text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sync_runs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sync_runs_job_fk FOREIGN KEY (tenant_id, sync_job_id)
        REFERENCES integrations.sync_jobs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sync_runs_number_unique UNIQUE (tenant_id, sync_job_id, run_number),
    CONSTRAINT sync_runs_number_positive CHECK (run_number > 0),
    CONSTRAINT sync_runs_status_valid CHECK (status IN ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled')),
    CONSTRAINT sync_runs_counts_nonnegative CHECK (records_read >= 0 AND records_created >= 0 AND records_updated >= 0 AND records_skipped >= 0 AND records_failed >= 0),
    CONSTRAINT sync_runs_cursor_before_object CHECK (jsonb_typeof(cursor_before) = 'object'),
    CONSTRAINT sync_runs_cursor_after_object CHECK (jsonb_typeof(cursor_after) = 'object'),
    CONSTRAINT sync_runs_summary_object CHECK (jsonb_typeof(summary) = 'object'),
    CONSTRAINT sync_runs_time_order CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT sync_runs_lifecycle CHECK (
        (status = 'queued' AND started_at IS NULL AND completed_at IS NULL)
        OR (status = 'running' AND started_at IS NOT NULL AND completed_at IS NULL)
        OR (status IN ('succeeded', 'partial', 'failed', 'cancelled') AND started_at IS NOT NULL AND completed_at IS NOT NULL)
    )
);
CREATE INDEX ix_integrations_sync_runs_job_recent
    ON integrations.sync_runs (tenant_id, sync_job_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 17. Cursores/checkpoints de sincronizacion
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.sync_cursors (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sync_job_id                     uuid NOT NULL,
    cursor_name                     varchar(120) NOT NULL,
    cursor_value                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    version                         bigint NOT NULL DEFAULT 1,
    last_advanced_at                timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sync_cursors_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sync_cursors_job_fk FOREIGN KEY (tenant_id, sync_job_id)
        REFERENCES integrations.sync_jobs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT sync_cursors_name_unique UNIQUE (tenant_id, sync_job_id, cursor_name),
    CONSTRAINT sync_cursors_name_not_blank CHECK (btrim(cursor_name) <> ''),
    CONSTRAINT sync_cursors_value_object CHECK (jsonb_typeof(cursor_value) = 'object'),
    CONSTRAINT sync_cursors_version_positive CHECK (version > 0)
);

-- ---------------------------------------------------------------------------
-- 18. Mapeo entre identificadores locales y externos
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.external_id_mappings (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    local_module                    varchar(80) NOT NULL,
    local_aggregate_type             varchar(100) NOT NULL,
    local_aggregate_id               uuid NOT NULL,
    external_resource_type          varchar(100) NOT NULL,
    external_resource_id            varchar(240) NOT NULL,
    external_parent_id              varchar(240),
    mapping_metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_synced_at                  timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT external_id_mappings_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT external_id_mappings_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT external_id_mappings_external_unique UNIQUE (tenant_id, integration_id, external_resource_type, external_resource_id),
    CONSTRAINT external_id_mappings_local_module_not_blank CHECK (btrim(local_module) <> ''),
    CONSTRAINT external_id_mappings_local_type_not_blank CHECK (btrim(local_aggregate_type) <> ''),
    CONSTRAINT external_id_mappings_external_type_not_blank CHECK (btrim(external_resource_type) <> ''),
    CONSTRAINT external_id_mappings_external_id_not_blank CHECK (btrim(external_resource_id) <> ''),
    CONSTRAINT external_id_mappings_metadata_object CHECK (jsonb_typeof(mapping_metadata) = 'object')
);
CREATE INDEX ix_integrations_external_mapping_local
    ON integrations.external_id_mappings (tenant_id, local_module, local_aggregate_type, local_aggregate_id);

-- ---------------------------------------------------------------------------
-- 19. Registro tecnico redactado de llamadas API
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.api_request_logs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid,
    correlation_id                  uuid,
    direction                       varchar(12) NOT NULL,
    http_method                     varchar(10),
    endpoint_host                   varchar(255),
    endpoint_path                   text,
    http_status                     smallint,
    duration_ms                     integer,
    request_bytes                   bigint,
    response_bytes                  bigint,
    outcome                         varchar(24) NOT NULL,
    error_code                      varchar(100),
    error_summary                   text,
    redacted_metadata               jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT api_request_logs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT api_request_logs_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT api_request_logs_direction_valid CHECK (direction IN ('inbound', 'outbound')),
    CONSTRAINT api_request_logs_status_range CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    CONSTRAINT api_request_logs_duration_nonnegative CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT api_request_logs_bytes_nonnegative CHECK ((request_bytes IS NULL OR request_bytes >= 0) AND (response_bytes IS NULL OR response_bytes >= 0)),
    CONSTRAINT api_request_logs_outcome_valid CHECK (outcome IN ('succeeded', 'failed', 'timeout', 'rejected', 'rate_limited')),
    CONSTRAINT api_request_logs_metadata_object CHECK (jsonb_typeof(redacted_metadata) = 'object')
);
CREATE INDEX ix_integrations_api_logs_recent
    ON integrations.api_request_logs (tenant_id, occurred_at DESC);
CREATE INDEX ix_integrations_api_logs_correlation
    ON integrations.api_request_logs (tenant_id, correlation_id)
    WHERE correlation_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 20. Buckets de rate limiting por conexion/recurso
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.rate_limit_buckets (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    integration_id                  uuid NOT NULL,
    bucket_key                      varchar(180) NOT NULL,
    window_started_at               timestamptz NOT NULL,
    window_seconds                  integer NOT NULL,
    request_count                   integer NOT NULL DEFAULT 0,
    limit_count                     integer NOT NULL,
    blocked_until                   timestamptz,
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rate_limit_buckets_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT rate_limit_buckets_connection_fk FOREIGN KEY (tenant_id, integration_id)
        REFERENCES integrations.integration_connections (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT rate_limit_buckets_key_unique UNIQUE (tenant_id, integration_id, bucket_key, window_started_at),
    CONSTRAINT rate_limit_buckets_key_not_blank CHECK (btrim(bucket_key) <> ''),
    CONSTRAINT rate_limit_buckets_window_positive CHECK (window_seconds > 0),
    CONSTRAINT rate_limit_buckets_counts_valid CHECK (request_count >= 0 AND limit_count > 0)
);

-- ---------------------------------------------------------------------------
-- 21. Inbox para eventos internos ya consumidos
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.processed_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_code                   varchar(120) NOT NULL,
    event_id                        uuid NOT NULL,
    event_type                      varchar(180) NOT NULL,
    processed_at                    timestamptz NOT NULL DEFAULT now(),
    result_reference_id             uuid,
    result_summary                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integrations_processed_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integrations_processed_events_once UNIQUE (tenant_id, consumer_code, event_id),
    CONSTRAINT integrations_processed_events_consumer_not_blank CHECK (btrim(consumer_code) <> ''),
    CONSTRAINT integrations_processed_events_type_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT integrations_processed_events_summary_object CHECK (jsonb_typeof(result_summary) = 'object')
);

-- ---------------------------------------------------------------------------
-- 22. Outbox de eventos propios de Integrations
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.event_outbox (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                        uuid NOT NULL DEFAULT gen_random_uuid(),
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
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integrations_event_outbox_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integrations_event_outbox_event_unique UNIQUE (tenant_id, event_id),
    CONSTRAINT integrations_event_outbox_aggregate_not_blank CHECK (btrim(aggregate_type) <> ''),
    CONSTRAINT integrations_event_outbox_type_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT integrations_event_outbox_version_positive CHECK (event_version > 0),
    CONSTRAINT integrations_event_outbox_attempts_nonnegative CHECK (publish_attempts >= 0),
    CONSTRAINT integrations_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object')
);
CREATE INDEX ix_integrations_event_outbox_pending
    ON integrations.event_outbox (tenant_id, available_at, occurred_at)
    WHERE published_at IS NULL;

-- ---------------------------------------------------------------------------
-- 23. Idempotencia para operaciones de Integrations
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.idempotency_records (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_scope                 varchar(120) NOT NULL,
    idempotency_key                 varchar(220) NOT NULL,
    request_hash                    char(64) NOT NULL,
    response_status                 varchar(24) NOT NULL DEFAULT 'in_progress',
    response_reference_id           uuid,
    response_snapshot               jsonb,
    expires_at                      timestamptz NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integrations_idempotency_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integrations_idempotency_once UNIQUE (tenant_id, operation_scope, idempotency_key),
    CONSTRAINT integrations_idempotency_scope_not_blank CHECK (btrim(operation_scope) <> ''),
    CONSTRAINT integrations_idempotency_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT integrations_idempotency_hash_format CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT integrations_idempotency_status_valid CHECK (response_status IN ('in_progress', 'succeeded', 'failed')),
    CONSTRAINT integrations_idempotency_snapshot_object CHECK (response_snapshot IS NULL OR jsonb_typeof(response_snapshot) = 'object'),
    CONSTRAINT integrations_idempotency_expiry CHECK (expires_at > created_at)
);

-- ---------------------------------------------------------------------------
-- 24. Auditoria de acciones administrativas y tecnicas
-- ---------------------------------------------------------------------------

CREATE TABLE integrations.audit_logs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    actor_user_id                   uuid,
    actor_type                      varchar(20) NOT NULL DEFAULT 'user',
    action                          varchar(120) NOT NULL,
    resource_type                   varchar(120) NOT NULL,
    resource_id                     uuid,
    correlation_id                  uuid,
    ip_address                      inet,
    user_agent                      text,
    before_snapshot                 jsonb,
    after_snapshot                  jsonb,
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT integrations_audit_logs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT integrations_audit_actor_type_valid CHECK (actor_type IN ('user', 'system', 'integration', 'worker')),
    CONSTRAINT integrations_audit_action_not_blank CHECK (btrim(action) <> ''),
    CONSTRAINT integrations_audit_resource_not_blank CHECK (btrim(resource_type) <> ''),
    CONSTRAINT integrations_audit_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT integrations_audit_before_object CHECK (before_snapshot IS NULL OR jsonb_typeof(before_snapshot) = 'object'),
    CONSTRAINT integrations_audit_after_object CHECK (after_snapshot IS NULL OR jsonb_typeof(after_snapshot) = 'object')
);
CREATE INDEX ix_integrations_audit_recent
    ON integrations.audit_logs (tenant_id, occurred_at DESC);
CREATE INDEX ix_integrations_audit_resource
    ON integrations.audit_logs (tenant_id, resource_type, resource_id)
    WHERE resource_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 25. Indices adicionales operativos
-- ---------------------------------------------------------------------------

CREATE INDEX ix_integrations_webhook_events_received
    ON integrations.inbound_webhook_events (tenant_id, received_at DESC);
CREATE INDEX ix_integrations_webhook_attempts_event
    ON integrations.inbound_webhook_attempts (tenant_id, webhook_event_id, attempt_number DESC);
CREATE INDEX ix_integrations_outbound_attempts_delivery
    ON integrations.outbound_delivery_attempts (tenant_id, delivery_id, attempt_number DESC);
CREATE INDEX ix_integrations_sync_cursors_job
    ON integrations.sync_cursors (tenant_id, sync_job_id);
CREATE INDEX ix_integrations_processed_events_recent
    ON integrations.processed_events (tenant_id, processed_at DESC);
CREATE INDEX ix_integrations_idempotency_expiry
    ON integrations.idempotency_records (tenant_id, expires_at);

-- ---------------------------------------------------------------------------
-- 26. Inicializacion de un tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION integrations.initialize_tenant_integrations(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id <> integrations.current_tenant_id() THEN
        RAISE EXCEPTION 'tenant_id no coincide con el contexto autenticado';
    END IF;

    INSERT INTO integrations.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.consume_oauth_authorization_state(
    p_tenant_id uuid,
    p_state_hash char(64)
)
RETURNS TABLE (
    provider_id uuid,
    integration_id uuid,
    redirect_uri text,
    requested_scopes text[],
    pkce_challenge text
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_state integrations.oauth_authorization_states%ROWTYPE;
BEGIN
    IF p_tenant_id IS NULL OR integrations.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant_id no coincide con el contexto autenticado';
    END IF;
    IF p_state_hash IS NULL OR p_state_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'state_hash no es valido';
    END IF;

    SELECT * INTO v_state
      FROM integrations.oauth_authorization_states
     WHERE tenant_id = p_tenant_id
       AND state_hash = p_state_hash
       AND consumed_at IS NULL
       AND expires_at > clock_timestamp()
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El estado OAuth no existe, vencio o ya fue consumido';
    END IF;

    UPDATE integrations.oauth_authorization_states
       SET consumed_at = clock_timestamp()
     WHERE tenant_id = p_tenant_id AND id = v_state.id;

    RETURN QUERY SELECT v_state.provider_id, v_state.integration_id,
                        v_state.redirect_uri, v_state.requested_scopes,
                        v_state.pkce_challenge;
END;
$$;

-- ---------------------------------------------------------------------------
-- 27. Encolar entrega saliente de forma idempotente
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION integrations.enqueue_outbound_delivery(
    p_tenant_id uuid,
    p_destination_id uuid,
    p_event_type varchar,
    p_idempotency_key varchar,
    p_payload jsonb,
    p_source_module varchar DEFAULT NULL,
    p_source_event_id uuid DEFAULT NULL,
    p_available_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_delivery_id uuid;
    v_destination_status varchar(20);
    v_connection_status varchar(24);
    v_provider_enabled boolean;
    v_integrations_enabled boolean;
    v_max_payload_bytes integer;
    v_payload_hash char(64);
    v_request_hash char(64);
    v_existing_hash char(64);
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id <> integrations.current_tenant_id() THEN
        RAISE EXCEPTION 'tenant_id no coincide con el contexto autenticado';
    END IF;
    IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
        RAISE EXCEPTION 'payload debe ser un objeto JSON';
    END IF;
    IF NULLIF(btrim(p_event_type), '') IS NULL
       OR NULLIF(btrim(p_idempotency_key), '') IS NULL
       OR (p_source_module IS NOT NULL AND btrim(p_source_module) = '') THEN
        RAISE EXCEPTION 'event_type e idempotency_key son obligatorios';
    END IF;

    v_payload_hash := encode(digest(convert_to(p_payload::text, 'UTF8'), 'sha256'), 'hex');
    v_request_hash := encode(digest(convert_to(jsonb_build_object(
        'event_type', p_event_type,
        'source_module', p_source_module,
        'source_event_id', p_source_event_id,
        'payload', p_payload
    )::text, 'UTF8'), 'sha256'), 'hex');

    SELECT id, request_hash INTO v_delivery_id, v_existing_hash
      FROM integrations.outbound_deliveries
     WHERE tenant_id = p_tenant_id
       AND destination_id = p_destination_id
       AND idempotency_key = p_idempotency_key
     FOR UPDATE;
    IF FOUND THEN
        IF v_existing_hash IS DISTINCT FROM v_request_hash THEN
            RAISE EXCEPTION 'La clave de idempotencia ya fue usada con una solicitud diferente';
        END IF;
        RETURN v_delivery_id;
    END IF;

    SELECT is_enabled, max_payload_bytes
      INTO v_integrations_enabled, v_max_payload_bytes
      FROM integrations.tenant_settings
     WHERE tenant_id = p_tenant_id
     FOR SHARE;
    IF NOT FOUND OR NOT v_integrations_enabled THEN
        RAISE EXCEPTION 'Integrations no esta inicializado o esta deshabilitado para este tenant';
    END IF;
    IF octet_length(p_payload::text) > v_max_payload_bytes THEN
        RAISE EXCEPTION 'El payload supera el maximo permitido de % bytes', v_max_payload_bytes;
    END IF;

    SELECT d.status, c.status, p.is_enabled
      INTO v_destination_status, v_connection_status, v_provider_enabled
      FROM integrations.outbound_webhook_destinations d
      JOIN integrations.integration_connections c
        ON c.tenant_id = d.tenant_id AND c.id = d.integration_id
      JOIN integrations.provider_catalog p
        ON p.tenant_id = c.tenant_id AND p.id = c.provider_id
     WHERE d.tenant_id = p_tenant_id AND d.id = p_destination_id
     FOR SHARE OF d, c, p;

    IF NOT FOUND OR v_destination_status <> 'active'
       OR v_connection_status NOT IN ('connected', 'degraded')
       OR NOT v_provider_enabled THEN
        RAISE EXCEPTION 'El destino, la conexion o el proveedor no estan activos';
    END IF;

    INSERT INTO integrations.outbound_deliveries (
        tenant_id, destination_id, source_module, source_event_id,
        event_type, idempotency_key, payload, payload_hash, request_hash, available_at
    ) VALUES (
        p_tenant_id, p_destination_id, p_source_module, p_source_event_id,
        p_event_type, p_idempotency_key, p_payload, v_payload_hash, v_request_hash,
        COALESCE(p_available_at, now())
    )
    ON CONFLICT (tenant_id, destination_id, idempotency_key) DO NOTHING
    RETURNING id INTO v_delivery_id;

    IF v_delivery_id IS NULL THEN
        SELECT id, request_hash INTO v_delivery_id, v_existing_hash
        FROM integrations.outbound_deliveries
        WHERE tenant_id = p_tenant_id
          AND destination_id = p_destination_id
          AND idempotency_key = p_idempotency_key;

        IF v_existing_hash IS DISTINCT FROM v_request_hash THEN
            RAISE EXCEPTION 'La clave de idempotencia ya fue usada con una solicitud diferente';
        END IF;
    END IF;

    RETURN v_delivery_id;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.protect_oauth_authorization_state()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.consumed_at IS NOT NULL OR OLD.expires_at <= now() THEN
            RETURN OLD;
        END IF;
        RAISE EXCEPTION 'No se puede eliminar un estado OAuth vigente sin consumir';
    END IF;

    IF OLD.consumed_at IS NOT NULL
       OR NEW.consumed_at IS NULL
       OR (to_jsonb(NEW) - ARRAY['consumed_at']) IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['consumed_at']) THEN
        RAISE EXCEPTION 'El estado OAuth es inmutable y solo puede consumirse una vez';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.validate_inbound_webhook_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_allowed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.processing_status <> 'received'
           OR NEW.signature_valid
           OR NEW.signature_checked_at IS NOT NULL
           OR NEW.processed_at IS NOT NULL
           OR NEW.routed_module IS NOT NULL
           OR NEW.routed_event_id IS NOT NULL THEN
            RAISE EXCEPTION 'Los webhooks deben recibirse sin verificar y en estado received';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' OR OLD.processing_status IN ('processed', 'rejected', 'ignored') THEN
        RAISE EXCEPTION 'Los eventos webhook son append-only al alcanzar un estado terminal';
    END IF;

    IF (to_jsonb(NEW) - ARRAY[
        'signature_valid', 'signature_checked_at', 'processing_status',
        'routed_module', 'routed_event_id', 'processed_at', 'rejection_reason'
    ]) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY[
        'signature_valid', 'signature_checked_at', 'processing_status',
        'routed_module', 'routed_event_id', 'processed_at', 'rejection_reason'
    ]) THEN
        RAISE EXCEPTION 'No se puede modificar el contenido recibido del webhook';
    END IF;
    IF OLD.signature_valid AND NOT NEW.signature_valid THEN
        RAISE EXCEPTION 'La verificacion de firma no puede revertirse';
    END IF;
    IF OLD.signature_checked_at IS NOT NULL
       AND NEW.signature_checked_at IS DISTINCT FROM OLD.signature_checked_at THEN
        RAISE EXCEPTION 'La fecha de verificacion de firma es inmutable';
    END IF;

    IF NEW.processing_status IS NOT DISTINCT FROM OLD.processing_status THEN
        RETURN NEW;
    END IF;
    v_allowed := CASE OLD.processing_status
        WHEN 'received' THEN NEW.processing_status IN ('verified', 'rejected', 'ignored')
        WHEN 'verified' THEN NEW.processing_status IN ('queued', 'rejected', 'ignored')
        WHEN 'queued' THEN NEW.processing_status IN ('processed', 'failed', 'ignored')
        WHEN 'failed' THEN NEW.processing_status IN ('queued', 'ignored')
        ELSE false
    END;
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'Transicion de webhook no permitida: % -> %', OLD.processing_status, NEW.processing_status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.validate_inbound_webhook_attempt_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' OR OLD.status <> 'running' THEN
        RAISE EXCEPTION 'Un intento webhook solo puede completarse una vez';
    END IF;
    IF NEW.status = 'running' OR NEW.completed_at IS NULL
       OR (to_jsonb(NEW) - ARRAY['status', 'completed_at', 'response_code', 'error_code', 'error_summary'])
          IS DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['status', 'completed_at', 'response_code', 'error_code', 'error_summary']) THEN
        RAISE EXCEPTION 'Solo se permite completar un intento webhook en ejecucion';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integrations.validate_outbound_delivery_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_allowed boolean;
BEGIN
    IF OLD.status IN ('delivered', 'cancelled') THEN
        RAISE EXCEPTION 'Una entrega completada o cancelada es inmutable';
    END IF;
    IF NEW.attempts_count < OLD.attempts_count THEN
        RAISE EXCEPTION 'attempts_count no puede disminuir';
    END IF;
    IF (to_jsonb(NEW) - ARRAY[
        'status', 'attempts_count', 'available_at', 'locked_at',
        'lock_owner', 'lease_expires_at', 'delivered_at',
        'last_error_code', 'last_error_summary', 'updated_at'
    ]) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY[
        'status', 'attempts_count', 'available_at', 'locked_at',
        'lock_owner', 'lease_expires_at', 'delivered_at',
        'last_error_code', 'last_error_summary', 'updated_at'
    ]) THEN
        RAISE EXCEPTION 'Los datos de solicitud de una entrega son inmutables';
    END IF;

    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;
    v_allowed := CASE OLD.status
        WHEN 'pending' THEN NEW.status IN ('processing', 'cancelled')
        WHEN 'retry_wait' THEN NEW.status IN ('processing', 'cancelled', 'dead_letter')
        WHEN 'processing' THEN NEW.status IN ('delivered', 'retry_wait', 'failed', 'cancelled', 'dead_letter')
        WHEN 'failed' THEN NEW.status = 'pending'
        WHEN 'dead_letter' THEN NEW.status = 'pending'
        ELSE false
    END;
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'Transicion de entrega no permitida: % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 28. Triggers updated_at y proteccion tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_catalog', 'credential_references',
        'integration_connections', 'integration_accounts', 'integration_scopes',
        'inbound_webhook_endpoints', 'outbound_webhook_destinations',
        'outbound_deliveries', 'sync_jobs', 'sync_cursors', 'external_id_mappings',
        'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON integrations.%I FOR EACH ROW EXECUTE FUNCTION integrations.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_catalog', 'credential_references',
        'integration_connections', 'integration_accounts', 'integration_scopes',
        'oauth_authorization_states', 'integration_health_checks',
        'inbound_webhook_endpoints', 'inbound_webhook_events', 'inbound_webhook_attempts',
        'outbound_webhook_destinations', 'outbound_deliveries', 'outbound_delivery_attempts',
        'sync_jobs', 'sync_runs', 'sync_cursors', 'external_id_mappings',
        'api_request_logs', 'rate_limit_buckets', 'processed_events', 'event_outbox',
        'idempotency_records', 'audit_logs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON integrations.%I FOR EACH ROW EXECUTE FUNCTION integrations.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_integrations_oauth_state_one_time
    BEFORE UPDATE OR DELETE ON integrations.oauth_authorization_states
    FOR EACH ROW EXECUTE FUNCTION integrations.protect_oauth_authorization_state();

CREATE TRIGGER trg_integrations_inbound_webhook_event_state
    BEFORE INSERT OR UPDATE OR DELETE ON integrations.inbound_webhook_events
    FOR EACH ROW EXECUTE FUNCTION integrations.validate_inbound_webhook_event_mutation();

CREATE TRIGGER trg_integrations_inbound_webhook_attempt_completion
    BEFORE UPDATE OR DELETE ON integrations.inbound_webhook_attempts
    FOR EACH ROW EXECUTE FUNCTION integrations.validate_inbound_webhook_attempt_update();

CREATE TRIGGER trg_integrations_outbound_delivery_state
    BEFORE UPDATE ON integrations.outbound_deliveries
    FOR EACH ROW EXECUTE FUNCTION integrations.validate_outbound_delivery_update();

-- ---------------------------------------------------------------------------
-- 29. Registros append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'integration_health_checks', 'outbound_delivery_attempts', 'api_request_logs',
        'processed_events', 'audit_logs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON integrations.%I FOR EACH ROW EXECUTE FUNCTION integrations.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 30. RLS + FORCE RLS en las 24 tablas tenant-scoped
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'provider_catalog', 'credential_references',
        'integration_connections', 'integration_accounts', 'integration_scopes',
        'oauth_authorization_states', 'integration_health_checks',
        'inbound_webhook_endpoints', 'inbound_webhook_events', 'inbound_webhook_attempts',
        'outbound_webhook_destinations', 'outbound_deliveries', 'outbound_delivery_attempts',
        'sync_jobs', 'sync_runs', 'sync_cursors', 'external_id_mappings',
        'api_request_logs', 'rate_limit_buckets', 'processed_events', 'event_outbox',
        'idempotency_records', 'audit_logs'
    ] LOOP
        EXECUTE format('ALTER TABLE integrations.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE integrations.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON integrations.%I USING (tenant_id = integrations.current_tenant_id()) WITH CHECK (tenant_id = integrations.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 31. Comentarios de propiedad y seguridad
-- ---------------------------------------------------------------------------

COMMENT ON TABLE integrations.provider_catalog IS
'Catalogo de conectores externos habilitados para el tenant. No contiene cuentas de adquirencia de Payments.';
COMMENT ON TABLE integrations.credential_references IS
'Solo referencias a secretos externos. Nunca guardar valores de API keys, client secrets, tokens ni claves privadas.';
COMMENT ON TABLE integrations.integration_connections IS
'Conexion configurada con un proveedor externo. company_id y branch_id son referencias UUID logicas validadas por Organization.';
COMMENT ON TABLE integrations.inbound_webhook_events IS
'Recepcion HTTP tecnica. Verificar firma, timestamp, nonce y replay en Rust antes de enrutar. Almacenar payload/header redactado.';
COMMENT ON TABLE integrations.outbound_webhook_destinations IS
'Destinos HTTPS configurados. Rust debe validar SSRF, DNS, redirects y rangos IP en cada entrega.';
COMMENT ON TABLE integrations.outbound_deliveries IS
'Cola de entregas salientes. Workers reclaman filas con FOR UPDATE SKIP LOCKED y lease; reintentos deben ser idempotentes.';
COMMENT ON TABLE integrations.external_id_mappings IS
'Asocia UUID logicos del modulo propietario con IDs externos; no crea FK a las tablas de negocio.';
COMMENT ON TABLE integrations.api_request_logs IS
'Logs tecnicos redactados: nunca registrar Authorization, cookies, tokens, secretos, PAN/CVV ni PII no necesaria.';
COMMENT ON TABLE integrations.processed_events IS
'Inbox idempotente para eventos internos entregados a Integrations.';
COMMENT ON TABLE integrations.event_outbox IS
'Outbox de eventos propios (conexion cambiada, sync completado, entrega externa fallida); publicar fuera de la transaccion.';
COMMENT ON FUNCTION integrations.consume_oauth_authorization_state(uuid, char) IS
'Consume atomica y una sola vez un estado OAuth vigente; devuelve los datos de inicio para validar el callback.';
COMMENT ON FUNCTION integrations.enqueue_outbound_delivery(uuid, uuid, varchar, varchar, jsonb, varchar, uuid, timestamptz) IS
'Encola de forma idempotente una entrega HTTPS a un destino activo. La validacion SSRF y la firma se implementan en Rust.';

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 17: INTEGRATIONS
-- ============================================================================
