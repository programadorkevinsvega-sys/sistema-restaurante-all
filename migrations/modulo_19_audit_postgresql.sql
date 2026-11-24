-- ============================================================================
-- RESTAURANT-OS - POS SAAS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 19: AUDIT (AUDITORIA OPERATIVA CENTRALIZADA)
-- Numeracion tecnica de migraciones; requisitos.md enumera Audit como modulo funcional 20.
-- Ubicacion del crate: crates/modules/audit
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD
--   * Mantener el registro central e inmutable de eventos de auditoria de cada
--     tenant: actor, accion, recurso, sucursal, resultado y correlacion.
--   * Recibir eventos normalizados de los modulos mediante contratos versionados.
--   * Mantener evidencia referenciada, retencion, legal holds, exportaciones,
--     alertas de seguridad y trazabilidad del acceso a la propia auditoria.
--   * Proporcionar una cadena SHA-256 secuencial por tenant y verificacion.
--
-- LIMITES DE PROPIEDAD
--   * platform.audit_logs sigue siendo la auditoria de superadministradores y
--     operaciones del plano de control SaaS. No se duplica ni se modifica aqui.
--   * integrations.audit_logs conserva auditoria tecnica de conexiones externas.
--   * analytics.query_audit_logs conserva auditoria especializada de consultas.
--   * Audit recibe eventos relevantes mediante contratos; no consulta ni modifica
--     tablas privadas de otros modulos.
--   * Los logs de aplicacion/observabilidad (traces, metrics y debug logs) no son
--     el libro de auditoria y pertenecen a la infraestructura de monitoring.
--
-- DEPENDENCIAS Y ARQUITECTURA
--   * Unica FK externa: platform.tenants(id).
--   * actor_id, company_id, branch_id, resource_id y request/correlation IDs son
--     referencias logicas UUID o identificadores externos; no crean acoplamiento.
--   * El crate expone contratos de escritura/consulta; adapters/local inserta en
--     este schema y un futuro adapter/grpc puede invocar la misma API remota.
--   * La aplicacion debe redactar PII, credenciales, tokens, PAN/CVV y secretos
--     antes de enviar eventos. No guardar payloads HTTP crudos.
--
-- SEGURIDAD
--   * Todas las tablas tenant-scoped tienen tenant_id, RLS y FORCE RLS.
--   * La aplicacion establece SET LOCAL app.tenant_id en cada transaccion.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * El propietario de funciones SECURITY DEFINER debe ser un rol dedicado,
--     NO SUPERUSER y NOBYPASSRLS; no usar postgres/superuser como function owner.
--   * El tenant se obtiene del contexto autenticado, nunca del body HTTP.
--   * Los registros de auditoria son append-only; correcciones se agregan como
--     nuevos eventos y nunca mediante UPDATE/DELETE de eventos previos. La
--     retencion aqui planifica archivo y elegibilidad; la purga legal requiere
--     un procedimiento privilegiado separado, legal hold y respaldo verificable.
--   * SHA-256 hash-chain por tenant y modulo fuente permite escrituras concurrentes
--     entre modulos sin una unica fila de secuencia global por tenant.
--     Para evidencia fuerte
--     exportar checkpoints a almacenamiento WORM/KMS fuera de esta base de datos.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * El catalogo comercial Audit se registra en modulo_0_admin_plataforma_postgresql.sql.
--   * Los permisos y roles de auditoria se registran en modulo_2_identity_usuarios_seguridad_postgresql.sql.
--   * Crea exclusivamente el schema audit; no modifica otros schemas de negocio.
--   * Ejecutar una sola vez en una base limpia; cambios posteriores via migraciones.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA audit IS
'Auditoria operativa central por tenant, eventos inmutables, evidencia, retencion, integridad y control de acceso a auditoria.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION audit.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Audit';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit.%.% es append-only: registre un nuevo evento, no modifique ni elimine el anterior',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION audit.validate_event_inbox_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_transition_allowed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'received' OR NEW.attempt_count <> 0 OR NEW.processed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Los eventos entrantes deben iniciar en estado received';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' OR OLD.status IN ('processed','dead_letter','ignored') THEN
        RAISE EXCEPTION 'Un evento entrante terminal es inmutable';
    END IF;
    IF (to_jsonb(NEW) - ARRAY[
        'status','attempt_count','processed_at','last_error_code','last_error_at'
    ]) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY[
        'status','attempt_count','processed_at','last_error_code','last_error_at'
    ]) THEN
        RAISE EXCEPTION 'El contenido recibido del evento es inmutable';
    END IF;
    IF NEW.attempt_count < OLD.attempt_count THEN
        RAISE EXCEPTION 'attempt_count no puede disminuir';
    END IF;
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;

    v_transition_allowed := CASE OLD.status
        WHEN 'received' THEN NEW.status IN ('processing','ignored','dead_letter')
        WHEN 'retry' THEN NEW.status IN ('processing','ignored','dead_letter')
        WHEN 'processing' THEN NEW.status IN ('processed','retry','dead_letter','ignored')
        ELSE false
    END;
    IF NOT v_transition_allowed THEN
        RAISE EXCEPTION 'Transicion de inbox no permitida: % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.compute_event_hash(
    p_previous_hash text,
    p_hash_payload jsonb
)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT encode(
        public.digest(convert_to(p_previous_hash || ':' || p_hash_payload::text, 'UTF8'), 'sha256'),
        'hex'
    );
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion, fuentes, catalogos y retencion
-- ---------------------------------------------------------------------------

CREATE TABLE audit.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    is_enabled                      boolean NOT NULL DEFAULT true,
    default_retention_days          integer NOT NULL DEFAULT 2555,
    security_retention_days         integer NOT NULL DEFAULT 3650,
    financial_retention_days        integer NOT NULL DEFAULT 3650,
    require_reason_for_exports      boolean NOT NULL DEFAULT true,
    require_mfa_for_exports         boolean NOT NULL DEFAULT true,
    allow_tenant_audit_exports      boolean NOT NULL DEFAULT true,
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_settings_retention_positive CHECK (
        default_retention_days > 0 AND security_retention_days > 0 AND financial_retention_days > 0
    ),
    CONSTRAINT audit_settings_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT audit_settings_export_mfa CHECK (NOT allow_tenant_audit_exports OR require_mfa_for_exports)
);

CREATE TABLE audit.audit_sources (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_code                     varchar(80) NOT NULL,
    display_name                    varchar(160) NOT NULL,
    source_type                     varchar(24) NOT NULL,
    source_version                  varchar(40),
    is_trusted                      boolean NOT NULL DEFAULT false,
    is_enabled                      boolean NOT NULL DEFAULT true,
    last_event_at                   timestamptz,
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_sources_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_sources_code_unique UNIQUE (tenant_id, source_code),
    CONSTRAINT audit_sources_code_not_blank CHECK (btrim(source_code) <> ''),
    CONSTRAINT audit_sources_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT audit_sources_type_valid CHECK (source_type IN ('module','platform','service','integration','worker','system')),
    CONSTRAINT audit_sources_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE TABLE audit.event_type_catalog (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_code                      varchar(160) NOT NULL,
    category                        varchar(40) NOT NULL,
    default_severity                varchar(16) NOT NULL DEFAULT 'info',
    default_classification          varchar(20) NOT NULL DEFAULT 'internal',
    description                     text,
    retention_policy_code           varchar(60),
    is_security_event               boolean NOT NULL DEFAULT false,
    is_enabled                      boolean NOT NULL DEFAULT true,
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_event_types_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_types_code_unique UNIQUE (tenant_id, event_code),
    CONSTRAINT audit_event_types_code_not_blank CHECK (btrim(event_code) <> ''),
    CONSTRAINT audit_event_types_category_valid CHECK (category IN (
        'authentication','authorization','administration','configuration','business',
        'financial','privacy','integration','security','data_change','system'
    )),
    CONSTRAINT audit_event_types_severity_valid CHECK (default_severity IN ('debug','info','notice','warning','error','critical')),
    CONSTRAINT audit_event_types_classification_valid CHECK (default_classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT audit_event_types_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE TABLE audit.retention_policies (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    policy_code                     varchar(60) NOT NULL,
    display_name                    varchar(160) NOT NULL,
    retention_days                  integer NOT NULL,
    archive_required                boolean NOT NULL DEFAULT true,
    applies_to_classification       varchar(20) NOT NULL DEFAULT 'internal',
    is_enabled                      boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_retention_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_retention_code_unique UNIQUE (tenant_id, policy_code),
    CONSTRAINT audit_retention_days_positive CHECK (retention_days > 0),
    CONSTRAINT audit_retention_classification_valid CHECK (applies_to_classification IN ('public','internal','confidential','restricted'))
);

-- ---------------------------------------------------------------------------
-- 2. Cadena de integridad y eventos canonicos
-- ---------------------------------------------------------------------------

ALTER TABLE audit.event_type_catalog
    ADD CONSTRAINT audit_event_types_retention_policy_fk
    FOREIGN KEY (tenant_id, retention_policy_code)
    REFERENCES audit.retention_policies(tenant_id, policy_code) ON DELETE RESTRICT;

CREATE TABLE audit.integrity_streams (
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    stream_key                      varchar(80) NOT NULL,
    last_sequence                   bigint NOT NULL DEFAULT 0,
    last_hash                       varchar(64) NOT NULL DEFAULT repeat('0', 64),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_integrity_streams_pk PRIMARY KEY (tenant_id, stream_key),
    CONSTRAINT audit_integrity_stream_key_not_blank CHECK (btrim(stream_key) <> ''),
    CONSTRAINT audit_integrity_sequence_nonnegative CHECK (last_sequence >= 0),
    CONSTRAINT audit_integrity_hash_valid CHECK (last_hash ~ '^[0-9a-f]{64}$')
);

CREATE TABLE audit.events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_uuid                      uuid NOT NULL,
    stream_key                      varchar(80) NOT NULL,
    stream_sequence                 bigint NOT NULL,
    source_id                       uuid NOT NULL,
    event_type_id                   uuid NOT NULL,
    source_code_snapshot            varchar(80) NOT NULL,
    event_code_snapshot             varchar(160) NOT NULL,
    schema_version                  smallint NOT NULL DEFAULT 1,
    actor_type                      varchar(24) NOT NULL,
    actor_id                        uuid,
    actor_role_codes                text[] NOT NULL DEFAULT ARRAY[]::text[],
    action                          varchar(120) NOT NULL,
    resource_type                   varchar(120) NOT NULL,
    resource_id                     varchar(180),
    company_id                      uuid,
    branch_id                       uuid,
    outcome                         varchar(20) NOT NULL DEFAULT 'succeeded',
    severity                        varchar(16) NOT NULL DEFAULT 'info',
    classification                  varchar(20) NOT NULL DEFAULT 'internal',
    occurred_at                     timestamptz NOT NULL,
    recorded_at                     timestamptz NOT NULL DEFAULT clock_timestamp(),
    request_id                      uuid,
    correlation_id                  uuid,
    causation_id                    uuid,
    source_ip                       inet,
    summary                         varchar(500),
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    hash_payload                    jsonb NOT NULL,
    previous_hash                   varchar(64) NOT NULL,
    event_hash                      varchar(64) NOT NULL,
    CONSTRAINT audit_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_events_uuid_unique UNIQUE (tenant_id, event_uuid),
    CONSTRAINT audit_events_sequence_unique UNIQUE (tenant_id, stream_key, stream_sequence),
    CONSTRAINT audit_events_stream_fk FOREIGN KEY (tenant_id, stream_key)
        REFERENCES audit.integrity_streams(tenant_id, stream_key) ON DELETE RESTRICT,
    CONSTRAINT audit_events_source_fk FOREIGN KEY (tenant_id, source_id)
        REFERENCES audit.audit_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_events_type_fk FOREIGN KEY (tenant_id, event_type_id)
        REFERENCES audit.event_type_catalog(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_events_sequence_positive CHECK (stream_sequence > 0),
    CONSTRAINT audit_events_stream_key_not_blank CHECK (btrim(stream_key) <> ''),
    CONSTRAINT audit_events_schema_version_positive CHECK (schema_version > 0),
    CONSTRAINT audit_events_actor_valid CHECK (actor_type IN ('user','system','service','integration','worker','platform_admin')),
    CONSTRAINT audit_events_outcome_valid CHECK (outcome IN ('succeeded','failed','denied','pending','cancelled')),
    CONSTRAINT audit_events_severity_valid CHECK (severity IN ('debug','info','notice','warning','error','critical')),
    CONSTRAINT audit_events_classification_valid CHECK (classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT audit_events_action_not_blank CHECK (btrim(action) <> ''),
    CONSTRAINT audit_events_resource_not_blank CHECK (btrim(resource_type) <> ''),
    CONSTRAINT audit_events_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT audit_events_hash_payload_object CHECK (jsonb_typeof(hash_payload) = 'object'),
    CONSTRAINT audit_events_hashes_valid CHECK (previous_hash ~ '^[0-9a-f]{64}$' AND event_hash ~ '^[0-9a-f]{64}$')
);

CREATE TABLE audit.event_changes (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                        uuid NOT NULL,
    field_path                      varchar(500) NOT NULL,
    change_type                     varchar(16) NOT NULL,
    before_value                    jsonb,
    after_value                     jsonb,
    is_redacted                     boolean NOT NULL DEFAULT false,
    classification                  varchar(20) NOT NULL DEFAULT 'internal',
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_event_changes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_changes_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_event_changes_path_not_blank CHECK (btrim(field_path) <> ''),
    CONSTRAINT audit_event_changes_type_valid CHECK (change_type IN ('insert','update','delete','redaction')),
    CONSTRAINT audit_event_changes_classification_valid CHECK (classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT audit_event_changes_redaction_valid CHECK (NOT is_redacted OR (before_value IS NULL AND after_value IS NULL))
);

CREATE TABLE audit.event_tags (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                        uuid NOT NULL,
    tag_code                        varchar(80) NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_event_tags_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_tags_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_event_tags_unique UNIQUE (tenant_id, event_id, tag_code),
    CONSTRAINT audit_event_tags_not_blank CHECK (btrim(tag_code) <> '')
);

CREATE TABLE audit.event_evidence (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                        uuid NOT NULL,
    evidence_type                   varchar(32) NOT NULL,
    storage_provider                varchar(40) NOT NULL,
    storage_object_key              text NOT NULL,
    content_type                    varchar(160),
    file_size_bytes                 bigint,
    sha256_hash                     varchar(64) NOT NULL,
    retention_lock_until            timestamptz,
    classification                  varchar(20) NOT NULL DEFAULT 'confidential',
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_event_evidence_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_evidence_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_event_evidence_type_valid CHECK (evidence_type IN ('document','image','export','signature','log_excerpt','other')),
    CONSTRAINT audit_event_evidence_storage_not_blank CHECK (btrim(storage_object_key) <> ''),
    CONSTRAINT audit_event_evidence_size_nonnegative CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    CONSTRAINT audit_event_evidence_hash_valid CHECK (sha256_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT audit_event_evidence_class_valid CHECK (classification IN ('public','internal','confidential','restricted'))
);

CREATE TABLE audit.integrity_checkpoints (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    stream_key                      varchar(80) NOT NULL,
    stream_sequence                 bigint NOT NULL,
    head_hash                       varchar(64) NOT NULL,
    external_anchor_provider        varchar(60),
    external_anchor_reference       text,
    signature_reference             text,
    anchored_at                     timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_integrity_checkpoints_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_integrity_checkpoints_stream_fk FOREIGN KEY (tenant_id, stream_key)
        REFERENCES audit.integrity_streams(tenant_id, stream_key) ON DELETE RESTRICT,
    CONSTRAINT audit_integrity_checkpoints_sequence_unique UNIQUE (tenant_id, stream_key, stream_sequence),
    CONSTRAINT audit_integrity_checkpoints_event_fk FOREIGN KEY (tenant_id, stream_key, stream_sequence)
        REFERENCES audit.events(tenant_id, stream_key, stream_sequence) ON DELETE RESTRICT,
    CONSTRAINT audit_integrity_checkpoints_hash_valid CHECK (head_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT audit_integrity_checkpoints_sequence_positive CHECK (stream_sequence > 0),
    CONSTRAINT audit_integrity_checkpoint_anchor_consistent CHECK (
        (anchored_at IS NULL AND external_anchor_reference IS NULL)
        OR (anchored_at IS NOT NULL AND external_anchor_reference IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------------
-- 3. Inbox, deduplicacion y checkpoints de fuentes
-- ---------------------------------------------------------------------------

CREATE TABLE audit.event_inbox (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_code                     varchar(80) NOT NULL,
    external_event_id               varchar(180) NOT NULL,
    event_code                      varchar(160) NOT NULL,
    schema_version                  smallint NOT NULL DEFAULT 1,
    payload_hash                    varchar(64) NOT NULL,
    sanitized_payload               jsonb NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'received',
    attempt_count                   integer NOT NULL DEFAULT 0,
    received_at                     timestamptz NOT NULL DEFAULT now(),
    processed_at                    timestamptz,
    last_error_code                 varchar(80),
    last_error_at                   timestamptz,
    CONSTRAINT audit_event_inbox_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_inbox_external_unique UNIQUE (tenant_id, source_code, external_event_id),
    CONSTRAINT audit_event_inbox_source_fk FOREIGN KEY (tenant_id, source_code)
        REFERENCES audit.audit_sources(tenant_id, source_code) ON DELETE RESTRICT,
    CONSTRAINT audit_event_inbox_type_fk FOREIGN KEY (tenant_id, event_code)
        REFERENCES audit.event_type_catalog(tenant_id, event_code) ON DELETE RESTRICT,
    CONSTRAINT audit_event_inbox_status_valid CHECK (status IN ('received','processing','processed','retry','dead_letter','ignored')),
    CONSTRAINT audit_event_inbox_schema_positive CHECK (schema_version > 0),
    CONSTRAINT audit_event_inbox_attempts_nonnegative CHECK (attempt_count >= 0),
    CONSTRAINT audit_event_inbox_source_not_blank CHECK (btrim(source_code) <> ''),
    CONSTRAINT audit_event_inbox_external_id_not_blank CHECK (btrim(external_event_id) <> ''),
    CONSTRAINT audit_event_inbox_code_not_blank CHECK (btrim(event_code) <> ''),
    CONSTRAINT audit_event_inbox_hash_valid CHECK (payload_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT audit_event_inbox_payload_object CHECK (jsonb_typeof(sanitized_payload) = 'object'),
    CONSTRAINT audit_event_inbox_processed_shape CHECK (
        (status IN ('processed','ignored')) = (processed_at IS NOT NULL)
    )
);

CREATE TABLE audit.processed_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_code                     varchar(80) NOT NULL,
    external_event_id               varchar(180) NOT NULL,
    payload_hash                    varchar(64) NOT NULL,
    audit_event_id                  uuid,
    processed_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_processed_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_processed_events_dedupe UNIQUE (tenant_id, source_code, external_event_id),
    CONSTRAINT audit_processed_events_event_fk FOREIGN KEY (tenant_id, audit_event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_processed_events_hash_valid CHECK (payload_hash ~ '^[0-9a-fA-F]{64}$')
);

CREATE TABLE audit.source_checkpoints (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_id                       uuid NOT NULL,
    partition_key                   varchar(180) NOT NULL DEFAULT 'default',
    cursor_value                    text,
    last_external_event_id          varchar(180),
    last_received_at                timestamptz,
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_source_checkpoints_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_source_checkpoints_source_fk FOREIGN KEY (tenant_id, source_id)
        REFERENCES audit.audit_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_source_checkpoints_unique UNIQUE (tenant_id, source_id, partition_key)
);

-- ---------------------------------------------------------------------------
-- 4. Legal holds, retencion y ciclo de vida de evidencia
-- ---------------------------------------------------------------------------

CREATE TABLE audit.legal_holds (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    hold_code                       varchar(80) NOT NULL,
    reason                          text NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'active',
    scope_definition                jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_by                    uuid NOT NULL,
    approved_by                     uuid,
    starts_at                       timestamptz NOT NULL DEFAULT now(),
    ends_at                         timestamptz,
    released_at                     timestamptz,
    release_reason                  text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_legal_holds_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_legal_holds_code_unique UNIQUE (tenant_id, hold_code),
    CONSTRAINT audit_legal_holds_status_valid CHECK (status IN ('pending','active','released','expired')),
    CONSTRAINT audit_legal_holds_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT audit_legal_holds_scope_object CHECK (jsonb_typeof(scope_definition) = 'object'),
    CONSTRAINT audit_legal_holds_dates_valid CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT audit_legal_holds_release_valid CHECK (status <> 'released' OR (released_at IS NOT NULL AND btrim(coalesce(release_reason,'')) <> ''))
);

CREATE TABLE audit.legal_hold_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    legal_hold_id                   uuid NOT NULL,
    event_id                        uuid NOT NULL,
    linked_at                       timestamptz NOT NULL DEFAULT now(),
    linked_by                       uuid NOT NULL,
    CONSTRAINT audit_legal_hold_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_legal_hold_events_hold_fk FOREIGN KEY (tenant_id, legal_hold_id)
        REFERENCES audit.legal_holds(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_legal_hold_events_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_legal_hold_events_unique UNIQUE (tenant_id, legal_hold_id, event_id)
);

CREATE TABLE audit.retention_runs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    policy_id                       uuid NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'queued',
    cutoff_at                       timestamptz NOT NULL,
    events_scanned                  bigint NOT NULL DEFAULT 0,
    events_archived                 bigint NOT NULL DEFAULT 0,
    events_held                     bigint NOT NULL DEFAULT 0,
    events_eligible                 bigint NOT NULL DEFAULT 0,
    started_at                      timestamptz,
    completed_at                    timestamptz,
    error_summary                   text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_retention_runs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_retention_runs_policy_fk FOREIGN KEY (tenant_id, policy_id)
        REFERENCES audit.retention_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_retention_runs_status_valid CHECK (status IN ('queued','running','completed','failed','cancelled')),
    CONSTRAINT audit_retention_runs_counts_nonnegative CHECK (
        events_scanned >= 0 AND events_archived >= 0 AND events_held >= 0 AND events_eligible >= 0
    ),
    CONSTRAINT audit_retention_runs_dates_valid CHECK (completed_at IS NULL OR started_at IS NOT NULL)
);

CREATE TABLE audit.retention_run_items (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    retention_run_id                uuid NOT NULL,
    event_id                        uuid NOT NULL,
    disposition                     varchar(20) NOT NULL,
    archive_reference               text,
    processed_at                    timestamptz,
    CONSTRAINT audit_retention_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_retention_items_run_fk FOREIGN KEY (tenant_id, retention_run_id)
        REFERENCES audit.retention_runs(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_retention_items_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_retention_items_unique UNIQUE (tenant_id, retention_run_id, event_id),
    CONSTRAINT audit_retention_items_disposition_valid CHECK (disposition IN ('held','archived','eligible','skipped'))
);

-- ---------------------------------------------------------------------------
-- 5. Exportaciones y control de acceso a la auditoria
-- ---------------------------------------------------------------------------

CREATE TABLE audit.export_requests (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    requested_by                    uuid NOT NULL,
    request_reason                  text NOT NULL,
    filters                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_format                varchar(12) NOT NULL DEFAULT 'jsonl',
    status                          varchar(20) NOT NULL DEFAULT 'pending_approval',
    approved_by                     uuid,
    approved_at                     timestamptz,
    rejected_reason                 text,
    row_limit                       integer NOT NULL DEFAULT 100000,
    requested_at                    timestamptz NOT NULL DEFAULT now(),
    started_at                      timestamptz,
    completed_at                    timestamptz,
    expires_at                      timestamptz,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_export_requests_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_export_format_valid CHECK (requested_format IN ('jsonl','csv','ndjson','pdf')),
    CONSTRAINT audit_export_status_valid CHECK (status IN ('pending_approval','approved','rejected','queued','running','completed','failed','expired','cancelled')),
    CONSTRAINT audit_export_reason_not_blank CHECK (btrim(request_reason) <> ''),
    CONSTRAINT audit_export_filters_object CHECK (jsonb_typeof(filters) = 'object'),
    CONSTRAINT audit_export_row_limit CHECK (row_limit BETWEEN 1 AND 1000000),
    CONSTRAINT audit_export_approval_consistent CHECK (
        (status NOT IN ('approved','queued','running','completed') OR approved_at IS NOT NULL)
    )
);

CREATE TABLE audit.export_artifacts (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    export_request_id               uuid NOT NULL,
    storage_provider                varchar(40) NOT NULL,
    storage_object_key              text NOT NULL,
    content_type                    varchar(160),
    file_size_bytes                 bigint NOT NULL,
    sha256_hash                     varchar(64) NOT NULL,
    record_count                    bigint NOT NULL DEFAULT 0,
    generated_at                    timestamptz NOT NULL DEFAULT now(),
    expires_at                      timestamptz NOT NULL,
    downloaded_at                   timestamptz,
    CONSTRAINT audit_export_artifacts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_export_artifacts_request_fk FOREIGN KEY (tenant_id, export_request_id)
        REFERENCES audit.export_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_export_artifacts_key_not_blank CHECK (btrim(storage_object_key) <> ''),
    CONSTRAINT audit_export_artifacts_size_nonnegative CHECK (file_size_bytes >= 0 AND record_count >= 0),
    CONSTRAINT audit_export_artifacts_hash_valid CHECK (sha256_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT audit_export_artifacts_expiry CHECK (expires_at > generated_at)
);

CREATE TABLE audit.access_policies (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    policy_code                     varchar(80) NOT NULL,
    minimum_role_code               varchar(80) NOT NULL,
    require_mfa                     boolean NOT NULL DEFAULT true,
    require_reason                  boolean NOT NULL DEFAULT true,
    allowed_classifications         text[] NOT NULL DEFAULT ARRAY['public','internal']::text[],
    max_range_days                  integer NOT NULL DEFAULT 365,
    is_enabled                      boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_access_policies_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_access_policy_code_unique UNIQUE (tenant_id, policy_code),
    CONSTRAINT audit_access_policy_range_positive CHECK (max_range_days > 0),
    CONSTRAINT audit_access_policy_class_valid CHECK (allowed_classifications <@ ARRAY['public','internal','confidential','restricted']::text[])
);

CREATE TABLE audit.access_grants (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    user_id                         uuid NOT NULL,
    policy_id                       uuid NOT NULL,
    granted_by                      uuid NOT NULL,
    valid_from                      timestamptz NOT NULL DEFAULT now(),
    valid_until                     timestamptz,
    revoked_at                      timestamptz,
    revocation_reason               text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_access_grants_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_access_grants_policy_fk FOREIGN KEY (tenant_id, policy_id)
        REFERENCES audit.access_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_access_grants_dates_valid CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT audit_access_grants_revoked_valid CHECK (revoked_at IS NULL OR btrim(coalesce(revocation_reason,'')) <> '')
);

CREATE TABLE audit.access_logs (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    user_id                         uuid,
    action                          varchar(80) NOT NULL,
    resource_scope                  varchar(80) NOT NULL,
    filters_hash                    varchar(64),
    result                          varchar(16) NOT NULL,
    denial_reason_code              varchar(80),
    request_id                      uuid,
    source_ip                       inet,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT audit_access_logs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_access_logs_action_not_blank CHECK (btrim(action) <> ''),
    CONSTRAINT audit_access_logs_result_valid CHECK (result IN ('allowed','denied','failed')),
    CONSTRAINT audit_access_logs_filter_hash CHECK (filters_hash IS NULL OR filters_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT audit_access_logs_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

-- ---------------------------------------------------------------------------
-- 6. Alertas de seguridad, redaccion y vistas guardadas
-- ---------------------------------------------------------------------------

CREATE TABLE audit.alert_rules (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    rule_code                       varchar(80) NOT NULL,
    display_name                    varchar(160) NOT NULL,
    description                     text,
    event_code_pattern               varchar(160),
    minimum_severity                varchar(16) NOT NULL DEFAULT 'warning',
    condition_definition            jsonb NOT NULL DEFAULT '{}'::jsonb,
    window_minutes                  integer NOT NULL DEFAULT 5,
    threshold_count                 integer NOT NULL DEFAULT 1,
    cooldown_minutes                integer NOT NULL DEFAULT 15,
    is_enabled                      boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_alert_rules_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_alert_rule_code_unique UNIQUE (tenant_id, rule_code),
    CONSTRAINT audit_alert_rule_severity_valid CHECK (minimum_severity IN ('debug','info','notice','warning','error','critical')),
    CONSTRAINT audit_alert_rule_condition_object CHECK (jsonb_typeof(condition_definition) = 'object'),
    CONSTRAINT audit_alert_rule_threshold_valid CHECK (window_minutes > 0 AND threshold_count > 0 AND cooldown_minutes >= 0)
);

CREATE TABLE audit.alert_events (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    alert_rule_id                   uuid NOT NULL,
    event_id                        uuid,
    severity                        varchar(16) NOT NULL,
    status                          varchar(20) NOT NULL DEFAULT 'open',
    title                           varchar(200) NOT NULL,
    details                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    triggered_at                    timestamptz NOT NULL DEFAULT now(),
    acknowledged_at                 timestamptz,
    resolved_at                     timestamptz,
    CONSTRAINT audit_alert_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_alert_events_rule_fk FOREIGN KEY (tenant_id, alert_rule_id)
        REFERENCES audit.alert_rules(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_alert_events_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_alert_event_severity_valid CHECK (severity IN ('debug','info','notice','warning','error','critical')),
    CONSTRAINT audit_alert_event_status_valid CHECK (status IN ('open','acknowledged','resolved','suppressed')),
    CONSTRAINT audit_alert_event_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT audit_alert_event_details_object CHECK (jsonb_typeof(details) = 'object')
);

CREATE TABLE audit.alert_acknowledgements (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    alert_event_id                  uuid NOT NULL,
    acknowledged_by                 uuid NOT NULL,
    action                          varchar(20) NOT NULL,
    note                            text,
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_alert_ack_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_alert_ack_event_fk FOREIGN KEY (tenant_id, alert_event_id)
        REFERENCES audit.alert_events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_alert_ack_action_valid CHECK (action IN ('acknowledged','resolved','reopened','suppressed'))
);

CREATE TABLE audit.redaction_policies (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    policy_code                     varchar(80) NOT NULL,
    field_path_pattern              varchar(500) NOT NULL,
    classification                  varchar(20) NOT NULL DEFAULT 'restricted',
    handling                         varchar(20) NOT NULL DEFAULT 'omit',
    is_enabled                      boolean NOT NULL DEFAULT true,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_redaction_policies_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_redaction_policy_code_unique UNIQUE (tenant_id, policy_code),
    CONSTRAINT audit_redaction_class_valid CHECK (classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT audit_redaction_handling_valid CHECK (handling IN ('omit','mask','hash','tokenize')),
    CONSTRAINT audit_redaction_pattern_not_blank CHECK (btrim(field_path_pattern) <> '')
);

CREATE TABLE audit.event_redactions (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                        uuid NOT NULL,
    policy_id                       uuid,
    field_path                      varchar(500) NOT NULL,
    reason                          text NOT NULL,
    redacted_by                     uuid NOT NULL,
    redaction_reference             varchar(180),
    occurred_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_event_redactions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_event_redactions_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_event_redactions_policy_fk FOREIGN KEY (tenant_id, policy_id)
        REFERENCES audit.redaction_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_event_redactions_path_not_blank CHECK (btrim(field_path) <> ''),
    CONSTRAINT audit_event_redactions_reason_not_blank CHECK (btrim(reason) <> '')
);

CREATE TABLE audit.idempotency_records (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_code                  varchar(120) NOT NULL,
    idempotency_key                 varchar(180) NOT NULL,
    request_hash                    varchar(64) NOT NULL,
    event_id                        uuid,
    status                          varchar(20) NOT NULL DEFAULT 'completed',
    expires_at                      timestamptz NOT NULL,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_idempotency_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_idempotency_key_unique UNIQUE (tenant_id, operation_code, idempotency_key),
    CONSTRAINT audit_idempotency_event_fk FOREIGN KEY (tenant_id, event_id)
        REFERENCES audit.events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT audit_idempotency_hash_valid CHECK (request_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT audit_idempotency_status_valid CHECK (status IN ('processing','completed','failed'))
);

CREATE TABLE audit.saved_views (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    owner_user_id                   uuid NOT NULL,
    view_name                       varchar(120) NOT NULL,
    description                     text,
    filters                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    visible_columns                 jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_shared                       boolean NOT NULL DEFAULT false,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_saved_views_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT audit_saved_view_name_not_blank CHECK (btrim(view_name) <> ''),
    CONSTRAINT audit_saved_view_filters_object CHECK (jsonb_typeof(filters) = 'object'),
    CONSTRAINT audit_saved_view_columns_array CHECK (jsonb_typeof(visible_columns) = 'array')
);

-- ---------------------------------------------------------------------------
-- 7. Indices de consulta y operacion
-- ---------------------------------------------------------------------------

CREATE INDEX ix_audit_sources_active ON audit.audit_sources (tenant_id, source_code) WHERE is_enabled;
CREATE INDEX ix_audit_event_types_active ON audit.event_type_catalog (tenant_id, event_code) WHERE is_enabled;
CREATE INDEX ix_audit_events_recent ON audit.events (tenant_id, occurred_at DESC, id DESC);
CREATE INDEX ix_audit_events_recorded ON audit.events (tenant_id, recorded_at DESC);
CREATE INDEX ix_audit_events_actor ON audit.events (tenant_id, actor_id, occurred_at DESC) WHERE actor_id IS NOT NULL;
CREATE INDEX ix_audit_events_resource ON audit.events (tenant_id, resource_type, resource_id, occurred_at DESC);
CREATE INDEX ix_audit_events_company_branch ON audit.events (tenant_id, company_id, branch_id, occurred_at DESC);
CREATE INDEX ix_audit_events_correlation ON audit.events (tenant_id, correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX ix_audit_events_request ON audit.events (tenant_id, request_id) WHERE request_id IS NOT NULL;
CREATE INDEX ix_audit_events_severity ON audit.events (tenant_id, severity, occurred_at DESC);
CREATE INDEX ix_audit_events_code ON audit.events (tenant_id, event_code_snapshot, occurred_at DESC);
CREATE INDEX ix_audit_event_changes_event ON audit.event_changes (tenant_id, event_id, created_at);
CREATE INDEX ix_audit_event_tags_tag ON audit.event_tags (tenant_id, tag_code, event_id);
CREATE INDEX ix_audit_event_evidence_event ON audit.event_evidence (tenant_id, event_id);
CREATE INDEX ix_audit_integrity_checkpoints_recent ON audit.integrity_checkpoints (tenant_id, created_at DESC);
CREATE INDEX ix_audit_inbox_pending ON audit.event_inbox (tenant_id, received_at) WHERE status IN ('received','retry');
CREATE INDEX ix_audit_inbox_status ON audit.event_inbox (tenant_id, status, received_at DESC);
CREATE INDEX ix_audit_processed_recent ON audit.processed_events (tenant_id, processed_at DESC);
CREATE INDEX ix_audit_holds_active ON audit.legal_holds (tenant_id, starts_at) WHERE status = 'active';
CREATE INDEX ix_audit_retention_runs_status ON audit.retention_runs (tenant_id, status, created_at DESC);
CREATE INDEX ix_audit_exports_status ON audit.export_requests (tenant_id, status, requested_at DESC);
CREATE INDEX ix_audit_access_logs_recent ON audit.access_logs (tenant_id, occurred_at DESC);
CREATE INDEX ix_audit_access_logs_user ON audit.access_logs (tenant_id, user_id, occurred_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX ix_audit_alert_events_open ON audit.alert_events (tenant_id, severity, triggered_at DESC) WHERE status = 'open';
CREATE INDEX ix_audit_redactions_event ON audit.event_redactions (tenant_id, event_id, occurred_at DESC);
CREATE INDEX ix_audit_idempotency_expiry ON audit.idempotency_records (expires_at);
CREATE INDEX ix_audit_saved_views_owner ON audit.saved_views (tenant_id, owner_user_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- 8. Funciones de inicializacion, escritura y verificacion
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit.initialize_tenant_audit(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $$
DECLARE
    v_context_tenant uuid := audit.current_tenant_id();
BEGIN
    IF p_tenant_id IS NULL OR v_context_tenant IS NULL OR v_context_tenant <> p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO audit.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO audit.retention_policies
        (tenant_id, policy_code, display_name, retention_days, archive_required, applies_to_classification)
    VALUES
        (p_tenant_id, 'operational', 'Auditoria operativa', 1095, true, 'internal'),
        (p_tenant_id, 'security', 'Auditoria de seguridad', 3650, true, 'confidential'),
        (p_tenant_id, 'financial', 'Auditoria financiera', 3650, true, 'restricted'),
        (p_tenant_id, 'privacy', 'Auditoria de privacidad', 3650, true, 'restricted')
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    INSERT INTO audit.audit_sources (tenant_id, source_code, display_name, source_type, is_trusted)
    VALUES
        (p_tenant_id, 'platform', 'Platform', 'platform', true),
        (p_tenant_id, 'tenancy', 'Tenancy', 'module', true),
        (p_tenant_id, 'identity', 'Identity', 'module', true),
        (p_tenant_id, 'organization', 'Organization', 'module', true),
        (p_tenant_id, 'catalog', 'Catalog', 'module', true),
        (p_tenant_id, 'sales', 'Sales', 'module', true),
        (p_tenant_id, 'kitchen', 'Kitchen', 'module', true),
        (p_tenant_id, 'inventory', 'Inventory', 'module', true),
        (p_tenant_id, 'procurement', 'Procurement', 'module', true),
        (p_tenant_id, 'production', 'Production', 'module', true),
        (p_tenant_id, 'purchasing', 'Purchasing', 'module', true),
        (p_tenant_id, 'payments', 'Payments', 'module', true),
        (p_tenant_id, 'cash', 'Cash', 'module', true),
        (p_tenant_id, 'customers', 'Customers', 'module', true),
        (p_tenant_id, 'workforce', 'Workforce', 'module', true),
        (p_tenant_id, 'finance', 'Finance', 'module', true),
        (p_tenant_id, 'billing', 'Billing', 'module', true),
        (p_tenant_id, 'automation', 'Automation', 'module', true),
        (p_tenant_id, 'integrations', 'Integrations', 'module', true),
        (p_tenant_id, 'analytics', 'Analytics', 'module', true),
        (p_tenant_id, 'audit', 'Audit', 'module', true),
        (p_tenant_id, 'api-server', 'API Server', 'service', true),
        (p_tenant_id, 'background-worker', 'Background Worker', 'worker', true)
    ON CONFLICT (tenant_id, source_code) DO NOTHING;

    INSERT INTO audit.event_type_catalog
        (tenant_id, event_code, category, default_severity, default_classification, description, retention_policy_code, is_security_event)
    VALUES
        (p_tenant_id, 'identity.authentication.succeeded', 'authentication', 'info', 'confidential', 'Autenticacion exitosa', 'security', true),
        (p_tenant_id, 'identity.authentication.failed', 'authentication', 'warning', 'confidential', 'Autenticacion fallida', 'security', true),
        (p_tenant_id, 'identity.authorization.denied', 'authorization', 'warning', 'confidential', 'Acceso denegado', 'security', true),
        (p_tenant_id, 'identity.role.assigned', 'authorization', 'notice', 'confidential', 'Asignacion de rol', 'security', true),
        (p_tenant_id, 'organization.company.updated', 'administration', 'notice', 'internal', 'Actualizacion de empresa', 'operational', false),
        (p_tenant_id, 'organization.branch.updated', 'administration', 'notice', 'internal', 'Actualizacion de sucursal', 'operational', false),
        (p_tenant_id, 'sales.sale.completed', 'business', 'info', 'internal', 'Venta completada', 'financial', false),
        (p_tenant_id, 'sales.sale.voided', 'business', 'warning', 'confidential', 'Venta anulada', 'financial', false),
        (p_tenant_id, 'payments.payment.refunded', 'financial', 'notice', 'confidential', 'Pago reembolsado', 'financial', false),
        (p_tenant_id, 'inventory.stock.adjusted', 'business', 'notice', 'confidential', 'Ajuste de inventario', 'operational', false),
        (p_tenant_id, 'billing.document.issued', 'financial', 'info', 'restricted', 'Documento fiscal emitido', 'financial', false),
        (p_tenant_id, 'workforce.employee.updated', 'administration', 'notice', 'confidential', 'Actualizacion de empleado', 'privacy', false),
        (p_tenant_id, 'privacy.request.created', 'privacy', 'notice', 'restricted', 'Solicitud de privacidad creada', 'privacy', true),
        (p_tenant_id, 'audit.export.requested', 'security', 'notice', 'restricted', 'Exportacion de auditoria solicitada', 'security', true),
        (p_tenant_id, 'audit.access.denied', 'security', 'warning', 'restricted', 'Acceso a auditoria denegado', 'security', true)
    ON CONFLICT (tenant_id, event_code) DO NOTHING;

    INSERT INTO audit.access_policies
        (tenant_id, policy_code, minimum_role_code, require_mfa, require_reason, allowed_classifications, max_range_days)
    VALUES
        (p_tenant_id, 'audit_reader', 'auditor', true, true, ARRAY['public','internal']::text[], 365),
        (p_tenant_id, 'audit_security_reader', 'security_auditor', true, true, ARRAY['public','internal','confidential']::text[], 90),
        (p_tenant_id, 'audit_owner', 'tenant_owner', true, true, ARRAY['public','internal','confidential','restricted']::text[], 3650)
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;

    INSERT INTO audit.redaction_policies
        (tenant_id, policy_code, field_path_pattern, classification, handling)
    VALUES
        (p_tenant_id, 'credentials', '*.password|*.secret|*.token|*.api_key', 'restricted', 'omit'),
        (p_tenant_id, 'payment_data', '*.pan|*.card_number|*.cvv|*.cvc', 'restricted', 'omit'),
        (p_tenant_id, 'personal_identifiers', '*.national_id|*.tax_id|*.document_number', 'restricted', 'mask'),
        (p_tenant_id, 'contact_data', '*.email|*.phone|*.address', 'confidential', 'mask')
    ON CONFLICT (tenant_id, policy_code) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION audit.append_event(
    p_source_code text,
    p_event_code text,
    p_action text,
    p_resource_type text,
    p_resource_id text,
    p_actor_type text,
    p_schema_version smallint DEFAULT 1,
    p_actor_id uuid DEFAULT NULL,
    p_actor_role_codes text[] DEFAULT ARRAY[]::text[],
    p_company_id uuid DEFAULT NULL,
    p_branch_id uuid DEFAULT NULL,
    p_outcome text DEFAULT 'succeeded',
    p_severity text DEFAULT NULL,
    p_occurred_at timestamptz DEFAULT now(),
    p_request_id uuid DEFAULT NULL,
    p_correlation_id uuid DEFAULT NULL,
    p_causation_id uuid DEFAULT NULL,
    p_source_ip inet DEFAULT NULL,
    p_summary text DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb,
    p_changes jsonb DEFAULT '[]'::jsonb,
    p_event_uuid uuid DEFAULT gen_random_uuid()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $$
DECLARE
    v_tenant_id uuid := audit.current_tenant_id();
    v_audit_enabled boolean;
    v_source_id uuid;
    v_event_type_id uuid;
    v_schema_version smallint;
    v_classification varchar(20);
    v_default_severity varchar(16);
    v_severity varchar(16);
    v_stream_key varchar(80);
    v_sequence bigint;
    v_previous_hash text;
    v_event_hash text;
    v_event_id uuid := gen_random_uuid();
    v_recorded_at timestamptz := clock_timestamp();
    v_payload jsonb;
    v_change jsonb;
    v_normalized_changes jsonb := '[]'::jsonb;
    v_is_redacted boolean;
    v_change_classification text;
BEGIN
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'app.tenant_id es obligatorio para registrar auditoria';
    END IF;
    SELECT is_enabled INTO v_audit_enabled
    FROM audit.tenant_settings
    WHERE tenant_id = v_tenant_id
    FOR SHARE;
    IF v_audit_enabled IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Audit no esta inicializado o esta deshabilitado para este tenant';
    END IF;
    IF p_source_code IS NULL OR btrim(p_source_code) = '' OR p_event_code IS NULL OR btrim(p_event_code) = '' THEN
        RAISE EXCEPTION 'source_code y event_code son obligatorios';
    END IF;
    IF p_action IS NULL OR btrim(p_action) = '' OR p_resource_type IS NULL OR btrim(p_resource_type) = '' THEN
        RAISE EXCEPTION 'action y resource_type son obligatorios';
    END IF;
    IF p_actor_type IS NULL OR p_actor_type NOT IN ('user','system','service','integration','worker','platform_admin') THEN
        RAISE EXCEPTION 'actor_type no permitido';
    END IF;
    IF p_schema_version IS NULL OR p_schema_version <= 0 THEN
        RAISE EXCEPTION 'schema_version debe ser mayor que cero';
    END IF;
    IF p_outcome IS NULL OR p_outcome NOT IN ('succeeded','failed','denied','pending','cancelled') THEN
        RAISE EXCEPTION 'outcome no permitido';
    END IF;
    IF p_severity IS NOT NULL AND p_severity NOT IN ('debug','info','notice','warning','error','critical') THEN
        RAISE EXCEPTION 'severity no permitida';
    END IF;
    IF p_occurred_at IS NULL OR p_event_uuid IS NULL THEN
        RAISE EXCEPTION 'occurred_at y event_uuid son obligatorios';
    END IF;
    IF jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' THEN
        RAISE EXCEPTION 'metadata debe ser un objeto JSON';
    END IF;
    IF jsonb_typeof(coalesce(p_changes, '[]'::jsonb)) <> 'array' THEN
        RAISE EXCEPTION 'changes debe ser un arreglo JSON';
    END IF;

    SELECT id INTO v_source_id
    FROM audit.audit_sources
    WHERE tenant_id = v_tenant_id AND source_code = p_source_code AND is_enabled AND is_trusted;
    IF v_source_id IS NULL THEN
        RAISE EXCEPTION 'Fuente de auditoria no registrada, deshabilitada o no confiable: %', p_source_code;
    END IF;

    SELECT id, default_classification, default_severity
      INTO v_event_type_id, v_classification, v_default_severity
    FROM audit.event_type_catalog
    WHERE tenant_id = v_tenant_id AND event_code = p_event_code AND is_enabled;
    IF v_event_type_id IS NULL THEN
        RAISE EXCEPTION 'Tipo de evento no registrado o deshabilitado: %', p_event_code;
    END IF;
    v_severity := coalesce(p_severity, v_default_severity);
    v_schema_version := p_schema_version;
    v_stream_key := p_source_code;

    -- Normalizar cambios antes de construir el hash: si un campo se marca como
    -- redactado, sus valores nunca se escriben ni siquiera en hash_payload.
    FOR v_change IN SELECT value FROM jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) LOOP
        IF jsonb_typeof(v_change) <> 'object'
           OR nullif(v_change->>'field_path','') IS NULL
           OR coalesce(v_change->>'change_type','') NOT IN ('insert','update','delete','redaction') THEN
            RAISE EXCEPTION 'Cada change debe incluir field_path y change_type valido';
        END IF;
        v_is_redacted := coalesce((v_change->>'is_redacted')::boolean, false);
        v_change_classification := coalesce(v_change->>'classification', 'internal');
        IF v_change_classification NOT IN ('public','internal','confidential','restricted') THEN
            RAISE EXCEPTION 'classification de change no permitida';
        END IF;
        v_normalized_changes := v_normalized_changes || jsonb_build_array(jsonb_build_object(
            'field_path', v_change->>'field_path',
            'change_type', v_change->>'change_type',
            'before_value', CASE WHEN v_is_redacted THEN NULL ELSE v_change->'before_value' END,
            'after_value', CASE WHEN v_is_redacted THEN NULL ELSE v_change->'after_value' END,
            'is_redacted', v_is_redacted,
            'classification', v_change_classification
        ));
    END LOOP;

    INSERT INTO audit.integrity_streams (tenant_id, stream_key)
    VALUES (v_tenant_id, v_stream_key)
    ON CONFLICT (tenant_id, stream_key) DO NOTHING;

    SELECT last_sequence + 1, last_hash
      INTO v_sequence, v_previous_hash
    FROM audit.integrity_streams
    WHERE tenant_id = v_tenant_id AND stream_key = v_stream_key
    FOR UPDATE;

    v_payload := jsonb_build_object(
        'tenant_id', v_tenant_id,
        'event_uuid', p_event_uuid,
        'stream_key', v_stream_key,
        'stream_sequence', v_sequence,
        'source_code', p_source_code,
        'event_code', p_event_code,
        'schema_version', v_schema_version,
        'actor_type', p_actor_type,
        'actor_id', p_actor_id,
        'actor_role_codes', coalesce(p_actor_role_codes, ARRAY[]::text[]),
        'action', p_action,
        'resource_type', p_resource_type,
        'resource_id', p_resource_id,
        'company_id', p_company_id,
        'branch_id', p_branch_id,
        'outcome', p_outcome,
        'severity', v_severity,
        'classification', v_classification,
        'occurred_at', p_occurred_at,
        'recorded_at', v_recorded_at,
        'request_id', p_request_id,
        'correlation_id', p_correlation_id,
        'causation_id', p_causation_id,
        'source_ip', CASE WHEN p_source_ip IS NULL THEN NULL ELSE p_source_ip::text END,
        'summary', p_summary,
        'metadata', coalesce(p_metadata, '{}'::jsonb),
        'changes', v_normalized_changes
    );
    v_event_hash := audit.compute_event_hash(v_previous_hash, v_payload);

    INSERT INTO audit.events (
        id, tenant_id, event_uuid, stream_key, stream_sequence, source_id, event_type_id,
        source_code_snapshot, event_code_snapshot, schema_version, actor_type, actor_id, actor_role_codes,
        action, resource_type, resource_id, company_id, branch_id, outcome, severity,
        classification, occurred_at, recorded_at, request_id, correlation_id, causation_id,
        source_ip, summary, metadata, hash_payload, previous_hash, event_hash
    )
    VALUES (
        v_event_id, v_tenant_id, p_event_uuid, v_stream_key, v_sequence, v_source_id, v_event_type_id,
        p_source_code, p_event_code, v_schema_version, p_actor_type, p_actor_id, coalesce(p_actor_role_codes, ARRAY[]::text[]),
        p_action, p_resource_type, p_resource_id, p_company_id, p_branch_id, p_outcome, v_severity,
        v_classification,
        p_occurred_at, v_recorded_at, p_request_id, p_correlation_id, p_causation_id,
        p_source_ip, left(p_summary, 500), coalesce(p_metadata, '{}'::jsonb), v_payload, v_previous_hash, v_event_hash
    );

    FOR v_change IN SELECT value FROM jsonb_array_elements(v_normalized_changes) LOOP
        INSERT INTO audit.event_changes (
            tenant_id, event_id, field_path, change_type, before_value, after_value,
            is_redacted, classification
        ) VALUES (
            v_tenant_id, v_event_id, v_change->>'field_path', v_change->>'change_type',
            CASE WHEN coalesce((v_change->>'is_redacted')::boolean, false) THEN NULL ELSE v_change->'before_value' END,
            CASE WHEN coalesce((v_change->>'is_redacted')::boolean, false) THEN NULL ELSE v_change->'after_value' END,
            coalesce((v_change->>'is_redacted')::boolean, false),
            v_change->>'classification'
        );
    END LOOP;

    UPDATE audit.integrity_streams
       SET last_sequence = v_sequence,
           last_hash = v_event_hash,
           updated_at = now()
     WHERE tenant_id = v_tenant_id AND stream_key = v_stream_key;

    UPDATE audit.audit_sources
       SET last_event_at = greatest(coalesce(last_event_at, p_occurred_at), p_occurred_at),
           updated_at = now()
     WHERE tenant_id = v_tenant_id AND id = v_source_id;

    RETURN v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION audit.verify_integrity_chain(
    p_stream_key text,
    p_from_sequence bigint DEFAULT 1,
    p_to_sequence bigint DEFAULT NULL
)
RETURNS TABLE (
    stream_sequence bigint,
    is_valid boolean,
    reason text,
    stored_hash varchar(64),
    calculated_hash text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $$
    WITH bounds AS (
        SELECT audit.current_tenant_id() AS tenant_id,
               p_stream_key AS stream_key,
               coalesce(p_to_sequence, (SELECT last_sequence FROM audit.integrity_streams WHERE tenant_id = audit.current_tenant_id() AND stream_key = p_stream_key)) AS to_seq
    ), ordered AS (
        SELECT e.stream_sequence,
               e.previous_hash,
               e.event_hash,
               e.hash_payload,
               lag(e.event_hash) OVER (ORDER BY e.stream_sequence) AS prior_event_hash,
               lag(e.stream_sequence) OVER (ORDER BY e.stream_sequence) AS prior_sequence
        FROM audit.events e
        CROSS JOIN bounds b
        WHERE e.tenant_id = b.tenant_id
          AND e.stream_key = b.stream_key
          AND e.stream_sequence <= b.to_seq
    ), checked AS (
        SELECT o.*,
               audit.compute_event_hash(o.previous_hash, o.hash_payload) AS expected_hash,
               CASE
                   WHEN o.prior_sequence IS NULL AND o.stream_sequence <> 1 THEN false
                   WHEN o.stream_sequence = 1 AND o.previous_hash <> repeat('0', 64) THEN false
                   WHEN o.prior_sequence IS NOT NULL AND o.stream_sequence = o.prior_sequence + 1
                        AND o.previous_hash <> o.prior_event_hash THEN false
                   WHEN o.prior_sequence IS NOT NULL AND o.stream_sequence <> o.prior_sequence + 1 THEN false
                   WHEN audit.compute_event_hash(o.previous_hash, o.hash_payload) <> o.event_hash THEN false
                   ELSE true
               END AS valid_flag
        FROM ordered o
    )
    SELECT c.stream_sequence,
           c.valid_flag,
           CASE WHEN c.valid_flag THEN 'ok' ELSE 'hash_or_chain_mismatch' END,
           c.event_hash,
           c.expected_hash
    FROM checked c
    WHERE c.stream_sequence >= greatest(coalesce(p_from_sequence, 1), 1)
    ORDER BY c.stream_sequence;
$$;

-- ---------------------------------------------------------------------------
-- 9. Triggers: updated_at, tenant inmutable y tablas append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','audit_sources','event_type_catalog','retention_policies',
        'legal_holds','export_requests','access_policies','alert_rules',
        'redaction_policies','saved_views'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON audit.%I FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','audit_sources','event_type_catalog','retention_policies',
        'integrity_streams','events','event_changes','event_tags','event_evidence','integrity_checkpoints',
        'event_inbox','processed_events','source_checkpoints','legal_holds','legal_hold_events',
        'retention_runs','retention_run_items','export_requests','export_artifacts',
        'access_policies','access_grants','access_logs','alert_rules','alert_events',
        'alert_acknowledgements','redaction_policies','event_redactions',
        'idempotency_records','saved_views'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON audit.%I FOR EACH ROW EXECUTE FUNCTION audit.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'events','event_changes','event_tags','event_evidence','integrity_checkpoints',
        'processed_events','access_logs','alert_acknowledgements','event_redactions'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON audit.%I FOR EACH ROW EXECUTE FUNCTION audit.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_audit_event_inbox_state
BEFORE INSERT OR UPDATE OR DELETE ON audit.event_inbox
FOR EACH ROW EXECUTE FUNCTION audit.validate_event_inbox_mutation();

-- ---------------------------------------------------------------------------
-- 10. RLS: todas las tablas tenant-scoped se aislan por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','audit_sources','event_type_catalog','retention_policies',
        'integrity_streams','events','event_changes','event_tags','event_evidence',
        'integrity_checkpoints','event_inbox','processed_events','source_checkpoints',
        'legal_holds','legal_hold_events','retention_runs','retention_run_items',
        'export_requests','export_artifacts','access_policies','access_grants','access_logs',
        'alert_rules','alert_events','alert_acknowledgements','redaction_policies',
        'event_redactions','idempotency_records','saved_views'
    ] LOOP
        EXECUTE format('ALTER TABLE audit.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE audit.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON audit.%I USING (tenant_id = audit.current_tenant_id()) WITH CHECK (tenant_id = audit.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;


-- ---------------------------------------------------------------------------
-- 11. Privilegios por funcion: conceder EXECUTE solo a roles de aplicacion
-- ---------------------------------------------------------------------------

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA audit FROM PUBLIC;

-- La migracion/deploy debe conceder solo los permisos necesarios a roles reales.
-- Ejemplo (sustituir por los nombres de roles de la instalacion):
--   GRANT USAGE ON SCHEMA audit TO app_runtime, audit_reader, tenant_bootstrapper;
--   GRANT EXECUTE ON FUNCTION audit.current_tenant_id() TO app_runtime, audit_reader;
--   GRANT EXECUTE ON FUNCTION audit.append_event(text,text,text,text,text,text,smallint,uuid,text[],uuid,uuid,text,text,timestamptz,uuid,uuid,uuid,inet,text,jsonb,jsonb,uuid) TO app_runtime;
--   GRANT EXECUTE ON FUNCTION audit.verify_integrity_chain(text,bigint,bigint) TO audit_reader;
--   GRANT EXECUTE ON FUNCTION audit.initialize_tenant_audit(uuid) TO tenant_bootstrapper;
-- No conceder INSERT/UPDATE/DELETE directo sobre audit.events, audit.event_changes,
-- audit.integrity_streams ni otras tablas append-only al rol de la aplicacion.

-- ---------------------------------------------------------------------------
-- 12. Comentarios de propiedad, integridad y seguridad
-- ---------------------------------------------------------------------------

COMMENT ON TABLE audit.events IS
'Libro central append-only de eventos operativos del tenant. Hash-chain SHA-256 por tenant; el evento original nunca se actualiza ni elimina.';
COMMENT ON TABLE audit.retention_runs IS
'Planificacion y trazabilidad del archivo/retencion. Este modulo no ejecuta purga automatica de eventos inmutables.';
COMMENT ON TABLE audit.event_changes IS
'Cambios de campos asociados a un evento. Antes de insertar, la aplicacion debe redactar datos personales, credenciales y datos de pago.';
COMMENT ON TABLE audit.event_inbox IS
'Inbox para eventos normalizados de modulos. No almacenar payload HTTP crudo, tokens, secretos, PAN ni CVV.';
COMMENT ON TABLE audit.integrity_streams IS
'Estado mutable de la cadena por tenant y modulo fuente; append_event bloquea solo el stream que escribe para reducir contencion entre modulos.';
COMMENT ON TABLE audit.integrity_checkpoints IS
'Anclas de integridad que deben exportarse a almacenamiento WORM o servicio de sellado externo para proteccion frente a administradores de la BD.';
COMMENT ON TABLE audit.event_evidence IS
'Solo guarda referencias y hashes de evidencia en almacenamiento externo; no almacena binarios en PostgreSQL.';
COMMENT ON TABLE audit.access_logs IS
'Registro append-only de accesos, consultas, exportaciones y denegaciones sobre el propio modulo Audit.';
COMMENT ON TABLE audit.export_artifacts IS
'Metadatos de artefactos de exportacion; el objeto se almacena fuera de PostgreSQL y debe tener URL temporal/control de acceso.';
COMMENT ON FUNCTION audit.append_event(text,text,text,text,text,text,smallint,uuid,text[],uuid,uuid,text,text,timestamptz,uuid,uuid,uuid,inet,text,jsonb,jsonb,uuid) IS
'Inserta un evento normalizado, agrega sus cambios y actualiza atomica y serializadamente el hash-chain del tenant autenticado.';
COMMENT ON FUNCTION audit.verify_integrity_chain(text,bigint,bigint) IS
'Verifica hashes y continuidad de la cadena del tenant autenticado dentro del rango solicitado.';

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 19: AUDIT
-- ============================================================================
