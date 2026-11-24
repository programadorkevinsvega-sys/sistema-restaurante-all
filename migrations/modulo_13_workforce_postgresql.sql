-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 13: WORKFORCE (PERSONAL, RELACIONES LABORALES, TURNOS Y ASISTENCIA)
-- Ubicacion del crate: crates/modules/workforce
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD DE WORKFORCE
--   * Expediente operativo del empleado y datos de contacto/emergencia.
--   * Departamentos, cargos, tipos de vinculacion y relaciones laborales.
--   * Asignaciones de cargo, empresa y sucursal (referencias logicas).
--   * Vinculacion opcional de un empleado con una cuenta de Identity.
--   * Documentos laborales, certificaciones y formacion.
--   * Plantillas de horario, turnos programados y asistencia real.
--   * Eventos de marcacion, ajustes de asistencia y solicitudes de ausencia.
--   * Inbox, Outbox e idempotencia para integracion entre modulos/servicios.
--
-- FUERA DE ALCANCE
--   * Cuentas de acceso, contrasenas, MFA, sesiones, roles y permisos: identity.
--   * Empresas legales, sucursales, direcciones corporativas: organization.
--   * Nomina, liquidaciones, deducciones y pagos salariales: finance/payroll
--     (cuando se implemente la capacidad especifica de nomina).
--   * Dispositivos, credenciales de reloj biometrico y conectores: integrations.
--   * Reclutamiento y postulaciones: no se incluyen en este modulo inicial.
--
-- LIMITES ENTRE MODULOS
--   * Este modulo solo crea FK fisicas hacia platform.tenants y hacia tablas
--     propias. company_id, branch_id, identity_user_id, actor_user_id y
--     source_device_id son referencias logicas UUID verificadas por contratos.
--   * Un empleado puede existir sin cuenta de Identity. employee_identity_links
--     es una vinculacion opcional, no crea usuarios ni permisos.
--   * Workforce no crea empresas/sucursales ni administra accesos al POS.
--   * Workforce registra asistencia y turnos; no calcula ni paga nomina.
--
-- PRIVACIDAD Y SEGURIDAD
--   * Datos personales sensibles deben cifrarse en la aplicacion con KMS/Vault.
--     No almacenar contrasenas, PAN/CVV, datos biometricos crudos ni diagnosticos.
--   * employee_documents.storage_key apunta a almacenamiento privado; no guardar
--     documentos binarios ni URLs publicas permanentes en PostgreSQL.
--   * Todas las tablas tenant-scoped tienen RLS + FORCE RLS.
--   * Cada transaccion autenticada establece SET LOCAL app.tenant_id = '<uuid>'.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * RLS aísla por tenant; Rust tambien valida company_id/branch_id y permisos.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * No requiere FK fisicas a Identity ni Organization; se integran por puertos.
--   * Ejecutar una sola vez en una base nueva, o administrar como migracion
--     versionada. No usar este archivo para actualizar una instalacion existente.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS workforce;

COMMENT ON SCHEMA workforce IS
'Expedientes laborales, asignaciones, horarios, turnos y asistencia. No administra credenciales, permisos ni nomina.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION workforce.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION workforce.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION workforce.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Workforce';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION workforce.prevent_scope_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_field text;
BEGIN
    FOREACH v_field IN ARRAY ARRAY[
        'tenant_id', 'employee_id', 'employment_record_id', 'company_id',
        'branch_id', 'work_schedule_template_id', 'shift_assignment_id',
        'attendance_record_id', 'leave_request_id', 'identity_user_id',
        'job_position_id', 'department_id', 'source_device_id'
    ] LOOP
        IF (to_jsonb(NEW) -> v_field) IS DISTINCT FROM (to_jsonb(OLD) -> v_field) THEN
            RAISE EXCEPTION 'No se permite cambiar % de un registro de Workforce', v_field;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION workforce.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre un evento o ajuste compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION workforce.prevent_department_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_creates_cycle boolean;
BEGIN
    IF NEW.parent_department_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_department_id = NEW.id THEN
        RAISE EXCEPTION 'Un departamento no puede ser su propio padre';
    END IF;

    WITH RECURSIVE descendants(id) AS (
        SELECT d.id
        FROM workforce.departments d
        WHERE d.tenant_id = NEW.tenant_id
          AND d.id = NEW.parent_department_id
        UNION
        SELECT d.id
        FROM workforce.departments d
        JOIN descendants x ON d.parent_department_id = x.id
        WHERE d.tenant_id = NEW.tenant_id
    )
    SELECT EXISTS (SELECT 1 FROM descendants WHERE id = NEW.id)
      INTO v_creates_cycle;

    IF v_creates_cycle THEN
        RAISE EXCEPTION 'La jerarquia de departamentos no puede contener ciclos';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.tenant_settings (
    id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                       uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_country_code            char(2) NOT NULL DEFAULT 'CO',
    default_timezone                varchar(64) NOT NULL DEFAULT 'America/Bogota',
    default_currency                char(3) NOT NULL DEFAULT 'COP',
    employee_code_prefix            varchar(12) NOT NULL DEFAULT 'EMP',
    next_employee_number            bigint NOT NULL DEFAULT 1 CHECK (next_employee_number > 0),
    require_shift_assignment        boolean NOT NULL DEFAULT false,
    require_attendance_approval     boolean NOT NULL DEFAULT true,
    allow_employee_multiple_branches boolean NOT NULL DEFAULT true,
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_tenant_settings_tenant_unique UNIQUE (tenant_id),
    CONSTRAINT workforce_tenant_settings_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_tenant_settings_country_upper CHECK (default_country_code = upper(default_country_code)),
    CONSTRAINT workforce_tenant_settings_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT workforce_tenant_settings_prefix_not_blank CHECK (btrim(employee_code_prefix) <> ''),
    CONSTRAINT workforce_tenant_settings_json_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Estructura interna: departamentos, cargos y tipos de vinculacion
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.departments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    department_code     varchar(40) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    parent_department_id uuid,
    manager_employee_id uuid,
    status              varchar(16) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'inactive', 'archived')),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_departments_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_departments_code_unique UNIQUE (tenant_id, department_code),
    CONSTRAINT workforce_departments_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT workforce_departments_code_not_blank CHECK (btrim(department_code) <> ''),
    CONSTRAINT workforce_departments_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT workforce_departments_parent_fk FOREIGN KEY (tenant_id, parent_department_id)
        REFERENCES workforce.departments (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE workforce.employment_types (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    type_code           varchar(40) NOT NULL,
    name                varchar(100) NOT NULL,
    description         text,
    requires_end_date   boolean NOT NULL DEFAULT false,
    is_system           boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employment_types_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employment_types_code_unique UNIQUE (tenant_id, type_code),
    CONSTRAINT workforce_employment_types_code_not_blank CHECK (btrim(type_code) <> ''),
    CONSTRAINT workforce_employment_types_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE workforce.job_positions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    position_code      varchar(40) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    department_id       uuid,
    seniority_level     varchar(24) CHECK (seniority_level IS NULL OR seniority_level IN ('entry', 'junior', 'mid', 'senior', 'lead', 'manager', 'executive')),
    is_manager          boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_job_positions_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_job_positions_code_unique UNIQUE (tenant_id, position_code),
    CONSTRAINT workforce_job_positions_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT workforce_job_positions_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT workforce_job_positions_department_fk FOREIGN KEY (tenant_id, department_id)
        REFERENCES workforce.departments (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 3. Expediente maestro del empleado
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.employees (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_number     varchar(48) NOT NULL,
    first_name          varchar(100) NOT NULL,
    middle_name         varchar(100),
    last_name           varchar(100) NOT NULL,
    second_last_name    varchar(100),
    preferred_name      varchar(120),
    work_email          varchar(320),
    work_phone          varchar(40),
    hire_date           date,
    termination_date    date,
    employee_status     varchar(20) NOT NULL DEFAULT 'pre_hire'
                        CHECK (employee_status IN ('pre_hire', 'active', 'on_leave', 'suspended', 'terminated', 'archived')),
    status_reason       varchar(240),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT workforce_employees_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employees_number_not_blank CHECK (btrim(employee_number) <> ''),
    CONSTRAINT workforce_employees_first_name_not_blank CHECK (btrim(first_name) <> ''),
    CONSTRAINT workforce_employees_last_name_not_blank CHECK (btrim(last_name) <> ''),
    CONSTRAINT workforce_employees_dates_valid CHECK (termination_date IS NULL OR hire_date IS NULL OR termination_date >= hire_date),
    CONSTRAINT workforce_employees_termination_status CHECK (
        (employee_status <> 'terminated' OR termination_date IS NOT NULL)
        AND (employee_status NOT IN ('active', 'on_leave', 'suspended') OR termination_date IS NULL)
    ),
    CONSTRAINT workforce_employees_hire_date_status CHECK (
        employee_status NOT IN ('active', 'on_leave', 'suspended', 'terminated') OR hire_date IS NOT NULL
    ),
    CONSTRAINT workforce_employees_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

ALTER TABLE workforce.departments
    ADD CONSTRAINT workforce_departments_manager_fk
    FOREIGN KEY (tenant_id, manager_employee_id)
    REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT;

CREATE TABLE workforce.employee_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL CHECK (new_status IN ('pre_hire', 'active', 'on_leave', 'suspended', 'terminated', 'archived')),
    change_reason       text,
    changed_by_user_id  uuid,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_status_history_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_status_history_previous_valid CHECK (previous_status IS NULL OR previous_status IN ('pre_hire', 'active', 'on_leave', 'suspended', 'terminated', 'archived')),
    CONSTRAINT workforce_employee_status_history_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_employee_status_history
    ON workforce.employee_status_history (tenant_id, employee_id, changed_at DESC);

CREATE UNIQUE INDEX uq_workforce_employees_number
    ON workforce.employees (tenant_id, lower(employee_number))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_workforce_employees_status_name
    ON workforce.employees (tenant_id, employee_status, lower(last_name), lower(first_name))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_workforce_employees_work_email
    ON workforce.employees (tenant_id, lower(work_email))
    WHERE work_email IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE workforce.employee_profiles (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id             uuid NOT NULL,
    date_of_birth           date,
    pronouns                varchar(40),
    nationality_country_code char(2),
    preferred_language      varchar(12) NOT NULL DEFAULT 'es-CO',
    profile_photo_key       text,
    personal_data_ciphertext bytea,
    personal_data_key_ref   varchar(240),
    profile_metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_profiles_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_profiles_employee_unique UNIQUE (tenant_id, employee_id),
    CONSTRAINT workforce_employee_profiles_country_upper CHECK (nationality_country_code IS NULL OR nationality_country_code = upper(nationality_country_code)),
    CONSTRAINT workforce_employee_profiles_cipher_pair CHECK ((personal_data_ciphertext IS NULL) = (personal_data_key_ref IS NULL)),
    CONSTRAINT workforce_employee_profiles_metadata_object CHECK (jsonb_typeof(profile_metadata) = 'object'),
    CONSTRAINT workforce_employee_profiles_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE workforce.employee_contacts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    contact_type        varchar(20) NOT NULL CHECK (contact_type IN ('personal_email', 'mobile', 'phone', 'other')),
    contact_value_ciphertext bytea NOT NULL,
    contact_value_key_ref varchar(240) NOT NULL,
    contact_value_hmac  char(64) NOT NULL,
    contact_value_masked varchar(100),
    is_primary          boolean NOT NULL DEFAULT false,
    is_verified         boolean NOT NULL DEFAULT false,
    verified_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_contacts_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_contacts_verified_consistent CHECK (is_verified = (verified_at IS NOT NULL)),
    CONSTRAINT workforce_employee_contacts_hmac_format CHECK (contact_value_hmac ~ '^[0-9a-f]{64}$'),
    CONSTRAINT workforce_employee_contacts_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_workforce_employee_primary_contact
    ON workforce.employee_contacts (tenant_id, employee_id, contact_type)
    WHERE is_primary;
CREATE INDEX ix_workforce_employee_contacts_fingerprint
    ON workforce.employee_contacts (tenant_id, contact_type, contact_value_hmac);

CREATE TABLE workforce.employee_addresses (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    address_type        varchar(20) NOT NULL CHECK (address_type IN ('residential', 'mailing', 'other')),
    address_ciphertext  bytea NOT NULL,
    address_key_ref     varchar(240) NOT NULL,
    country_code        char(2) NOT NULL,
    is_primary          boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_addresses_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_addresses_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT workforce_employee_addresses_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_workforce_employee_primary_address
    ON workforce.employee_addresses (tenant_id, employee_id, address_type)
    WHERE is_primary;

CREATE TABLE workforce.employee_emergency_contacts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    contact_name        varchar(180) NOT NULL,
    relationship_label  varchar(80),
    phone_ciphertext    bytea NOT NULL,
    phone_key_ref       varchar(240) NOT NULL,
    email_ciphertext    bytea,
    email_key_ref       varchar(240),
    priority_order      smallint NOT NULL DEFAULT 1 CHECK (priority_order > 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_emergency_contacts_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_emergency_contact_email_cipher_pair CHECK ((email_ciphertext IS NULL) = (email_key_ref IS NULL)),
    CONSTRAINT workforce_employee_emergency_contacts_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_workforce_emergency_contact_priority
    ON workforce.employee_emergency_contacts (tenant_id, employee_id, priority_order);

CREATE TABLE workforce.employee_documents (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    document_type       varchar(40) NOT NULL,
    document_number_ciphertext bytea,
    document_number_key_ref varchar(240),
    storage_key         text NOT NULL,
    original_file_name  varchar(255),
    mime_type           varchar(120),
    file_size_bytes     bigint CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    checksum_sha256     char(64),
    issued_at           date,
    expires_at          date,
    verification_status varchar(20) NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected', 'expired')),
    verified_by_user_id uuid,
    verified_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_documents_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_documents_storage_not_blank CHECK (btrim(storage_key) <> ''),
    CONSTRAINT workforce_employee_documents_number_cipher_pair CHECK ((document_number_ciphertext IS NULL) = (document_number_key_ref IS NULL)),
    CONSTRAINT workforce_employee_documents_dates CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT workforce_employee_documents_checksum_format CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT workforce_employee_documents_verified_consistent CHECK ((verification_status = 'verified') = (verified_at IS NOT NULL)),
    CONSTRAINT workforce_employee_documents_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_employee_documents_expiry
    ON workforce.employee_documents (tenant_id, expires_at)
    WHERE expires_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Vinculacion laboral y asignaciones
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.employment_records (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id             uuid NOT NULL,
    employment_type_id      uuid NOT NULL,
    company_id              uuid NOT NULL,
    contract_reference      varchar(100),
    start_date              date NOT NULL,
    end_date                date,
    probation_end_date      date,
    employment_status       varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (employment_status IN ('draft', 'active', 'suspended', 'completed', 'terminated', 'cancelled')),
    standard_weekly_minutes integer CHECK (standard_weekly_minutes IS NULL OR standard_weekly_minutes BETWEEN 1 AND 10080),
    is_primary              boolean NOT NULL DEFAULT true,
    private_notes_ciphertext bytea,
    private_notes_key_ref   varchar(240),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employment_records_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employment_records_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT workforce_employment_records_probation CHECK (probation_end_date IS NULL OR probation_end_date >= start_date),
    CONSTRAINT workforce_employment_records_status_dates CHECK (
        (employment_status NOT IN ('active', 'suspended') OR end_date IS NULL)
        AND (employment_status NOT IN ('completed', 'terminated') OR end_date IS NOT NULL)
    ),
    CONSTRAINT workforce_employment_records_private_cipher_pair CHECK ((private_notes_ciphertext IS NULL) = (private_notes_key_ref IS NULL)),
    CONSTRAINT workforce_employment_records_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_employment_records_type_fk FOREIGN KEY (tenant_id, employment_type_id)
        REFERENCES workforce.employment_types (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_employment_records_employee_status
    ON workforce.employment_records (tenant_id, employee_id, employment_status, start_date DESC);
CREATE INDEX ix_workforce_employment_records_company
    ON workforce.employment_records (tenant_id, company_id, employment_status);
CREATE UNIQUE INDEX uq_workforce_primary_active_employment
    ON workforce.employment_records (tenant_id, employee_id)
    WHERE is_primary AND employment_status = 'active';

CREATE TABLE workforce.employee_compensation_terms (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employment_record_id uuid NOT NULL,
    compensation_type   varchar(20) NOT NULL CHECK (compensation_type IN ('salary', 'hourly', 'daily', 'commission_only', 'mixed', 'other')),
    amount              numeric(19,4) NOT NULL CHECK (amount >= 0),
    currency            char(3) NOT NULL,
    pay_frequency       varchar(20) NOT NULL CHECK (pay_frequency IN ('hourly', 'daily', 'weekly', 'biweekly', 'semimonthly', 'monthly', 'other')),
    effective_from      date NOT NULL,
    effective_to        date,
    confidential_note_ciphertext bytea,
    confidential_note_key_ref varchar(240),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_compensation_terms_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_compensation_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT workforce_compensation_currency_format CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT workforce_compensation_note_cipher_pair CHECK ((confidential_note_ciphertext IS NULL) = (confidential_note_key_ref IS NULL)),
    CONSTRAINT workforce_compensation_employment_fk FOREIGN KEY (tenant_id, employment_record_id)
        REFERENCES workforce.employment_records (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_compensation_effective
    ON workforce.employee_compensation_terms (tenant_id, employment_record_id, effective_from DESC);

CREATE TABLE workforce.employee_position_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    job_position_id     uuid NOT NULL,
    department_id       uuid,
    manager_employee_id uuid,
    company_id          uuid NOT NULL,
    effective_from      date NOT NULL,
    effective_to        date,
    assignment_status   varchar(16) NOT NULL DEFAULT 'active'
                        CHECK (assignment_status IN ('active', 'ended', 'cancelled')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_position_assignments_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_position_assignment_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT workforce_position_assignment_not_self_manager CHECK (manager_employee_id IS NULL OR manager_employee_id <> employee_id),
    CONSTRAINT workforce_position_assignment_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_position_assignment_position_fk FOREIGN KEY (tenant_id, job_position_id)
        REFERENCES workforce.job_positions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_position_assignment_department_fk FOREIGN KEY (tenant_id, department_id)
        REFERENCES workforce.departments (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_position_assignment_manager_fk FOREIGN KEY (tenant_id, manager_employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_position_assignments_employee
    ON workforce.employee_position_assignments (tenant_id, employee_id, effective_from DESC);
CREATE INDEX ix_workforce_position_assignments_manager
    ON workforce.employee_position_assignments (tenant_id, manager_employee_id)
    WHERE manager_employee_id IS NOT NULL;

CREATE TABLE workforce.employee_branch_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    assignment_label    varchar(100),
    is_primary          boolean NOT NULL DEFAULT false,
    effective_from      date NOT NULL,
    effective_to        date,
    assignment_status   varchar(16) NOT NULL DEFAULT 'active'
                        CHECK (assignment_status IN ('active', 'ended', 'cancelled')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_branch_assignments_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_branch_assignment_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT workforce_employee_branch_assignments_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_branch_assignments_employee
    ON workforce.employee_branch_assignments (tenant_id, employee_id, assignment_status);
CREATE INDEX ix_workforce_branch_assignments_branch
    ON workforce.employee_branch_assignments (tenant_id, branch_id, assignment_status);
CREATE UNIQUE INDEX uq_workforce_primary_employee_branch
    ON workforce.employee_branch_assignments (tenant_id, employee_id)
    WHERE is_primary AND assignment_status = 'active';

CREATE TABLE workforce.employee_identity_links (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    identity_user_id    uuid NOT NULL,
    linked_at           timestamptz NOT NULL DEFAULT now(),
    linked_by_user_id   uuid,
    revoked_at          timestamptz,
    revoked_by_user_id  uuid,
    link_status         varchar(16) NOT NULL DEFAULT 'active'
                        CHECK (link_status IN ('active', 'revoked')),
    CONSTRAINT workforce_employee_identity_links_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_identity_link_revocation_consistent CHECK ((link_status = 'revoked') = (revoked_at IS NOT NULL)),
    CONSTRAINT workforce_identity_link_revoker_consistent CHECK (
        (link_status = 'revoked' AND revoked_by_user_id IS NOT NULL)
        OR (link_status = 'active' AND revoked_by_user_id IS NULL)
    ),
    CONSTRAINT workforce_employee_identity_links_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_workforce_active_identity_link_user
    ON workforce.employee_identity_links (tenant_id, identity_user_id)
    WHERE link_status = 'active';
CREATE UNIQUE INDEX uq_workforce_active_identity_link_employee
    ON workforce.employee_identity_links (tenant_id, employee_id)
    WHERE link_status = 'active';
CREATE INDEX ix_workforce_identity_links_employee
    ON workforce.employee_identity_links (tenant_id, employee_id, link_status);

-- ---------------------------------------------------------------------------
-- 5. Plantillas de horarios y turnos
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.work_schedule_templates (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    template_code       varchar(40) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    branch_id           uuid,
    timezone            varchar(64) NOT NULL DEFAULT 'America/Bogota',
    effective_from      date,
    effective_to        date,
    template_status     varchar(16) NOT NULL DEFAULT 'active'
                        CHECK (template_status IN ('active', 'inactive', 'archived')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_work_schedule_templates_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_work_schedule_templates_code_unique UNIQUE (tenant_id, template_code),
    CONSTRAINT workforce_schedule_template_dates CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from),
    CONSTRAINT workforce_schedule_template_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE workforce.work_schedule_template_days (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    work_schedule_template_id uuid NOT NULL,
    day_of_week             smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    interval_number         smallint NOT NULL DEFAULT 1 CHECK (interval_number > 0),
    starts_at               time NOT NULL,
    ends_at                 time NOT NULL,
    end_day_offset          smallint NOT NULL DEFAULT 0 CHECK (end_day_offset IN (0, 1)),
    break_minutes           integer NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
    is_working_day          boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_schedule_template_day_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_schedule_template_day_interval_unique UNIQUE (tenant_id, work_schedule_template_id, day_of_week, interval_number),
    CONSTRAINT workforce_schedule_template_day_time_valid CHECK (
        (is_working_day AND (
            (end_day_offset = 0 AND ends_at > starts_at)
            OR (end_day_offset = 1 AND ends_at < starts_at)
        ))
        OR (NOT is_working_day AND end_day_offset = 0)
    ),
    CONSTRAINT workforce_schedule_template_day_fk FOREIGN KEY (tenant_id, work_schedule_template_id)
        REFERENCES workforce.work_schedule_templates (tenant_id, id) ON DELETE CASCADE
);

CREATE TABLE workforce.shift_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    work_schedule_template_id uuid,
    shift_code          varchar(48),
    starts_at           timestamptz NOT NULL,
    ends_at             timestamptz NOT NULL,
    planned_break_minutes integer NOT NULL DEFAULT 0 CHECK (planned_break_minutes >= 0),
    shift_status        varchar(20) NOT NULL DEFAULT 'scheduled'
                        CHECK (shift_status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
    notes               text,
    created_by_user_id  uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_shift_assignments_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_shift_assignments_scope_unique UNIQUE (tenant_id, employee_id, company_id, branch_id, id),
    CONSTRAINT workforce_shift_assignments_time_valid CHECK (ends_at > starts_at),
    CONSTRAINT workforce_shift_assignments_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_shift_assignments_template_fk FOREIGN KEY (tenant_id, work_schedule_template_id)
        REFERENCES workforce.work_schedule_templates (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_shifts_employee_time
    ON workforce.shift_assignments (tenant_id, employee_id, starts_at, ends_at);
CREATE INDEX ix_workforce_shifts_branch_time
    ON workforce.shift_assignments (tenant_id, branch_id, starts_at)
    WHERE shift_status IN ('scheduled', 'confirmed', 'in_progress');

-- ---------------------------------------------------------------------------
-- 6. Marcaciones y asistencia
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.shift_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    shift_assignment_id uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL CHECK (new_status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
    changed_by_user_id  uuid,
    change_note         text,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_shift_status_history_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_shift_status_history_previous_valid CHECK (previous_status IS NULL OR previous_status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
    CONSTRAINT workforce_shift_status_history_shift_fk FOREIGN KEY (tenant_id, shift_assignment_id)
        REFERENCES workforce.shift_assignments (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_shift_status_history
    ON workforce.shift_status_history (tenant_id, shift_assignment_id, changed_at DESC);

CREATE TABLE workforce.time_clock_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    event_type          varchar(20) NOT NULL CHECK (event_type IN ('clock_in', 'clock_out', 'break_start', 'break_end')),
    occurred_at         timestamptz NOT NULL,
    recorded_at         timestamptz NOT NULL DEFAULT now(),
    source_type         varchar(20) NOT NULL CHECK (source_type IN ('web', 'mobile', 'kiosk', 'device', 'manual', 'import')),
    source_device_id    uuid,
    source_reference    varchar(160),
    location_latitude   numeric(10,7),
    location_longitude  numeric(10,7),
    location_accuracy_m numeric(10,2),
    event_payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id  uuid,
    CONSTRAINT workforce_time_clock_events_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_time_clock_events_scope_unique UNIQUE (tenant_id, employee_id, company_id, branch_id, id),
    CONSTRAINT workforce_time_clock_events_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_time_clock_events_geo_lat CHECK (location_latitude IS NULL OR location_latitude BETWEEN -90 AND 90),
    CONSTRAINT workforce_time_clock_events_geo_lon CHECK (location_longitude IS NULL OR location_longitude BETWEEN -180 AND 180),
    CONSTRAINT workforce_time_clock_events_accuracy CHECK (location_accuracy_m IS NULL OR location_accuracy_m >= 0),
    CONSTRAINT workforce_time_clock_events_payload_object CHECK (jsonb_typeof(event_payload) = 'object')
);
CREATE INDEX ix_workforce_clock_events_employee_time
    ON workforce.time_clock_events (tenant_id, employee_id, occurred_at DESC);
CREATE INDEX ix_workforce_clock_events_branch_time
    ON workforce.time_clock_events (tenant_id, branch_id, occurred_at DESC);
CREATE UNIQUE INDEX uq_workforce_clock_event_source_reference
    ON workforce.time_clock_events (tenant_id, source_type, source_reference)
    WHERE source_reference IS NOT NULL;

CREATE TABLE workforce.attendance_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    shift_assignment_id uuid,
    clock_in_event_id   uuid,
    clock_out_event_id  uuid,
    clock_in_at         timestamptz NOT NULL,
    clock_out_at        timestamptz,
    break_minutes       integer NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
    worked_minutes      integer CHECK (worked_minutes IS NULL OR worked_minutes >= 0),
    attendance_status   varchar(20) NOT NULL DEFAULT 'open'
                        CHECK (attendance_status IN ('open', 'submitted', 'approved', 'rejected', 'corrected')),
    reviewed_by_user_id uuid,
    reviewed_at         timestamptz,
    review_note         text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_attendance_records_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_attendance_clock_order CHECK (clock_out_at IS NULL OR clock_out_at > clock_in_at),
    CONSTRAINT workforce_attendance_status_clock_consistent CHECK (
        (attendance_status = 'open' AND clock_out_at IS NULL)
        OR (attendance_status <> 'open' AND clock_out_at IS NOT NULL)
    ),
    CONSTRAINT workforce_attendance_review_consistent CHECK (
        (attendance_status IN ('approved', 'rejected', 'corrected') AND reviewed_at IS NOT NULL AND reviewed_by_user_id IS NOT NULL)
        OR (attendance_status NOT IN ('approved', 'rejected', 'corrected') AND reviewed_at IS NULL AND reviewed_by_user_id IS NULL)
    ),
    CONSTRAINT workforce_attendance_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_attendance_shift_fk FOREIGN KEY (tenant_id, employee_id, company_id, branch_id, shift_assignment_id)
        REFERENCES workforce.shift_assignments (tenant_id, employee_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_attendance_clock_in_event_fk FOREIGN KEY (tenant_id, employee_id, company_id, branch_id, clock_in_event_id)
        REFERENCES workforce.time_clock_events (tenant_id, employee_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_attendance_clock_out_event_fk FOREIGN KEY (tenant_id, employee_id, company_id, branch_id, clock_out_event_id)
        REFERENCES workforce.time_clock_events (tenant_id, employee_id, company_id, branch_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_workforce_attendance_one_open_per_employee
    ON workforce.attendance_records (tenant_id, employee_id)
    WHERE clock_out_at IS NULL;
CREATE INDEX ix_workforce_attendance_employee_clockin
    ON workforce.attendance_records (tenant_id, employee_id, clock_in_at DESC);
CREATE INDEX ix_workforce_attendance_branch_status
    ON workforce.attendance_records (tenant_id, branch_id, attendance_status, clock_in_at DESC);
CREATE UNIQUE INDEX uq_workforce_attendance_clock_in_event
    ON workforce.attendance_records (tenant_id, clock_in_event_id)
    WHERE clock_in_event_id IS NOT NULL;
CREATE UNIQUE INDEX uq_workforce_attendance_clock_out_event
    ON workforce.attendance_records (tenant_id, clock_out_event_id)
    WHERE clock_out_event_id IS NOT NULL;

CREATE OR REPLACE FUNCTION workforce.validate_attendance_clock_event_types()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_type varchar(20);
BEGIN
    IF NEW.clock_in_event_id IS NOT NULL THEN
        SELECT e.event_type INTO v_event_type
        FROM workforce.time_clock_events e
        WHERE e.tenant_id = NEW.tenant_id AND e.id = NEW.clock_in_event_id;
        IF v_event_type IS DISTINCT FROM 'clock_in' THEN
            RAISE EXCEPTION 'clock_in_event_id debe referenciar una marcacion clock_in';
        END IF;
    END IF;

    IF NEW.clock_out_event_id IS NOT NULL THEN
        SELECT e.event_type INTO v_event_type
        FROM workforce.time_clock_events e
        WHERE e.tenant_id = NEW.tenant_id AND e.id = NEW.clock_out_event_id;
        IF v_event_type IS DISTINCT FROM 'clock_out' THEN
            RAISE EXCEPTION 'clock_out_event_id debe referenciar una marcacion clock_out';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_workforce_attendance_clock_event_types
    BEFORE INSERT OR UPDATE OF clock_in_event_id, clock_out_event_id
    ON workforce.attendance_records
    FOR EACH ROW EXECUTE FUNCTION workforce.validate_attendance_clock_event_types();

CREATE TABLE workforce.attendance_adjustments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    attendance_record_id uuid NOT NULL,
    adjustment_type     varchar(24) NOT NULL CHECK (adjustment_type IN ('clock_in', 'clock_out', 'break_minutes', 'worked_minutes', 'status')),
    previous_value      jsonb,
    requested_value     jsonb NOT NULL,
    reason              text NOT NULL,
    adjustment_status   varchar(16) NOT NULL DEFAULT 'pending'
                        CHECK (adjustment_status IN ('pending', 'approved', 'rejected', 'cancelled')),
    requested_by_user_id uuid,
    decided_by_user_id  uuid,
    decided_at          timestamptz,
    decision_note       text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_attendance_adjustments_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_attendance_adjustment_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT workforce_attendance_adjustment_decision_consistent CHECK (
        (adjustment_status IN ('approved', 'rejected') AND decided_at IS NOT NULL AND decided_by_user_id IS NOT NULL)
        OR (adjustment_status NOT IN ('approved', 'rejected') AND decided_at IS NULL AND decided_by_user_id IS NULL)
    ),
    CONSTRAINT workforce_attendance_adjustments_attendance_fk FOREIGN KEY (tenant_id, attendance_record_id)
        REFERENCES workforce.attendance_records (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_attendance_adjustment_previous_object CHECK (previous_value IS NULL OR jsonb_typeof(previous_value) IN ('object', 'array', 'string', 'number', 'boolean', 'null')),
    CONSTRAINT workforce_attendance_adjustment_requested_object CHECK (jsonb_typeof(requested_value) IN ('object', 'array', 'string', 'number', 'boolean', 'null'))
);

-- ---------------------------------------------------------------------------
-- 7. Ausencias y permisos laborales
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.leave_types (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    leave_code          varchar(40) NOT NULL,
    name                varchar(120) NOT NULL,
    description         text,
    requires_approval   boolean NOT NULL DEFAULT true,
    requires_document   boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_leave_types_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_leave_types_code_unique UNIQUE (tenant_id, leave_code),
    CONSTRAINT workforce_leave_types_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE workforce.leave_requests (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    leave_type_id       uuid NOT NULL,
    company_id          uuid NOT NULL,
    branch_id           uuid,
    starts_at           timestamptz NOT NULL,
    ends_at             timestamptz NOT NULL,
    requested_hours     numeric(8,2) CHECK (requested_hours IS NULL OR requested_hours > 0),
    request_reason      text,
    document_storage_key text,
    request_status      varchar(20) NOT NULL DEFAULT 'submitted'
                        CHECK (request_status IN ('draft', 'submitted', 'approved', 'rejected', 'cancelled', 'withdrawn')),
    submitted_at        timestamptz,
    resolved_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_leave_requests_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_leave_requests_period CHECK (ends_at > starts_at),
    CONSTRAINT workforce_leave_requests_submission CHECK (
        request_status NOT IN ('submitted', 'approved', 'rejected') OR submitted_at IS NOT NULL
    ),
    CONSTRAINT workforce_leave_requests_resolution CHECK ((request_status IN ('approved', 'rejected') AND resolved_at IS NOT NULL) OR request_status NOT IN ('approved', 'rejected')),
    CONSTRAINT workforce_leave_requests_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT workforce_leave_requests_type_fk FOREIGN KEY (tenant_id, leave_type_id)
        REFERENCES workforce.leave_types (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_leave_requests_employee_period
    ON workforce.leave_requests (tenant_id, employee_id, starts_at, ends_at);
CREATE INDEX ix_workforce_leave_requests_status
    ON workforce.leave_requests (tenant_id, request_status, starts_at);

CREATE TABLE workforce.leave_approvals (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    leave_request_id    uuid NOT NULL,
    decision            varchar(16) NOT NULL CHECK (decision IN ('approved', 'rejected', 'returned', 'cancelled')),
    approver_user_id    uuid NOT NULL,
    decision_note       text,
    decided_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_leave_approvals_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_leave_approvals_request_fk FOREIGN KEY (tenant_id, leave_request_id)
        REFERENCES workforce.leave_requests (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_leave_approvals_request
    ON workforce.leave_approvals (tenant_id, leave_request_id, decided_at DESC);

-- ---------------------------------------------------------------------------
-- 8. Certificaciones y formacion
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.employee_certifications (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    certification_name  varchar(180) NOT NULL,
    issuer_name         varchar(180),
    certificate_reference_ciphertext bytea,
    certificate_reference_key_ref varchar(240),
    issued_at           date,
    expires_at          date,
    verification_status varchar(16) NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected', 'expired')),
    document_storage_key text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_certifications_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_employee_certifications_dates CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT workforce_employee_certifications_cipher_pair CHECK ((certificate_reference_ciphertext IS NULL) = (certificate_reference_key_ref IS NULL)),
    CONSTRAINT workforce_employee_certifications_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_certifications_expiry
    ON workforce.employee_certifications (tenant_id, expires_at)
    WHERE expires_at IS NOT NULL;

CREATE TABLE workforce.employee_training_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    employee_id         uuid NOT NULL,
    training_name       varchar(180) NOT NULL,
    provider_name       varchar(180),
    training_category   varchar(80),
    starts_at           timestamptz,
    completed_at        timestamptz,
    duration_minutes    integer CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    training_status     varchar(16) NOT NULL DEFAULT 'planned'
                        CHECK (training_status IN ('planned', 'in_progress', 'completed', 'failed', 'cancelled')),
    result_note         text,
    evidence_storage_key text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_employee_training_records_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_training_dates CHECK (completed_at IS NULL OR starts_at IS NULL OR completed_at >= starts_at),
    CONSTRAINT workforce_training_completion_consistent CHECK (
        training_status NOT IN ('completed', 'failed') OR completed_at IS NOT NULL
    ),
    CONSTRAINT workforce_employee_training_records_employee_fk FOREIGN KEY (tenant_id, employee_id)
        REFERENCES workforce.employees (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_workforce_training_employee_status
    ON workforce.employee_training_records (tenant_id, employee_id, training_status);

-- ---------------------------------------------------------------------------
-- 9. Inbox, Outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE workforce.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    source_module       varchar(80) NOT NULL,
    event_id            uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    payload_sha256      char(64),
    processed_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_processed_events_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_processed_events_unique UNIQUE (tenant_id, source_module, event_id)
);

CREATE TABLE workforce.event_outbox (
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
    delivery_attempts   integer NOT NULL DEFAULT 0 CHECK (delivery_attempts >= 0),
    last_error          text,
    CONSTRAINT workforce_event_outbox_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object')
);
CREATE INDEX ix_workforce_outbox_pending
    ON workforce.event_outbox (available_at, occurred_at)
    WHERE published_at IS NULL;

CREATE TABLE workforce.idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_name      varchar(120) NOT NULL,
    idempotency_key     varchar(180) NOT NULL,
    request_sha256      char(64) NOT NULL,
    response_status     integer,
    response_payload    jsonb,
    completed_at        timestamptz,
    expires_at          timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workforce_idempotency_records_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT workforce_idempotency_records_unique UNIQUE (tenant_id, operation_name, idempotency_key),
    CONSTRAINT workforce_idempotency_response_object CHECK (response_payload IS NULL OR jsonb_typeof(response_payload) = 'object')
);

-- ---------------------------------------------------------------------------
-- 10. Indices adicionales de consulta operacional
-- ---------------------------------------------------------------------------

CREATE INDEX ix_workforce_departments_parent
    ON workforce.departments (tenant_id, parent_department_id);
CREATE INDEX ix_workforce_job_positions_department
    ON workforce.job_positions (tenant_id, department_id, is_active);
CREATE INDEX ix_workforce_contacts_employee
    ON workforce.employee_contacts (tenant_id, employee_id);
CREATE INDEX ix_workforce_addresses_employee
    ON workforce.employee_addresses (tenant_id, employee_id);
CREATE INDEX ix_workforce_documents_employee_type
    ON workforce.employee_documents (tenant_id, employee_id, document_type);
CREATE INDEX ix_workforce_position_assignments_position
    ON workforce.employee_position_assignments (tenant_id, job_position_id, assignment_status);
CREATE INDEX ix_workforce_schedule_templates_branch
    ON workforce.work_schedule_templates (tenant_id, branch_id, template_status);
CREATE INDEX ix_workforce_schedule_days_template
    ON workforce.work_schedule_template_days (tenant_id, work_schedule_template_id, day_of_week);
CREATE INDEX ix_workforce_shifts_status_time
    ON workforce.shift_assignments (tenant_id, shift_status, starts_at);
CREATE INDEX ix_workforce_attendance_open
    ON workforce.attendance_records (tenant_id, employee_id, clock_in_at)
    WHERE clock_out_at IS NULL;
CREATE INDEX ix_workforce_adjustments_pending
    ON workforce.attendance_adjustments (tenant_id, created_at)
    WHERE adjustment_status = 'pending';
CREATE INDEX ix_workforce_leave_types_active
    ON workforce.leave_types (tenant_id, is_active, leave_code);
CREATE INDEX ix_workforce_certifications_employee
    ON workforce.employee_certifications (tenant_id, employee_id, expires_at);
CREATE INDEX ix_workforce_processed_events_time
    ON workforce.processed_events (tenant_id, processed_at DESC);

-- ---------------------------------------------------------------------------
-- 11. Inicializacion de datos predeterminados por tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION workforce.initialize_tenant_workforce(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id es obligatorio';
    END IF;
    IF workforce.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El contexto app.tenant_id debe coincidir con p_tenant_id';
    END IF;

    INSERT INTO workforce.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO workforce.employment_types
        (tenant_id, type_code, name, description, requires_end_date, is_system)
    VALUES
        (p_tenant_id, 'permanent', 'Indefinido / permanente', 'Vinculacion sin fecha de finalizacion predeterminada.', false, true),
        (p_tenant_id, 'fixed_term', 'Termino fijo', 'Vinculacion con fecha de finalizacion acordada.', true, true),
        (p_tenant_id, 'temporary', 'Temporal', 'Vinculacion temporal segun politica de la empresa.', true, true),
        (p_tenant_id, 'contractor', 'Contratista', 'Prestacion de servicios o vinculacion independiente.', true, true),
        (p_tenant_id, 'internship', 'Practica / pasantia', 'Programa de practica o aprendizaje.', true, true)
    ON CONFLICT (tenant_id, type_code) DO NOTHING;

    INSERT INTO workforce.leave_types
        (tenant_id, leave_code, name, description, requires_approval, requires_document)
    VALUES
        (p_tenant_id, 'annual', 'Vacaciones', 'Ausencia programada; reglas de elegibilidad segun politica aplicable.', true, false),
        (p_tenant_id, 'sick', 'Incapacidad / enfermedad', 'Ausencia por motivo de salud; no almacenar diagnosticos en este modulo.', true, true),
        (p_tenant_id, 'personal', 'Permiso personal', 'Ausencia por asuntos personales.', true, false),
        (p_tenant_id, 'unpaid', 'Permiso no remunerado', 'Ausencia no remunerada segun aprobacion y politica.', true, false),
        (p_tenant_id, 'other', 'Otra ausencia', 'Categoria configurable por la empresa.', true, false)
    ON CONFLICT (tenant_id, leave_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Triggers: updated_at, tenant/scope inmutable y jerarquia
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'departments', 'employment_types', 'job_positions',
        'employees', 'employee_profiles', 'employee_contacts', 'employee_addresses',
        'employee_emergency_contacts', 'employee_documents', 'employment_records',
        'employee_compensation_terms', 'employee_position_assignments',
        'employee_branch_assignments', 'work_schedule_templates',
        'work_schedule_template_days', 'shift_assignments', 'attendance_records',
        'attendance_adjustments', 'leave_types', 'leave_requests',
        'employee_certifications', 'employee_training_records', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON workforce.%I FOR EACH ROW EXECUTE FUNCTION workforce.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'departments', 'employment_types', 'job_positions',
        'employees', 'employee_status_history', 'employee_profiles', 'employee_contacts', 'employee_addresses',
        'employee_emergency_contacts', 'employee_documents', 'employment_records',
        'employee_compensation_terms', 'employee_position_assignments',
        'employee_branch_assignments', 'employee_identity_links',
        'work_schedule_templates', 'work_schedule_template_days', 'shift_assignments',
        'shift_status_history', 'time_clock_events', 'attendance_records', 'attendance_adjustments',
        'leave_types', 'leave_requests', 'leave_approvals', 'employee_certifications',
        'employee_training_records', 'processed_events', 'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON workforce.%I FOR EACH ROW EXECUTE FUNCTION workforce.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'employee_profiles', 'employee_contacts', 'employee_addresses',
        'employee_emergency_contacts', 'employee_documents', 'employment_records',
        'employee_compensation_terms', 'employee_position_assignments',
        'employee_branch_assignments', 'employee_identity_links',
        'work_schedule_templates', 'work_schedule_template_days', 'shift_assignments',
        'time_clock_events', 'attendance_records', 'attendance_adjustments',
        'leave_requests', 'leave_approvals', 'employee_certifications', 'employee_training_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON workforce.%I FOR EACH ROW EXECUTE FUNCTION workforce.prevent_scope_change()',
            'trg_' || v_table || '_scope_immutable', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'employee_status_history', 'shift_status_history', 'time_clock_events', 'leave_approvals', 'processed_events'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON workforce.%I FOR EACH ROW EXECUTE FUNCTION workforce.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_workforce_departments_prevent_cycle
    BEFORE INSERT OR UPDATE OF parent_department_id ON workforce.departments
    FOR EACH ROW EXECUTE FUNCTION workforce.prevent_department_cycle();

-- ---------------------------------------------------------------------------
-- 13. Row Level Security: todas las tablas aisladas por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'departments', 'employment_types', 'job_positions',
        'employees', 'employee_status_history', 'employee_profiles', 'employee_contacts', 'employee_addresses',
        'employee_emergency_contacts', 'employee_documents', 'employment_records',
        'employee_compensation_terms', 'employee_position_assignments',
        'employee_branch_assignments', 'employee_identity_links',
        'work_schedule_templates', 'work_schedule_template_days', 'shift_assignments',
        'shift_status_history', 'time_clock_events', 'attendance_records', 'attendance_adjustments',
        'leave_types', 'leave_requests', 'leave_approvals', 'employee_certifications',
        'employee_training_records', 'processed_events', 'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE workforce.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE workforce.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON workforce.%I USING (tenant_id = workforce.current_tenant_id()) WITH CHECK (tenant_id = workforce.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. Comentarios de propiedad y contratos
-- ---------------------------------------------------------------------------

COMMENT ON TABLE workforce.employees IS
'Expediente maestro laboral. work_email/work_phone deben ser datos corporativos de trabajo, no contactos personales; los contactos personales se guardan cifrados en employee_contacts. No es una cuenta de acceso; las credenciales pertenecen a Identity.';
COMMENT ON TABLE workforce.employee_status_history IS
'Historial append-only de cambios de estado del empleado; se inserta en la misma transaccion que el cambio de estado.';
COMMENT ON TABLE workforce.shift_status_history IS
'Historial append-only de transiciones de turnos; se inserta en la misma transaccion que el cambio de estado.';
COMMENT ON TABLE workforce.employee_identity_links IS
'Vinculacion opcional empleado-cuenta identity. identity_user_id es referencia logica validada por contrato; un empleado puede no tener acceso al sistema.';
COMMENT ON TABLE workforce.employment_records IS
'Relacion laboral/contractual. company_id es referencia logica a Organization; no crea dependencia fisica entre modulos.';
COMMENT ON TABLE workforce.employee_compensation_terms IS
'Condiciones de remuneracion como dato laboral confidencial. No ejecuta nomina, deducciones ni pagos; esos procesos pertenecen a Finance/Payroll.';
COMMENT ON TABLE workforce.employee_branch_assignments IS
'Asignaciones de trabajo a sucursales. branch_id/company_id son UUID logicos validados mediante Organization.';
COMMENT ON TABLE workforce.shift_assignments IS
'Planificacion de turnos. Los conflictos de horario y limites de jornada requieren validacion transaccional en application/domain.';
COMMENT ON TABLE workforce.time_clock_events IS
'Eventos de marcacion append-only. Correcciones deben registrarse mediante attendance_adjustments, nunca editando la marcacion original.';
COMMENT ON TABLE workforce.attendance_records IS
'Resumen de asistencia derivado de eventos de marcacion; las transiciones y calculos se coordinan desde Workforce application.';
COMMENT ON TABLE workforce.leave_approvals IS
'Historial append-only de decisiones sobre solicitudes de ausencia; approver_user_id es referencia logica a Identity.';
COMMENT ON TABLE workforce.employee_documents IS
'Metadatos y referencia privada a objeto documental. Los binarios residen en almacenamiento privado; los datos identificativos se cifran en la aplicacion.';
COMMENT ON TABLE workforce.event_outbox IS
'Outbox transaccional para publicar eventos versionados de Workforce despues del commit.';

COMMIT;

-- ============================================================================
-- FIN MODULO 13: WORKFORCE
-- ============================================================================
