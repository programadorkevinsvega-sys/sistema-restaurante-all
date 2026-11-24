-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 14: FINANCE (CONTABILIDAD, LIBRO MAYOR, IMPUESTOS Y CUENTAS)
-- Ubicacion del crate: crates/modules/finance
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD DE FINANCE
--   * Libros contables por empresa legal y moneda funcional.
--   * Ejercicios y periodos fiscales; cierre y reapertura controlados.
--   * Plan de cuentas, centros de costo y mapeos contables.
--   * Asientos contables de partida doble, lotes de contabilizacion e historial.
--   * Cuentas por cobrar y por pagar, vencimientos y aplicaciones de pagos.
--   * Cuentas bancarias, extractos y conciliaciones.
--   * Catalogo de impuestos, tarifas, periodos y declaraciones.
--   * Inbox, Outbox e idempotencia para integracion entre modulos.
--
-- FUERA DE ALCANCE
--   * Procesamiento/autorizacion/captura de pagos: payments.
--   * Caja fisica, turnos, arqueos y movimientos de efectivo: cash.
--   * Ventas y documentos comerciales de origen: sales.
--   * Proveedores y ordenes de compra: procurement / purchasing.
--   * Clientes y sus perfiles: customers.
--   * Expedientes/turnos del personal: workforce.
--   * Calculo y pago de nomina, propinas y compensaciones variables: fase
--     posterior de Finance/Payroll; no esta incluido en este esquema.
--   * Facturacion y suscripcion SaaS de la plataforma: platform.
--   * Finance conserva referencias externas UUID/texto; no crea FK fisicas
--     hacia tablas privadas de otros modulos.
--
-- LIMITES Y SEGURIDAD
--   * La unica FK externa de este modulo es platform.tenants(id).
--   * Todas las tablas operativas incluyen tenant_id y RLS + FORCE RLS.
--   * Cada transaccion autenticada establece SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant debe derivarse de una sesion autenticada, nunca del body HTTP.
--   * El rol runtime no debe ser superusuario, owner de tablas ni BYPASSRLS.
--   * RLS aísla por tenant; Rust valida company_id, libro, sucursal y permisos.
--   * No almacenar numeros completos de tarjeta, CVV, credenciales bancarias ni
--     secretos de pasarelas. Utilizar KMS/Vault y guardar solo referencias.
--   * Los asientos contabilizados y sus lineas son inmutables; las correcciones
--     se realizan con asientos de reverso/ajuste, no editando el asiento original.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * No requiere FK fisicas a Identity, Organization, Sales, Payments, Cash,
--     Procurement, Purchasing, Customers ni Workforce.
--   * Ejecutar una sola vez en una base nueva, o como migracion versionada.
--   * No ejecutar este archivo encima de un schema finance ya existente.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS finance;

COMMENT ON SCHEMA finance IS
'Contabilidad, libro mayor, periodos, impuestos, cuentas por cobrar/pagar y conciliacion financiera. No procesa pagos ni administra caja fisica.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION finance.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION finance.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Finance';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una correccion compensatoria',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION finance.prevent_posted_journal_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_entry_id uuid;
    v_status text;
BEGIN
    v_entry_id := COALESCE(NEW.journal_entry_id, OLD.journal_entry_id);
    SELECT status INTO v_status
      FROM finance.journal_entries
     WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id)
       AND id = v_entry_id;

    IF v_status IN ('posted', 'reversed') THEN
        RAISE EXCEPTION 'No se pueden modificar lineas de un asiento contabilizado/revertido; cree un asiento compensatorio';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.prevent_chart_account_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cycle boolean;
BEGIN
    IF NEW.parent_account_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.parent_account_id = NEW.id THEN
        RAISE EXCEPTION 'Una cuenta contable no puede ser su propia cuenta padre';
    END IF;

    WITH RECURSIVE ancestors(id, parent_account_id) AS (
        SELECT a.id, a.parent_account_id
          FROM finance.chart_of_accounts a
         WHERE a.tenant_id = NEW.tenant_id
           AND a.accounting_book_id = NEW.accounting_book_id
           AND a.id = NEW.parent_account_id
        UNION
        SELECT a.id, a.parent_account_id
          FROM finance.chart_of_accounts a
          JOIN ancestors x ON a.id = x.parent_account_id
         WHERE a.tenant_id = NEW.tenant_id
           AND a.accounting_book_id = NEW.accounting_book_id
    )
    SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = NEW.id) INTO v_cycle;

    IF v_cycle THEN
        RAISE EXCEPTION 'La jerarquia del plan de cuentas no puede contener ciclos';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.prevent_posted_journal_header_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_reversal_status text;
    v_reversal_of_entry_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('posted', 'reversed') THEN
            RAISE EXCEPTION 'No se puede eliminar un asiento contabilizado/revertido';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status IN ('posted', 'reversed') THEN
        IF (to_jsonb(NEW) - ARRAY['status', 'reversed_by_journal_entry_id', 'updated_at'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['status', 'reversed_by_journal_entry_id', 'updated_at']) THEN
            RAISE EXCEPTION 'No se puede modificar el contenido de un asiento contabilizado/revertido';
        END IF;
        IF OLD.status = 'reversed' AND NEW.status <> 'reversed' THEN
            RAISE EXCEPTION 'Un asiento revertido no puede volver a otro estado';
        END IF;
        IF NEW.status NOT IN (OLD.status, 'reversed') THEN
            RAISE EXCEPTION 'Transicion de estado no permitida para un asiento contabilizado';
        END IF;
        IF NEW.status = 'reversed' THEN
            SELECT status, reverses_journal_entry_id
              INTO v_reversal_status, v_reversal_of_entry_id
              FROM finance.journal_entries
             WHERE tenant_id = NEW.tenant_id
               AND accounting_book_id = NEW.accounting_book_id
               AND id = NEW.reversed_by_journal_entry_id;
            IF v_reversal_status <> 'posted' OR v_reversal_of_entry_id IS DISTINCT FROM NEW.id THEN
                RAISE EXCEPTION 'El asiento solo puede marcarse revertido cuando su asiento de reverso esta contabilizado y lo referencia';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.validate_journal_entry_for_posting()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_status text;
    v_fiscal_year_status text;
    v_period_start date;
    v_period_end date;
    v_original_entry_status text;
BEGIN
    IF NEW.status = 'posted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'posted') THEN
        SELECT p.status, p.starts_on, p.ends_on, fy.status
          INTO v_period_status, v_period_start, v_period_end, v_fiscal_year_status
          FROM finance.accounting_periods p
          JOIN finance.fiscal_years fy
            ON fy.tenant_id = p.tenant_id
           AND fy.accounting_book_id = p.accounting_book_id
           AND fy.id = p.fiscal_year_id
         WHERE p.tenant_id = NEW.tenant_id
           AND p.id = NEW.accounting_period_id
           AND p.accounting_book_id = NEW.accounting_book_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El periodo contable no existe para el libro indicado';
        END IF;
        IF v_period_status <> 'open' THEN
            RAISE EXCEPTION 'No se puede contabilizar en un periodo que no esta abierto';
        END IF;
        IF v_fiscal_year_status <> 'open' THEN
            RAISE EXCEPTION 'No se puede contabilizar en un ejercicio fiscal cerrado o bloqueado';
        END IF;
        IF NEW.entry_date < v_period_start OR NEW.entry_date > v_period_end THEN
            RAISE EXCEPTION 'La fecha del asiento esta fuera del periodo contable';
        END IF;
        IF NEW.company_id IS NULL THEN
            RAISE EXCEPTION 'Todo asiento debe identificar una empresa legal';
        END IF;
        IF NEW.reverses_journal_entry_id IS NOT NULL THEN
            SELECT status
              INTO v_original_entry_status
              FROM finance.journal_entries
             WHERE tenant_id = NEW.tenant_id
               AND accounting_book_id = NEW.accounting_book_id
               AND id = NEW.reverses_journal_entry_id;
            IF v_original_entry_status IS DISTINCT FROM 'posted' THEN
                RAISE EXCEPTION 'Un asiento de reverso solo puede contabilizarse si el original esta contabilizado';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.assert_journal_entry_balanced()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_entry_id uuid;
    v_status text;
    v_line_count bigint;
    v_debits numeric(24,4);
    v_credits numeric(24,4);
BEGIN
    IF TG_TABLE_NAME = 'journal_entries' THEN
        v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
        v_entry_id := COALESCE(NEW.id, OLD.id);
    ELSE
        v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
        v_entry_id := COALESCE(NEW.journal_entry_id, OLD.journal_entry_id);
    END IF;

    SELECT status INTO v_status
      FROM finance.journal_entries
     WHERE tenant_id = v_tenant_id AND id = v_entry_id;

    IF NOT FOUND OR v_status NOT IN ('posted', 'reversed') THEN
        RETURN NULL;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(debit_amount), 0), COALESCE(SUM(credit_amount), 0)
      INTO v_line_count, v_debits, v_credits
      FROM finance.journal_entry_lines
     WHERE tenant_id = v_tenant_id AND journal_entry_id = v_entry_id;

    IF v_line_count < 2 OR v_debits <= 0 OR v_credits <= 0 OR v_debits <> v_credits THEN
        RAISE EXCEPTION 'El asiento % no esta balanceado: lineas %, debitos %, creditos %',
            v_entry_id, v_line_count, v_debits, v_credits;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION finance.validate_application_reversal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_amount numeric(24,4);
    v_currency_code char(3);
    v_reversal_of_application_id uuid;
BEGIN
    IF NEW.reversal_of_application_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'receivable_applications' THEN
        SELECT amount, currency_code, reversal_of_application_id
          INTO v_amount, v_currency_code, v_reversal_of_application_id
          FROM finance.receivable_applications
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.reversal_of_application_id;
    ELSE
        SELECT amount, currency_code, reversal_of_application_id
          INTO v_amount, v_currency_code, v_reversal_of_application_id
          FROM finance.payable_applications
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.reversal_of_application_id;
    END IF;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La aplicacion original que se desea revertir no existe';
    END IF;
    IF v_reversal_of_application_id IS NOT NULL THEN
        RAISE EXCEPTION 'No se puede revertir una aplicacion que ya es un reverso';
    END IF;
    IF NEW.amount IS DISTINCT FROM v_amount OR NEW.currency_code IS DISTINCT FROM v_currency_code THEN
        RAISE EXCEPTION 'El reverso debe coincidir con el importe y moneda de la aplicacion original';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion financiera por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE finance.tenant_settings (
    tenant_id uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_currency_code char(3),
    accounting_basis varchar(20) NOT NULL DEFAULT 'accrual',
    default_fiscal_year_start_month smallint NOT NULL DEFAULT 1,
    allow_backdated_entries boolean NOT NULL DEFAULT false,
    require_journal_approval boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT finance_tenant_currency_format CHECK (default_currency_code IS NULL OR default_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT finance_tenant_basis_check CHECK (accounting_basis IN ('accrual', 'cash', 'mixed')),
    CONSTRAINT finance_tenant_year_month_check CHECK (default_fiscal_year_start_month BETWEEN 1 AND 12)
);

-- ---------------------------------------------------------------------------
-- 2. Libros contables, ejercicios y periodos
-- ---------------------------------------------------------------------------

CREATE TABLE finance.accounting_books (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL,
    book_code varchar(40) NOT NULL,
    name varchar(160) NOT NULL,
    functional_currency_code char(3) NOT NULL,
    accounting_basis varchar(20) NOT NULL DEFAULT 'accrual',
    fiscal_year_start_month smallint NOT NULL DEFAULT 1,
    decimal_places smallint NOT NULL DEFAULT 2,
    is_default boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT accounting_books_code_nonblank CHECK (btrim(book_code) <> ''),
    CONSTRAINT accounting_books_name_nonblank CHECK (btrim(name) <> ''),
    CONSTRAINT accounting_books_currency_format CHECK (functional_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT accounting_books_basis_check CHECK (accounting_basis IN ('accrual', 'cash', 'mixed')),
    CONSTRAINT accounting_books_year_month_check CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
    CONSTRAINT accounting_books_decimal_places_check CHECK (decimal_places BETWEEN 0 AND 4),
    CONSTRAINT uq_accounting_books_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_accounting_books_tenant_company_id UNIQUE (tenant_id, company_id, id),
    CONSTRAINT uq_accounting_books_code UNIQUE (tenant_id, company_id, book_code)
);
CREATE UNIQUE INDEX uq_accounting_books_default_company
    ON finance.accounting_books (tenant_id, company_id) WHERE is_default;

CREATE TABLE finance.fiscal_years (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    year_code varchar(20) NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    closed_at timestamptz,
    closed_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_year_dates_check CHECK (ends_on >= starts_on),
    CONSTRAINT fiscal_year_status_check CHECK (status IN ('open', 'closed', 'locked')),
    CONSTRAINT fiscal_year_closed_at_check CHECK (status NOT IN ('closed', 'locked') OR closed_at IS NOT NULL),
    CONSTRAINT fiscal_year_code_nonblank CHECK (btrim(year_code) <> ''),
    CONSTRAINT uq_fiscal_years_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_fiscal_years_code UNIQUE (tenant_id, accounting_book_id, year_code),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.accounting_periods (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    fiscal_year_id uuid NOT NULL,
    period_code varchar(30) NOT NULL,
    name varchar(100) NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    closed_at timestamptz,
    closed_by_user_id uuid,
    reopened_at timestamptz,
    reopened_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT accounting_period_dates_check CHECK (ends_on >= starts_on),
    CONSTRAINT accounting_period_status_check CHECK (status IN ('open', 'soft_closed', 'closed', 'locked')),
    CONSTRAINT accounting_period_closed_at_check CHECK (status NOT IN ('closed', 'locked') OR closed_at IS NOT NULL),
    CONSTRAINT accounting_period_code_nonblank CHECK (btrim(period_code) <> ''),
    CONSTRAINT uq_accounting_periods_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_accounting_periods_code UNIQUE (tenant_id, accounting_book_id, period_code),
    FOREIGN KEY (tenant_id, accounting_book_id, fiscal_year_id)
        REFERENCES finance.fiscal_years (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION finance.validate_accounting_period_bounds()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_year_start date;
    v_year_end date;
BEGIN
    SELECT starts_on, ends_on
      INTO v_year_start, v_year_end
      FROM finance.fiscal_years
     WHERE tenant_id = NEW.tenant_id
       AND accounting_book_id = NEW.accounting_book_id
       AND id = NEW.fiscal_year_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ejercicio fiscal no existe para el libro indicado';
    END IF;
    IF NEW.starts_on < v_year_start OR NEW.ends_on > v_year_end THEN
        RAISE EXCEPTION 'El periodo contable debe estar contenido en su ejercicio fiscal';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_finance_accounting_period_bounds
    BEFORE INSERT OR UPDATE OF accounting_book_id, fiscal_year_id, starts_on, ends_on
    ON finance.accounting_periods
    FOR EACH ROW EXECUTE FUNCTION finance.validate_accounting_period_bounds();

CREATE OR REPLACE FUNCTION finance.validate_fiscal_year_period_bounds()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM finance.accounting_periods p
         WHERE p.tenant_id = NEW.tenant_id
           AND p.accounting_book_id = NEW.accounting_book_id
           AND p.fiscal_year_id = NEW.id
           AND (p.starts_on < NEW.starts_on OR p.ends_on > NEW.ends_on)
    ) THEN
        RAISE EXCEPTION 'No se puede acortar un ejercicio fiscal por debajo de sus periodos contables';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_finance_fiscal_year_period_bounds
    BEFORE UPDATE OF starts_on, ends_on ON finance.fiscal_years
    FOR EACH ROW EXECUTE FUNCTION finance.validate_fiscal_year_period_bounds();

-- ---------------------------------------------------------------------------
-- 3. Plan de cuentas, mapeos y centros de costo
-- ---------------------------------------------------------------------------

CREATE TABLE finance.chart_of_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    parent_account_id uuid,
    account_code varchar(40) NOT NULL,
    name varchar(180) NOT NULL,
    description text,
    account_type varchar(20) NOT NULL,
    normal_balance varchar(10) NOT NULL,
    is_control_account boolean NOT NULL DEFAULT false,
    allow_manual_posting boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chart_account_code_nonblank CHECK (btrim(account_code) <> ''),
    CONSTRAINT chart_account_name_nonblank CHECK (btrim(name) <> ''),
    CONSTRAINT chart_account_type_check CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense', 'contra_asset', 'contra_revenue', 'contra_expense')),
    CONSTRAINT chart_account_normal_balance_check CHECK (normal_balance IN ('debit', 'credit')),
    CONSTRAINT chart_account_not_own_parent CHECK (parent_account_id IS NULL OR parent_account_id <> id),
    CONSTRAINT uq_chart_accounts_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_chart_accounts_code UNIQUE (tenant_id, accounting_book_id, account_code),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, parent_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.account_mappings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    mapping_code varchar(80) NOT NULL,
    description varchar(180),
    chart_account_id uuid NOT NULL,
    source_module varchar(60),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT account_mappings_code_nonblank CHECK (btrim(mapping_code) <> ''),
    CONSTRAINT uq_account_mappings_code UNIQUE (tenant_id, accounting_book_id, mapping_code),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, chart_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.cost_centers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    parent_cost_center_id uuid,
    cost_center_code varchar(40) NOT NULL,
    name varchar(160) NOT NULL,
    company_id uuid,
    branch_id uuid,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cost_center_code_nonblank CHECK (btrim(cost_center_code) <> ''),
    CONSTRAINT cost_center_name_nonblank CHECK (btrim(name) <> ''),
    CONSTRAINT cost_center_not_own_parent CHECK (parent_cost_center_id IS NULL OR parent_cost_center_id <> id),
    CONSTRAINT cost_center_branch_requires_company CHECK (branch_id IS NULL OR company_id IS NOT NULL),
    CONSTRAINT uq_cost_centers_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_cost_centers_code UNIQUE (tenant_id, accounting_book_id, cost_center_code),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, company_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, parent_cost_center_id)
        REFERENCES finance.cost_centers (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION finance.prevent_cost_center_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cycle boolean;
BEGIN
    IF NEW.parent_cost_center_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.parent_cost_center_id = NEW.id THEN
        RAISE EXCEPTION 'Un centro de costo no puede ser su propio padre';
    END IF;

    WITH RECURSIVE ancestors(id, parent_cost_center_id) AS (
        SELECT c.id, c.parent_cost_center_id
          FROM finance.cost_centers c
         WHERE c.tenant_id = NEW.tenant_id
           AND c.accounting_book_id = NEW.accounting_book_id
           AND c.id = NEW.parent_cost_center_id
        UNION
        SELECT c.id, c.parent_cost_center_id
          FROM finance.cost_centers c
          JOIN ancestors a ON c.id = a.parent_cost_center_id
         WHERE c.tenant_id = NEW.tenant_id
           AND c.accounting_book_id = NEW.accounting_book_id
    )
    SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = NEW.id) INTO v_cycle;

    IF v_cycle THEN
        RAISE EXCEPTION 'La jerarquia de centros de costo no puede contener ciclos';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_finance_cost_center_cycle
    BEFORE INSERT OR UPDATE OF parent_cost_center_id ON finance.cost_centers
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_cost_center_cycle();

-- ---------------------------------------------------------------------------
-- 4. Impuestos y tipos de cambio
-- ---------------------------------------------------------------------------

CREATE TABLE finance.tax_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tax_code varchar(50) NOT NULL,
    name varchar(160) NOT NULL,
    description text,
    tax_kind varchar(30) NOT NULL DEFAULT 'vat',
    is_recoverable boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_categories_code_nonblank CHECK (btrim(tax_code) <> ''),
    CONSTRAINT tax_categories_kind_check CHECK (tax_kind IN ('vat', 'sales_tax', 'withholding', 'excise', 'municipal', 'other')),
    CONSTRAINT uq_tax_categories_code UNIQUE (tenant_id, tax_code),
    CONSTRAINT uq_tax_categories_tenant_id UNIQUE (tenant_id, id)
);

CREATE TABLE finance.tax_rates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tax_category_id uuid NOT NULL,
    rate_code varchar(50) NOT NULL,
    name varchar(160) NOT NULL,
    rate_percent numeric(12,6) NOT NULL,
    applies_to varchar(20) NOT NULL DEFAULT 'both',
    jurisdiction_code varchar(80),
    effective_from date NOT NULL,
    effective_to date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_rates_percent_check CHECK (rate_percent >= 0 AND rate_percent <= 100),
    CONSTRAINT tax_rates_dates_check CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT tax_rates_applies_check CHECK (applies_to IN ('sales', 'purchases', 'both')),
    CONSTRAINT tax_rates_code_nonblank CHECK (btrim(rate_code) <> ''),
    CONSTRAINT uq_tax_rates_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_tax_rates_code UNIQUE (tenant_id, tax_category_id, rate_code, effective_from),
    FOREIGN KEY (tenant_id, tax_category_id)
        REFERENCES finance.tax_categories (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.exchange_rates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    from_currency_code char(3) NOT NULL,
    to_currency_code char(3) NOT NULL,
    rate_date date NOT NULL,
    rate_type varchar(20) NOT NULL DEFAULT 'spot',
    exchange_rate numeric(24,10) NOT NULL,
    source_name varchar(120),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT exchange_rates_currency_check CHECK (from_currency_code ~ '^[A-Z]{3}$' AND to_currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT exchange_rates_different_currency CHECK (from_currency_code <> to_currency_code),
    CONSTRAINT exchange_rates_positive CHECK (exchange_rate > 0),
    CONSTRAINT exchange_rates_type_check CHECK (rate_type IN ('spot', 'closing', 'average', 'contractual', 'manual')),
    CONSTRAINT uq_exchange_rates UNIQUE (tenant_id, from_currency_code, to_currency_code, rate_date, rate_type)
);

-- ---------------------------------------------------------------------------
-- 5. Lotes de contabilizacion y libro diario (partida doble)
-- ---------------------------------------------------------------------------

CREATE TABLE finance.posting_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    batch_code varchar(60) NOT NULL,
    source_module varchar(60) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'pending',
    total_entries integer NOT NULL DEFAULT 0,
    started_at timestamptz,
    completed_at timestamptz,
    error_summary text,
    created_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT posting_batches_code_nonblank CHECK (btrim(batch_code) <> ''),
    CONSTRAINT posting_batches_status_check CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    CONSTRAINT posting_batches_entries_nonnegative CHECK (total_entries >= 0),
    CONSTRAINT uq_posting_batches_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_posting_batches_code UNIQUE (tenant_id, accounting_book_id, batch_code),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.journal_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    accounting_period_id uuid NOT NULL,
    posting_batch_id uuid,
    company_id uuid NOT NULL,
    branch_id uuid,
    entry_number varchar(60) NOT NULL,
    entry_date date NOT NULL,
    document_date date,
    description varchar(500) NOT NULL,
    source_module varchar(60) NOT NULL DEFAULT 'manual',
    source_document_id uuid,
    source_event_id varchar(160),
    status varchar(20) NOT NULL DEFAULT 'draft',
    is_adjustment boolean NOT NULL DEFAULT false,
    reverses_journal_entry_id uuid,
    reversed_by_journal_entry_id uuid,
    created_by_user_id uuid,
    approved_by_user_id uuid,
    approved_at timestamptz,
    posted_by_user_id uuid,
    posted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT journal_entries_number_nonblank CHECK (btrim(entry_number) <> ''),
    CONSTRAINT journal_entries_description_nonblank CHECK (btrim(description) <> ''),
    CONSTRAINT journal_entries_source_nonblank CHECK (btrim(source_module) <> ''),
    CONSTRAINT journal_entries_status_check CHECK (status IN ('draft', 'pending_approval', 'approved', 'posted', 'reversed', 'void')),
    CONSTRAINT journal_entries_not_self_reversal CHECK (reverses_journal_entry_id IS NULL OR reverses_journal_entry_id <> id),
    CONSTRAINT journal_entries_reversed_by_check CHECK ((status = 'reversed') = (reversed_by_journal_entry_id IS NOT NULL)),
    CONSTRAINT journal_entries_posted_at_check CHECK (status NOT IN ('posted', 'reversed') OR posted_at IS NOT NULL),
    CONSTRAINT uq_journal_entries_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_journal_entries_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_journal_entries_number UNIQUE (tenant_id, accounting_book_id, entry_number),
    FOREIGN KEY (tenant_id, company_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, accounting_period_id)
        REFERENCES finance.accounting_periods (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, posting_batch_id)
        REFERENCES finance.posting_batches (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, reverses_journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, reversed_by_journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_journal_entries_source_event
    ON finance.journal_entries (tenant_id, source_module, source_event_id)
    WHERE source_event_id IS NOT NULL;
CREATE UNIQUE INDEX uq_journal_entries_single_reversal
    ON finance.journal_entries (tenant_id, accounting_book_id, reverses_journal_entry_id)
    WHERE reverses_journal_entry_id IS NOT NULL;

CREATE TABLE finance.journal_entry_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    journal_entry_id uuid NOT NULL,
    line_number integer NOT NULL,
    chart_account_id uuid NOT NULL,
    cost_center_id uuid,
    description varchar(500),
    currency_code char(3) NOT NULL,
    exchange_rate numeric(24,10) NOT NULL DEFAULT 1,
    original_amount numeric(24,4) NOT NULL,
    debit_amount numeric(24,4) NOT NULL DEFAULT 0,
    credit_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_rate_id uuid,
    party_type varchar(20),
    party_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT journal_lines_number_positive CHECK (line_number > 0),
    CONSTRAINT journal_lines_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT journal_lines_exchange_rate_positive CHECK (exchange_rate > 0),
    CONSTRAINT journal_lines_original_amount_positive CHECK (original_amount > 0),
    CONSTRAINT journal_lines_debit_credit_check CHECK (
        debit_amount >= 0 AND credit_amount >= 0 AND
        ((debit_amount > 0 AND credit_amount = 0) OR (credit_amount > 0 AND debit_amount = 0))
    ),
    CONSTRAINT journal_lines_party_type_check CHECK (party_type IS NULL OR party_type IN ('customer', 'supplier', 'employee', 'other')),
    CONSTRAINT uq_journal_entry_lines_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_journal_entry_lines_number UNIQUE (tenant_id, journal_entry_id, line_number),
    FOREIGN KEY (tenant_id, accounting_book_id, journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, chart_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, cost_center_id)
        REFERENCES finance.cost_centers (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, tax_rate_id)
        REFERENCES finance.tax_rates (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.journal_entry_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    journal_entry_id uuid NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason text,
    changed_by_user_id uuid,
    changed_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT journal_history_to_status_check CHECK (to_status IN ('draft', 'pending_approval', 'approved', 'posted', 'reversed', 'void')),
    FOREIGN KEY (tenant_id, journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 6. Cuentas por cobrar (cliente es referencia logica a Customers)
-- ---------------------------------------------------------------------------

CREATE TABLE finance.receivable_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    control_account_id uuid NOT NULL,
    credit_limit numeric(24,4),
    payment_terms_days integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivable_accounts_credit_limit_check CHECK (credit_limit IS NULL OR credit_limit >= 0),
    CONSTRAINT receivable_accounts_terms_check CHECK (payment_terms_days >= 0),
    CONSTRAINT uq_receivable_accounts_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_receivable_accounts_customer UNIQUE (tenant_id, accounting_book_id, customer_id),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, control_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.receivables (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    receivable_account_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid,
    document_type varchar(30) NOT NULL DEFAULT 'invoice',
    document_number varchar(80) NOT NULL,
    source_module varchar(60) NOT NULL,
    source_document_id uuid,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    currency_code char(3) NOT NULL,
    exchange_rate numeric(24,10) NOT NULL DEFAULT 1,
    subtotal_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_amount numeric(24,4) NOT NULL,
    outstanding_amount numeric(24,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    journal_entry_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivables_dates_check CHECK (due_date >= issue_date),
    CONSTRAINT receivables_amounts_check CHECK (subtotal_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0 AND outstanding_amount >= 0 AND outstanding_amount <= total_amount),
    CONSTRAINT receivables_total_check CHECK (total_amount = subtotal_amount + tax_amount),
    CONSTRAINT receivables_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT receivables_exchange_rate_check CHECK (exchange_rate > 0),
    CONSTRAINT receivables_type_check CHECK (document_type IN ('invoice', 'debit_note', 'interest', 'other')),
    CONSTRAINT receivables_status_check CHECK (status IN ('draft', 'open', 'partially_paid', 'paid', 'overdue', 'cancelled', 'written_off')),
    CONSTRAINT receivables_status_balance_check CHECK (
        (status IN ('paid', 'written_off') AND outstanding_amount = 0)
        OR (status = 'partially_paid' AND outstanding_amount > 0 AND outstanding_amount < total_amount)
        OR (status IN ('open', 'overdue') AND outstanding_amount > 0)
        OR status IN ('draft', 'cancelled')
    ),
    CONSTRAINT uq_receivables_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_receivables_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_receivables_number UNIQUE (tenant_id, accounting_book_id, document_type, document_number),
    FOREIGN KEY (tenant_id, company_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, receivable_account_id)
        REFERENCES finance.receivable_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.receivable_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    receivable_id uuid NOT NULL,
    line_number integer NOT NULL,
    description varchar(300) NOT NULL,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    unit_price numeric(24,4) NOT NULL,
    tax_rate_id uuid,
    tax_amount numeric(24,4) NOT NULL DEFAULT 0,
    line_total numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivable_lines_number_positive CHECK (line_number > 0),
    CONSTRAINT receivable_lines_values_check CHECK (quantity > 0 AND unit_price >= 0 AND tax_amount >= 0 AND line_total = round(quantity * unit_price + tax_amount, 4)),
    CONSTRAINT uq_receivable_lines_number UNIQUE (tenant_id, receivable_id, line_number),
    FOREIGN KEY (tenant_id, receivable_id)
        REFERENCES finance.receivables (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, tax_rate_id)
        REFERENCES finance.tax_rates (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.receivable_installments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    receivable_id uuid NOT NULL,
    installment_number integer NOT NULL,
    due_date date NOT NULL,
    amount numeric(24,4) NOT NULL,
    settled_amount numeric(24,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivable_installments_number_positive CHECK (installment_number > 0),
    CONSTRAINT receivable_installments_amounts_check CHECK (amount > 0 AND settled_amount >= 0 AND settled_amount <= amount),
    CONSTRAINT receivable_installments_status_check CHECK (status IN ('open', 'partially_settled', 'settled', 'overdue', 'cancelled')),
    CONSTRAINT receivable_installments_status_amount_check CHECK (
        (status = 'settled' AND settled_amount = amount)
        OR (status = 'partially_settled' AND settled_amount > 0 AND settled_amount < amount)
        OR (status = 'open' AND settled_amount = 0)
        OR (status = 'overdue' AND settled_amount < amount)
        OR status = 'cancelled'
    ),
    CONSTRAINT uq_receivable_installments_tenant_id UNIQUE (tenant_id, receivable_id, id),
    CONSTRAINT uq_receivable_installments_number UNIQUE (tenant_id, receivable_id, installment_number),
    FOREIGN KEY (tenant_id, receivable_id)
        REFERENCES finance.receivables (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.receivable_applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    receivable_id uuid NOT NULL,
    installment_id uuid,
    payment_transaction_id uuid,
    external_payment_reference varchar(160),
    applied_at timestamptz NOT NULL DEFAULT now(),
    amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL,
    applied_by_user_id uuid,
    reversal_of_application_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivable_applications_amount_check CHECK (amount > 0),
    CONSTRAINT receivable_applications_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT receivable_applications_not_self_reversal CHECK (reversal_of_application_id IS NULL OR reversal_of_application_id <> id),
    CONSTRAINT uq_receivable_applications_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_receivable_applications_account_id UNIQUE (tenant_id, receivable_id, id),
    FOREIGN KEY (tenant_id, receivable_id)
        REFERENCES finance.receivables (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receivable_id, installment_id)
        REFERENCES finance.receivable_installments (tenant_id, receivable_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receivable_id, reversal_of_application_id)
        REFERENCES finance.receivable_applications (tenant_id, receivable_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_receivable_application_single_reversal
    ON finance.receivable_applications (tenant_id, reversal_of_application_id)
    WHERE reversal_of_application_id IS NOT NULL;

CREATE TABLE finance.receivable_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    receivable_id uuid NOT NULL,
    adjustment_type varchar(20) NOT NULL,
    amount numeric(24,4) NOT NULL,
    reason text NOT NULL,
    journal_entry_id uuid,
    created_by_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT receivable_adjustments_type_check CHECK (adjustment_type IN ('credit_note', 'write_off', 'interest', 'correction')),
    CONSTRAINT receivable_adjustments_amount_check CHECK (amount > 0),
    CONSTRAINT receivable_adjustments_reason_nonblank CHECK (btrim(reason) <> ''),
    FOREIGN KEY (tenant_id, receivable_id)
        REFERENCES finance.receivables (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 7. Cuentas por pagar (proveedor es referencia logica a Procurement)
-- ---------------------------------------------------------------------------

CREATE TABLE finance.payable_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    control_account_id uuid NOT NULL,
    payment_terms_days integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payable_accounts_terms_check CHECK (payment_terms_days >= 0),
    CONSTRAINT uq_payable_accounts_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_payable_accounts_supplier UNIQUE (tenant_id, accounting_book_id, supplier_id),
    FOREIGN KEY (tenant_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, control_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.payables (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    payable_account_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid,
    document_type varchar(30) NOT NULL DEFAULT 'supplier_invoice',
    document_number varchar(80) NOT NULL,
    supplier_document_number varchar(100),
    source_module varchar(60) NOT NULL,
    source_document_id uuid,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    currency_code char(3) NOT NULL,
    exchange_rate numeric(24,10) NOT NULL DEFAULT 1,
    subtotal_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_amount numeric(24,4) NOT NULL,
    outstanding_amount numeric(24,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    journal_entry_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payables_dates_check CHECK (due_date >= issue_date),
    CONSTRAINT payables_amounts_check CHECK (subtotal_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0 AND outstanding_amount >= 0 AND outstanding_amount <= total_amount),
    CONSTRAINT payables_total_check CHECK (total_amount = subtotal_amount + tax_amount),
    CONSTRAINT payables_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT payables_exchange_rate_check CHECK (exchange_rate > 0),
    CONSTRAINT payables_type_check CHECK (document_type IN ('supplier_invoice', 'debit_note', 'expense', 'other')),
    CONSTRAINT payables_status_check CHECK (status IN ('draft', 'open', 'partially_paid', 'paid', 'overdue', 'cancelled', 'disputed')),
    CONSTRAINT payables_status_balance_check CHECK (
        (status = 'paid' AND outstanding_amount = 0)
        OR (status = 'partially_paid' AND outstanding_amount > 0 AND outstanding_amount < total_amount)
        OR (status IN ('open', 'overdue') AND outstanding_amount > 0)
        OR status IN ('draft', 'cancelled', 'disputed')
    ),
    CONSTRAINT uq_payables_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_payables_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    CONSTRAINT uq_payables_number UNIQUE (tenant_id, accounting_book_id, document_type, document_number),
    FOREIGN KEY (tenant_id, company_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, payable_account_id)
        REFERENCES finance.payable_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, journal_entry_id)
        REFERENCES finance.journal_entries (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.payable_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payable_id uuid NOT NULL,
    line_number integer NOT NULL,
    description varchar(300) NOT NULL,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    unit_price numeric(24,4) NOT NULL,
    tax_rate_id uuid,
    tax_amount numeric(24,4) NOT NULL DEFAULT 0,
    line_total numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payable_lines_number_positive CHECK (line_number > 0),
    CONSTRAINT payable_lines_values_check CHECK (quantity > 0 AND unit_price >= 0 AND tax_amount >= 0 AND line_total = round(quantity * unit_price + tax_amount, 4)),
    CONSTRAINT uq_payable_lines_number UNIQUE (tenant_id, payable_id, line_number),
    FOREIGN KEY (tenant_id, payable_id)
        REFERENCES finance.payables (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, tax_rate_id)
        REFERENCES finance.tax_rates (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.payable_installments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payable_id uuid NOT NULL,
    installment_number integer NOT NULL,
    due_date date NOT NULL,
    amount numeric(24,4) NOT NULL,
    settled_amount numeric(24,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payable_installments_number_positive CHECK (installment_number > 0),
    CONSTRAINT payable_installments_amounts_check CHECK (amount > 0 AND settled_amount >= 0 AND settled_amount <= amount),
    CONSTRAINT payable_installments_status_check CHECK (status IN ('open', 'partially_settled', 'settled', 'overdue', 'cancelled')),
    CONSTRAINT payable_installments_status_amount_check CHECK (
        (status = 'settled' AND settled_amount = amount)
        OR (status = 'partially_settled' AND settled_amount > 0 AND settled_amount < amount)
        OR (status = 'open' AND settled_amount = 0)
        OR (status = 'overdue' AND settled_amount < amount)
        OR status = 'cancelled'
    ),
    CONSTRAINT uq_payable_installments_tenant_id UNIQUE (tenant_id, payable_id, id),
    CONSTRAINT uq_payable_installments_number UNIQUE (tenant_id, payable_id, installment_number),
    FOREIGN KEY (tenant_id, payable_id)
        REFERENCES finance.payables (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.payable_applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    payable_id uuid NOT NULL,
    installment_id uuid,
    disbursement_id uuid,
    external_payment_reference varchar(160),
    applied_at timestamptz NOT NULL DEFAULT now(),
    amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL,
    applied_by_user_id uuid,
    reversal_of_application_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payable_applications_amount_check CHECK (amount > 0),
    CONSTRAINT payable_applications_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT payable_applications_not_self_reversal CHECK (reversal_of_application_id IS NULL OR reversal_of_application_id <> id),
    CONSTRAINT uq_payable_applications_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_payable_applications_account_id UNIQUE (tenant_id, payable_id, id),
    FOREIGN KEY (tenant_id, payable_id)
        REFERENCES finance.payables (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, payable_id, installment_id)
        REFERENCES finance.payable_installments (tenant_id, payable_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, payable_id, reversal_of_application_id)
        REFERENCES finance.payable_applications (tenant_id, payable_id, id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_payable_application_single_reversal
    ON finance.payable_applications (tenant_id, reversal_of_application_id)
    WHERE reversal_of_application_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Bancos, extractos y conciliacion
-- ---------------------------------------------------------------------------

CREATE TABLE finance.bank_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    accounting_book_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid,
    bank_code varchar(80),
    bank_name varchar(160) NOT NULL,
    account_label varchar(120) NOT NULL,
    account_type varchar(20) NOT NULL,
    currency_code char(3) NOT NULL,
    account_number_last4 varchar(4),
    encrypted_account_reference text,
    secret_reference varchar(300),
    chart_account_id uuid NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_accounts_type_check CHECK (account_type IN ('checking', 'savings', 'wallet', 'other')),
    CONSTRAINT bank_accounts_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT bank_accounts_last4_check CHECK (account_number_last4 IS NULL OR account_number_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT uq_bank_accounts_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_bank_accounts_tenant_book_id UNIQUE (tenant_id, accounting_book_id, id),
    FOREIGN KEY (tenant_id, company_id, accounting_book_id)
        REFERENCES finance.accounting_books (tenant_id, company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, accounting_book_id, chart_account_id)
        REFERENCES finance.chart_of_accounts (tenant_id, accounting_book_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.bank_statement_imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    bank_account_id uuid NOT NULL,
    source_file_reference varchar(500),
    source_format varchar(30),
    statement_start_date date NOT NULL,
    statement_end_date date NOT NULL,
    opening_balance numeric(24,4) NOT NULL,
    closing_balance numeric(24,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'imported',
    imported_by_user_id uuid,
    imported_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_statement_import_dates_check CHECK (statement_end_date >= statement_start_date),
    CONSTRAINT bank_statement_import_status_check CHECK (status IN ('imported', 'reviewing', 'reconciled', 'rejected')),
    CONSTRAINT uq_bank_statement_imports_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_bank_statement_imports_account_id UNIQUE (tenant_id, bank_account_id, id),
    FOREIGN KEY (tenant_id, bank_account_id)
        REFERENCES finance.bank_accounts (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.bank_statement_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    bank_statement_import_id uuid NOT NULL,
    line_number integer NOT NULL,
    external_transaction_id varchar(160),
    transaction_date date NOT NULL,
    value_date date,
    description varchar(500),
    reference_text varchar(180),
    debit_amount numeric(24,4) NOT NULL DEFAULT 0,
    credit_amount numeric(24,4) NOT NULL DEFAULT 0,
    running_balance numeric(24,4),
    currency_code char(3) NOT NULL,
    is_reconciled boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_statement_lines_number_positive CHECK (line_number > 0),
    CONSTRAINT bank_statement_lines_amount_check CHECK (debit_amount >= 0 AND credit_amount >= 0 AND NOT (debit_amount > 0 AND credit_amount > 0)),
    CONSTRAINT bank_statement_lines_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT uq_bank_statement_lines_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_bank_statement_lines_number UNIQUE (tenant_id, bank_statement_import_id, line_number),
    FOREIGN KEY (tenant_id, bank_statement_import_id)
        REFERENCES finance.bank_statement_imports (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.bank_reconciliations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    bank_account_id uuid NOT NULL,
    bank_statement_import_id uuid NOT NULL,
    reconciliation_code varchar(60) NOT NULL,
    statement_closing_balance numeric(24,4) NOT NULL,
    book_closing_balance numeric(24,4) NOT NULL,
    difference_amount numeric(24,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'draft',
    reconciled_by_user_id uuid,
    reconciled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_reconciliations_status_check CHECK (status IN ('draft', 'in_progress', 'completed', 'approved', 'cancelled')),
    CONSTRAINT bank_reconciliations_review_check CHECK (
        status NOT IN ('completed', 'approved')
        OR (reconciled_by_user_id IS NOT NULL AND reconciled_at IS NOT NULL)
    ),
    CONSTRAINT bank_reconciliations_code_nonblank CHECK (btrim(reconciliation_code) <> ''),
    CONSTRAINT uq_bank_reconciliations_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_bank_reconciliations_code UNIQUE (tenant_id, bank_account_id, reconciliation_code),
    FOREIGN KEY (tenant_id, bank_account_id)
        REFERENCES finance.bank_accounts (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, bank_account_id, bank_statement_import_id)
        REFERENCES finance.bank_statement_imports (tenant_id, bank_account_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.bank_reconciliation_matches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    bank_reconciliation_id uuid NOT NULL,
    bank_statement_line_id uuid NOT NULL,
    journal_entry_line_id uuid,
    match_type varchar(20) NOT NULL DEFAULT 'exact',
    matched_amount numeric(24,4) NOT NULL,
    matched_by_user_id uuid,
    matched_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_reconciliation_matches_type_check CHECK (match_type IN ('exact', 'partial', 'grouped', 'manual')),
    CONSTRAINT bank_reconciliation_matches_amount_check CHECK (matched_amount > 0),
    CONSTRAINT uq_bank_reconciliation_matches_line UNIQUE (tenant_id, bank_reconciliation_id, bank_statement_line_id, journal_entry_line_id),
    FOREIGN KEY (tenant_id, bank_reconciliation_id)
        REFERENCES finance.bank_reconciliations (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, bank_statement_line_id)
        REFERENCES finance.bank_statement_lines (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, journal_entry_line_id)
        REFERENCES finance.journal_entry_lines (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 9. Periodos y declaraciones tributarias
-- ---------------------------------------------------------------------------

CREATE TABLE finance.tax_periods (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id uuid NOT NULL,
    jurisdiction_code varchar(80) NOT NULL,
    tax_kind varchar(30) NOT NULL,
    period_code varchar(30) NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_period_dates_check CHECK (ends_on >= starts_on),
    CONSTRAINT tax_period_status_check CHECK (status IN ('open', 'prepared', 'filed', 'closed')),
    CONSTRAINT tax_period_code_nonblank CHECK (btrim(period_code) <> ''),
    CONSTRAINT uq_tax_periods_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_tax_periods_company_period UNIQUE (tenant_id, company_id, jurisdiction_code, tax_kind, period_code)
);

CREATE TABLE finance.tax_filings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tax_period_id uuid NOT NULL,
    filing_number varchar(100),
    filing_date date,
    due_date date,
    currency_code char(3) NOT NULL,
    taxable_base_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_due_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_credit_amount numeric(24,4) NOT NULL DEFAULT 0,
    net_payable_amount numeric(24,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'draft',
    external_confirmation_reference varchar(160),
    prepared_by_user_id uuid,
    submitted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_filings_currency_check CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT tax_filings_amounts_check CHECK (
        taxable_base_amount >= 0 AND tax_due_amount >= 0 AND tax_credit_amount >= 0
        AND net_payable_amount = GREATEST(tax_due_amount - tax_credit_amount, 0)
    ),
    CONSTRAINT tax_filings_status_check CHECK (status IN ('draft', 'reviewed', 'submitted', 'accepted', 'rejected', 'amended')),
    CONSTRAINT tax_filings_submission_check CHECK (
        status NOT IN ('submitted', 'accepted', 'rejected') OR submitted_at IS NOT NULL
    ),
    CONSTRAINT uq_tax_filings_tenant_id UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, tax_period_id)
        REFERENCES finance.tax_periods (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE finance.tax_filing_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tax_filing_id uuid NOT NULL,
    tax_category_id uuid,
    tax_rate_id uuid,
    line_code varchar(80) NOT NULL,
    description varchar(300),
    taxable_base_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_due_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_credit_amount numeric(24,4) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_filing_lines_code_nonblank CHECK (btrim(line_code) <> ''),
    CONSTRAINT tax_filing_lines_amounts_check CHECK (taxable_base_amount >= 0 AND tax_due_amount >= 0 AND tax_credit_amount >= 0),
    CONSTRAINT uq_tax_filing_lines_code UNIQUE (tenant_id, tax_filing_id, line_code),
    FOREIGN KEY (tenant_id, tax_filing_id)
        REFERENCES finance.tax_filings (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, tax_category_id)
        REFERENCES finance.tax_categories (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, tax_rate_id)
        REFERENCES finance.tax_rates (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 10. Inbox, Outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE finance.processed_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    consumer_name varchar(120) NOT NULL,
    event_id varchar(180) NOT NULL,
    event_type varchar(160) NOT NULL,
    payload_hash varchar(128),
    processed_at timestamptz NOT NULL DEFAULT now(),
    result_reference_id uuid,
    CONSTRAINT processed_events_consumer_nonblank CHECK (btrim(consumer_name) <> ''),
    CONSTRAINT processed_events_id_nonblank CHECK (btrim(event_id) <> ''),
    CONSTRAINT uq_finance_processed_events UNIQUE (tenant_id, consumer_name, event_id)
);

CREATE TABLE finance.event_outbox (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type varchar(100) NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type varchar(180) NOT NULL,
    event_version integer NOT NULL DEFAULT 1,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    available_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    publish_attempts integer NOT NULL DEFAULT 0,
    last_error text,
    CONSTRAINT event_outbox_version_positive CHECK (event_version > 0),
    CONSTRAINT event_outbox_attempts_nonnegative CHECK (publish_attempts >= 0),
    CONSTRAINT uq_finance_event_outbox_event UNIQUE (tenant_id, id)
);

CREATE TABLE finance.idempotency_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    operation_scope varchar(120) NOT NULL,
    idempotency_key varchar(180) NOT NULL,
    request_hash varchar(128) NOT NULL,
    response_status integer,
    response_body jsonb,
    resource_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    CONSTRAINT idempotency_scope_nonblank CHECK (btrim(operation_scope) <> ''),
    CONSTRAINT idempotency_key_nonblank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT uq_finance_idempotency UNIQUE (tenant_id, operation_scope, idempotency_key)
);

-- ---------------------------------------------------------------------------
-- 11. Indices operativos
-- ---------------------------------------------------------------------------

CREATE INDEX ix_fiscal_years_book_dates ON finance.fiscal_years (tenant_id, accounting_book_id, starts_on, ends_on);
CREATE INDEX ix_accounting_periods_book_dates ON finance.accounting_periods (tenant_id, accounting_book_id, starts_on, ends_on, status);
CREATE INDEX ix_chart_accounts_parent ON finance.chart_of_accounts (tenant_id, accounting_book_id, parent_account_id);
CREATE INDEX ix_account_mappings_source ON finance.account_mappings (tenant_id, source_module, is_active);
CREATE INDEX ix_cost_centers_branch ON finance.cost_centers (tenant_id, branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX ix_tax_rates_effective ON finance.tax_rates (tenant_id, tax_category_id, effective_from, effective_to) WHERE is_active;
CREATE INDEX ix_exchange_rates_lookup ON finance.exchange_rates (tenant_id, from_currency_code, to_currency_code, rate_date DESC);
CREATE INDEX ix_posting_batches_status ON finance.posting_batches (tenant_id, accounting_book_id, status, created_at DESC);
CREATE INDEX ix_journal_entries_date_status ON finance.journal_entries (tenant_id, accounting_book_id, entry_date, status);
CREATE INDEX ix_journal_entries_period ON finance.journal_entries (tenant_id, accounting_period_id, status);
CREATE INDEX ix_journal_entries_company_date ON finance.journal_entries (tenant_id, company_id, entry_date);
CREATE INDEX ix_journal_entries_branch_date ON finance.journal_entries (tenant_id, branch_id, entry_date) WHERE branch_id IS NOT NULL;
CREATE INDEX ix_journal_entry_lines_account ON finance.journal_entry_lines (tenant_id, accounting_book_id, chart_account_id);
CREATE INDEX ix_journal_entry_lines_cost_center ON finance.journal_entry_lines (tenant_id, cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX ix_journal_history_entry_date ON finance.journal_entry_status_history (tenant_id, journal_entry_id, changed_at DESC);
CREATE INDEX ix_receivables_customer_status ON finance.receivables (tenant_id, receivable_account_id, status, due_date);
CREATE INDEX ix_receivables_due ON finance.receivables (tenant_id, due_date) WHERE outstanding_amount > 0;
CREATE INDEX ix_receivable_installments_due ON finance.receivable_installments (tenant_id, due_date, status);
CREATE INDEX ix_receivable_applications_payment ON finance.receivable_applications (tenant_id, payment_transaction_id) WHERE payment_transaction_id IS NOT NULL;
CREATE INDEX ix_payables_supplier_status ON finance.payables (tenant_id, payable_account_id, status, due_date);
CREATE INDEX ix_payables_due ON finance.payables (tenant_id, due_date) WHERE outstanding_amount > 0;
CREATE INDEX ix_payable_installments_due ON finance.payable_installments (tenant_id, due_date, status);
CREATE INDEX ix_payable_applications_disbursement ON finance.payable_applications (tenant_id, disbursement_id) WHERE disbursement_id IS NOT NULL;
CREATE INDEX ix_bank_statement_lines_import_date ON finance.bank_statement_lines (tenant_id, bank_statement_import_id, transaction_date);
CREATE INDEX ix_bank_statement_lines_external ON finance.bank_statement_lines (tenant_id, external_transaction_id) WHERE external_transaction_id IS NOT NULL;
CREATE INDEX ix_bank_reconciliations_status ON finance.bank_reconciliations (tenant_id, bank_account_id, status, created_at DESC);
CREATE INDEX ix_bank_reconciliation_matches_statement ON finance.bank_reconciliation_matches (tenant_id, bank_statement_line_id);
CREATE INDEX ix_tax_periods_company_dates ON finance.tax_periods (tenant_id, company_id, starts_on, ends_on);
CREATE INDEX ix_tax_filings_period_status ON finance.tax_filings (tenant_id, tax_period_id, status);
CREATE INDEX ix_event_outbox_pending ON finance.event_outbox (tenant_id, available_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX ix_idempotency_expiry ON finance.idempotency_records (tenant_id, expires_at) WHERE expires_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 12. Triggers de integridad y reglas de contabilizacion
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'accounting_books', 'fiscal_years', 'accounting_periods',
        'chart_of_accounts', 'account_mappings', 'cost_centers', 'tax_categories',
        'tax_rates', 'posting_batches', 'journal_entries', 'receivable_accounts',
        'receivables', 'receivable_installments', 'payable_accounts', 'payables',
        'payable_installments', 'bank_accounts', 'bank_reconciliations',
        'tax_periods', 'tax_filings'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON finance.%I FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'accounting_books', 'fiscal_years', 'accounting_periods',
        'chart_of_accounts', 'account_mappings', 'cost_centers', 'tax_categories',
        'tax_rates', 'exchange_rates', 'posting_batches', 'journal_entries',
        'journal_entry_lines', 'journal_entry_status_history', 'receivable_accounts',
        'receivables', 'receivable_lines', 'receivable_installments',
        'receivable_applications', 'receivable_adjustments', 'payable_accounts',
        'payables', 'payable_lines', 'payable_installments', 'payable_applications',
        'bank_accounts', 'bank_statement_imports', 'bank_statement_lines',
        'bank_reconciliations', 'bank_reconciliation_matches', 'tax_periods',
        'tax_filings', 'tax_filing_lines', 'processed_events', 'event_outbox',
        'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON finance.%I FOR EACH ROW EXECUTE FUNCTION finance.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_finance_chart_account_cycle
    BEFORE INSERT OR UPDATE OF parent_account_id ON finance.chart_of_accounts
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_chart_account_cycle();

CREATE OR REPLACE FUNCTION finance.validate_bank_reconciliation_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_reconciliation_import_id uuid;
    v_statement_import_id uuid;
    v_bank_company_id uuid;
    v_bank_book_id uuid;
    v_entry_company_id uuid;
    v_entry_book_id uuid;
    v_entry_status text;
BEGIN
    SELECT r.bank_statement_import_id, b.company_id, b.accounting_book_id
      INTO v_reconciliation_import_id, v_bank_company_id, v_bank_book_id
      FROM finance.bank_reconciliations r
      JOIN finance.bank_accounts b
        ON b.tenant_id = r.tenant_id
       AND b.id = r.bank_account_id
     WHERE r.tenant_id = NEW.tenant_id
       AND r.id = NEW.bank_reconciliation_id;

    SELECT l.bank_statement_import_id
      INTO v_statement_import_id
      FROM finance.bank_statement_lines l
     WHERE l.tenant_id = NEW.tenant_id
       AND l.id = NEW.bank_statement_line_id;

    IF v_reconciliation_import_id IS DISTINCT FROM v_statement_import_id THEN
        RAISE EXCEPTION 'La linea bancaria debe pertenecer al extracto de la conciliacion';
    END IF;

    IF NEW.journal_entry_line_id IS NOT NULL THEN
        SELECT e.company_id, e.accounting_book_id, e.status
          INTO v_entry_company_id, v_entry_book_id, v_entry_status
          FROM finance.journal_entry_lines l
          JOIN finance.journal_entries e
            ON e.tenant_id = l.tenant_id
           AND e.accounting_book_id = l.accounting_book_id
           AND e.id = l.journal_entry_id
         WHERE l.tenant_id = NEW.tenant_id
           AND l.id = NEW.journal_entry_line_id;

        IF v_entry_status IS DISTINCT FROM 'posted'
           OR v_entry_company_id IS DISTINCT FROM v_bank_company_id
           OR v_entry_book_id IS DISTINCT FROM v_bank_book_id THEN
            RAISE EXCEPTION 'La linea contable debe ser de un asiento contabilizado en la misma empresa y libro de la cuenta bancaria';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_finance_bank_reconciliation_match_scope
    BEFORE INSERT OR UPDATE OF bank_reconciliation_id, bank_statement_line_id, journal_entry_line_id
    ON finance.bank_reconciliation_matches
    FOR EACH ROW EXECUTE FUNCTION finance.validate_bank_reconciliation_match();

CREATE TRIGGER trg_finance_journal_header_immutable
    BEFORE UPDATE OR DELETE ON finance.journal_entries
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_posted_journal_header_mutation();

CREATE TRIGGER trg_finance_journal_entry_posting_guard
    BEFORE INSERT OR UPDATE OF status ON finance.journal_entries
    FOR EACH ROW EXECUTE FUNCTION finance.validate_journal_entry_for_posting();

CREATE TRIGGER trg_finance_journal_lines_posted_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON finance.journal_entry_lines
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_posted_journal_mutation();

CREATE CONSTRAINT TRIGGER trg_finance_journal_lines_balance
    AFTER INSERT OR UPDATE OR DELETE ON finance.journal_entry_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION finance.assert_journal_entry_balanced();

CREATE CONSTRAINT TRIGGER trg_finance_journal_header_balance
    AFTER INSERT OR UPDATE OF status ON finance.journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION finance.assert_journal_entry_balanced();

CREATE TRIGGER trg_finance_journal_history_append_only
    BEFORE UPDATE OR DELETE ON finance.journal_entry_status_history
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_append_only_mutation();

CREATE TRIGGER trg_finance_processed_events_append_only
    BEFORE UPDATE OR DELETE ON finance.processed_events
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_append_only_mutation();

CREATE TRIGGER trg_finance_receivable_applications_append_only
    BEFORE UPDATE OR DELETE ON finance.receivable_applications
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_append_only_mutation();

CREATE TRIGGER trg_finance_receivable_application_reversal
    BEFORE INSERT ON finance.receivable_applications
    FOR EACH ROW EXECUTE FUNCTION finance.validate_application_reversal();

CREATE TRIGGER trg_finance_receivable_adjustments_append_only
    BEFORE UPDATE OR DELETE ON finance.receivable_adjustments
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_append_only_mutation();

CREATE TRIGGER trg_finance_payable_applications_append_only
    BEFORE UPDATE OR DELETE ON finance.payable_applications
    FOR EACH ROW EXECUTE FUNCTION finance.prevent_append_only_mutation();

CREATE TRIGGER trg_finance_payable_application_reversal
    BEFORE INSERT ON finance.payable_applications
    FOR EACH ROW EXECUTE FUNCTION finance.validate_application_reversal();

-- ---------------------------------------------------------------------------
-- 13. Inicializacion financiera de un tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION finance.initialize_tenant_finance(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR finance.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El contexto app.tenant_id debe coincidir con el tenant solicitado';
    END IF;

    INSERT INTO finance.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. Row Level Security: todas las tablas tenant-scoped
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'accounting_books', 'fiscal_years', 'accounting_periods',
        'chart_of_accounts', 'account_mappings', 'cost_centers', 'tax_categories',
        'tax_rates', 'exchange_rates', 'posting_batches', 'journal_entries',
        'journal_entry_lines', 'journal_entry_status_history', 'receivable_accounts',
        'receivables', 'receivable_lines', 'receivable_installments',
        'receivable_applications', 'receivable_adjustments', 'payable_accounts',
        'payables', 'payable_lines', 'payable_installments', 'payable_applications',
        'bank_accounts', 'bank_statement_imports', 'bank_statement_lines',
        'bank_reconciliations', 'bank_reconciliation_matches', 'tax_periods',
        'tax_filings', 'tax_filing_lines', 'processed_events', 'event_outbox',
        'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE finance.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE finance.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON finance.%I USING (tenant_id = finance.current_tenant_id()) WITH CHECK (tenant_id = finance.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 15. Comentarios de propiedad y contratos
-- ---------------------------------------------------------------------------

COMMENT ON TABLE finance.accounting_books IS
'Libro mayor por empresa legal. company_id es referencia logica a Organization; el libro y sus cuentas pertenecen a Finance.';
COMMENT ON TABLE finance.chart_of_accounts IS
'Plan de cuentas propio del libro contable. Las cuentas padre y las referencias de movimientos se validan dentro de Finance.';
COMMENT ON TABLE finance.journal_entries IS
'Cabecera de asiento de partida doble. Las referencias source_module/source_document_id identifican el origen sin FK a otros modulos.';
COMMENT ON TABLE finance.journal_entry_lines IS
'Lineas contables. Un asiento posted/reversed debe tener al menos dos lineas y total debitos igual a total creditos; las lineas contabilizadas son inmutables.';
COMMENT ON TABLE finance.receivables IS
'Cuentas por cobrar. customer_id/source_document_id son referencias logicas; Payments procesa el cobro y Finance aplica la liquidacion a la cuenta.';
COMMENT ON TABLE finance.payables IS
'Cuentas por pagar. supplier_id se resuelve mediante Procurement; Payments/Integrations ejecutan el desembolso y Finance aplica la liquidacion.';
COMMENT ON TABLE finance.bank_accounts IS
'Cuenta bancaria financiera. No almacenar credenciales ni numero completo de cuenta en texto plano; utilizar referencia cifrada o KMS/Vault.';
COMMENT ON TABLE finance.bank_statement_lines IS
'Lineas importadas de un extracto bancario. No representan movimientos de Cash ni transacciones de Payments hasta su conciliacion.';
COMMENT ON TABLE finance.tax_filings IS
'Preparacion y seguimiento de declaraciones tributarias; la presentacion ante la autoridad fiscal se realiza mediante el flujo autorizado de Integrations o proceso manual.';
COMMENT ON TABLE finance.event_outbox IS
'Eventos de Finance confirmados dentro de la misma transaccion de negocio y publicados por un worker independiente.';

COMMIT;

-- ============================================================================
-- FIN MODULO 14: FINANCE
-- NOTA: requiere pruebas en PostgreSQL real antes de produccion.
-- ============================================================================
