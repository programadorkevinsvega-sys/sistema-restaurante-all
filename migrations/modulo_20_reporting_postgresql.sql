-- ============================================================================
-- RESTAURANT-OS - POS SAAS MULTIEMPRESA / MULTISUCURSAL
-- MODULO 20: REPORTING (PLANTILLAS, EJECUCION, EXPORTACION Y DISTRIBUCION)
-- Ubicacion del crate: crates/modules/reporting
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD
--   * Definir catalogos, reportes guardados, plantillas y versiones.
--   * Gestionar parametros, secciones, permisos y solicitudes de informes.
--   * Ejecutar informes mediante workers, conservar ejecuciones y artefactos.
--   * Programar informes y registrar entregas a destinatarios autorizados.
--   * Mantener cuotas de exportacion, aprobaciones e idempotencia.
--
-- LIMITES DE PROPIEDAD
--   * Analytics es propietario de metricas, dimensiones, hechos, KPI y dashboards.
--     Reporting consume su API/contrato semantico; no consulta sus tablas privadas.
--   * Audit es propietario de la auditoria central. Reporting no crea un segundo
--     libro de auditoria: publica eventos report.generated, report.downloaded, etc.
--   * Integrations es propietario del transporte externo, conexiones, OAuth,
--     webhooks y credenciales. Reporting conserva intenciones/resultado de entrega,
--     pero nunca credenciales ni implementaciones de proveedores.
--   * Automation es propietario de workflows generales. Reporting mantiene sus
--     propias programaciones de informes y puede publicar eventos para Automation.
--   * Los datos originales de ventas, pagos, inventario, finanzas y personal siguen
--     perteneciendo a sus modulos fuente.
--   * Los binarios (PDF/XLSX/CSV) se almacenan en object storage. PostgreSQL guarda
--     solo metadata, ubicacion opaca y checksum; no almacena archivos en BYTEA.
--
-- DEPENDENCIAS Y ARQUITECTURA
--   * Unica FK externa: platform.tenants(id), referencia canonica del tenant.
--   * company_id, branch_id, actor_id, integration_connection_id y semantic_source
--     son referencias logicas UUID/codigos validados mediante contratos publicos.
--   * Las definiciones de consulta son declarativas JSON; nunca ejecutar SQL libre
--     recibido desde el frontend ni compilar plantillas con codigo arbitrario.
--   * Analytics entrega datasets/metricas por contrato versionado. Reporting aplica
--     presentacion, formato, paginacion y exportacion.
--   * adapters/local ejecuta dentro del monolito; adapters/grpc puede invocar el
--     mismo contrato cuando Analytics/Reporting se separen como microservicios.
--
-- SEGURIDAD
--   * Todas las tablas tenant-scoped tienen tenant_id, RLS y FORCE RLS.
--   * La app establece SET LOCAL app.tenant_id dentro de cada transaccion.
--   * El tenant se obtiene del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * Revalidar autorizacion en generacion y descarga (TOCTOU); no confiar en que
--     una solicitud autorizada anteriormente lo siga estando.
--   * URLs/objetos de almacenamiento deben ser privados y entregarse con URLs
--     firmadas de corta duracion. No usar rutas publicas predecibles.
--   * PII, valores de parametros sensibles y contenido de informes no deben quedar
--     en logs ni metadata. Aplicar redaccion y minimizacion en Rust.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql y modulo_2_identity_usuarios_seguridad_postgresql.sql.
--   * Reporting se registra como modulo comercial en Platform; Analytics se consume
--     por contrato, sin FK ni lectura directa de sus tablas.
--   * Ejecutar una sola vez despues de sus dependencias en una base limpia.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS reporting;

COMMENT ON SCHEMA reporting IS
'Plantillas, definiciones, solicitudes, ejecuciones, artefactos y distribucion de informes. Analytics conserva los modelos y KPI; Audit conserva el libro central de auditoria.';

-- ---------------------------------------------------------------------------
-- 0. Funciones comunes
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reporting.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION reporting.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Reporting';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'reporting.%.% es append-only; registre una nueva version o un nuevo evento',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.jsonb_sha256(p_value jsonb)
RETURNS char(64)
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT encode(public.digest(convert_to(p_value::text, 'UTF8'), 'sha256'), 'hex')::char(64);
$$;

CREATE OR REPLACE FUNCTION reporting.validate_template_version_checksum()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.definition_checksum IS DISTINCT FROM reporting.jsonb_sha256(NEW.template_definition) THEN
        RAISE EXCEPTION 'definition_checksum no coincide con template_definition';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.guard_template_version_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR NEW.template_id IS DISTINCT FROM OLD.template_id
       OR NEW.version_number IS DISTINCT FROM OLD.version_number THEN
        RAISE EXCEPTION 'No se permite cambiar la identidad de una version de plantilla';
    END IF;
    IF OLD.lifecycle_status IN ('published','retired') AND
       (NEW.template_definition IS DISTINCT FROM OLD.template_definition
        OR NEW.definition_checksum IS DISTINCT FROM OLD.definition_checksum
        OR NEW.published_at IS DISTINCT FROM OLD.published_at
        OR NEW.published_by_user_id IS DISTINCT FROM OLD.published_by_user_id
        OR NEW.created_by_user_id IS DISTINCT FROM OLD.created_by_user_id
        OR NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
        RAISE EXCEPTION 'El contenido de una version publicada es inmutable';
    END IF;
    IF OLD.lifecycle_status = 'retired' AND NEW.lifecycle_status <> 'retired' THEN
        RAISE EXCEPTION 'Una version retirada no puede reactivarse';
    END IF;
    IF OLD.lifecycle_status = 'draft' AND NEW.lifecycle_status = 'retired' THEN
        RAISE EXCEPTION 'Una version borrador debe publicarse antes de retirarse';
    END IF;
    IF OLD.lifecycle_status = 'draft' AND NEW.lifecycle_status = 'published' THEN
        NEW.published_at := COALESCE(NEW.published_at, now());
    END IF;
    IF OLD.lifecycle_status IN ('published','retired') AND NEW.lifecycle_status = 'draft' THEN
        RAISE EXCEPTION 'Una version publicada no puede volver a borrador';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.guard_artifact_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (to_jsonb(NEW) - 'artifact_status') IS DISTINCT FROM (to_jsonb(OLD) - 'artifact_status') THEN
        RAISE EXCEPTION 'La metadata del artefacto es inmutable; solo se permite cambiar artifact_status';
    END IF;
    IF OLD.artifact_status = 'deleted' AND NEW.artifact_status <> 'deleted' THEN
        RAISE EXCEPTION 'Un artefacto eliminado no puede reactivarse';
    END IF;
    IF OLD.artifact_status = 'expired' AND NEW.artifact_status = 'available' THEN
        RAISE EXCEPTION 'Un artefacto expirado no puede volver a estar disponible';
    END IF;
    IF NEW.artifact_status NOT IN ('available','expired','quarantined','deleted') THEN
        RAISE EXCEPTION 'Estado de artefacto no permitido';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion del tenant y catalogo de informes
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    is_enabled                      boolean NOT NULL DEFAULT true,
    reporting_timezone              varchar(64) NOT NULL DEFAULT 'America/Bogota',
    default_output_format           varchar(12) NOT NULL DEFAULT 'pdf',
    max_rows_per_run                integer NOT NULL DEFAULT 250000,
    max_daily_exports_per_actor     integer NOT NULL DEFAULT 100,
    max_daily_export_bytes          bigint NOT NULL DEFAULT 1073741824,
    artifact_retention_days         integer NOT NULL DEFAULT 90,
    schedule_max_runs_per_day       integer NOT NULL DEFAULT 100,
    require_approval_for_restricted boolean NOT NULL DEFAULT true,
    signed_download_ttl_seconds     integer NOT NULL DEFAULT 300,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reporting_timezone_not_blank CHECK (btrim(reporting_timezone) <> ''),
    CONSTRAINT reporting_default_format CHECK (default_output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_rows_positive CHECK (max_rows_per_run BETWEEN 1 AND 10000000),
    CONSTRAINT reporting_daily_exports_positive CHECK (max_daily_exports_per_actor BETWEEN 1 AND 1000000),
    CONSTRAINT reporting_daily_bytes_positive CHECK (max_daily_export_bytes BETWEEN 1024 AND 1099511627776),
    CONSTRAINT reporting_retention_positive CHECK (artifact_retention_days BETWEEN 1 AND 36500),
    CONSTRAINT reporting_schedule_limit_positive CHECK (schedule_max_runs_per_day BETWEEN 1 AND 100000),
    CONSTRAINT reporting_download_ttl_range CHECK (signed_download_ttl_seconds BETWEEN 30 AND 3600),
    CONSTRAINT reporting_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TABLE reporting.report_catalog (
    report_catalog_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_code                     varchar(100) NOT NULL,
    display_name                    varchar(180) NOT NULL,
    description                     text,
    category                        varchar(40) NOT NULL,
    semantic_source_code            varchar(120) NOT NULL,
    supported_output_formats        text[] NOT NULL DEFAULT ARRAY['pdf','xlsx','csv']::text[],
    minimum_classification          varchar(20) NOT NULL DEFAULT 'internal',
    is_system                       boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    metadata                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reporting_catalog_code UNIQUE (tenant_id, report_code),
    CONSTRAINT uq_reporting_catalog_tenant_id UNIQUE (tenant_id, report_catalog_id),
    CONSTRAINT reporting_catalog_code_not_blank CHECK (btrim(report_code) <> ''),
    CONSTRAINT reporting_catalog_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT reporting_catalog_category CHECK (category IN ('sales','inventory','purchasing','production','kitchen','payments','cash','customers','workforce','finance','billing','security','operations','custom')),
    CONSTRAINT reporting_catalog_source_not_blank CHECK (btrim(semantic_source_code) <> ''),
    CONSTRAINT reporting_catalog_formats_nonempty CHECK (cardinality(supported_output_formats) > 0),
    CONSTRAINT reporting_catalog_formats_valid CHECK (supported_output_formats <@ ARRAY['pdf','xlsx','csv','json','html']::text[]),
    CONSTRAINT reporting_catalog_classification CHECK (minimum_classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT reporting_catalog_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Plantillas y versiones inmutables
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_templates (
    template_id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    template_code                   varchar(100) NOT NULL,
    display_name                    varchar(180) NOT NULL,
    description                     text,
    template_type                   varchar(20) NOT NULL,
    is_system                       boolean NOT NULL DEFAULT false,
    is_active                       boolean NOT NULL DEFAULT true,
    created_by_user_id              uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reporting_template_code UNIQUE (tenant_id, template_code),
    CONSTRAINT uq_reporting_template_tenant_id UNIQUE (tenant_id, template_id),
    CONSTRAINT reporting_template_type CHECK (template_type IN ('pdf_layout','xlsx_layout','csv_mapping','html_layout','json_layout')),
    CONSTRAINT reporting_template_code_not_blank CHECK (btrim(template_code) <> ''),
    CONSTRAINT reporting_template_name_not_blank CHECK (btrim(display_name) <> '')
);

CREATE TABLE reporting.report_template_versions (
    template_version_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    template_id                     uuid NOT NULL,
    version_number                  integer NOT NULL,
    template_definition             jsonb NOT NULL,
    definition_checksum             char(64) NOT NULL,
    lifecycle_status                varchar(16) NOT NULL DEFAULT 'draft',
    published_at                    timestamptz,
    published_by_user_id            uuid,
    created_by_user_id              uuid,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_template_version_template FOREIGN KEY (tenant_id, template_id)
        REFERENCES reporting.report_templates(tenant_id, template_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_template_version UNIQUE (tenant_id, template_id, version_number),
    CONSTRAINT uq_reporting_template_version_id UNIQUE (tenant_id, template_id, template_version_id),
    CONSTRAINT reporting_template_version_positive CHECK (version_number > 0),
    CONSTRAINT reporting_template_definition_object CHECK (jsonb_typeof(template_definition) = 'object'),
    CONSTRAINT reporting_template_checksum CHECK (definition_checksum ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT reporting_template_lifecycle CHECK (lifecycle_status IN ('draft','published','retired')),
    CONSTRAINT reporting_template_publish_fields CHECK (
        (lifecycle_status = 'draft' AND published_at IS NULL) OR
        (lifecycle_status IN ('published','retired') AND published_at IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------------
-- 3. Definiciones de informes, parametros y secciones
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_definitions (
    report_definition_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_catalog_id                uuid,
    template_id                      uuid,
    template_version_id              uuid,
    report_code                      varchar(120) NOT NULL,
    display_name                     varchar(180) NOT NULL,
    description                      text,
    audience                         varchar(20) NOT NULL DEFAULT 'tenant',
    company_id                       uuid,
    branch_id                        uuid,
    default_output_format            varchar(12) NOT NULL DEFAULT 'pdf',
    allowed_output_formats            text[] NOT NULL DEFAULT ARRAY['pdf','xlsx','csv']::text[],
    classification                   varchar(20) NOT NULL DEFAULT 'internal',
    parameter_schema                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    filter_schema                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    definition_config                jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_system                        boolean NOT NULL DEFAULT false,
    requires_approval                boolean NOT NULL DEFAULT false,
    is_active                        boolean NOT NULL DEFAULT true,
    created_by_user_id               uuid,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    updated_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_definition_catalog FOREIGN KEY (tenant_id, report_catalog_id)
        REFERENCES reporting.report_catalog(tenant_id, report_catalog_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reporting_definition_template_version FOREIGN KEY (tenant_id, template_id, template_version_id)
        REFERENCES reporting.report_template_versions(tenant_id, template_id, template_version_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_definition_code UNIQUE (tenant_id, report_code),
    CONSTRAINT uq_reporting_definition_tenant_id UNIQUE (tenant_id, report_definition_id),
    CONSTRAINT reporting_definition_audience CHECK (audience IN ('tenant','company','branch','personal')),
    CONSTRAINT reporting_definition_scope CHECK (
        (audience = 'tenant' AND company_id IS NULL AND branch_id IS NULL) OR
        (audience = 'company' AND company_id IS NOT NULL AND branch_id IS NULL) OR
        (audience = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL) OR
        (audience = 'personal' AND company_id IS NULL AND branch_id IS NULL AND created_by_user_id IS NOT NULL)
    ),
    CONSTRAINT reporting_definition_default_format CHECK (default_output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_definition_formats_nonempty CHECK (cardinality(allowed_output_formats) > 0),
    CONSTRAINT reporting_definition_formats_valid CHECK (allowed_output_formats <@ ARRAY['pdf','xlsx','csv','json','html']::text[]),
    CONSTRAINT reporting_definition_default_in_allowed CHECK (default_output_format = ANY(allowed_output_formats)),
    CONSTRAINT reporting_definition_classification CHECK (classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT reporting_definition_json_objects CHECK (
        jsonb_typeof(parameter_schema) = 'object' AND jsonb_typeof(filter_schema) = 'object' AND jsonb_typeof(definition_config) = 'object'
    ),
    CONSTRAINT reporting_definition_template_pair CHECK ((template_id IS NULL) = (template_version_id IS NULL)),
    CONSTRAINT reporting_definition_code_not_blank CHECK (btrim(report_code) <> ''),
    CONSTRAINT reporting_definition_name_not_blank CHECK (btrim(display_name) <> '')
);

CREATE TABLE reporting.report_definition_parameters (
    parameter_id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id             uuid NOT NULL,
    parameter_code                   varchar(100) NOT NULL,
    display_name                     varchar(160) NOT NULL,
    data_type                        varchar(20) NOT NULL,
    is_required                      boolean NOT NULL DEFAULT false,
    default_value                    jsonb,
    validation_rules                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    display_order                    integer NOT NULL DEFAULT 0,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_parameter_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_parameter_code UNIQUE (tenant_id, report_definition_id, parameter_code),
    CONSTRAINT reporting_parameter_type CHECK (data_type IN ('string','integer','decimal','boolean','date','datetime','enum','uuid','array','object')),
    CONSTRAINT reporting_parameter_code_not_blank CHECK (btrim(parameter_code) <> ''),
    CONSTRAINT reporting_parameter_rules_object CHECK (jsonb_typeof(validation_rules) = 'object'),
    CONSTRAINT reporting_parameter_order_nonnegative CHECK (display_order >= 0)
);

CREATE TABLE reporting.report_definition_sections (
    section_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id             uuid NOT NULL,
    section_code                     varchar(100) NOT NULL,
    display_name                     varchar(180) NOT NULL,
    semantic_source_code             varchar(120) NOT NULL,
    section_type                     varchar(24) NOT NULL DEFAULT 'table',
    query_definition                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    presentation_config              jsonb NOT NULL DEFAULT '{}'::jsonb,
    display_order                    integer NOT NULL DEFAULT 0,
    is_required                      boolean NOT NULL DEFAULT true,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_section_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_section_code UNIQUE (tenant_id, report_definition_id, section_code),
    CONSTRAINT reporting_section_type CHECK (section_type IN ('table','summary','chart','text','kpi','appendix')),
    CONSTRAINT reporting_section_source_not_blank CHECK (btrim(semantic_source_code) <> ''),
    CONSTRAINT reporting_section_json_objects CHECK (jsonb_typeof(query_definition) = 'object' AND jsonb_typeof(presentation_config) = 'object'),
    CONSTRAINT reporting_section_order_nonnegative CHECK (display_order >= 0)
);

-- ---------------------------------------------------------------------------
-- 4. Politicas de acceso y concesiones
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_access_policies (
    access_policy_id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id             uuid NOT NULL,
    policy_code                      varchar(100) NOT NULL,
    display_name                     varchar(160) NOT NULL,
    principal_scope                  varchar(20) NOT NULL DEFAULT 'tenant',
    permitted_formats                text[] NOT NULL DEFAULT ARRAY['pdf','xlsx','csv']::text[],
    max_rows                          integer NOT NULL DEFAULT 100000,
    requires_approval                boolean NOT NULL DEFAULT false,
    allow_schedule                   boolean NOT NULL DEFAULT true,
    allow_download                   boolean NOT NULL DEFAULT true,
    is_active                        boolean NOT NULL DEFAULT true,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    updated_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_access_policy_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_access_policy_tenant_id UNIQUE (tenant_id, access_policy_id),
    CONSTRAINT uq_reporting_access_policy_code UNIQUE (tenant_id, report_definition_id, policy_code),
    CONSTRAINT reporting_access_principal_scope CHECK (principal_scope IN ('tenant','company','branch','personal')),
    CONSTRAINT reporting_access_formats_nonempty CHECK (cardinality(permitted_formats) > 0),
    CONSTRAINT reporting_access_formats_valid CHECK (permitted_formats <@ ARRAY['pdf','xlsx','csv','json','html']::text[]),
    CONSTRAINT reporting_access_max_rows CHECK (max_rows BETWEEN 1 AND 10000000)
);

CREATE TABLE reporting.report_access_grants (
    access_grant_id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    access_policy_id                 uuid NOT NULL,
    principal_type                   varchar(16) NOT NULL,
    principal_key                    varchar(160) NOT NULL,
    company_id                       uuid,
    branch_id                        uuid,
    granted_by_user_id               uuid,
    granted_at                       timestamptz NOT NULL DEFAULT now(),
    expires_at                       timestamptz,
    revoked_at                       timestamptz,
    metadata                         jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT fk_reporting_grant_policy FOREIGN KEY (tenant_id, access_policy_id)
        REFERENCES reporting.report_access_policies(tenant_id, access_policy_id) ON DELETE RESTRICT,
    CONSTRAINT reporting_grant_principal_type CHECK (principal_type IN ('user','role','service')),
    CONSTRAINT reporting_grant_principal_not_blank CHECK (btrim(principal_key) <> ''),
    CONSTRAINT reporting_grant_expiry CHECK (expires_at IS NULL OR expires_at > granted_at),
    CONSTRAINT reporting_grant_scope CHECK (branch_id IS NULL OR company_id IS NOT NULL),
    CONSTRAINT reporting_grant_revocation CHECK (revoked_at IS NULL OR revoked_at >= granted_at),
    CONSTRAINT reporting_grant_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

-- ---------------------------------------------------------------------------
-- 5. Programaciones y destinatarios
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_schedules (
    report_schedule_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id             uuid NOT NULL,
    schedule_code                    varchar(100) NOT NULL,
    display_name                     varchar(180) NOT NULL,
    cron_expression                  varchar(120) NOT NULL,
    timezone                         varchar(64) NOT NULL,
    start_at                         timestamptz NOT NULL,
    end_at                           timestamptz,
    next_run_at                      timestamptz,
    last_run_at                      timestamptz,
    output_format                    varchar(12) NOT NULL DEFAULT 'pdf',
    scope_filters                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    parameter_values                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    schedule_status                  varchar(16) NOT NULL DEFAULT 'active',
    misfire_policy                   varchar(16) NOT NULL DEFAULT 'skip',
    max_instances                    smallint NOT NULL DEFAULT 1,
    created_by_user_id               uuid,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    updated_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_schedule_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_schedule_code UNIQUE (tenant_id, schedule_code),
    CONSTRAINT uq_reporting_schedule_tenant_id UNIQUE (tenant_id, report_schedule_id),
    CONSTRAINT reporting_schedule_cron_not_blank CHECK (btrim(cron_expression) <> ''),
    CONSTRAINT reporting_schedule_timezone_not_blank CHECK (btrim(timezone) <> ''),
    CONSTRAINT reporting_schedule_date_range CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT reporting_schedule_format CHECK (output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_schedule_status CHECK (schedule_status IN ('active','paused','completed','cancelled','failed')),
    CONSTRAINT reporting_schedule_misfire CHECK (misfire_policy IN ('skip','run_once','catch_up_limited')),
    CONSTRAINT reporting_schedule_instances CHECK (max_instances BETWEEN 1 AND 20),
    CONSTRAINT reporting_schedule_next_run CHECK (schedule_status <> 'active' OR next_run_at IS NOT NULL),
    CONSTRAINT reporting_schedule_json_objects CHECK (jsonb_typeof(scope_filters) = 'object' AND jsonb_typeof(parameter_values) = 'object')
);

CREATE TABLE reporting.report_schedule_recipients (
    schedule_recipient_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_schedule_id               uuid NOT NULL,
    recipient_type                   varchar(20) NOT NULL,
    recipient_reference              varchar(180) NOT NULL,
    delivery_channel                 varchar(16) NOT NULL,
    integration_connection_id        uuid,
    is_active                        boolean NOT NULL DEFAULT true,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_schedule_recipient FOREIGN KEY (tenant_id, report_schedule_id)
        REFERENCES reporting.report_schedules(tenant_id, report_schedule_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_schedule_recipient UNIQUE (tenant_id, report_schedule_id, recipient_type, recipient_reference, delivery_channel),
    CONSTRAINT reporting_schedule_recipient_type CHECK (recipient_type IN ('user','role','external_reference')),
    CONSTRAINT reporting_schedule_recipient_not_blank CHECK (btrim(recipient_reference) <> ''),
    CONSTRAINT reporting_schedule_recipient_channel CHECK (delivery_channel IN ('in_app','email','webhook','portal'))
);

-- ---------------------------------------------------------------------------
-- 6. Solicitudes, ejecuciones y resultados
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_requests (
    report_request_id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id              uuid NOT NULL,
    report_schedule_id                uuid,
    requested_by_user_id              uuid,
    company_id                        uuid,
    branch_id                         uuid,
    request_origin                    varchar(16) NOT NULL DEFAULT 'manual',
    output_format                     varchar(12) NOT NULL,
    parameter_values                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    filter_values                     jsonb NOT NULL DEFAULT '{}'::jsonb,
    request_reason                    varchar(500),
    request_status                    varchar(16) NOT NULL DEFAULT 'queued',
    priority                          smallint NOT NULL DEFAULT 5,
    requested_at                      timestamptz NOT NULL DEFAULT now(),
    approved_at                       timestamptz,
    completed_at                      timestamptz,
    CONSTRAINT fk_reporting_request_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reporting_request_schedule FOREIGN KEY (tenant_id, report_schedule_id)
        REFERENCES reporting.report_schedules(tenant_id, report_schedule_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_request_tenant_id UNIQUE (tenant_id, report_request_id),
    CONSTRAINT reporting_request_origin CHECK (request_origin IN ('manual','schedule','automation','api','system')),
    CONSTRAINT reporting_request_format CHECK (output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_request_status CHECK (request_status IN ('queued','awaiting_approval','approved','running','succeeded','failed','cancelled','expired')),
    CONSTRAINT reporting_request_priority CHECK (priority BETWEEN 1 AND 10),
    CONSTRAINT reporting_request_scope CHECK (branch_id IS NULL OR company_id IS NOT NULL),
    CONSTRAINT reporting_request_json_objects CHECK (jsonb_typeof(parameter_values) = 'object' AND jsonb_typeof(filter_values) = 'object'),
    CONSTRAINT reporting_request_completion_time CHECK (completed_at IS NULL OR completed_at >= requested_at)
);

CREATE TABLE reporting.report_runs (
    report_run_id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_request_id                 uuid NOT NULL,
    run_number                        integer NOT NULL DEFAULT 1,
    run_status                        varchar(16) NOT NULL DEFAULT 'queued',
    worker_id                         varchar(160),
    lease_expires_at                  timestamptz,
    started_at                        timestamptz,
    completed_at                      timestamptz,
    rows_processed                    bigint NOT NULL DEFAULT 0,
    bytes_generated                   bigint NOT NULL DEFAULT 0,
    duration_ms                       bigint,
    source_watermarks                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    result_metadata                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_code                        varchar(100),
    error_message                     varchar(1200),
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_run_request FOREIGN KEY (tenant_id, report_request_id)
        REFERENCES reporting.report_requests(tenant_id, report_request_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_run_number UNIQUE (tenant_id, report_request_id, run_number),
    CONSTRAINT uq_reporting_run_tenant_id UNIQUE (tenant_id, report_run_id),
    CONSTRAINT reporting_run_number_positive CHECK (run_number > 0),
    CONSTRAINT reporting_run_status CHECK (run_status IN ('queued','running','succeeded','failed','cancelled','expired')),
    CONSTRAINT reporting_run_counts CHECK (rows_processed >= 0 AND bytes_generated >= 0 AND (duration_ms IS NULL OR duration_ms >= 0)),
    CONSTRAINT reporting_run_timestamps CHECK (
        (completed_at IS NULL OR started_at IS NOT NULL) AND
        (started_at IS NULL OR started_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT reporting_run_lease CHECK (lease_expires_at IS NULL OR run_status = 'running'),
    CONSTRAINT reporting_run_json_objects CHECK (jsonb_typeof(source_watermarks) = 'object' AND jsonb_typeof(result_metadata) = 'object')
);

CREATE TABLE reporting.report_run_parameters (
    run_parameter_id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_run_id                     uuid NOT NULL,
    parameter_code                    varchar(100) NOT NULL,
    parameter_value                   jsonb NOT NULL,
    is_sensitive                      boolean NOT NULL DEFAULT false,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_run_parameter_run FOREIGN KEY (tenant_id, report_run_id)
        REFERENCES reporting.report_runs(tenant_id, report_run_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_run_parameter UNIQUE (tenant_id, report_run_id, parameter_code),
    CONSTRAINT reporting_run_parameter_code_not_blank CHECK (btrim(parameter_code) <> '')
);

CREATE TABLE reporting.report_run_sections (
    run_section_id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_run_id                     uuid NOT NULL,
    section_code                      varchar(100) NOT NULL,
    section_status                    varchar(16) NOT NULL DEFAULT 'pending',
    rows_returned                     bigint NOT NULL DEFAULT 0,
    duration_ms                       bigint,
    source_watermark                  jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_code                        varchar(100),
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_run_section_run FOREIGN KEY (tenant_id, report_run_id)
        REFERENCES reporting.report_runs(tenant_id, report_run_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_run_section UNIQUE (tenant_id, report_run_id, section_code),
    CONSTRAINT reporting_run_section_status CHECK (section_status IN ('pending','running','succeeded','failed','skipped')),
    CONSTRAINT reporting_run_section_counts CHECK (rows_returned >= 0 AND (duration_ms IS NULL OR duration_ms >= 0)),
    CONSTRAINT reporting_run_section_watermark_object CHECK (jsonb_typeof(source_watermark) = 'object')
);

-- ---------------------------------------------------------------------------
-- 7. Artefactos y entregas
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_artifacts (
    report_artifact_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_run_id                     uuid NOT NULL,
    artifact_type                     varchar(20) NOT NULL DEFAULT 'primary',
    output_format                     varchar(12) NOT NULL,
    storage_provider                  varchar(40) NOT NULL,
    storage_object_key                text NOT NULL,
    file_name                         varchar(255) NOT NULL,
    content_type                      varchar(160) NOT NULL,
    file_size_bytes                   bigint NOT NULL,
    checksum_sha256                   char(64) NOT NULL,
    page_count                        integer,
    row_count                         bigint,
    classification                    varchar(20) NOT NULL DEFAULT 'internal',
    artifact_status                   varchar(16) NOT NULL DEFAULT 'available',
    expires_at                        timestamptz,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_artifact_run FOREIGN KEY (tenant_id, report_run_id)
        REFERENCES reporting.report_runs(tenant_id, report_run_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_artifact_tenant_id UNIQUE (tenant_id, report_artifact_id),
    CONSTRAINT uq_reporting_artifact_run_pair UNIQUE (tenant_id, report_run_id, report_artifact_id),
    CONSTRAINT reporting_artifact_type CHECK (artifact_type IN ('primary','appendix','preview','source_data')),
    CONSTRAINT reporting_artifact_format CHECK (output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_artifact_provider_not_blank CHECK (btrim(storage_provider) <> ''),
    CONSTRAINT reporting_artifact_key_not_blank CHECK (btrim(storage_object_key) <> ''),
    CONSTRAINT reporting_artifact_file_name_not_blank CHECK (btrim(file_name) <> ''),
    CONSTRAINT reporting_artifact_size CHECK (file_size_bytes >= 0),
    CONSTRAINT reporting_artifact_checksum CHECK (checksum_sha256 ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT reporting_artifact_page_count CHECK (page_count IS NULL OR page_count >= 0),
    CONSTRAINT reporting_artifact_row_count CHECK (row_count IS NULL OR row_count >= 0),
    CONSTRAINT reporting_artifact_classification CHECK (classification IN ('public','internal','confidential','restricted')),
    CONSTRAINT reporting_artifact_status CHECK (artifact_status IN ('available','expired','quarantined','deleted')),
    CONSTRAINT reporting_artifact_expiry CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE TABLE reporting.report_deliveries (
    report_delivery_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_run_id                     uuid NOT NULL,
    report_artifact_id                uuid,
    delivery_channel                  varchar(16) NOT NULL,
    recipient_type                    varchar(20) NOT NULL,
    recipient_reference              varchar(180) NOT NULL,
    integration_connection_id        uuid,
    delivery_status                   varchar(16) NOT NULL DEFAULT 'pending',
    scheduled_at                      timestamptz,
    delivered_at                      timestamptz,
    last_attempt_at                   timestamptz,
    provider_message_reference         varchar(180),
    failure_code                      varchar(100),
    created_at                        timestamptz NOT NULL DEFAULT now(),
    updated_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_delivery_run FOREIGN KEY (tenant_id, report_run_id)
        REFERENCES reporting.report_runs(tenant_id, report_run_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reporting_delivery_artifact FOREIGN KEY (tenant_id, report_run_id, report_artifact_id)
        REFERENCES reporting.report_artifacts(tenant_id, report_run_id, report_artifact_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_delivery_tenant_id UNIQUE (tenant_id, report_delivery_id),
    CONSTRAINT reporting_delivery_channel CHECK (delivery_channel IN ('in_app','email','webhook','portal')),
    CONSTRAINT reporting_delivery_recipient_type CHECK (recipient_type IN ('user','role','external_reference')),
    CONSTRAINT reporting_delivery_recipient_not_blank CHECK (btrim(recipient_reference) <> ''),
    CONSTRAINT reporting_delivery_status CHECK (delivery_status IN ('pending','queued','sending','delivered','failed','cancelled')),
    CONSTRAINT reporting_delivery_delivered_time CHECK (delivered_at IS NULL OR delivered_at >= created_at)
);

CREATE TABLE reporting.report_delivery_attempts (
    delivery_attempt_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_delivery_id                uuid NOT NULL,
    attempt_number                    integer NOT NULL,
    attempted_at                      timestamptz NOT NULL DEFAULT now(),
    outcome                           varchar(16) NOT NULL,
    provider_message_reference         varchar(180),
    provider_status_code              varchar(80),
    duration_ms                       integer,
    error_code                        varchar(100),
    error_message_redacted             varchar(1000),
    response_metadata                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT fk_reporting_delivery_attempt FOREIGN KEY (tenant_id, report_delivery_id)
        REFERENCES reporting.report_deliveries(tenant_id, report_delivery_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_delivery_attempt_number UNIQUE (tenant_id, report_delivery_id, attempt_number),
    CONSTRAINT reporting_delivery_attempt_positive CHECK (attempt_number > 0),
    CONSTRAINT reporting_delivery_attempt_outcome CHECK (outcome IN ('accepted','delivered','transient_failure','permanent_failure','rejected')),
    CONSTRAINT reporting_delivery_attempt_duration CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT reporting_delivery_attempt_metadata_object CHECK (jsonb_typeof(response_metadata) = 'object')
);

-- ---------------------------------------------------------------------------
-- 8. Aprobaciones, favoritos y cuotas
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.report_approval_requests (
    report_approval_request_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_request_id                 uuid NOT NULL,
    approval_status                  varchar(16) NOT NULL DEFAULT 'pending',
    requested_by_user_id              uuid,
    approval_reason                   varchar(500) NOT NULL,
    decided_at                        timestamptz,
    expires_at                        timestamptz,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_approval_request FOREIGN KEY (tenant_id, report_request_id)
        REFERENCES reporting.report_requests(tenant_id, report_request_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_approval_request UNIQUE (tenant_id, report_request_id),
    CONSTRAINT uq_reporting_approval_tenant_id UNIQUE (tenant_id, report_approval_request_id),
    CONSTRAINT reporting_approval_status CHECK (approval_status IN ('pending','approved','rejected','expired','cancelled')),
    CONSTRAINT reporting_approval_reason_not_blank CHECK (btrim(approval_reason) <> ''),
    CONSTRAINT reporting_approval_expiry CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE TABLE reporting.report_approval_decisions (
    report_approval_decision_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_approval_request_id        uuid NOT NULL,
    decision                          varchar(12) NOT NULL,
    decided_by_user_id                uuid NOT NULL,
    decision_reason                   varchar(1000),
    decided_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_approval_decision_request FOREIGN KEY (tenant_id, report_approval_request_id)
        REFERENCES reporting.report_approval_requests(tenant_id, report_approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_approval_decision UNIQUE (tenant_id, report_approval_request_id),
    CONSTRAINT reporting_approval_decision_value CHECK (decision IN ('approved','rejected'))
);

CREATE TABLE reporting.report_favorites (
    report_favorite_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    report_definition_id              uuid NOT NULL,
    actor_user_id                     uuid NOT NULL,
    favorite_name                     varchar(160),
    saved_filters                     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    updated_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_reporting_favorite_definition FOREIGN KEY (tenant_id, report_definition_id)
        REFERENCES reporting.report_definitions(tenant_id, report_definition_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reporting_favorite_user UNIQUE (tenant_id, report_definition_id, actor_user_id),
    CONSTRAINT reporting_favorite_filters_object CHECK (jsonb_typeof(saved_filters) = 'object')
);

CREATE TABLE reporting.report_export_usage (
    report_export_usage_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    usage_date                        date NOT NULL,
    actor_key                         varchar(160) NOT NULL,
    output_format                     varchar(12) NOT NULL,
    export_count                      integer NOT NULL DEFAULT 0,
    bytes_generated                   bigint NOT NULL DEFAULT 0,
    rows_exported                     bigint NOT NULL DEFAULT 0,
    updated_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reporting_export_usage UNIQUE (tenant_id, usage_date, actor_key, output_format),
    CONSTRAINT reporting_export_actor_not_blank CHECK (btrim(actor_key) <> ''),
    CONSTRAINT reporting_export_format CHECK (output_format IN ('pdf','xlsx','csv','json','html')),
    CONSTRAINT reporting_export_counts CHECK (export_count >= 0 AND bytes_generated >= 0 AND rows_exported >= 0)
);

-- ---------------------------------------------------------------------------
-- 9. Ingesta, outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE reporting.event_inbox (
    event_inbox_id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module                     varchar(80) NOT NULL,
    event_id                          varchar(180) NOT NULL,
    event_type                        varchar(180) NOT NULL,
    event_version                     varchar(30) NOT NULL,
    occurred_at                       timestamptz NOT NULL,
    received_at                       timestamptz NOT NULL DEFAULT now(),
    available_at                      timestamptz NOT NULL DEFAULT now(),
    event_payload                     jsonb NOT NULL,
    payload_checksum                  char(64) NOT NULL,
    processing_status                 varchar(16) NOT NULL DEFAULT 'pending',
    attempt_count                     integer NOT NULL DEFAULT 0,
    locked_by                         varchar(160),
    locked_at                         timestamptz,
    processed_at                      timestamptz,
    last_error_code                   varchar(100),
    last_error_message                varchar(1000),
    CONSTRAINT uq_reporting_inbox_source_event UNIQUE (tenant_id, source_module, event_id),
    CONSTRAINT reporting_inbox_source_not_blank CHECK (btrim(source_module) <> ''),
    CONSTRAINT reporting_inbox_event_not_blank CHECK (btrim(event_id) <> '' AND btrim(event_type) <> ''),
    CONSTRAINT reporting_inbox_payload_object CHECK (jsonb_typeof(event_payload) = 'object'),
    CONSTRAINT reporting_inbox_checksum CHECK (payload_checksum ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT reporting_inbox_status CHECK (processing_status IN ('pending','processing','processed','failed','dead_letter')),
    CONSTRAINT reporting_inbox_attempts CHECK (attempt_count >= 0),
    CONSTRAINT reporting_inbox_lock_consistency CHECK ((locked_by IS NULL) = (locked_at IS NULL))
);

CREATE TABLE reporting.processed_events (
    processed_event_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module                     varchar(80) NOT NULL,
    event_id                          varchar(180) NOT NULL,
    event_type                        varchar(180) NOT NULL,
    projection_code                   varchar(100) NOT NULL,
    processed_at                      timestamptz NOT NULL DEFAULT now(),
    result_metadata                   jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_reporting_processed_event UNIQUE (tenant_id, source_module, event_id, projection_code),
    CONSTRAINT reporting_processed_metadata_object CHECK (jsonb_typeof(result_metadata) = 'object')
);

CREATE TABLE reporting.event_outbox (
    event_outbox_id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type                    varchar(100) NOT NULL,
    aggregate_id                      uuid NOT NULL,
    event_type                        varchar(180) NOT NULL,
    event_version                     varchar(30) NOT NULL DEFAULT 'v1',
    event_payload                     jsonb NOT NULL,
    occurred_at                       timestamptz NOT NULL DEFAULT now(),
    published_at                      timestamptz,
    publish_attempts                  integer NOT NULL DEFAULT 0,
    last_error_code                   varchar(100),
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reporting_outbox_aggregate_not_blank CHECK (btrim(aggregate_type) <> ''),
    CONSTRAINT reporting_outbox_event_not_blank CHECK (btrim(event_type) <> ''),
    CONSTRAINT reporting_outbox_payload_object CHECK (jsonb_typeof(event_payload) = 'object'),
    CONSTRAINT reporting_outbox_attempts CHECK (publish_attempts >= 0)
);

CREATE TABLE reporting.idempotency_records (
    idempotency_record_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    idempotency_key                   varchar(180) NOT NULL,
    operation_code                    varchar(100) NOT NULL,
    request_fingerprint               char(64) NOT NULL,
    resource_type                     varchar(80) NOT NULL,
    resource_id                       uuid NOT NULL,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    expires_at                        timestamptz NOT NULL,
    CONSTRAINT uq_reporting_idempotency_key UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT reporting_idempotency_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT reporting_idempotency_fingerprint CHECK (request_fingerprint ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT reporting_idempotency_expiry CHECK (expires_at > created_at)
);

-- ---------------------------------------------------------------------------
-- 10. Indices de ejecucion, agenda, acceso y entrega
-- ---------------------------------------------------------------------------

CREATE INDEX ix_reporting_catalog_category ON reporting.report_catalog (tenant_id, category, is_active);
CREATE INDEX ix_reporting_templates_active ON reporting.report_templates (tenant_id, is_active, template_code);
CREATE INDEX ix_reporting_template_versions ON reporting.report_template_versions (tenant_id, template_id, version_number DESC);
CREATE INDEX ix_reporting_definitions_scope ON reporting.report_definitions (tenant_id, audience, company_id, branch_id, is_active);
CREATE INDEX ix_reporting_parameters_definition ON reporting.report_definition_parameters (tenant_id, report_definition_id, display_order);
CREATE INDEX ix_reporting_sections_definition ON reporting.report_definition_sections (tenant_id, report_definition_id, display_order);
CREATE INDEX ix_reporting_access_policy_active ON reporting.report_access_policies (tenant_id, report_definition_id, is_active);
CREATE INDEX ix_reporting_access_grants_principal ON reporting.report_access_grants (tenant_id, principal_type, principal_key, expires_at) WHERE revoked_at IS NULL;
CREATE INDEX ix_reporting_schedules_due ON reporting.report_schedules (tenant_id, next_run_at) WHERE schedule_status = 'active';
CREATE INDEX ix_reporting_schedule_recipients ON reporting.report_schedule_recipients (tenant_id, report_schedule_id, is_active);
CREATE INDEX ix_reporting_requests_queue ON reporting.report_requests (tenant_id, priority, requested_at) WHERE request_status IN ('queued','approved');
CREATE INDEX ix_reporting_requests_actor ON reporting.report_requests (tenant_id, requested_by_user_id, requested_at DESC) WHERE requested_by_user_id IS NOT NULL;
CREATE INDEX ix_reporting_runs_request ON reporting.report_runs (tenant_id, report_request_id, run_number DESC);
CREATE INDEX ix_reporting_runs_worker_lease ON reporting.report_runs (tenant_id, lease_expires_at) WHERE run_status = 'running';
CREATE INDEX ix_reporting_run_parameters ON reporting.report_run_parameters (tenant_id, report_run_id);
CREATE INDEX ix_reporting_run_sections ON reporting.report_run_sections (tenant_id, report_run_id, section_status);
CREATE INDEX ix_reporting_artifacts_run ON reporting.report_artifacts (tenant_id, report_run_id, created_at DESC);
CREATE INDEX ix_reporting_artifacts_expiry ON reporting.report_artifacts (tenant_id, expires_at) WHERE artifact_status = 'available';
CREATE INDEX ix_reporting_deliveries_pending ON reporting.report_deliveries (tenant_id, scheduled_at, created_at) WHERE delivery_status IN ('pending','queued','failed');
CREATE INDEX ix_reporting_delivery_attempts_recent ON reporting.report_delivery_attempts (tenant_id, report_delivery_id, attempted_at DESC);
CREATE INDEX ix_reporting_approval_pending ON reporting.report_approval_requests (tenant_id, created_at) WHERE approval_status = 'pending';
CREATE INDEX ix_reporting_favorites_actor ON reporting.report_favorites (tenant_id, actor_user_id);
CREATE INDEX ix_reporting_export_usage_date ON reporting.report_export_usage (tenant_id, usage_date DESC, actor_key);
CREATE INDEX ix_reporting_inbox_pending ON reporting.event_inbox (tenant_id, available_at, received_at) WHERE processing_status IN ('pending','failed');
CREATE INDEX ix_reporting_inbox_lease ON reporting.event_inbox (tenant_id, locked_at) WHERE processing_status = 'processing';
CREATE INDEX ix_reporting_processed_recent ON reporting.processed_events (tenant_id, processed_at DESC);
CREATE INDEX ix_reporting_outbox_pending ON reporting.event_outbox (tenant_id, created_at) WHERE published_at IS NULL;
CREATE INDEX ix_reporting_idempotency_expiry ON reporting.idempotency_records (tenant_id, expires_at);

-- ---------------------------------------------------------------------------
-- 11. Triggers de actualizacion, tenant inmutable y append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','report_catalog','report_templates','report_definitions',
        'report_access_policies','report_schedules','report_deliveries',
        'report_favorites','report_export_usage'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON reporting.%I FOR EACH ROW EXECUTE FUNCTION reporting.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','report_catalog','report_templates','report_template_versions',
        'report_definitions','report_definition_parameters','report_definition_sections',
        'report_access_policies','report_access_grants','report_schedules',
        'report_schedule_recipients','report_requests','report_runs','report_run_parameters',
        'report_run_sections','report_artifacts','report_deliveries','report_delivery_attempts',
        'report_approval_requests','report_approval_decisions','report_favorites',
        'report_export_usage','event_inbox','processed_events','event_outbox','idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON reporting.%I FOR EACH ROW EXECUTE FUNCTION reporting.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_reporting_template_version_guard
BEFORE UPDATE ON reporting.report_template_versions
FOR EACH ROW EXECUTE FUNCTION reporting.guard_template_version_update();
CREATE TRIGGER trg_reporting_template_version_checksum
BEFORE INSERT OR UPDATE ON reporting.report_template_versions
FOR EACH ROW EXECUTE FUNCTION reporting.validate_template_version_checksum();
CREATE TRIGGER trg_reporting_template_version_no_delete
BEFORE DELETE ON reporting.report_template_versions
FOR EACH ROW EXECUTE FUNCTION reporting.prevent_append_only_mutation();

CREATE TRIGGER trg_reporting_artifact_guard
BEFORE UPDATE ON reporting.report_artifacts
FOR EACH ROW EXECUTE FUNCTION reporting.guard_artifact_update();
CREATE TRIGGER trg_reporting_artifact_no_delete
BEFORE DELETE ON reporting.report_artifacts
FOR EACH ROW EXECUTE FUNCTION reporting.prevent_append_only_mutation();

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'report_run_parameters','report_delivery_attempts',
        'report_approval_decisions','processed_events'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON reporting.%I FOR EACH ROW EXECUTE FUNCTION reporting.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Inicializacion por tenant y catalogo base
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reporting.initialize_tenant_reporting(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO reporting.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO reporting.report_catalog (
        tenant_id, report_code, display_name, description, category,
        semantic_source_code, supported_output_formats, minimum_classification,
        is_system, is_active
    ) VALUES
    (p_tenant_id, 'sales_summary', 'Resumen de ventas', 'Ventas e indicadores comerciales por periodo, empresa y sucursal.', 'sales', 'sales_summary_v1', ARRAY['pdf','xlsx','csv']::text[], 'confidential', true, true),
    (p_tenant_id, 'branch_performance', 'Rendimiento de sucursales', 'Comparacion de indicadores operativos y comerciales por sucursal.', 'operations', 'branch_performance_v1', ARRAY['pdf','xlsx']::text[], 'confidential', true, true),
    (p_tenant_id, 'inventory_status', 'Estado de inventario', 'Existencias, movimientos y alertas de inventario.', 'inventory', 'inventory_status_v1', ARRAY['pdf','xlsx','csv']::text[], 'confidential', true, true),
    (p_tenant_id, 'purchasing_summary', 'Resumen de compras', 'Solicitudes, ordenes y recepciones de compra.', 'purchasing', 'purchasing_summary_v1', ARRAY['pdf','xlsx','csv']::text[], 'confidential', true, true),
    (p_tenant_id, 'production_summary', 'Resumen de produccion', 'Produccion, rendimiento, consumo y mermas.', 'production', 'production_summary_v1', ARRAY['pdf','xlsx']::text[], 'confidential', true, true),
    (p_tenant_id, 'kitchen_performance', 'Rendimiento de cocina', 'Tiempos de preparacion, comandas y cumplimiento.', 'kitchen', 'kitchen_performance_v1', ARRAY['pdf','xlsx']::text[], 'internal', true, true),
    (p_tenant_id, 'finance_statement', 'Estado financiero', 'Informe financiero publicado mediante el contrato semantico de Finance/Analytics.', 'finance', 'finance_statement_v1', ARRAY['pdf','xlsx']::text[], 'restricted', true, true),
    (p_tenant_id, 'workforce_attendance', 'Asistencia del personal', 'Asistencia, turnos y horas trabajadas.', 'workforce', 'workforce_attendance_v1', ARRAY['pdf','xlsx','csv']::text[], 'confidential', true, true),
    (p_tenant_id, 'customer_activity', 'Actividad de clientes', 'Actividad y fidelizacion de clientes, con datos minimizados.', 'customers', 'customer_activity_v1', ARRAY['pdf','xlsx']::text[], 'confidential', true, true),
    (p_tenant_id, 'billing_documents', 'Documentos de facturacion', 'Documentos emitidos, estados y totales tributarios.', 'billing', 'billing_documents_v1', ARRAY['pdf','xlsx','csv']::text[], 'restricted', true, true)
    ON CONFLICT (tenant_id, report_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Creacion idempotente de solicitudes de informe
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reporting.create_report_request(
    p_tenant_id uuid,
    p_report_definition_id uuid,
    p_company_id uuid,
    p_branch_id uuid,
    p_requested_by_user_id uuid,
    p_output_format varchar,
    p_parameter_values jsonb,
    p_filter_values jsonb,
    p_idempotency_key varchar,
    p_request_reason varchar DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_definition reporting.report_definitions%ROWTYPE;
    v_request_id uuid := gen_random_uuid();
    v_fingerprint char(64);
    v_existing reporting.idempotency_records%ROWTYPE;
    v_catalog_formats text[];
    v_requires_approval boolean := false;
    v_reporting_enabled boolean;
    v_require_restricted_approval boolean;
    v_request_status varchar(16);
    v_inserted integer;
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'Se requiere una clave de idempotencia';
    END IF;
    IF p_requested_by_user_id IS NULL THEN
        RAISE EXCEPTION 'Se requiere el usuario solicitante';
    END IF;
    IF p_parameter_values IS NULL OR jsonb_typeof(p_parameter_values) <> 'object'
       OR p_filter_values IS NULL OR jsonb_typeof(p_filter_values) <> 'object' THEN
        RAISE EXCEPTION 'Parametros y filtros deben ser objetos JSON';
    END IF;

    SELECT is_enabled, require_approval_for_restricted
      INTO v_reporting_enabled, v_require_restricted_approval
    FROM reporting.tenant_settings
    WHERE tenant_id = p_tenant_id;
    IF NOT FOUND OR NOT v_reporting_enabled THEN
        RAISE EXCEPTION 'Reporting no esta habilitado o no ha sido inicializado para el tenant';
    END IF;

    SELECT * INTO v_definition
    FROM reporting.report_definitions
    WHERE tenant_id = p_tenant_id
      AND report_definition_id = p_report_definition_id
      AND is_active = true
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Definicion de informe inexistente o inactiva';
    END IF;
    IF p_output_format IS NULL OR NOT (p_output_format = ANY(v_definition.allowed_output_formats)) THEN
        RAISE EXCEPTION 'Formato % no permitido para el informe', p_output_format;
    END IF;
    IF v_definition.report_catalog_id IS NOT NULL THEN
        SELECT supported_output_formats INTO v_catalog_formats
        FROM reporting.report_catalog
        WHERE tenant_id = p_tenant_id AND report_catalog_id = v_definition.report_catalog_id AND is_active = true;
        IF v_catalog_formats IS NULL OR NOT (p_output_format = ANY(v_catalog_formats)) THEN
            RAISE EXCEPTION 'Formato % no permitido por el catalogo del informe', p_output_format;
        END IF;
    END IF;
    IF v_definition.audience = 'company'
       AND (p_company_id IS DISTINCT FROM v_definition.company_id) THEN
        RAISE EXCEPTION 'El informe requiere el alcance de company definido en el reporte';
    ELSIF v_definition.audience = 'branch' AND (p_company_id IS NULL OR p_branch_id IS NULL OR p_company_id IS DISTINCT FROM v_definition.company_id OR p_branch_id IS DISTINCT FROM v_definition.branch_id) THEN
        RAISE EXCEPTION 'El informe requiere el alcance de branch definido en el reporte';
    ELSIF v_definition.audience = 'personal'
          AND v_definition.created_by_user_id IS DISTINCT FROM p_requested_by_user_id THEN
        RAISE EXCEPTION 'El informe personal solo puede ser solicitado por su propietario';
    END IF;

    SELECT (v_definition.requires_approval
            OR (v_definition.classification = 'restricted' AND v_require_restricted_approval)
            OR EXISTS (
                SELECT 1 FROM reporting.report_access_policies ap
                WHERE ap.tenant_id = p_tenant_id
                  AND ap.report_definition_id = p_report_definition_id
                  AND ap.is_active = true
                  AND ap.requires_approval = true
            ))
      INTO v_requires_approval;
    v_request_status := CASE WHEN v_requires_approval THEN 'awaiting_approval' ELSE 'queued' END;

    v_fingerprint := reporting.jsonb_sha256(jsonb_build_object(
        'report_definition_id', p_report_definition_id,
        'company_id', p_company_id,
        'branch_id', p_branch_id,
        'requested_by_user_id', p_requested_by_user_id,
        'output_format', p_output_format,
        'parameter_values', p_parameter_values,
        'filter_values', p_filter_values,
        'request_reason', p_request_reason
    ));

    INSERT INTO reporting.idempotency_records (
        tenant_id, idempotency_key, operation_code, request_fingerprint,
        resource_type, resource_id, expires_at
    ) VALUES (
        p_tenant_id, p_idempotency_key, 'create_report_request', v_fingerprint,
        'report_request', v_request_id, now() + interval '7 days'
    )
    ON CONFLICT (tenant_id, idempotency_key) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    IF v_inserted = 0 THEN
        SELECT * INTO v_existing
        FROM reporting.idempotency_records
        WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key
        FOR UPDATE;
        IF v_existing.expires_at > now() THEN
            IF v_existing.request_fingerprint IS DISTINCT FROM v_fingerprint THEN
                RAISE EXCEPTION 'La clave de idempotencia ya fue usada con parametros diferentes';
            END IF;
            RETURN v_existing.resource_id;
        END IF;
        UPDATE reporting.idempotency_records
           SET operation_code = 'create_report_request',
               request_fingerprint = v_fingerprint,
               resource_type = 'report_request',
               resource_id = v_request_id,
               created_at = now(),
               expires_at = now() + interval '7 days'
         WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key;
    END IF;

    INSERT INTO reporting.report_requests (
        report_request_id, tenant_id, report_definition_id, requested_by_user_id,
        company_id, branch_id, request_origin, output_format,
        parameter_values, filter_values, request_reason, request_status
    ) VALUES (
        v_request_id, p_tenant_id, p_report_definition_id, p_requested_by_user_id,
        p_company_id, p_branch_id, 'manual', p_output_format,
        p_parameter_values, p_filter_values, p_request_reason, v_request_status
    );

    IF v_requires_approval THEN
        INSERT INTO reporting.report_approval_requests (
            tenant_id, report_request_id, approval_status, requested_by_user_id, approval_reason
        ) VALUES (
            p_tenant_id, v_request_id, 'pending', p_requested_by_user_id,
            COALESCE(NULLIF(btrim(p_request_reason), ''), 'El informe requiere aprobacion por su nivel de clasificacion o politica de acceso')
        );
    END IF;

    INSERT INTO reporting.event_outbox (
        tenant_id, aggregate_type, aggregate_id, event_type, event_version, event_payload
    ) VALUES (
        p_tenant_id, 'report_request', v_request_id,
        CASE WHEN v_requires_approval THEN 'reporting.report_approval_requested' ELSE 'reporting.report_requested' END, 'v1',
        jsonb_build_object('report_request_id', v_request_id, 'report_definition_id', p_report_definition_id,
                           'company_id', p_company_id, 'branch_id', p_branch_id,
                           'output_format', p_output_format, 'approval_required', v_requires_approval,
                           'requested_at', now())
    );

    RETURN v_request_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. Inicio y finalizacion de ejecuciones por workers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reporting.start_report_run(
    p_tenant_id uuid,
    p_report_request_id uuid,
    p_worker_id varchar,
    p_lease_seconds integer DEFAULT 300
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request reporting.report_requests%ROWTYPE;
    v_expired_run_id uuid;
    v_run_number integer;
    v_run_id uuid := gen_random_uuid();
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;
    IF p_worker_id IS NULL OR btrim(p_worker_id) = '' THEN
        RAISE EXCEPTION 'worker_id es obligatorio';
    END IF;
    IF p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 30 AND 3600 THEN
        RAISE EXCEPTION 'lease_seconds debe estar entre 30 y 3600';
    END IF;

    SELECT * INTO v_request
    FROM reporting.report_requests
    WHERE tenant_id = p_tenant_id AND report_request_id = p_report_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud de informe no encontrada';
    END IF;
    IF v_request.request_status = 'running' THEN
        SELECT report_run_id INTO v_expired_run_id
        FROM reporting.report_runs
        WHERE tenant_id = p_tenant_id
          AND report_request_id = p_report_request_id
          AND run_status = 'running'
          AND lease_expires_at <= now()
        ORDER BY run_number DESC
        LIMIT 1
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La solicitud ya tiene una ejecucion activa';
        END IF;

        UPDATE reporting.report_runs
           SET run_status = 'expired',
               completed_at = now(),
               lease_expires_at = NULL
         WHERE tenant_id = p_tenant_id AND report_run_id = v_expired_run_id;
        UPDATE reporting.report_requests
           SET request_status = 'failed',
               completed_at = now()
         WHERE tenant_id = p_tenant_id AND report_request_id = p_report_request_id;

        INSERT INTO reporting.event_outbox (
            tenant_id, aggregate_type, aggregate_id, event_type, event_version, event_payload
        ) VALUES (
            p_tenant_id, 'report_run', v_expired_run_id,
            'reporting.report_run_lease_expired', 'v1',
            jsonb_build_object('report_run_id', v_expired_run_id,
                               'report_request_id', p_report_request_id,
                               'expired_at', now())
        );
        v_request.request_status := 'failed';
    END IF;
    IF v_request.request_status NOT IN ('queued','approved','failed') THEN
        RAISE EXCEPTION 'La solicitud no esta disponible para ejecucion (estado: %)', v_request.request_status;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM reporting.report_runs
        WHERE tenant_id = p_tenant_id
          AND report_request_id = p_report_request_id
          AND run_status = 'running'
          AND (lease_expires_at IS NULL OR lease_expires_at > now())
    ) THEN
        RAISE EXCEPTION 'La solicitud ya tiene una ejecucion activa';
    END IF;

    SELECT COALESCE(MAX(run_number), 0) + 1 INTO v_run_number
    FROM reporting.report_runs
    WHERE tenant_id = p_tenant_id AND report_request_id = p_report_request_id;

    INSERT INTO reporting.report_runs (
        report_run_id, tenant_id, report_request_id, run_number,
        run_status, worker_id, lease_expires_at, started_at
    ) VALUES (
        v_run_id, p_tenant_id, p_report_request_id, v_run_number,
        'running', p_worker_id, now() + make_interval(secs => p_lease_seconds), now()
    );

    UPDATE reporting.report_requests
       SET request_status = 'running',
           completed_at = NULL
     WHERE tenant_id = p_tenant_id AND report_request_id = p_report_request_id;

    RETURN v_run_id;
END;
$$;

CREATE OR REPLACE FUNCTION reporting.finish_report_run(
    p_tenant_id uuid,
    p_report_run_id uuid,
    p_final_status varchar,
    p_rows_processed bigint DEFAULT 0,
    p_bytes_generated bigint DEFAULT 0,
    p_duration_ms bigint DEFAULT NULL,
    p_result_metadata jsonb DEFAULT '{}'::jsonb,
    p_error_code varchar DEFAULT NULL,
    p_error_message varchar DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request_id uuid;
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;
    IF p_final_status IS NULL OR p_final_status NOT IN ('succeeded','failed','cancelled','expired') THEN
        RAISE EXCEPTION 'Estado final no permitido';
    END IF;
    IF p_rows_processed IS NULL OR p_bytes_generated IS NULL
       OR p_rows_processed < 0 OR p_bytes_generated < 0
       OR (p_duration_ms IS NOT NULL AND p_duration_ms < 0) THEN
        RAISE EXCEPTION 'Las cantidades no pueden ser negativas';
    END IF;
    IF p_result_metadata IS NULL OR jsonb_typeof(p_result_metadata) <> 'object' THEN
        RAISE EXCEPTION 'result_metadata debe ser un objeto JSON';
    END IF;

    UPDATE reporting.report_runs
       SET run_status = p_final_status,
           completed_at = now(),
           rows_processed = p_rows_processed,
           bytes_generated = p_bytes_generated,
           duration_ms = p_duration_ms,
           result_metadata = p_result_metadata,
           error_code = p_error_code,
           error_message = p_error_message,
           lease_expires_at = NULL
     WHERE tenant_id = p_tenant_id
       AND report_run_id = p_report_run_id
       AND run_status = 'running'
       AND lease_expires_at > now()
    RETURNING report_request_id INTO v_request_id;

    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'Ejecucion no encontrada o no esta en estado running';
    END IF;

    UPDATE reporting.report_requests
       SET request_status = CASE WHEN p_final_status = 'succeeded' THEN 'succeeded'
                                 WHEN p_final_status = 'cancelled' THEN 'cancelled'
                                 ELSE 'failed' END,
           completed_at = now()
     WHERE tenant_id = p_tenant_id AND report_request_id = v_request_id;

    INSERT INTO reporting.event_outbox (
        tenant_id, aggregate_type, aggregate_id, event_type, event_version, event_payload
    ) VALUES (
        p_tenant_id, 'report_run', p_report_run_id,
        CASE WHEN p_final_status = 'succeeded' THEN 'reporting.report_generated' ELSE 'reporting.report_run_finished' END,
        'v1',
        jsonb_build_object('report_run_id', p_report_run_id, 'report_request_id', v_request_id,
                           'status', p_final_status, 'rows_processed', p_rows_processed,
                           'bytes_generated', p_bytes_generated, 'finished_at', now())
    );
END;
$$;

CREATE OR REPLACE FUNCTION reporting.decide_report_approval(
    p_tenant_id uuid,
    p_report_approval_request_id uuid,
    p_decision varchar,
    p_decided_by_user_id uuid,
    p_decision_reason varchar DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_approval reporting.report_approval_requests%ROWTYPE;
    v_request reporting.report_requests%ROWTYPE;
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;
    IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected') THEN
        RAISE EXCEPTION 'Decision debe ser approved o rejected';
    END IF;
    IF p_decided_by_user_id IS NULL THEN
        RAISE EXCEPTION 'Se requiere el usuario que decide';
    END IF;

    SELECT * INTO v_approval
    FROM reporting.report_approval_requests
    WHERE tenant_id = p_tenant_id
      AND report_approval_request_id = p_report_approval_request_id
    FOR UPDATE;
    IF NOT FOUND OR v_approval.approval_status <> 'pending' THEN
        RAISE EXCEPTION 'Solicitud de aprobacion inexistente o ya resuelta';
    END IF;
    IF v_approval.expires_at IS NOT NULL AND v_approval.expires_at <= now() THEN
        RAISE EXCEPTION 'La solicitud de aprobacion ha expirado';
    END IF;

    SELECT * INTO v_request
    FROM reporting.report_requests
    WHERE tenant_id = p_tenant_id AND report_request_id = v_approval.report_request_id
    FOR UPDATE;

    IF v_request.requested_by_user_id = p_decided_by_user_id THEN
        RAISE EXCEPTION 'El solicitante no puede aprobar su propia solicitud';
    END IF;

    INSERT INTO reporting.report_approval_decisions (
        tenant_id, report_approval_request_id, decision, decided_by_user_id, decision_reason
    ) VALUES (
        p_tenant_id, p_report_approval_request_id, p_decision, p_decided_by_user_id, p_decision_reason
    );

    UPDATE reporting.report_approval_requests
       SET approval_status = p_decision,
           decided_at = now()
     WHERE tenant_id = p_tenant_id
       AND report_approval_request_id = p_report_approval_request_id;

    UPDATE reporting.report_requests
       SET request_status = CASE WHEN p_decision = 'approved' THEN 'approved' ELSE 'cancelled' END,
           approved_at = CASE WHEN p_decision = 'approved' THEN now() ELSE approved_at END,
           completed_at = CASE WHEN p_decision = 'rejected' THEN now() ELSE completed_at END
     WHERE tenant_id = p_tenant_id AND report_request_id = v_approval.report_request_id;

    INSERT INTO reporting.event_outbox (
        tenant_id, aggregate_type, aggregate_id, event_type, event_version, event_payload
    ) VALUES (
        p_tenant_id, 'report_request', v_approval.report_request_id,
        CASE WHEN p_decision = 'approved' THEN 'reporting.report_approved' ELSE 'reporting.report_rejected' END,
        'v1', jsonb_build_object('report_request_id', v_approval.report_request_id,
                                 'approval_request_id', p_report_approval_request_id,
                                 'decision', p_decision, 'decided_by_user_id', p_decided_by_user_id,
                                 'decided_at', now())
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 15. Reserva atomica de cuota diaria de exportacion
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reporting.reserve_export_quota(
    p_tenant_id uuid,
    p_actor_key varchar,
    p_output_format varchar,
    p_estimated_bytes bigint DEFAULT 0,
    p_estimated_rows bigint DEFAULT 0
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_settings reporting.tenant_settings%ROWTYPE;
    v_usage_date date;
    v_count integer;
    v_bytes bigint;
BEGIN
    IF p_tenant_id IS DISTINCT FROM reporting.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;
    IF p_actor_key IS NULL OR btrim(p_actor_key) = '' THEN
        RAISE EXCEPTION 'actor_key es obligatorio';
    END IF;
    IF p_output_format IS NULL OR p_output_format NOT IN ('pdf','xlsx','csv','json','html') THEN
        RAISE EXCEPTION 'Formato de exportacion no permitido';
    END IF;
    IF p_estimated_bytes IS NULL OR p_estimated_rows IS NULL
       OR p_estimated_bytes < 0 OR p_estimated_rows < 0 THEN
        RAISE EXCEPTION 'Estimaciones no pueden ser negativas';
    END IF;

    SELECT * INTO v_settings
    FROM reporting.tenant_settings
    WHERE tenant_id = p_tenant_id AND is_enabled = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reporting no esta habilitado para el tenant';
    END IF;
    IF p_estimated_bytes > v_settings.max_daily_export_bytes
       OR p_estimated_rows > v_settings.max_rows_per_run THEN
        RETURN false;
    END IF;

    v_usage_date := (now() AT TIME ZONE v_settings.reporting_timezone)::date;
    INSERT INTO reporting.report_export_usage (
        tenant_id, usage_date, actor_key, output_format, export_count, bytes_generated, rows_exported
    ) VALUES (
        p_tenant_id, v_usage_date, p_actor_key, p_output_format, 1, p_estimated_bytes, p_estimated_rows
    )
    ON CONFLICT (tenant_id, usage_date, actor_key, output_format)
    DO UPDATE SET
        export_count = reporting.report_export_usage.export_count + 1,
        bytes_generated = reporting.report_export_usage.bytes_generated + EXCLUDED.bytes_generated,
        rows_exported = reporting.report_export_usage.rows_exported + EXCLUDED.rows_exported,
        updated_at = now()
    WHERE reporting.report_export_usage.export_count < v_settings.max_daily_exports_per_actor
      AND reporting.report_export_usage.bytes_generated + EXCLUDED.bytes_generated <= v_settings.max_daily_export_bytes
    RETURNING export_count, bytes_generated INTO v_count, v_bytes;

    RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------------
-- 16. Comentarios de propiedad y controles
-- ---------------------------------------------------------------------------

COMMENT ON TABLE reporting.report_catalog IS
'Catalogo de informes disponibles por tenant. semantic_source_code referencia un contrato de Analytics, no una tabla consultada directamente.';
COMMENT ON TABLE reporting.report_template_versions IS
'Versiones de plantillas: el borrador puede editarse y publicarse; despues de publicada su contenido/checksum quedan inmutables. Para cambiarla se inserta una nueva version.';
COMMENT ON TABLE reporting.report_definitions IS
'Definiciones guardadas de informes. parameter_schema, filter_schema y definition_config son declarativos y nunca deben interpretarse como SQL libre.';
COMMENT ON TABLE reporting.report_schedules IS
'Programaciones propias de informes. Cron y timezone deben ser validados por el scheduler Rust, incluyendo cambios DST y politicas misfire.';
COMMENT ON TABLE reporting.report_requests IS
'Solicitudes de generacion. La autorizacion de alcance debe verificarse en API y nuevamente por el worker antes de consultar Analytics.';
COMMENT ON TABLE reporting.report_runs IS
'Ejecuciones de informes y sus leases de worker. Los procesos deben reclamar filas con SELECT FOR UPDATE SKIP LOCKED o un mecanismo equivalente. report_run_sections conserva estados operativos actualizables durante la ejecucion.';
COMMENT ON TABLE reporting.report_artifacts IS
'Metadata de archivos privados en object storage. Nunca almacenar bytes ni credenciales/signed URLs permanentes en esta tabla.';
COMMENT ON TABLE reporting.report_deliveries IS
'Intenciones y estados de entrega. Integrations realiza el transporte externo y conserva conexiones/credenciales. recipient_reference debe ser un identificador opaco, no una direccion personal en texto plano.';
COMMENT ON TABLE reporting.report_delivery_attempts IS
'Historial append-only de intentos de entrega; mensajes y metadatos deben estar redactados.';
COMMENT ON TABLE reporting.report_export_usage IS
'Contadores diarios atomicos de exportaciones por actor, formato y tenant.';
COMMENT ON FUNCTION reporting.create_report_request(uuid,uuid,uuid,uuid,uuid,character varying,jsonb,jsonb,character varying,character varying) IS
'Crea solicitudes idempotentes. La autorizacion de usuario, empresa y sucursal debe ser validada por la capa de aplicacion antes de invocar la funcion.';
COMMENT ON FUNCTION reporting.start_report_run(uuid,uuid,character varying,integer) IS
'Inicia una ejecucion bajo bloqueo de la solicitud. El worker debe validar autorizacion y lease antes de procesar.';
COMMENT ON FUNCTION reporting.finish_report_run(uuid,uuid,character varying,bigint,bigint,bigint,jsonb,character varying,character varying) IS
'Cierra una ejecucion y publica su evento de resultado dentro de la misma transaccion.';

-- ---------------------------------------------------------------------------
-- 17. RLS: todas las tablas se aislan por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings','report_catalog','report_templates','report_template_versions',
        'report_definitions','report_definition_parameters','report_definition_sections',
        'report_access_policies','report_access_grants','report_schedules',
        'report_schedule_recipients','report_requests','report_runs','report_run_parameters',
        'report_run_sections','report_artifacts','report_deliveries','report_delivery_attempts',
        'report_approval_requests','report_approval_decisions','report_favorites',
        'report_export_usage','event_inbox','processed_events','event_outbox','idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE reporting.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE reporting.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON reporting.%I USING (tenant_id = reporting.current_tenant_id()) WITH CHECK (tenant_id = reporting.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

COMMIT;

-- ============================================================================
-- FIN DEL MODULO 20: REPORTING
-- ============================================================================
