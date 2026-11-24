-- ============================================================================
-- RESTAURANT-OS - POS SaaS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 16: AUTOMATION
-- Motor: PostgreSQL 15+
--
-- Responsabilidad:
--   * Definicion y versionamiento de workflows.
--   * Triggers por eventos, horario, ejecucion manual o webhook recibido.
--   * Condiciones, pasos, transiciones y acciones declarativas.
--   * Ejecuciones, cola de trabajo, intentos, aprobaciones y dead letters.
--   * Programacion, rate limiting, idempotencia, Inbox y Outbox.
--
-- Fuera de alcance:
--   * No envia correos/SMS/WhatsApp directamente: delega en Integrations.
--   * No administra credenciales/conexiones externas: pertenecen a Integrations.
--   * No lee ni modifica tablas privadas de Sales, Inventory, Billing, etc.
--   * No ejecuta SQL arbitrario ni codigo proporcionado por tenants.
--   * No reemplaza la autorizacion de Identity ni las reglas de negocio de cada modulo.
--
-- Integracion:
--   * Los eventos entran mediante contratos versionados / adaptadores.
--   * Las acciones se despachan mediante puertos locales o gRPC.
--   * Los codigos de accion deben estar registrados en automation.action_allowlist
--     y validados nuevamente por el adaptador Rust antes de ejecutarse.
--   * Las credenciales se referencian mediante IDs de Integrations/KMS/Vault;
--     nunca se almacenan secretos en este schema.
--
-- Seguridad:
--   * Toda tabla tenant-scoped tiene tenant_id, RLS y FORCE RLS.
--   * app.tenant_id debe establecerse por transaccion autenticada.
--   * Los roles de aplicacion no deben tener BYPASSRLS ni ser superusuarios.
--   * FORCE RLS no protege frente a superusuarios ni roles con BYPASSRLS.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS automation;

COMMENT ON SCHEMA automation IS
'Motor transversal de automatizaciones: workflows versionados, triggers, condiciones, ejecuciones, tareas y eventos. No posee canales de comunicacion ni conexiones externas.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION automation.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION automation.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION automation.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Automation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION automation.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre un evento compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion y estructura organizativa de workflows
-- ---------------------------------------------------------------------------

CREATE TABLE automation.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    is_enabled                      boolean NOT NULL DEFAULT true,
    default_timezone                varchar(80) NOT NULL DEFAULT 'UTC',
    max_active_workflows            integer NOT NULL DEFAULT 100,
    max_runs_per_day                integer NOT NULL DEFAULT 10000,
    max_concurrent_runs             integer NOT NULL DEFAULT 50,
    default_run_retention_days      integer NOT NULL DEFAULT 90,
    max_payload_bytes               integer NOT NULL DEFAULT 262144,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_settings_active_workflows_positive CHECK (max_active_workflows > 0),
    CONSTRAINT automation_settings_runs_positive CHECK (max_runs_per_day > 0),
    CONSTRAINT automation_settings_concurrency_positive CHECK (max_concurrent_runs > 0),
    CONSTRAINT automation_settings_retention_positive CHECK (default_run_retention_days BETWEEN 1 AND 3650),
    CONSTRAINT automation_settings_payload_positive CHECK (max_payload_bytes BETWEEN 1024 AND 10485760),
    CONSTRAINT automation_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TABLE automation.workflow_folders (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    parent_folder_id uuid,
    code            varchar(80) NOT NULL,
    name            varchar(160) NOT NULL,
    description     text,
    sort_order      integer NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_folders_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_folders_code_unique UNIQUE (tenant_id, code),
    CONSTRAINT automation_folders_parent_fk FOREIGN KEY (tenant_id, parent_folder_id)
        REFERENCES automation.workflow_folders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_folders_no_self_parent CHECK (parent_folder_id IS NULL OR parent_folder_id <> id),
    CONSTRAINT automation_folders_code_nonblank CHECK (btrim(code) <> ''),
    CONSTRAINT automation_folders_name_nonblank CHECK (btrim(name) <> '')
);

CREATE TABLE automation.workflows (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    folder_id           uuid,
    code                varchar(100) NOT NULL,
    name                varchar(180) NOT NULL,
    description         text,
    status              varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'active', 'paused', 'archived')),
    published_version_id uuid,
    owner_user_id       uuid,
    created_by_user_id  uuid,
    updated_by_user_id  uuid,
    archived_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflows_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflows_code_unique UNIQUE (tenant_id, code),
    CONSTRAINT automation_workflows_folder_fk FOREIGN KEY (tenant_id, folder_id)
        REFERENCES automation.workflow_folders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflows_published_state CHECK (
        status NOT IN ('active', 'paused') OR published_version_id IS NOT NULL
    ),
    CONSTRAINT automation_workflows_code_nonblank CHECK (btrim(code) <> ''),
    CONSTRAINT automation_workflows_name_nonblank CHECK (btrim(name) <> ''),
    CONSTRAINT automation_workflows_archive_shape CHECK ((status = 'archived') = (archived_at IS NOT NULL))
);
CREATE INDEX ix_automation_workflows_status
    ON automation.workflows (tenant_id, status, updated_at DESC);

CREATE TABLE automation.workflow_versions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_id         uuid NOT NULL,
    version_number      integer NOT NULL,
    status              varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'published', 'superseded')),
    definition_hash     varchar(128),
    changelog           text,
    created_by_user_id  uuid,
    published_by_user_id uuid,
    published_at        timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_versions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_versions_workflow_id_unique UNIQUE (tenant_id, workflow_id, id),
    CONSTRAINT automation_workflow_versions_number_unique UNIQUE (tenant_id, workflow_id, version_number),
    CONSTRAINT automation_workflow_versions_workflow_fk FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES automation.workflows (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_versions_number_positive CHECK (version_number > 0),
    CONSTRAINT automation_workflow_versions_hash_format CHECK (definition_hash IS NULL OR definition_hash ~ '^[0-9a-fA-F]{32,128}$'),
    CONSTRAINT automation_workflow_versions_publish_shape CHECK (
        (status = 'draft' AND published_at IS NULL)
        OR (status IN ('published', 'superseded') AND published_at IS NOT NULL)
    )
);

ALTER TABLE automation.workflows
    ADD CONSTRAINT automation_workflows_published_version_fk
    FOREIGN KEY (tenant_id, id, published_version_id)
    REFERENCES automation.workflow_versions (tenant_id, workflow_id, id)
    DEFERRABLE INITIALLY DEFERRED;

-- ---------------------------------------------------------------------------
-- 2. Triggers, filtros y condiciones declarativas
-- ---------------------------------------------------------------------------

CREATE TABLE automation.workflow_triggers (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_version_id uuid NOT NULL,
    trigger_type        varchar(20) NOT NULL
                        CHECK (trigger_type IN ('event', 'schedule', 'manual', 'webhook')),
    source_module       varchar(80),
    event_type          varchar(180),
    event_version       integer,
    is_enabled          boolean NOT NULL DEFAULT true,
    trigger_config      jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_triggers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_triggers_version_id_unique UNIQUE (tenant_id, workflow_version_id, id),
    CONSTRAINT automation_workflow_triggers_version_fk FOREIGN KEY (tenant_id, workflow_version_id)
        REFERENCES automation.workflow_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_triggers_event_shape CHECK (
        trigger_type NOT IN ('event', 'webhook')
        OR (event_type IS NOT NULL AND btrim(event_type) <> '' AND event_version IS NOT NULL AND event_version > 0)
    ),
    CONSTRAINT automation_workflow_triggers_event_source CHECK (
        trigger_type <> 'event' OR (source_module IS NOT NULL AND btrim(source_module) <> '')
    ),
    CONSTRAINT automation_workflow_triggers_source_nonblank CHECK (source_module IS NULL OR btrim(source_module) <> ''),
    CONSTRAINT automation_workflow_triggers_config_object CHECK (jsonb_typeof(trigger_config) = 'object')
);
CREATE INDEX ix_automation_workflow_triggers_event
    ON automation.workflow_triggers (tenant_id, source_module, event_type, is_enabled)
    WHERE is_enabled = true;

CREATE TABLE automation.trigger_filters (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    trigger_id          uuid NOT NULL,
    field_path          varchar(500) NOT NULL,
    comparison_operator varchar(24) NOT NULL
                        CHECK (comparison_operator IN ('eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'not_in', 'contains', 'exists')),
    expected_value      jsonb,
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_trigger_filters_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_trigger_filters_trigger_fk FOREIGN KEY (tenant_id, trigger_id)
        REFERENCES automation.workflow_triggers (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT automation_trigger_filters_path_nonblank CHECK (btrim(field_path) <> ''),
    CONSTRAINT automation_trigger_filters_value_shape CHECK (comparison_operator = 'exists' OR expected_value IS NOT NULL)
);
CREATE INDEX ix_automation_trigger_filters_trigger
    ON automation.trigger_filters (tenant_id, trigger_id, sort_order);

CREATE TABLE automation.workflow_conditions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_version_id uuid NOT NULL,
    parent_node_id      uuid,
    node_type           varchar(16) NOT NULL CHECK (node_type IN ('group', 'predicate')),
    group_operator      varchar(8) CHECK (group_operator IN ('all', 'any', 'not')),
    field_path          varchar(500),
    comparison_operator varchar(24)
                        CHECK (comparison_operator IN ('eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'not_in', 'contains', 'starts_with', 'ends_with', 'exists')),
    expected_value      jsonb,
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_conditions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_conditions_version_id_unique UNIQUE (tenant_id, workflow_version_id, id),
    CONSTRAINT automation_workflow_conditions_version_fk FOREIGN KEY (tenant_id, workflow_version_id)
        REFERENCES automation.workflow_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_conditions_parent_fk FOREIGN KEY (tenant_id, workflow_version_id, parent_node_id)
        REFERENCES automation.workflow_conditions (tenant_id, workflow_version_id, id) ON DELETE CASCADE,
    CONSTRAINT automation_workflow_conditions_shape CHECK (
        (node_type = 'group' AND group_operator IS NOT NULL AND field_path IS NULL AND comparison_operator IS NULL AND expected_value IS NULL)
        OR
        (node_type = 'predicate' AND group_operator IS NULL AND field_path IS NOT NULL AND btrim(field_path) <> '' AND comparison_operator IS NOT NULL
            AND (comparison_operator = 'exists' OR expected_value IS NOT NULL))
    ),
    CONSTRAINT automation_workflow_conditions_no_self_parent CHECK (parent_node_id IS NULL OR parent_node_id <> id)
);
CREATE INDEX ix_automation_workflow_conditions_tree
    ON automation.workflow_conditions (tenant_id, workflow_version_id, parent_node_id, sort_order);

-- ---------------------------------------------------------------------------
-- 3. Pasos y transiciones del workflow
-- ---------------------------------------------------------------------------

CREATE TABLE automation.workflow_steps (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_version_id     uuid NOT NULL,
    step_key                varchar(100) NOT NULL,
    name                    varchar(180) NOT NULL,
    step_type               varchar(20) NOT NULL
                            CHECK (step_type IN ('action', 'condition', 'delay', 'approval', 'end')),
    action_target_module    varchar(80),
    action_code             varchar(120),
    condition_root_node_id  uuid,
    delay_seconds           integer,
    timeout_seconds         integer NOT NULL DEFAULT 300,
    max_attempts            smallint NOT NULL DEFAULT 3,
    initial_retry_delay_seconds integer NOT NULL DEFAULT 5,
    max_retry_delay_seconds integer NOT NULL DEFAULT 300,
    backoff_multiplier      numeric(6,3) NOT NULL DEFAULT 2.0,
    action_config           jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort_order              integer NOT NULL DEFAULT 0,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_steps_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_steps_version_id_unique UNIQUE (tenant_id, workflow_version_id, id),
    CONSTRAINT automation_workflow_steps_key_unique UNIQUE (tenant_id, workflow_version_id, step_key),
    CONSTRAINT automation_workflow_steps_version_fk FOREIGN KEY (tenant_id, workflow_version_id)
        REFERENCES automation.workflow_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_steps_condition_fk FOREIGN KEY (tenant_id, workflow_version_id, condition_root_node_id)
        REFERENCES automation.workflow_conditions (tenant_id, workflow_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_steps_shape CHECK (
        (step_type = 'action' AND action_target_module IS NOT NULL AND btrim(action_target_module) <> '' AND action_code IS NOT NULL AND btrim(action_code) <> '' AND condition_root_node_id IS NULL AND delay_seconds IS NULL)
        OR (step_type = 'condition' AND condition_root_node_id IS NOT NULL AND action_target_module IS NULL AND action_code IS NULL AND delay_seconds IS NULL)
        OR (step_type = 'delay' AND delay_seconds IS NOT NULL AND delay_seconds >= 0 AND action_target_module IS NULL AND action_code IS NULL AND condition_root_node_id IS NULL)
        OR (step_type IN ('approval', 'end') AND action_target_module IS NULL AND action_code IS NULL AND condition_root_node_id IS NULL AND delay_seconds IS NULL)
    ),
    CONSTRAINT automation_workflow_steps_timeout_positive CHECK (timeout_seconds > 0),
    CONSTRAINT automation_workflow_steps_attempts_positive CHECK (max_attempts BETWEEN 1 AND 20),
    CONSTRAINT automation_workflow_steps_retry_delay_check CHECK (initial_retry_delay_seconds >= 0 AND max_retry_delay_seconds >= initial_retry_delay_seconds),
    CONSTRAINT automation_workflow_steps_backoff_check CHECK (backoff_multiplier >= 1 AND backoff_multiplier <= 10),
    CONSTRAINT automation_workflow_steps_config_object CHECK (jsonb_typeof(action_config) = 'object')
);
CREATE INDEX ix_automation_workflow_steps_version
    ON automation.workflow_steps (tenant_id, workflow_version_id, sort_order);

CREATE TABLE automation.workflow_transitions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_version_id uuid NOT NULL,
    from_step_id        uuid NOT NULL,
    to_step_id          uuid NOT NULL,
    outcome_code        varchar(40) NOT NULL DEFAULT 'success',
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_transitions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_transitions_route_unique UNIQUE (tenant_id, workflow_version_id, from_step_id, outcome_code),
    CONSTRAINT automation_workflow_transitions_from_fk FOREIGN KEY (tenant_id, workflow_version_id, from_step_id)
        REFERENCES automation.workflow_steps (tenant_id, workflow_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_transitions_to_fk FOREIGN KEY (tenant_id, workflow_version_id, to_step_id)
        REFERENCES automation.workflow_steps (tenant_id, workflow_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_transitions_no_self_loop CHECK (from_step_id <> to_step_id),
    CONSTRAINT automation_workflow_transitions_outcome_nonblank CHECK (btrim(outcome_code) <> '')
);
CREATE INDEX ix_automation_workflow_transitions_to
    ON automation.workflow_transitions (tenant_id, workflow_version_id, to_step_id);

-- ---------------------------------------------------------------------------
-- 4. Programacion de triggers de calendario
-- ---------------------------------------------------------------------------

CREATE TABLE automation.workflow_schedules (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    trigger_id          uuid NOT NULL,
    cron_expression     varchar(120) NOT NULL,
    timezone_name       varchar(80) NOT NULL,
    starts_at           timestamptz,
    ends_at             timestamptz,
    next_fire_at        timestamptz,
    last_fire_at        timestamptz,
    misfire_policy      varchar(20) NOT NULL DEFAULT 'skip'
                        CHECK (misfire_policy IN ('skip', 'run_once', 'catch_up')),
    max_catch_up        smallint NOT NULL DEFAULT 1,
    is_enabled          boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_schedules_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_schedules_trigger_unique UNIQUE (tenant_id, trigger_id),
    CONSTRAINT automation_workflow_schedules_trigger_fk FOREIGN KEY (tenant_id, trigger_id)
        REFERENCES automation.workflow_triggers (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT automation_workflow_schedules_cron_nonblank CHECK (btrim(cron_expression) <> ''),
    CONSTRAINT automation_workflow_schedules_timezone_nonblank CHECK (btrim(timezone_name) <> ''),
    CONSTRAINT automation_workflow_schedules_dates CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at),
    CONSTRAINT automation_workflow_schedules_catchup_check CHECK (max_catch_up BETWEEN 1 AND 100)
);
CREATE INDEX ix_automation_workflow_schedules_due
    ON automation.workflow_schedules (tenant_id, next_fire_at)
    WHERE is_enabled = true;

CREATE TABLE automation.scheduled_occurrences (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    schedule_id         uuid NOT NULL,
    scheduled_for       timestamptz NOT NULL,
    occurrence_status   varchar(20) NOT NULL DEFAULT 'pending'
                        CHECK (occurrence_status IN ('pending', 'started', 'skipped', 'failed')),
    workflow_run_id     uuid,
    processed_at        timestamptz,
    error_message       text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_scheduled_occurrences_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_scheduled_occurrences_unique UNIQUE (tenant_id, schedule_id, scheduled_for),
    CONSTRAINT automation_scheduled_occurrences_schedule_fk FOREIGN KEY (tenant_id, schedule_id)
        REFERENCES automation.workflow_schedules (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_scheduled_occurrences_processed_shape CHECK (
        (occurrence_status IN ('started', 'skipped', 'failed') AND processed_at IS NOT NULL)
        OR (occurrence_status = 'pending' AND processed_at IS NULL)
    )
);
CREATE INDEX ix_automation_scheduled_occurrences_pending
    ON automation.scheduled_occurrences (tenant_id, scheduled_for)
    WHERE occurrence_status = 'pending';

-- ---------------------------------------------------------------------------
-- 5. Registro de ejecuciones y seguimiento de cada paso
-- ---------------------------------------------------------------------------

CREATE TABLE automation.workflow_runs (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_id             uuid NOT NULL,
    workflow_version_id     uuid NOT NULL,
    trigger_id              uuid NOT NULL,
    trigger_event_id        varchar(180),
    trigger_event_type      varchar(180),
    trigger_event_version   integer,
    trigger_payload_hash    varchar(128) NOT NULL,
    request_hash            varchar(128) NOT NULL,
    trigger_payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
    execution_context       jsonb NOT NULL DEFAULT '{}'::jsonb,
    idempotency_key         varchar(180) NOT NULL,
    correlation_id          uuid,
    causation_id            uuid,
    run_status              varchar(24) NOT NULL DEFAULT 'queued'
                            CHECK (run_status IN ('queued', 'running', 'waiting', 'succeeded', 'failed', 'cancelled', 'timed_out', 'dead_letter')),
    started_at              timestamptz,
    finished_at             timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_runs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_runs_version_id_unique UNIQUE (tenant_id, id, workflow_version_id),
    CONSTRAINT automation_workflow_runs_idempotency_unique UNIQUE (tenant_id, workflow_id, idempotency_key),
    CONSTRAINT automation_workflow_runs_workflow_fk FOREIGN KEY (tenant_id, workflow_id)
        REFERENCES automation.workflows (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_runs_version_fk FOREIGN KEY (tenant_id, workflow_id, workflow_version_id)
        REFERENCES automation.workflow_versions (tenant_id, workflow_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_runs_trigger_fk FOREIGN KEY (tenant_id, workflow_version_id, trigger_id)
        REFERENCES automation.workflow_triggers (tenant_id, workflow_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_runs_hash_format CHECK (trigger_payload_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT automation_workflow_runs_request_hash_format CHECK (request_hash ~ '^[A-Fa-f0-9]{64}$'),
    CONSTRAINT automation_workflow_runs_event_version_positive CHECK (trigger_event_version IS NULL OR trigger_event_version > 0),
    CONSTRAINT automation_workflow_runs_payload_object CHECK (jsonb_typeof(trigger_payload) = 'object'),
    CONSTRAINT automation_workflow_runs_context_object CHECK (jsonb_typeof(execution_context) = 'object'),
    CONSTRAINT automation_workflow_runs_idempotency_nonblank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT automation_workflow_runs_dates CHECK (finished_at IS NULL OR (started_at IS NOT NULL AND finished_at >= started_at)),
    CONSTRAINT automation_workflow_runs_terminal_shape CHECK (
        (run_status IN ('succeeded', 'failed', 'cancelled', 'timed_out', 'dead_letter') AND finished_at IS NOT NULL)
        OR (run_status IN ('queued', 'running', 'waiting') AND finished_at IS NULL)
    )
);
ALTER TABLE automation.scheduled_occurrences
    ADD CONSTRAINT automation_scheduled_occurrences_run_fk
    FOREIGN KEY (tenant_id, workflow_run_id)
    REFERENCES automation.workflow_runs (tenant_id, id) ON DELETE RESTRICT;

CREATE INDEX ix_automation_workflow_runs_workflow
    ON automation.workflow_runs (tenant_id, workflow_id, created_at DESC);
CREATE INDEX ix_automation_workflow_runs_status
    ON automation.workflow_runs (tenant_id, run_status, created_at)
    WHERE run_status IN ('queued', 'running', 'waiting');
CREATE INDEX ix_automation_workflow_runs_event
    ON automation.workflow_runs (tenant_id, trigger_event_id)
    WHERE trigger_event_id IS NOT NULL;

CREATE TABLE automation.workflow_run_steps (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_run_id     uuid NOT NULL,
    workflow_version_id uuid NOT NULL,
    workflow_step_id    uuid NOT NULL,
    step_status         varchar(24) NOT NULL DEFAULT 'pending'
                        CHECK (step_status IN ('pending', 'queued', 'running', 'waiting_approval', 'succeeded', 'failed', 'skipped', 'cancelled', 'dead_letter')),
    input_snapshot      jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_snapshot     jsonb,
    error_code          varchar(100),
    error_message       text,
    scheduled_at        timestamptz,
    started_at          timestamptz,
    finished_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_run_steps_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_run_steps_run_scope_unique UNIQUE (tenant_id, workflow_run_id, id),
    CONSTRAINT automation_workflow_run_steps_run_step_unique UNIQUE (tenant_id, workflow_run_id, workflow_step_id),
    CONSTRAINT automation_workflow_run_steps_run_fk FOREIGN KEY (tenant_id, workflow_run_id, workflow_version_id)
        REFERENCES automation.workflow_runs (tenant_id, id, workflow_version_id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_run_steps_definition_fk FOREIGN KEY (tenant_id, workflow_version_id, workflow_step_id)
        REFERENCES automation.workflow_steps (tenant_id, workflow_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_run_steps_input_object CHECK (jsonb_typeof(input_snapshot) = 'object'),
    CONSTRAINT automation_workflow_run_steps_output_object CHECK (output_snapshot IS NULL OR jsonb_typeof(output_snapshot) = 'object'),
    CONSTRAINT automation_workflow_run_steps_dates CHECK (finished_at IS NULL OR (started_at IS NOT NULL AND finished_at >= started_at))
);
CREATE INDEX ix_automation_workflow_run_steps_status
    ON automation.workflow_run_steps (tenant_id, step_status, scheduled_at)
    WHERE step_status IN ('pending', 'queued', 'running', 'waiting_approval');

CREATE TABLE automation.workflow_step_attempts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    run_step_id         uuid NOT NULL,
    attempt_number      smallint NOT NULL,
    attempt_status      varchar(20) NOT NULL
                        CHECK (attempt_status IN ('started', 'succeeded', 'failed', 'timed_out', 'cancelled')),
    request_snapshot    jsonb NOT NULL DEFAULT '{}'::jsonb,
    response_snapshot   jsonb,
    error_class         varchar(100),
    error_message       text,
    started_at          timestamptz NOT NULL DEFAULT now(),
    finished_at         timestamptz,
    duration_ms         bigint,
    CONSTRAINT automation_workflow_step_attempts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_step_attempts_number_unique UNIQUE (tenant_id, run_step_id, attempt_number),
    CONSTRAINT automation_workflow_step_attempts_run_step_fk FOREIGN KEY (tenant_id, run_step_id)
        REFERENCES automation.workflow_run_steps (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_step_attempts_number_positive CHECK (attempt_number > 0),
    CONSTRAINT automation_workflow_step_attempts_request_object CHECK (jsonb_typeof(request_snapshot) = 'object'),
    CONSTRAINT automation_workflow_step_attempts_response_object CHECK (response_snapshot IS NULL OR jsonb_typeof(response_snapshot) = 'object'),
    CONSTRAINT automation_workflow_step_attempts_dates CHECK (finished_at IS NULL OR finished_at >= started_at),
    CONSTRAINT automation_workflow_step_attempts_duration CHECK (duration_ms IS NULL OR duration_ms >= 0)
);
CREATE INDEX ix_automation_step_attempts_run_step
    ON automation.workflow_step_attempts (tenant_id, run_step_id, attempt_number DESC);

CREATE TABLE automation.workflow_run_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_run_id     uuid NOT NULL,
    run_step_id         uuid,
    event_code          varchar(100) NOT NULL,
    event_message       text,
    event_data          jsonb NOT NULL DEFAULT '{}'::jsonb,
    actor_type          varchar(20) NOT NULL DEFAULT 'system'
                        CHECK (actor_type IN ('system', 'user', 'service', 'worker')),
    actor_id            uuid,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_run_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_run_events_run_fk FOREIGN KEY (tenant_id, workflow_run_id)
        REFERENCES automation.workflow_runs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_run_events_step_fk FOREIGN KEY (tenant_id, workflow_run_id, run_step_id)
        REFERENCES automation.workflow_run_steps (tenant_id, workflow_run_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_run_events_code_nonblank CHECK (btrim(event_code) <> ''),
    CONSTRAINT automation_workflow_run_events_data_object CHECK (jsonb_typeof(event_data) = 'object')
);
CREATE INDEX ix_automation_workflow_run_events_timeline
    ON automation.workflow_run_events (tenant_id, workflow_run_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 6. Aprobaciones humanas para acciones sensibles
-- ---------------------------------------------------------------------------

CREATE TABLE automation.workflow_approvals (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    workflow_run_id     uuid NOT NULL,
    run_step_id         uuid NOT NULL,
    approval_status     varchar(20) NOT NULL DEFAULT 'pending'
                        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'expired', 'cancelled')),
    requested_by_user_id uuid,
    assigned_approver_user_id uuid,
    approval_message    text,
    due_at              timestamptz,
    decided_at          timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_approvals_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_approvals_run_fk FOREIGN KEY (tenant_id, workflow_run_id)
        REFERENCES automation.workflow_runs (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_approvals_run_step_fk FOREIGN KEY (tenant_id, workflow_run_id, run_step_id)
        REFERENCES automation.workflow_run_steps (tenant_id, workflow_run_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_workflow_approvals_decision_shape CHECK (
        (approval_status = 'pending' AND decided_at IS NULL)
        OR (approval_status <> 'pending' AND decided_at IS NOT NULL)
    )
);
CREATE INDEX ix_automation_workflow_approvals_pending
    ON automation.workflow_approvals (tenant_id, assigned_approver_user_id, due_at)
    WHERE approval_status = 'pending';

CREATE TABLE automation.workflow_approval_decisions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    approval_id         uuid NOT NULL,
    decision            varchar(16) NOT NULL CHECK (decision IN ('approved', 'rejected')),
    decided_by_user_id  uuid NOT NULL,
    comments            text,
    decided_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_workflow_approval_decisions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_workflow_approval_decisions_approval_fk FOREIGN KEY (tenant_id, approval_id)
        REFERENCES automation.workflow_approvals (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_automation_workflow_approval_decisions_approval
    ON automation.workflow_approval_decisions (tenant_id, approval_id, decided_at);

-- ---------------------------------------------------------------------------
-- 7. Cola de ejecucion, dead letters y control de consumo
-- ---------------------------------------------------------------------------

CREATE TABLE automation.execution_queue (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    run_step_id         uuid NOT NULL,
    queue_status        varchar(20) NOT NULL DEFAULT 'ready'
                        CHECK (queue_status IN ('ready', 'leased', 'completed', 'cancelled', 'dead_letter')),
    priority            smallint NOT NULL DEFAULT 0,
    available_at        timestamptz NOT NULL DEFAULT now(),
    lease_owner         varchar(160),
    lease_expires_at    timestamptz,
    delivery_attempts   integer NOT NULL DEFAULT 0,
    last_error          text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_execution_queue_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_execution_queue_run_step_id_unique UNIQUE (tenant_id, run_step_id, id),
    CONSTRAINT automation_execution_queue_run_step_unique UNIQUE (tenant_id, run_step_id),
    CONSTRAINT automation_execution_queue_run_step_fk FOREIGN KEY (tenant_id, run_step_id)
        REFERENCES automation.workflow_run_steps (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_execution_queue_attempts_nonnegative CHECK (delivery_attempts >= 0),
    CONSTRAINT automation_execution_queue_lease_shape CHECK (
        (queue_status = 'leased' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)
        OR (queue_status <> 'leased' AND lease_owner IS NULL AND lease_expires_at IS NULL)
    )
);
CREATE INDEX ix_automation_execution_queue_ready
    ON automation.execution_queue (tenant_id, priority DESC, available_at, created_at)
    WHERE queue_status = 'ready';
CREATE INDEX ix_automation_execution_queue_expired_lease
    ON automation.execution_queue (tenant_id, lease_expires_at)
    WHERE queue_status = 'leased';

CREATE TABLE automation.dead_letter_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    run_step_id         uuid NOT NULL,
    source_queue_id     uuid,
    failure_code        varchar(100) NOT NULL,
    failure_message     text,
    failure_snapshot   jsonb NOT NULL DEFAULT '{}'::jsonb,
    dead_lettered_at    timestamptz NOT NULL DEFAULT now(),
    reprocessed_at      timestamptz,
    reprocessed_by_user_id uuid,
    resolution_notes    text,
    CONSTRAINT automation_dead_letter_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_dead_letter_items_run_step_fk FOREIGN KEY (tenant_id, run_step_id)
        REFERENCES automation.workflow_run_steps (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_dead_letter_items_queue_fk FOREIGN KEY (tenant_id, run_step_id, source_queue_id)
        REFERENCES automation.execution_queue (tenant_id, run_step_id, id) ON DELETE RESTRICT,
    CONSTRAINT automation_dead_letter_items_code_nonblank CHECK (btrim(failure_code) <> ''),
    CONSTRAINT automation_dead_letter_items_snapshot_object CHECK (jsonb_typeof(failure_snapshot) = 'object'),
    CONSTRAINT automation_dead_letter_items_reprocess_shape CHECK (reprocessed_at IS NULL OR reprocessed_at >= dead_lettered_at)
);
CREATE INDEX ix_automation_dead_letter_unresolved
    ON automation.dead_letter_items (tenant_id, dead_lettered_at)
    WHERE reprocessed_at IS NULL;

CREATE TABLE automation.rate_limit_buckets (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    bucket_key          varchar(180) NOT NULL,
    window_started_at   timestamptz NOT NULL,
    window_seconds      integer NOT NULL,
    request_count       integer NOT NULL DEFAULT 0,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_rate_limit_buckets_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_rate_limit_buckets_unique UNIQUE (tenant_id, bucket_key, window_started_at),
    CONSTRAINT automation_rate_limit_buckets_key_nonblank CHECK (btrim(bucket_key) <> ''),
    CONSTRAINT automation_rate_limit_buckets_window_positive CHECK (window_seconds > 0),
    CONSTRAINT automation_rate_limit_buckets_count_nonnegative CHECK (request_count >= 0)
);

-- ---------------------------------------------------------------------------
-- 8. Allowlist de acciones, Inbox, Outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE automation.action_allowlist (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    target_module       varchar(80) NOT NULL,
    action_code         varchar(120) NOT NULL,
    description         text,
    requires_approval   boolean NOT NULL DEFAULT false,
    requires_idempotency boolean NOT NULL DEFAULT true,
    is_enabled          boolean NOT NULL DEFAULT true,
    configuration       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_action_allowlist_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_action_allowlist_unique UNIQUE (tenant_id, target_module, action_code),
    CONSTRAINT automation_action_allowlist_module_nonblank CHECK (btrim(target_module) <> ''),
    CONSTRAINT automation_action_allowlist_code_nonblank CHECK (btrim(action_code) <> ''),
    CONSTRAINT automation_action_allowlist_config_object CHECK (jsonb_typeof(configuration) = 'object')
);

CREATE TABLE automation.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_name       varchar(120) NOT NULL,
    event_id            varchar(180) NOT NULL,
    event_type          varchar(180) NOT NULL,
    payload_hash        varchar(128),
    processed_at        timestamptz NOT NULL DEFAULT now(),
    result_reference_id uuid,
    CONSTRAINT automation_processed_events_unique UNIQUE (tenant_id, consumer_name, event_id),
    CONSTRAINT automation_processed_events_consumer_nonblank CHECK (btrim(consumer_name) <> ''),
    CONSTRAINT automation_processed_events_event_nonblank CHECK (btrim(event_id) <> ''),
    CONSTRAINT automation_processed_events_type_nonblank CHECK (btrim(event_type) <> '')
);

CREATE TABLE automation.event_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type      varchar(100) NOT NULL,
    aggregate_id        uuid NOT NULL,
    event_type          varchar(180) NOT NULL,
    event_version       integer NOT NULL DEFAULT 1,
    payload             jsonb NOT NULL,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    available_at        timestamptz NOT NULL DEFAULT now(),
    published_at        timestamptz,
    publish_attempts    integer NOT NULL DEFAULT 0,
    last_error          text,
    CONSTRAINT automation_event_outbox_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_event_outbox_version_positive CHECK (event_version > 0),
    CONSTRAINT automation_event_outbox_attempts_nonnegative CHECK (publish_attempts >= 0),
    CONSTRAINT automation_event_outbox_aggregate_nonblank CHECK (btrim(aggregate_type) <> ''),
    CONSTRAINT automation_event_outbox_type_nonblank CHECK (btrim(event_type) <> ''),
    CONSTRAINT automation_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object')
);
CREATE INDEX ix_automation_event_outbox_pending
    ON automation.event_outbox (tenant_id, available_at, occurred_at)
    WHERE published_at IS NULL;

CREATE TABLE automation.idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_scope     varchar(120) NOT NULL,
    idempotency_key     varchar(180) NOT NULL,
    request_hash        varchar(128) NOT NULL,
    response_status     integer,
    response_body       jsonb,
    resource_id         uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz,
    CONSTRAINT automation_idempotency_unique UNIQUE (tenant_id, operation_scope, idempotency_key),
    CONSTRAINT automation_idempotency_scope_nonblank CHECK (btrim(operation_scope) <> ''),
    CONSTRAINT automation_idempotency_key_nonblank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT automation_idempotency_status CHECK (response_status IS NULL OR response_status BETWEEN 100 AND 599),
    CONSTRAINT automation_idempotency_response_object CHECK (response_body IS NULL OR jsonb_typeof(response_body) = 'object'),
    CONSTRAINT automation_idempotency_dates CHECK (expires_at IS NULL OR expires_at > created_at)
);
CREATE INDEX ix_automation_idempotency_expiry
    ON automation.idempotency_records (tenant_id, expires_at)
    WHERE expires_at IS NOT NULL;

CREATE TABLE automation.audit_logs (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    actor_type          varchar(20) NOT NULL CHECK (actor_type IN ('user', 'system', 'service', 'worker')),
    actor_id            uuid,
    action_code         varchar(120) NOT NULL,
    resource_type       varchar(100) NOT NULL,
    resource_id         uuid,
    before_snapshot     jsonb,
    after_snapshot      jsonb,
    ip_address          inet,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_audit_logs_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT automation_audit_logs_action_nonblank CHECK (btrim(action_code) <> ''),
    CONSTRAINT automation_audit_logs_resource_nonblank CHECK (btrim(resource_type) <> ''),
    CONSTRAINT automation_audit_logs_before_object CHECK (before_snapshot IS NULL OR jsonb_typeof(before_snapshot) = 'object'),
    CONSTRAINT automation_audit_logs_after_object CHECK (after_snapshot IS NULL OR jsonb_typeof(after_snapshot) = 'object')
);
CREATE INDEX ix_automation_audit_logs_resource
    ON automation.audit_logs (tenant_id, resource_type, resource_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Funciones de inicializacion, publicacion y creacion de ejecuciones
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION automation.initialize_tenant_automation(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tenant_id IS NULL OR automation.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant no coincide con el contexto autenticado';
    END IF;

    INSERT INTO automation.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION automation.publish_workflow_version(
    p_tenant_id uuid,
    p_workflow_id uuid,
    p_workflow_version_id uuid,
    p_published_by_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_workflow automation.workflows%ROWTYPE;
    v_version automation.workflow_versions%ROWTYPE;
    v_settings automation.tenant_settings%ROWTYPE;
    v_step_count integer;
    v_root_count integer;
    v_unreachable_step_count integer;
    v_terminal_step_count integer;
    v_invalid_terminal_steps integer;
    v_trigger_count integer;
    v_invalid_actions integer;
    v_invalid_schedules integer;
    v_invalid_condition_parents integer;
    v_has_cycle boolean;
    v_has_condition_cycle boolean;
    v_definition jsonb;
    v_definition_hash text;
BEGIN
    IF p_tenant_id IS NULL OR automation.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant no coincide con el contexto autenticado';
    END IF;

    SELECT * INTO v_settings
      FROM automation.tenant_settings
     WHERE tenant_id = p_tenant_id
     FOR UPDATE;
    IF NOT FOUND OR v_settings.is_enabled = false THEN
        RAISE EXCEPTION 'Automation no esta inicializado o esta deshabilitado para este tenant';
    END IF;

    SELECT * INTO v_workflow
      FROM automation.workflows
     WHERE tenant_id = p_tenant_id AND id = p_workflow_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Workflow no encontrado';
    END IF;
    IF v_workflow.status = 'archived' THEN
        RAISE EXCEPTION 'No se puede publicar un workflow archivado';
    END IF;

    IF v_workflow.status <> 'active' AND (
        SELECT count(*) FROM automation.workflows w
         WHERE w.tenant_id = p_tenant_id AND w.status = 'active'
    ) >= v_settings.max_active_workflows THEN
        RAISE EXCEPTION 'El tenant alcanzo el maximo de workflows activos';
    END IF;

    SELECT * INTO v_version
      FROM automation.workflow_versions
     WHERE tenant_id = p_tenant_id AND workflow_id = p_workflow_id AND id = p_workflow_version_id
     FOR UPDATE;
    IF NOT FOUND OR v_version.status <> 'draft' THEN
        RAISE EXCEPTION 'La version debe existir y estar en estado draft';
    END IF;

    SELECT count(*) INTO v_step_count
      FROM automation.workflow_steps
     WHERE tenant_id = p_tenant_id AND workflow_version_id = p_workflow_version_id;
    IF v_step_count = 0 THEN
        RAISE EXCEPTION 'El workflow necesita al menos un paso';
    END IF;

    SELECT count(*) INTO v_root_count
      FROM automation.workflow_steps s
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = p_workflow_version_id
       AND NOT EXISTS (
           SELECT 1 FROM automation.workflow_transitions t
            WHERE t.tenant_id = s.tenant_id
              AND t.workflow_version_id = s.workflow_version_id
              AND t.to_step_id = s.id
       );
    IF v_root_count = 0 THEN
        RAISE EXCEPTION 'El workflow necesita al menos un paso inicial sin transiciones entrantes';
    END IF;

    WITH RECURSIVE reachable(step_id) AS (
        SELECT s.id
          FROM automation.workflow_steps s
         WHERE s.tenant_id = p_tenant_id
           AND s.workflow_version_id = p_workflow_version_id
           AND NOT EXISTS (
               SELECT 1 FROM automation.workflow_transitions t
                WHERE t.tenant_id = s.tenant_id
                  AND t.workflow_version_id = s.workflow_version_id
                  AND t.to_step_id = s.id
           )
        UNION
        SELECT t.to_step_id
          FROM reachable r
          JOIN automation.workflow_transitions t
            ON t.tenant_id = p_tenant_id
           AND t.workflow_version_id = p_workflow_version_id
           AND t.from_step_id = r.step_id
    )
    SELECT count(*) INTO v_unreachable_step_count
      FROM automation.workflow_steps s
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = p_workflow_version_id
       AND NOT EXISTS (SELECT 1 FROM reachable r WHERE r.step_id = s.id);
    IF v_unreachable_step_count > 0 THEN
        RAISE EXCEPTION 'Hay % pasos que no son alcanzables desde un paso inicial', v_unreachable_step_count;
    END IF;

    SELECT count(*) INTO v_terminal_step_count
      FROM automation.workflow_steps
     WHERE tenant_id = p_tenant_id
       AND workflow_version_id = p_workflow_version_id
       AND step_type = 'end';
    IF v_terminal_step_count = 0 THEN
        RAISE EXCEPTION 'El workflow necesita al menos un paso terminal end';
    END IF;

    SELECT count(*) INTO v_invalid_terminal_steps
      FROM automation.workflow_steps s
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = p_workflow_version_id
       AND (
           (s.step_type = 'end' AND EXISTS (
               SELECT 1 FROM automation.workflow_transitions t
                WHERE t.tenant_id = s.tenant_id
                  AND t.workflow_version_id = s.workflow_version_id
                  AND t.from_step_id = s.id
           ))
           OR
           (s.step_type <> 'end' AND NOT EXISTS (
               SELECT 1 FROM automation.workflow_transitions t
                WHERE t.tenant_id = s.tenant_id
                  AND t.workflow_version_id = s.workflow_version_id
                  AND t.from_step_id = s.id
           ))
       );
    IF v_invalid_terminal_steps > 0 THEN
        RAISE EXCEPTION 'Todos los caminos deben terminar en un paso end y los pasos end no pueden tener transiciones salientes';
    END IF;

    SELECT count(*) INTO v_trigger_count
      FROM automation.workflow_triggers
     WHERE tenant_id = p_tenant_id
       AND workflow_version_id = p_workflow_version_id
       AND is_enabled = true;
    IF v_trigger_count = 0 THEN
        RAISE EXCEPTION 'El workflow necesita al menos un trigger habilitado';
    END IF;

    SELECT count(*) INTO v_invalid_actions
      FROM automation.workflow_steps s
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = p_workflow_version_id
       AND s.step_type = 'action'
       AND NOT EXISTS (
           SELECT 1 FROM automation.action_allowlist a
            WHERE a.tenant_id = s.tenant_id
              AND a.target_module = s.action_target_module
              AND a.action_code = s.action_code
              AND a.is_enabled = true
       );
    IF v_invalid_actions > 0 THEN
        RAISE EXCEPTION 'Hay % acciones que no estan habilitadas en automation.action_allowlist', v_invalid_actions;
    END IF;

    SELECT count(*) INTO v_invalid_schedules
      FROM automation.workflow_triggers t
     WHERE t.tenant_id = p_tenant_id
       AND t.workflow_version_id = p_workflow_version_id
       AND t.is_enabled = true
       AND t.trigger_type = 'schedule'
       AND NOT EXISTS (
           SELECT 1 FROM automation.workflow_schedules s
            WHERE s.tenant_id = t.tenant_id AND s.trigger_id = t.id AND s.is_enabled = true
       );
    IF v_invalid_schedules > 0 THEN
        RAISE EXCEPTION 'Hay % triggers schedule sin una programacion habilitada', v_invalid_schedules;
    END IF;

    SELECT count(*) INTO v_invalid_schedules
      FROM automation.workflow_schedules s
      JOIN automation.workflow_triggers t
        ON t.tenant_id = s.tenant_id AND t.id = s.trigger_id
     WHERE s.tenant_id = p_tenant_id
       AND t.workflow_version_id = p_workflow_version_id
       AND t.trigger_type <> 'schedule';
    IF v_invalid_schedules > 0 THEN
        RAISE EXCEPTION 'Hay programaciones asociadas a triggers que no son de tipo schedule';
    END IF;

    SELECT count(*) INTO v_invalid_condition_parents
      FROM automation.workflow_conditions c
      JOIN automation.workflow_conditions p
        ON p.tenant_id = c.tenant_id
       AND p.workflow_version_id = c.workflow_version_id
       AND p.id = c.parent_node_id
     WHERE c.tenant_id = p_tenant_id
       AND c.workflow_version_id = p_workflow_version_id
       AND p.node_type <> 'group';
    IF v_invalid_condition_parents > 0 THEN
        RAISE EXCEPTION 'Hay nodos de condicion cuyo padre no es un grupo';
    END IF;

    SELECT count(*) INTO v_invalid_condition_parents
      FROM automation.workflow_steps s
      JOIN automation.workflow_conditions c
        ON c.tenant_id = s.tenant_id
       AND c.workflow_version_id = s.workflow_version_id
       AND c.id = s.condition_root_node_id
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = p_workflow_version_id
       AND s.step_type = 'condition'
       AND c.parent_node_id IS NOT NULL;
    IF v_invalid_condition_parents > 0 THEN
        RAISE EXCEPTION 'Los pasos condition deben referenciar nodos raiz del arbol de condiciones';
    END IF;

    WITH RECURSIVE condition_walk(root_id, current_id, path, has_cycle) AS (
        SELECT c.id, c.id, ARRAY[c.id]::uuid[], false
          FROM automation.workflow_conditions c
         WHERE c.tenant_id = p_tenant_id AND c.workflow_version_id = p_workflow_version_id
        UNION ALL
        SELECT w.root_id, child.id, w.path || child.id, child.id = ANY(w.path)
          FROM condition_walk w
          JOIN automation.workflow_conditions child
            ON child.tenant_id = p_tenant_id
           AND child.workflow_version_id = p_workflow_version_id
           AND child.parent_node_id = w.current_id
         WHERE NOT w.has_cycle
    )
    SELECT coalesce(bool_or(has_cycle), false) INTO v_has_condition_cycle FROM condition_walk;
    IF v_has_condition_cycle THEN
        RAISE EXCEPTION 'El arbol de condiciones contiene ciclos';
    END IF;

    WITH RECURSIVE graph_walk(start_id, current_id) AS (
        SELECT t.from_step_id, t.to_step_id
          FROM automation.workflow_transitions t
         WHERE t.tenant_id = p_tenant_id AND t.workflow_version_id = p_workflow_version_id
        UNION
        SELECT g.start_id, t.to_step_id
          FROM graph_walk g
          JOIN automation.workflow_transitions t
            ON t.tenant_id = p_tenant_id
           AND t.workflow_version_id = p_workflow_version_id
           AND t.from_step_id = g.current_id
    )
    SELECT coalesce(bool_or(start_id = current_id), false) INTO v_has_cycle FROM graph_walk;
    IF v_has_cycle THEN
        RAISE EXCEPTION 'El grafo del workflow contiene ciclos; modele ciclos mediante recurrencia programada o pasos acotados';
    END IF;

    SELECT jsonb_build_object(
        'triggers', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
                                FROM automation.workflow_triggers t
                               WHERE t.tenant_id = p_tenant_id AND t.workflow_version_id = p_workflow_version_id), '[]'::jsonb),
        'trigger_filters', coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.trigger_id, f.sort_order, f.id)
                                       FROM automation.trigger_filters f
                                       JOIN automation.workflow_triggers t ON t.tenant_id = f.tenant_id AND t.id = f.trigger_id
                                      WHERE f.tenant_id = p_tenant_id AND t.workflow_version_id = p_workflow_version_id), '[]'::jsonb),
        'conditions', coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.parent_node_id NULLS FIRST, c.sort_order, c.id)
                                  FROM automation.workflow_conditions c
                                 WHERE c.tenant_id = p_tenant_id AND c.workflow_version_id = p_workflow_version_id), '[]'::jsonb),
        'steps', coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.sort_order, s.step_key)
                             FROM automation.workflow_steps s
                            WHERE s.tenant_id = p_tenant_id AND s.workflow_version_id = p_workflow_version_id), '[]'::jsonb),
        'transitions', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.from_step_id, t.outcome_code)
                                   FROM automation.workflow_transitions t
                                  WHERE t.tenant_id = p_tenant_id AND t.workflow_version_id = p_workflow_version_id), '[]'::jsonb),
        'schedules', coalesce((SELECT jsonb_agg(to_jsonb(s) - ARRAY['next_fire_at', 'last_fire_at', 'updated_at'] ORDER BY s.id)
                                 FROM automation.workflow_schedules s
                                 JOIN automation.workflow_triggers t ON t.tenant_id = s.tenant_id AND t.id = s.trigger_id
                                WHERE s.tenant_id = p_tenant_id AND t.workflow_version_id = p_workflow_version_id), '[]'::jsonb)
    ) INTO v_definition;
    v_definition_hash := encode(digest(v_definition::text, 'sha256'), 'hex');

    IF v_workflow.published_version_id IS NOT NULL
       AND v_workflow.published_version_id <> p_workflow_version_id THEN
        UPDATE automation.workflow_versions
           SET status = 'superseded', updated_at = now()
         WHERE tenant_id = p_tenant_id
           AND workflow_id = p_workflow_id
           AND id = v_workflow.published_version_id
           AND status = 'published';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'La version publicada anterior no esta en un estado valido';
        END IF;
    END IF;

    UPDATE automation.workflow_versions
       SET status = 'published', definition_hash = v_definition_hash,
           published_by_user_id = p_published_by_user_id,
           published_at = now(), updated_at = now()
     WHERE tenant_id = p_tenant_id AND id = p_workflow_version_id;

    UPDATE automation.workflows
       SET status = 'active', published_version_id = p_workflow_version_id,
           updated_by_user_id = p_published_by_user_id, updated_at = now()
     WHERE tenant_id = p_tenant_id AND id = p_workflow_id;

    INSERT INTO automation.audit_logs (
        tenant_id, actor_type, actor_id, action_code,
        resource_type, resource_id, after_snapshot
    ) VALUES (
        p_tenant_id, CASE WHEN p_published_by_user_id IS NULL THEN 'system' ELSE 'user' END,
        p_published_by_user_id, 'workflow.version_published', 'workflow', p_workflow_id,
        jsonb_build_object('workflow_version_id', p_workflow_version_id, 'version_number', v_version.version_number)
    );
END;
$$;

CREATE OR REPLACE FUNCTION automation.start_workflow_run(
    p_tenant_id uuid,
    p_workflow_id uuid,
    p_trigger_id uuid,
    p_idempotency_key varchar(180),
    p_trigger_payload jsonb DEFAULT '{}'::jsonb,
    p_trigger_event_id varchar(180) DEFAULT NULL,
    p_trigger_event_type varchar(180) DEFAULT NULL,
    p_source_module varchar(80) DEFAULT NULL,
    p_correlation_id uuid DEFAULT NULL,
    p_causation_id uuid DEFAULT NULL,
    p_trigger_event_version integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_workflow automation.workflows%ROWTYPE;
    v_trigger automation.workflow_triggers%ROWTYPE;
    v_settings automation.tenant_settings%ROWTYPE;
    v_active_runs integer;
    v_daily_runs integer;
    v_day_start timestamptz;
    v_next_day_start timestamptz;
    v_run_id uuid;
    v_existing_request_hash text;
    v_payload_hash text;
    v_request_hash text;
BEGIN
    IF p_tenant_id IS NULL OR automation.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant no coincide con el contexto autenticado';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key es obligatorio';
    END IF;
    IF p_trigger_payload IS NULL OR jsonb_typeof(p_trigger_payload) <> 'object' THEN
        RAISE EXCEPTION 'trigger_payload debe ser un objeto JSON';
    END IF;

    SELECT * INTO v_settings
      FROM automation.tenant_settings
     WHERE tenant_id = p_tenant_id
     FOR UPDATE;
    IF NOT FOUND OR v_settings.is_enabled = false THEN
        RAISE EXCEPTION 'Automation no esta inicializado o esta deshabilitado para este tenant';
    END IF;
    IF octet_length(p_trigger_payload::text) > v_settings.max_payload_bytes THEN
        RAISE EXCEPTION 'El payload supera el maximo permitido de % bytes', v_settings.max_payload_bytes;
    END IF;

    v_payload_hash := encode(digest(p_trigger_payload::text, 'sha256'), 'hex');
    v_request_hash := encode(digest(jsonb_build_object(
        'trigger_id', p_trigger_id,
        'trigger_event_id', p_trigger_event_id,
        'trigger_event_type', p_trigger_event_type,
        'trigger_event_version', p_trigger_event_version,
        'source_module', p_source_module,
        'trigger_payload', p_trigger_payload
    )::text, 'sha256'), 'hex');
    SELECT id, request_hash INTO v_run_id, v_existing_request_hash
      FROM automation.workflow_runs
     WHERE tenant_id = p_tenant_id
       AND workflow_id = p_workflow_id
       AND idempotency_key = p_idempotency_key
     FOR UPDATE;
    IF FOUND THEN
        IF v_existing_request_hash IS DISTINCT FROM v_request_hash THEN
            RAISE EXCEPTION 'La clave de idempotencia ya fue usada con una solicitud diferente';
        END IF;
        RETURN v_run_id;
    END IF;

    SELECT * INTO v_workflow
      FROM automation.workflows
     WHERE tenant_id = p_tenant_id AND id = p_workflow_id
     FOR SHARE;
    IF NOT FOUND OR v_workflow.status <> 'active' OR v_workflow.published_version_id IS NULL THEN
        RAISE EXCEPTION 'Workflow inexistente, inactivo o sin version publicada';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM automation.workflow_versions v
         WHERE v.tenant_id = p_tenant_id
           AND v.workflow_id = p_workflow_id
           AND v.id = v_workflow.published_version_id
           AND v.status = 'published'
    ) THEN
        RAISE EXCEPTION 'La version activa del workflow no esta publicada';
    END IF;

    SELECT * INTO v_trigger
      FROM automation.workflow_triggers
     WHERE tenant_id = p_tenant_id
       AND id = p_trigger_id
       AND workflow_version_id = v_workflow.published_version_id
       AND is_enabled = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trigger no habilitado en la version publicada';
    END IF;

    IF v_trigger.trigger_type IN ('event', 'webhook') THEN
        IF p_trigger_event_id IS NULL OR btrim(p_trigger_event_id) = ''
           OR p_trigger_event_type IS DISTINCT FROM v_trigger.event_type
           OR p_trigger_event_version IS DISTINCT FROM v_trigger.event_version THEN
            RAISE EXCEPTION 'El identificador, tipo o version del evento no coincide con el trigger';
        END IF;
        IF v_trigger.source_module IS NOT NULL
           AND p_source_module IS DISTINCT FROM v_trigger.source_module THEN
            RAISE EXCEPTION 'El modulo de origen no coincide con el trigger';
        END IF;
    ELSIF p_trigger_event_version IS NOT NULL THEN
        RAISE EXCEPTION 'La version del evento solo se admite para triggers de evento o webhook';
    END IF;

    SELECT count(*) INTO v_active_runs
      FROM automation.workflow_runs
     WHERE tenant_id = p_tenant_id
       AND run_status IN ('queued', 'running', 'waiting');
    IF v_active_runs >= v_settings.max_concurrent_runs THEN
        RAISE EXCEPTION 'Se alcanzo el maximo de ejecuciones concurrentes configurado para el tenant';
    END IF;

    BEGIN
        v_day_start := date_trunc('day', now() AT TIME ZONE v_settings.default_timezone)
                       AT TIME ZONE v_settings.default_timezone;
        v_next_day_start := (date_trunc('day', now() AT TIME ZONE v_settings.default_timezone) + interval '1 day')
                            AT TIME ZONE v_settings.default_timezone;
    EXCEPTION WHEN invalid_parameter_value THEN
        RAISE EXCEPTION 'La zona horaria % configurada para el tenant no es valida', v_settings.default_timezone;
    END;
    SELECT count(*) INTO v_daily_runs
      FROM automation.workflow_runs
     WHERE tenant_id = p_tenant_id
       AND created_at >= v_day_start
       AND created_at < v_next_day_start;
    IF v_daily_runs >= v_settings.max_runs_per_day THEN
        RAISE EXCEPTION 'El tenant alcanzo el maximo diario de ejecuciones configurado';
    END IF;

    INSERT INTO automation.workflow_runs (
        tenant_id, workflow_id, workflow_version_id, trigger_id,
        trigger_event_id, trigger_event_type, trigger_event_version,
        trigger_payload_hash, request_hash, trigger_payload,
        idempotency_key, correlation_id, causation_id,
        run_status
    ) VALUES (
        p_tenant_id, p_workflow_id, v_workflow.published_version_id, p_trigger_id,
        p_trigger_event_id, p_trigger_event_type, p_trigger_event_version,
        v_payload_hash, v_request_hash, p_trigger_payload,
        p_idempotency_key, p_correlation_id, p_causation_id,
        'queued'
    )
    ON CONFLICT (tenant_id, workflow_id, idempotency_key) DO NOTHING
    RETURNING id INTO v_run_id;

    IF v_run_id IS NULL THEN
        SELECT id, request_hash INTO v_run_id, v_existing_request_hash
          FROM automation.workflow_runs
         WHERE tenant_id = p_tenant_id
           AND workflow_id = p_workflow_id
           AND idempotency_key = p_idempotency_key
         FOR UPDATE;
        IF v_existing_request_hash IS DISTINCT FROM v_request_hash THEN
            RAISE EXCEPTION 'La clave de idempotencia ya fue usada con una solicitud diferente';
        END IF;
        RETURN v_run_id;
    END IF;

    INSERT INTO automation.workflow_run_steps (
        tenant_id, workflow_run_id, workflow_version_id, workflow_step_id,
        step_status, input_snapshot
    )
    SELECT p_tenant_id, v_run_id, s.workflow_version_id, s.id,
           'pending', '{}'::jsonb
      FROM automation.workflow_steps s
     WHERE s.tenant_id = p_tenant_id
       AND s.workflow_version_id = v_workflow.published_version_id;

    INSERT INTO automation.execution_queue (tenant_id, run_step_id, queue_status, available_at)
    SELECT p_tenant_id, rs.id, 'ready', now()
      FROM automation.workflow_run_steps rs
      JOIN automation.workflow_steps s
        ON s.tenant_id = rs.tenant_id
       AND s.workflow_version_id = rs.workflow_version_id
       AND s.id = rs.workflow_step_id
     WHERE rs.tenant_id = p_tenant_id
       AND rs.workflow_run_id = v_run_id
       AND NOT EXISTS (
           SELECT 1 FROM automation.workflow_transitions t
            WHERE t.tenant_id = s.tenant_id
              AND t.workflow_version_id = s.workflow_version_id
              AND t.to_step_id = s.id
       );

    UPDATE automation.workflow_run_steps rs
       SET step_status = 'queued', scheduled_at = now(), updated_at = now()
      FROM automation.execution_queue q
     WHERE q.tenant_id = rs.tenant_id
       AND q.run_step_id = rs.id
       AND q.queue_status = 'ready'
       AND rs.tenant_id = p_tenant_id
       AND rs.workflow_run_id = v_run_id;

    INSERT INTO automation.workflow_run_events (
        tenant_id, workflow_run_id, event_code, event_message, event_data, actor_type
    ) VALUES (
        p_tenant_id, v_run_id, 'workflow.run_queued', 'Ejecucion creada y encolada',
        jsonb_build_object('workflow_id', p_workflow_id, 'workflow_version_id', v_workflow.published_version_id,
                           'trigger_id', p_trigger_id, 'trigger_event_id', p_trigger_event_id),
        'system'
    );

    INSERT INTO automation.event_outbox (
        tenant_id, aggregate_type, aggregate_id, event_type, event_version, payload
    ) VALUES (
        p_tenant_id, 'workflow_run', v_run_id, 'automation.workflow_run_queued.v1', 1,
        jsonb_build_object('workflow_run_id', v_run_id, 'workflow_id', p_workflow_id,
                           'workflow_version_id', v_workflow.published_version_id,
                           'trigger_id', p_trigger_id, 'correlation_id', p_correlation_id)
    );

    RETURN v_run_id;
END;
$$;

CREATE OR REPLACE FUNCTION automation.validate_schedule_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_type varchar(20);
BEGIN
    SELECT trigger_type INTO v_trigger_type
      FROM automation.workflow_triggers
     WHERE tenant_id = NEW.tenant_id AND id = NEW.trigger_id;
    IF v_trigger_type IS DISTINCT FROM 'schedule' THEN
        RAISE EXCEPTION 'workflow_schedules solo puede asociarse a triggers de tipo schedule';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_automation_schedule_trigger_validation
    BEFORE INSERT OR UPDATE OF tenant_id, trigger_id ON automation.workflow_schedules
    FOR EACH ROW EXECUTE FUNCTION automation.validate_schedule_trigger();

-- ---------------------------------------------------------------------------
-- 10. Triggers de mantenimiento, tenant inmutable y append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'workflow_folders', 'workflows', 'workflow_versions',
        'workflow_triggers', 'workflow_schedules', 'workflow_steps',
        'workflow_run_steps', 'workflow_runs', 'workflow_approvals',
        'execution_queue', 'action_allowlist', 'rate_limit_buckets'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON automation.%I FOR EACH ROW EXECUTE FUNCTION automation.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'workflow_folders', 'workflows', 'workflow_versions', 'workflow_triggers',
        'trigger_filters', 'workflow_conditions', 'workflow_steps', 'workflow_transitions',
        'workflow_schedules', 'scheduled_occurrences', 'workflow_runs',
        'workflow_run_steps', 'workflow_step_attempts', 'workflow_run_events',
        'workflow_approvals', 'workflow_approval_decisions', 'execution_queue',
        'dead_letter_items', 'rate_limit_buckets', 'action_allowlist',
        'processed_events', 'event_outbox', 'idempotency_records', 'audit_logs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON automation.%I FOR EACH ROW EXECUTE FUNCTION automation.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'workflow_run_events', 'workflow_approval_decisions',
        'processed_events', 'audit_logs'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON automation.%I FOR EACH ROW EXECUTE FUNCTION automation.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- Las versiones publicadas y superseded son inmutables. Para cambiar un
-- workflow se crea una nueva version draft en vez de alterar la publicada.
CREATE OR REPLACE FUNCTION automation.prevent_published_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status = 'published' THEN
        IF TG_OP = 'UPDATE'
           AND NEW.status = 'superseded'
           AND (to_jsonb(NEW) - ARRAY['status', 'updated_at']) IS NOT DISTINCT FROM
               (to_jsonb(OLD) - ARRAY['status', 'updated_at']) THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Una version publicada solo puede marcarse como superseded al publicar una version nueva';
    END IF;
    IF OLD.status = 'superseded' THEN
        RAISE EXCEPTION 'Las versiones publicadas de workflows son inmutables; cree una nueva version draft';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NEW.status NOT IN ('draft', 'published') THEN
        RAISE EXCEPTION 'Transicion de estado de version no permitida: % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_automation_workflow_versions_immutable
    BEFORE UPDATE OR DELETE ON automation.workflow_versions
    FOR EACH ROW EXECUTE FUNCTION automation.prevent_published_version_mutation();

CREATE OR REPLACE FUNCTION automation.prevent_published_definition_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar(20);
    v_version_id uuid;
BEGIN
    v_version_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.workflow_version_id ELSE NEW.workflow_version_id END;
    SELECT status INTO v_status
      FROM automation.workflow_versions
     WHERE tenant_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END
       AND id = v_version_id
     FOR SHARE;
    IF v_status IN ('published', 'superseded') THEN
        -- El cursor operativo del scheduler puede avanzar sin alterar la
        -- definicion publicada: cron, zona, vigencia y politica siguen fijos.
        IF TG_TABLE_NAME = 'workflow_schedules'
           AND TG_OP = 'UPDATE'
           AND (NEW.tenant_id, NEW.trigger_id, NEW.cron_expression, NEW.timezone_name,
                NEW.starts_at, NEW.ends_at, NEW.misfire_policy, NEW.max_catch_up, NEW.is_enabled)
               IS NOT DISTINCT FROM
               (OLD.tenant_id, OLD.trigger_id, OLD.cron_expression, OLD.timezone_name,
                OLD.starts_at, OLD.ends_at, OLD.misfire_policy, OLD.max_catch_up, OLD.is_enabled) THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'No se permite cambiar definiciones de una version publicada';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'workflow_triggers', 'trigger_filters', 'workflow_conditions',
        'workflow_steps', 'workflow_transitions', 'workflow_schedules'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON automation.%I FOR EACH ROW EXECUTE FUNCTION automation.prevent_published_definition_mutation()',
            'trg_' || v_table || '_published_definition_immutable', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. RLS + FORCE RLS para todas las tablas con tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'workflow_folders', 'workflows', 'workflow_versions',
        'workflow_triggers', 'trigger_filters', 'workflow_conditions', 'workflow_steps',
        'workflow_transitions', 'workflow_schedules', 'scheduled_occurrences',
        'workflow_runs', 'workflow_run_steps', 'workflow_step_attempts',
        'workflow_run_events', 'workflow_approvals', 'workflow_approval_decisions',
        'execution_queue', 'dead_letter_items', 'rate_limit_buckets', 'action_allowlist',
        'processed_events', 'event_outbox', 'idempotency_records', 'audit_logs'
    ] LOOP
        EXECUTE format('ALTER TABLE automation.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE automation.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON automation.%I USING (tenant_id = automation.current_tenant_id()) WITH CHECK (tenant_id = automation.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Comentarios de propiedad y contratos
-- ---------------------------------------------------------------------------

COMMENT ON TABLE automation.workflows IS
'Identidad estable de un flujo. Su definicion ejecutable pertenece a workflow_versions.';
COMMENT ON TABLE automation.workflow_versions IS
'Versiones inmutables una vez publicadas. Las ediciones se hacen en versiones draft nuevas.';
COMMENT ON TABLE automation.workflow_steps IS
'Pasos declarativos. action_target_module/action_code deben existir en action_allowlist y ser validados por el adaptador Rust.';
COMMENT ON TABLE automation.workflow_schedules IS
'Definicion de cron inmutable tras publicar; next_fire_at y last_fire_at son cursores operativos actualizables por el scheduler.';
COMMENT ON TABLE automation.action_allowlist IS
'Lista de acciones autorizadas por tenant. No habilita SQL arbitrario, scripts dinamicos ni acceso directo a tablas de otros modulos.';
COMMENT ON TABLE automation.workflow_runs IS
'Instancias de ejecucion con snapshot del payload de entrada, version exacta y clave de idempotencia. Persistir solo datos necesarios y redactar PII, secretos y datos de pago antes de insertar.';
COMMENT ON COLUMN automation.workflow_runs.request_hash IS
'Hash de la solicitud completa usada para validar la reutilizacion de una clave de idempotencia.';
COMMENT ON COLUMN automation.workflow_step_attempts.request_snapshot IS
'Snapshot tecnico redactado; nunca guardar tokens, contrasenas, secretos, PAN/CVV ni credenciales de proveedores.';
COMMENT ON COLUMN automation.workflow_step_attempts.response_snapshot IS
'Respuesta tecnica redactada; nunca guardar secretos ni datos sensibles innecesarios.';
COMMENT ON TABLE automation.execution_queue IS
'Cola persistente para workers. Los workers deben reclamar tareas con SELECT FOR UPDATE SKIP LOCKED y leases con vencimiento.';
COMMENT ON TABLE automation.event_outbox IS
'Eventos pendientes para publicacion confiable. El publicador debe implementar reintentos y deduplicacion en consumidores.';
COMMENT ON TABLE automation.processed_events IS
'Inbox idempotente: una misma combinacion tenant/consumer/event_id se procesa una sola vez.';
COMMENT ON FUNCTION automation.publish_workflow_version(uuid, uuid, uuid, uuid) IS
'Valida estructura basica y allowlist antes de publicar una version. La validacion semantica completa del grafo y las expresiones corresponde tambien al servicio Rust.';
COMMENT ON FUNCTION automation.start_workflow_run(uuid, uuid, uuid, varchar, jsonb, varchar, varchar, varchar, uuid, uuid, integer) IS
'Crea idempotentemente una ejecucion desde un workflow activo; encola sus pasos iniciales sin aristas entrantes.';

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 16: AUTOMATION
-- ============================================================================
