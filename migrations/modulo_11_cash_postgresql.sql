-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 11: CASH (CAJAS, TURNOS, EFECTIVO, ARQUEOS Y MOVIMIENTOS)
-- Ubicacion del crate: crates/modules/cash
-- Motor objetivo: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants)
--   * Los modulos Organization, Identity, Sales, Payments, Finance e
--     Integrations se conectan mediante contratos publicos; no se crean FK
--     fisicas hacia sus tablas.
--
-- CODIGO DEL MODULO SAAS:
--   Debe registrarse 'cash' en platform.modules mediante una migracion
--   propiedad de Platform. Este archivo no modifica platform.modules.
--
-- RESPONSABILIDAD DE CASH:
--   * Cajas/terminales de efectivo por sucursal y moneda.
--   * Apertura, turnos, cajeros asignados, cierre y arqueos.
--   * Fondo inicial, entradas/salidas manuales y gastos menores en efectivo.
--   * Libro inmutable de movimientos del cajon.
--   * Traslados entre cajas y movimientos hacia/desde cajas fuertes.
--   * Conteo por denominaciones, diferencias y conciliacion de turno.
--   * Eventos de apertura de gaveta y auditoria operacional.
--   * Inbox, Outbox e idempotencia para eventos entre modulos/servicios.
--
-- FUERA DE ALCANCE:
--   * Ventas, pedidos y devoluciones comerciales: sales.
--   * Metodos de pago, cobros, capturas y reembolsos: payments.
--   * Contabilidad, bancos, cuentas por cobrar/pagar: finance.
--   * Terminales/dispositivos fisicos y sus credenciales: integrations.
--   * Usuarios, roles y permisos: identity.
--   * Existencias y movimientos de inventario: inventory.
--
-- LIMITES ENTRE MODULOS:
--   * Cash solo crea FK fisica a platform.tenants y a tablas propias.
--   * company_id, branch_id, user_id, terminal_id, payment_transaction_id,
--     payment_refund_id, sales_sale_id y source_reference_id son referencias
--     logicas validadas por puertos/contratos del modulo propietario.
--   * Cash no duplica transacciones de Payments. Consume eventos de pagos
--     cuyo metodo sea efectivo y registra el efecto sobre el cajon.
--   * Payments conserva la transaccion/reembolso; Cash conserva el movimiento
--     fisico de efectivo y el arqueo de la caja.
--   * La recepcion/entrega de efectivo y su efecto de caja deben procesarse
--     idempotentemente en una transaccion local del modulo Cash.
--
-- AISLAMIENTO Y SEGURIDAD:
--   * Todas las tablas tenant-scoped incluyen tenant_id y RLS + FORCE RLS.
--   * Cada transaccion autenticada ejecuta SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant se deriva de la sesion verificada; nunca confiar en el body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * RLS garantiza aislamiento por tenant; Rust valida permisos y alcance de
--     company_id/branch_id/registro/caja para cada operacion.
--
-- INSTALACION:
--   * Ejecutar despues de Platform. No depende de que Payments/Sales esten
--     instalados porque sus identificadores son referencias logicas.
--   * No ejecutar sobre un schema cash existente sin una migracion versionada.
--   * El SQL define estructura y guardas; los flujos multi-fila deben
--     implementarse en application/services y probarse con concurrencia real.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS cash;

COMMENT ON SCHEMA cash IS
'Administracion de cajas, turnos, efectivo, arqueos, gastos menores y traslados fisicos. No procesa cobros ni administra bancos/contabilidad.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION cash.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION cash.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION cash.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Cash';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION cash.prevent_scope_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_field text;
BEGIN
    FOREACH v_field IN ARRAY ARRAY[
        'tenant_id', 'company_id', 'branch_id', 'cash_register_id',
        'cash_session_id', 'safe_id'
    ] LOOP
        IF (to_jsonb(NEW) -> v_field) IS DISTINCT FROM (to_jsonb(OLD) -> v_field) THEN
            RAISE EXCEPTION 'No se permite cambiar % de un registro de Cash', v_field;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION cash.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre un movimiento/evento compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE cash.tenant_settings (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_currency            char(3) NOT NULL DEFAULT 'COP',
    require_open_session        boolean NOT NULL DEFAULT true,
    allow_multiple_cashiers     boolean NOT NULL DEFAULT true,
    require_closing_count       boolean NOT NULL DEFAULT true,
    require_supervisor_approval boolean NOT NULL DEFAULT true,
    allow_negative_cash         boolean NOT NULL DEFAULT false,
    max_manual_cash_out         numeric(19,4),
    settings                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_tenant_settings_tenant_unique UNIQUE (tenant_id),
    CONSTRAINT cash_tenant_settings_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_tenant_settings_currency_upper CHECK (default_currency = upper(default_currency)),
    CONSTRAINT cash_tenant_settings_max_cash_out CHECK (max_manual_cash_out IS NULL OR max_manual_cash_out >= 0),
    CONSTRAINT cash_tenant_settings_json_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Cajas y turnos
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_registers (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    register_code       varchar(50) NOT NULL,
    display_name        varchar(140) NOT NULL,
    register_type       varchar(20) NOT NULL DEFAULT 'till'
                        CHECK (register_type IN ('till', 'portable', 'service_desk', 'virtual')),
    currency            char(3) NOT NULL DEFAULT 'COP',
    terminal_id         uuid,
    status              varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'inactive', 'maintenance', 'blocked')),
    requires_session    boolean NOT NULL DEFAULT true,
    allow_cash_in       boolean NOT NULL DEFAULT true,
    allow_cash_out      boolean NOT NULL DEFAULT true,
    allow_safe_drops    boolean NOT NULL DEFAULT true,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_registers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_registers_scope_unique UNIQUE (tenant_id, id, company_id, branch_id),
    CONSTRAINT cash_registers_scope_currency_unique UNIQUE (tenant_id, id, company_id, branch_id, currency),
    CONSTRAINT cash_registers_code_unique UNIQUE (tenant_id, branch_id, register_code),
    CONSTRAINT cash_registers_code_not_blank CHECK (btrim(register_code) <> ''),
    CONSTRAINT cash_registers_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT cash_registers_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_registers_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX ix_cash_registers_branch_status
    ON cash.cash_registers (tenant_id, company_id, branch_id, status, register_code);

CREATE TABLE cash.cash_sessions (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_register_id        uuid NOT NULL,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    session_number          varchar(60) NOT NULL,
    business_date           date NOT NULL,
    currency                char(3) NOT NULL,
    session_status          varchar(20) NOT NULL DEFAULT 'opening'
                            CHECK (session_status IN ('opening', 'open', 'closing', 'closed', 'cancelled')),
    opened_by_user_id       uuid NOT NULL,
    closed_by_user_id       uuid,
    opening_float_amount    numeric(19,4) NOT NULL DEFAULT 0 CHECK (opening_float_amount >= 0),
    opened_at               timestamptz,
    closing_started_at      timestamptz,
    closed_at               timestamptz,
    notes                   text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_sessions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_sessions_register_session_unique UNIQUE (tenant_id, cash_register_id, id),
    CONSTRAINT cash_sessions_register_session_currency_unique UNIQUE (tenant_id, cash_register_id, id, currency),
    CONSTRAINT cash_sessions_number_unique UNIQUE (tenant_id, cash_register_id, session_number),
    CONSTRAINT cash_sessions_register_scope_fk FOREIGN KEY
        (tenant_id, cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_sessions_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_sessions_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT cash_sessions_open_time_shape CHECK (
        (session_status = 'opening' AND opened_at IS NULL AND closed_at IS NULL) OR
        (session_status IN ('open', 'closing') AND opened_at IS NOT NULL AND closed_at IS NULL) OR
        (session_status = 'closed' AND opened_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= opened_at) OR
        (session_status = 'cancelled' AND closed_at IS NOT NULL)
    )
);

CREATE INDEX ix_cash_sessions_register_status
    ON cash.cash_sessions (tenant_id, cash_register_id, session_status, opened_at DESC);
CREATE INDEX ix_cash_sessions_branch_business_date
    ON cash.cash_sessions (tenant_id, company_id, branch_id, business_date DESC);
CREATE UNIQUE INDEX uq_cash_sessions_one_active_per_register
    ON cash.cash_sessions (tenant_id, cash_register_id)
    WHERE session_status IN ('opening', 'open', 'closing');

CREATE TABLE cash.cash_session_cashiers (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_session_id     uuid NOT NULL,
    user_id             uuid NOT NULL,
    assignment_role     varchar(20) NOT NULL DEFAULT 'cashier'
                        CHECK (assignment_role IN ('cashier', 'assistant', 'supervisor')),
    assigned_at         timestamptz NOT NULL DEFAULT now(),
    unassigned_at       timestamptz,
    assigned_by_user_id uuid NOT NULL,
    notes               text,
    CONSTRAINT cash_session_cashiers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_session_cashiers_session_fk FOREIGN KEY (tenant_id, cash_session_id)
        REFERENCES cash.cash_sessions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_session_cashiers_time CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)
);
CREATE UNIQUE INDEX uq_cash_session_cashier_active
    ON cash.cash_session_cashiers (tenant_id, cash_session_id, user_id)
    WHERE unassigned_at IS NULL;
CREATE INDEX ix_cash_session_cashiers_user
    ON cash.cash_session_cashiers (tenant_id, user_id, assigned_at DESC);

CREATE TABLE cash.cash_session_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_session_id     uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL,
    changed_by_user_id  uuid NOT NULL,
    reason              text,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT cash_session_status_history_session_fk FOREIGN KEY (tenant_id, cash_session_id)
        REFERENCES cash.cash_sessions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_session_status_history_status CHECK (
        new_status IN ('opening', 'open', 'closing', 'closed', 'cancelled')
        AND (previous_status IS NULL OR previous_status IN ('opening', 'open', 'closing', 'closed', 'cancelled'))
    ),
    CONSTRAINT cash_session_status_history_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX ix_cash_session_status_history_session
    ON cash.cash_session_status_history (tenant_id, cash_session_id, changed_at DESC);

CREATE TABLE cash.cash_register_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_register_id    uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL,
    changed_by_user_id  uuid NOT NULL,
    reason              text,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_register_status_history_register_fk FOREIGN KEY (tenant_id, cash_register_id)
        REFERENCES cash.cash_registers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_register_status_history_status CHECK (
        new_status IN ('active', 'inactive', 'maintenance', 'blocked')
        AND (previous_status IS NULL OR previous_status IN ('active', 'inactive', 'maintenance', 'blocked'))
    )
);
CREATE INDEX ix_cash_register_status_history_register
    ON cash.cash_register_status_history (tenant_id, cash_register_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- 3. Traslados entre cajas (la confirmacion crea movimientos emparejados)
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_register_transfers (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid NOT NULL,
    branch_id                   uuid NOT NULL,
    transfer_number             varchar(60) NOT NULL,
    source_cash_register_id     uuid NOT NULL,
    destination_cash_register_id uuid NOT NULL,
    source_cash_session_id      uuid,
    destination_cash_session_id uuid,
    currency                    char(3) NOT NULL,
    amount                      numeric(19,4) NOT NULL CHECK (amount > 0),
    transfer_status             varchar(20) NOT NULL DEFAULT 'draft'
                                CHECK (transfer_status IN ('draft', 'pending', 'approved', 'posted', 'cancelled', 'rejected')),
    requested_by_user_id        uuid NOT NULL,
    approved_by_user_id         uuid,
    posted_by_user_id           uuid,
    requested_at                timestamptz NOT NULL DEFAULT now(),
    approved_at                 timestamptz,
    posted_at                   timestamptz,
    reason                      text,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_register_transfers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_register_transfers_number_unique UNIQUE (tenant_id, branch_id, transfer_number),
    CONSTRAINT cash_register_transfers_source_fk FOREIGN KEY
        (tenant_id, source_cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_register_transfers_destination_fk FOREIGN KEY
        (tenant_id, destination_cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_register_transfers_source_session_fk FOREIGN KEY
        (tenant_id, source_cash_register_id, source_cash_session_id, currency)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_register_transfers_destination_session_fk FOREIGN KEY
        (tenant_id, destination_cash_register_id, destination_cash_session_id, currency)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_register_transfers_different_registers CHECK (source_cash_register_id <> destination_cash_register_id),
    CONSTRAINT cash_register_transfers_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_register_transfers_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT cash_register_transfers_approval_shape CHECK (
        transfer_status NOT IN ('approved', 'posted')
        OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL)
    ),
    CONSTRAINT cash_register_transfers_posted_shape CHECK (
        (transfer_status = 'posted' AND posted_at IS NOT NULL AND posted_by_user_id IS NOT NULL)
        OR (transfer_status <> 'posted' AND posted_at IS NULL AND posted_by_user_id IS NULL)
    )
);
CREATE INDEX ix_cash_register_transfers_status
    ON cash.cash_register_transfers (tenant_id, company_id, branch_id, transfer_status, requested_at DESC);

-- ---------------------------------------------------------------------------
-- 4. Libro de movimientos del cajon (append-only)
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_movements (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid NOT NULL,
    branch_id                   uuid NOT NULL,
    cash_register_id            uuid NOT NULL,
    cash_session_id             uuid NOT NULL,
    transfer_id                 uuid,
    movement_number             varchar(80) NOT NULL,
    movement_type               varchar(30) NOT NULL
                                CHECK (movement_type IN (
                                    'sale_cash_in', 'refund_cash_out', 'cash_in', 'cash_out',
                                    'expense_out', 'safe_drop_out', 'safe_drop_in',
                                    'transfer_in', 'transfer_out', 'adjustment_in', 'adjustment_out'
                                )),
    direction                   varchar(3) NOT NULL CHECK (direction IN ('in', 'out')),
    amount                      numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                    char(3) NOT NULL,
    payment_transaction_id      uuid,
    payment_refund_id           uuid,
    sales_sale_id               uuid,
    expense_category_id         uuid,
    source_module               varchar(60),
    source_event_id             uuid,
    source_reference_id         uuid,
    reversal_of_movement_id     uuid,
    actor_user_id               uuid NOT NULL,
    occurred_at                 timestamptz NOT NULL DEFAULT now(),
    reason                      text,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_movements_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_movements_tenant_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT cash_movements_register_id_unique UNIQUE (tenant_id, cash_register_id, id),
    CONSTRAINT cash_movements_register_session_currency_unique
        UNIQUE (tenant_id, cash_register_id, cash_session_id, id, currency),
    CONSTRAINT cash_movements_branch_currency_unique
        UNIQUE (tenant_id, company_id, branch_id, id, currency),
    CONSTRAINT cash_movements_register_scope_fk FOREIGN KEY
        (tenant_id, cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_movements_session_fk FOREIGN KEY (tenant_id, cash_register_id, cash_session_id, currency)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_movements_transfer_fk FOREIGN KEY (tenant_id, transfer_id)
        REFERENCES cash.cash_register_transfers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_movements_reversal_fk FOREIGN KEY (tenant_id, cash_register_id, reversal_of_movement_id)
        REFERENCES cash.cash_movements (tenant_id, cash_register_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_movements_movement_number_unique UNIQUE (tenant_id, cash_register_id, movement_number),
    CONSTRAINT cash_movements_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_movements_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT cash_movements_direction_matches_type CHECK (
        (movement_type IN ('sale_cash_in', 'safe_drop_in', 'transfer_in', 'adjustment_in') AND direction = 'in') OR
        (movement_type IN ('refund_cash_out', 'cash_out', 'expense_out', 'safe_drop_out', 'transfer_out', 'adjustment_out') AND direction = 'out') OR
        (movement_type = 'cash_in' AND direction = 'in')
    ),
    CONSTRAINT cash_movements_transfer_shape CHECK (
        (movement_type IN ('transfer_in', 'transfer_out') AND transfer_id IS NOT NULL) OR
        (movement_type NOT IN ('transfer_in', 'transfer_out') AND transfer_id IS NULL)
    ),
    CONSTRAINT cash_movements_payment_source_shape CHECK (
        (movement_type <> 'sale_cash_in' OR payment_transaction_id IS NOT NULL) AND
        (movement_type <> 'refund_cash_out' OR payment_refund_id IS NOT NULL) AND
        (movement_type <> 'expense_out' OR expense_category_id IS NOT NULL)
    ),
    CONSTRAINT cash_movements_reversal_not_self CHECK (reversal_of_movement_id IS NULL OR reversal_of_movement_id <> id)
);
CREATE INDEX ix_cash_movements_session_time
    ON cash.cash_movements (tenant_id, cash_session_id, occurred_at, id);
CREATE INDEX ix_cash_movements_branch_time
    ON cash.cash_movements (tenant_id, company_id, branch_id, occurred_at DESC);
CREATE INDEX ix_cash_movements_type_time
    ON cash.cash_movements (tenant_id, movement_type, occurred_at DESC);
CREATE UNIQUE INDEX uq_cash_movements_payment_transaction
    ON cash.cash_movements (tenant_id, payment_transaction_id)
    WHERE payment_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cash_movements_payment_refund
    ON cash.cash_movements (tenant_id, payment_refund_id)
    WHERE payment_refund_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cash_movements_single_reversal
    ON cash.cash_movements (tenant_id, reversal_of_movement_id)
    WHERE reversal_of_movement_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cash_movements_transfer_type
    ON cash.cash_movements (tenant_id, transfer_id, movement_type)
    WHERE transfer_id IS NOT NULL;
CREATE UNIQUE INDEX uq_cash_movements_source_event
    ON cash.cash_movements (tenant_id, source_module, source_event_id)
    WHERE source_module IS NOT NULL AND source_event_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Gastos menores / salidas justificadas de efectivo
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_expense_categories (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    category_code       varchar(50) NOT NULL,
    display_name        varchar(120) NOT NULL,
    description         text,
    requires_receipt    boolean NOT NULL DEFAULT false,
    requires_approval   boolean NOT NULL DEFAULT true,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_expense_categories_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_expense_categories_code_unique UNIQUE (tenant_id, category_code),
    CONSTRAINT cash_expense_categories_code_not_blank CHECK (btrim(category_code) <> ''),
    CONSTRAINT cash_expense_categories_name_not_blank CHECK (btrim(display_name) <> '')
);

CREATE TABLE cash.cash_expenses (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    cash_register_id        uuid NOT NULL,
    cash_session_id         uuid NOT NULL,
    expense_category_id     uuid NOT NULL,
    cash_movement_id        uuid,
    expense_number          varchar(60) NOT NULL,
    description             varchar(500) NOT NULL,
    payee_name              varchar(180),
    supplier_id             uuid,
    document_reference      varchar(120),
    net_amount              numeric(19,4) NOT NULL CHECK (net_amount >= 0),
    tax_amount              numeric(19,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount            numeric(19,4) NOT NULL CHECK (total_amount > 0),
    currency                char(3) NOT NULL,
    expense_status          varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (expense_status IN ('draft', 'pending_approval', 'approved', 'paid', 'rejected', 'voided')),
    requested_by_user_id    uuid NOT NULL,
    approved_by_user_id     uuid,
    paid_by_user_id         uuid,
    expense_date            date NOT NULL DEFAULT CURRENT_DATE,
    approved_at             timestamptz,
    paid_at                 timestamptz,
    notes                   text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_expenses_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_expenses_number_unique UNIQUE (tenant_id, branch_id, expense_number),
    CONSTRAINT cash_expenses_category_fk FOREIGN KEY (tenant_id, expense_category_id)
        REFERENCES cash.cash_expense_categories (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_expenses_register_scope_fk FOREIGN KEY
        (tenant_id, cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_expenses_session_fk FOREIGN KEY (tenant_id, cash_register_id, cash_session_id, currency)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_expenses_movement_fk FOREIGN KEY
        (tenant_id, cash_register_id, cash_session_id, cash_movement_id, currency)
        REFERENCES cash.cash_movements
        (tenant_id, cash_register_id, cash_session_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_expenses_movement_unique UNIQUE (tenant_id, cash_movement_id),
    CONSTRAINT cash_expenses_amounts CHECK (total_amount = net_amount + tax_amount),
    CONSTRAINT cash_expenses_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_expenses_approval_shape CHECK (
        expense_status <> 'approved'
        OR (approved_by_user_id IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT cash_expenses_paid_shape CHECK (
        expense_status <> 'paid'
        OR (cash_movement_id IS NOT NULL AND paid_by_user_id IS NOT NULL AND paid_at IS NOT NULL)
    ),
    CONSTRAINT cash_expenses_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
ALTER TABLE cash.cash_movements
    ADD CONSTRAINT cash_movements_expense_category_fk
    FOREIGN KEY (tenant_id, expense_category_id)
    REFERENCES cash.cash_expense_categories (tenant_id, id) ON DELETE RESTRICT;

CREATE INDEX ix_cash_expenses_session_status
    ON cash.cash_expenses (tenant_id, cash_session_id, expense_status, expense_date DESC);

CREATE TABLE cash.cash_expense_attachments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    expense_id          uuid NOT NULL,
    file_reference      varchar(500) NOT NULL,
    file_name           varchar(255) NOT NULL,
    content_type        varchar(120),
    file_size_bytes     bigint CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    uploaded_by_user_id uuid NOT NULL,
    uploaded_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_expense_attachments_expense_fk FOREIGN KEY (tenant_id, expense_id)
        REFERENCES cash.cash_expenses (tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX ix_cash_expense_attachments_expense
    ON cash.cash_expense_attachments (tenant_id, expense_id, uploaded_at DESC);

-- ---------------------------------------------------------------------------
-- 6. Denominaciones y arqueos de caja
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_denominations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    currency            char(3) NOT NULL,
    denomination_code   varchar(40) NOT NULL,
    denomination_type   varchar(12) NOT NULL CHECK (denomination_type IN ('coin', 'banknote', 'other')),
    denomination_value  numeric(19,4) NOT NULL CHECK (denomination_value > 0),
    display_order       integer NOT NULL DEFAULT 0,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_denominations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_denominations_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT cash_denominations_code_unique UNIQUE (tenant_id, currency, denomination_code),
    CONSTRAINT cash_denominations_currency_upper CHECK (currency = upper(currency))
);
CREATE INDEX ix_cash_denominations_active
    ON cash.cash_denominations (tenant_id, currency, is_active, display_order);

CREATE TABLE cash.cash_counts (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    cash_register_id    uuid NOT NULL,
    cash_session_id     uuid NOT NULL,
    count_type          varchar(20) NOT NULL CHECK (count_type IN ('opening', 'closing', 'spot_check', 'transfer')),
    count_status        varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (count_status IN ('draft', 'submitted', 'approved', 'rejected', 'cancelled')),
    currency            char(3) NOT NULL,
    total_amount        numeric(19,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    counted_by_user_id  uuid NOT NULL,
    submitted_by_user_id uuid,
    approved_by_user_id uuid,
    counted_at          timestamptz NOT NULL DEFAULT now(),
    submitted_at        timestamptz,
    approved_at         timestamptz,
    notes               text,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_counts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_counts_currency_unique UNIQUE (tenant_id, id, currency),
    CONSTRAINT cash_counts_session_id_unique UNIQUE (tenant_id, cash_session_id, id),
    CONSTRAINT cash_counts_register_scope_fk FOREIGN KEY
        (tenant_id, cash_register_id, company_id, branch_id, currency)
        REFERENCES cash.cash_registers (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_counts_session_fk FOREIGN KEY (tenant_id, cash_register_id, cash_session_id, currency)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_counts_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_counts_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT cash_counts_submitted_shape CHECK (
        count_status NOT IN ('submitted', 'approved', 'rejected')
        OR (submitted_at IS NOT NULL AND submitted_by_user_id IS NOT NULL)
    ),
    CONSTRAINT cash_counts_approved_shape CHECK (
        (count_status = 'approved' AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL)
        OR (count_status <> 'approved' AND approved_at IS NULL AND approved_by_user_id IS NULL)
    )
);
CREATE INDEX ix_cash_counts_session_type
    ON cash.cash_counts (tenant_id, cash_session_id, count_type, counted_at DESC);
CREATE UNIQUE INDEX uq_cash_counts_opening_per_session
    ON cash.cash_counts (tenant_id, cash_session_id) WHERE count_type = 'opening' AND count_status <> 'cancelled';
CREATE UNIQUE INDEX uq_cash_counts_closing_per_session
    ON cash.cash_counts (tenant_id, cash_session_id) WHERE count_type = 'closing' AND count_status <> 'cancelled';

CREATE TABLE cash.cash_count_lines (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_count_id               uuid NOT NULL,
    denomination_id             uuid NOT NULL,
    currency                    char(3) NOT NULL,
    denomination_value_snapshot numeric(19,4) NOT NULL CHECK (denomination_value_snapshot > 0),
    quantity                    bigint NOT NULL CHECK (quantity >= 0),
    line_total                  numeric(19,4) GENERATED ALWAYS AS
                                (denomination_value_snapshot * quantity) STORED,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_count_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_count_lines_count_fk FOREIGN KEY (tenant_id, cash_count_id, currency)
        REFERENCES cash.cash_counts (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_count_lines_denomination_fk FOREIGN KEY (tenant_id, denomination_id, currency)
        REFERENCES cash.cash_denominations (tenant_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_count_lines_count_denomination_unique UNIQUE (tenant_id, cash_count_id, denomination_id)
);
CREATE INDEX ix_cash_count_lines_count
    ON cash.cash_count_lines (tenant_id, cash_count_id);

CREATE TABLE cash.cash_session_reconciliations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_session_id         uuid NOT NULL,
    closing_count_id        uuid NOT NULL,
    opening_float_amount    numeric(19,4) NOT NULL CHECK (opening_float_amount >= 0),
    expected_cash_amount    numeric(19,4) NOT NULL,
    counted_cash_amount     numeric(19,4) NOT NULL,
    variance_amount         numeric(19,4) NOT NULL,
    reconciliation_status   varchar(20) NOT NULL DEFAULT 'pending'
                            CHECK (reconciliation_status IN ('pending', 'balanced', 'over', 'short', 'approved', 'rejected')),
    reconciled_by_user_id   uuid NOT NULL,
    approved_by_user_id     uuid,
    reconciled_at           timestamptz NOT NULL DEFAULT now(),
    approved_at             timestamptz,
    notes                   text,
    non_cash_summary        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_session_reconciliations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_session_reconciliations_session_unique UNIQUE (tenant_id, cash_session_id),
    CONSTRAINT cash_session_reconciliations_session_fk FOREIGN KEY (tenant_id, cash_session_id)
        REFERENCES cash.cash_sessions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_session_reconciliations_closing_count_fk FOREIGN KEY
        (tenant_id, cash_session_id, closing_count_id)
        REFERENCES cash.cash_counts (tenant_id, cash_session_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_session_reconciliations_variance CHECK (variance_amount = counted_cash_amount - expected_cash_amount),
    CONSTRAINT cash_session_reconciliations_status_consistent CHECK (
        (reconciliation_status = 'balanced' AND variance_amount = 0) OR
        (reconciliation_status = 'over' AND variance_amount > 0) OR
        (reconciliation_status = 'short' AND variance_amount < 0) OR
        reconciliation_status IN ('pending', 'approved', 'rejected')
    ),
    CONSTRAINT cash_session_reconciliations_approved_shape CHECK (
        (reconciliation_status = 'approved'
            AND approved_by_user_id IS NOT NULL AND approved_at IS NOT NULL) OR
        (reconciliation_status <> 'approved'
            AND approved_by_user_id IS NULL AND approved_at IS NULL)
    ),
    CONSTRAINT cash_session_reconciliations_non_cash_object CHECK (jsonb_typeof(non_cash_summary) = 'object')
);

-- ---------------------------------------------------------------------------
-- 7. Cajas fuertes y traslados de efectivo
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_safes (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    safe_code           varchar(50) NOT NULL,
    display_name        varchar(140) NOT NULL,
    currency            char(3) NOT NULL DEFAULT 'COP',
    safe_status         varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (safe_status IN ('active', 'inactive', 'blocked')),
    max_balance_amount  numeric(19,4),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_safes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_safes_scope_unique UNIQUE (tenant_id, id, company_id, branch_id),
    CONSTRAINT cash_safes_scope_currency_unique UNIQUE (tenant_id, id, company_id, branch_id, currency),
    CONSTRAINT cash_safes_code_unique UNIQUE (tenant_id, branch_id, safe_code),
    CONSTRAINT cash_safes_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT cash_safes_max_balance CHECK (max_balance_amount IS NULL OR max_balance_amount >= 0),
    CONSTRAINT cash_safes_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE TABLE cash.cash_safe_movements (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid NOT NULL,
    branch_id                   uuid NOT NULL,
    safe_id                     uuid NOT NULL,
    movement_type               varchar(20) NOT NULL
                                CHECK (movement_type IN ('deposit', 'withdrawal', 'adjustment_in', 'adjustment_out')),
    direction                   varchar(3) NOT NULL CHECK (direction IN ('in', 'out')),
    amount                      numeric(19,4) NOT NULL CHECK (amount > 0),
    currency                    char(3) NOT NULL,
    cash_movement_id            uuid,
    actor_user_id               uuid NOT NULL,
    occurred_at                 timestamptz NOT NULL DEFAULT now(),
    reason                      text,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_safe_movements_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT cash_safe_movements_safe_scope_fk FOREIGN KEY (tenant_id, safe_id, company_id, branch_id, currency)
        REFERENCES cash.cash_safes (tenant_id, id, company_id, branch_id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_safe_movements_cash_movement_fk FOREIGN KEY
        (tenant_id, company_id, branch_id, cash_movement_id, currency)
        REFERENCES cash.cash_movements (tenant_id, company_id, branch_id, id, currency) ON DELETE RESTRICT,
    CONSTRAINT cash_safe_movements_direction_type CHECK (
        (movement_type IN ('deposit', 'adjustment_in') AND direction = 'in') OR
        (movement_type IN ('withdrawal', 'adjustment_out') AND direction = 'out')
    ),
    CONSTRAINT cash_safe_movements_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT cash_safe_movements_source_present CHECK (cash_movement_id IS NOT NULL OR reason IS NOT NULL)
);
CREATE INDEX ix_cash_safe_movements_safe_time
    ON cash.cash_safe_movements (tenant_id, safe_id, occurred_at DESC);
CREATE UNIQUE INDEX uq_cash_safe_movements_cash_movement
    ON cash.cash_safe_movements (tenant_id, cash_movement_id)
    WHERE cash_movement_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Eventos de gaveta (telemetria operativa, no son movimientos monetarios)
-- ---------------------------------------------------------------------------

CREATE TABLE cash.cash_drawer_events (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    cash_register_id        uuid NOT NULL,
    cash_session_id         uuid,
    event_type              varchar(24) NOT NULL
                            CHECK (event_type IN ('open_requested', 'opened', 'open_failed', 'forced_open', 'closed')),
    trigger_source          varchar(40) NOT NULL,
    source_reference_id     uuid,
    actor_user_id           uuid,
    device_reference        varchar(160),
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    result_code             varchar(80),
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT cash_drawer_events_register_fk FOREIGN KEY (tenant_id, cash_register_id)
        REFERENCES cash.cash_registers (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_drawer_events_session_fk FOREIGN KEY (tenant_id, cash_register_id, cash_session_id)
        REFERENCES cash.cash_sessions (tenant_id, cash_register_id, id) ON DELETE RESTRICT,
    CONSTRAINT cash_drawer_events_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX ix_cash_drawer_events_register_time
    ON cash.cash_drawer_events (tenant_id, cash_register_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Inbox, Outbox e idempotencia
-- ---------------------------------------------------------------------------

CREATE TABLE cash.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    producer_module     varchar(80) NOT NULL,
    producer_event_id   uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    payload_hash        char(64),
    processed_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_processed_events_unique UNIQUE (tenant_id, producer_module, producer_event_id),
    CONSTRAINT cash_processed_events_module_not_blank CHECK (btrim(producer_module) <> ''),
    CONSTRAINT cash_processed_events_type_not_blank CHECK (btrim(event_type) <> '')
);

CREATE TABLE cash.event_outbox (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    aggregate_type      varchar(100) NOT NULL,
    aggregate_id        uuid NOT NULL,
    event_type          varchar(160) NOT NULL,
    event_version       integer NOT NULL DEFAULT 1 CHECK (event_version > 0),
    payload             jsonb NOT NULL,
    publish_status      varchar(20) NOT NULL DEFAULT 'pending'
                        CHECK (publish_status IN ('pending', 'processing', 'published', 'failed')),
    attempts            integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at        timestamptz NOT NULL DEFAULT now(),
    locked_at           timestamptz,
    published_at        timestamptz,
    last_error          text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT cash_event_outbox_publish_shape CHECK (publish_status <> 'published' OR published_at IS NOT NULL)
);
CREATE INDEX ix_cash_event_outbox_pending
    ON cash.event_outbox (available_at, created_at)
    WHERE publish_status IN ('pending', 'failed');
CREATE INDEX ix_cash_event_outbox_aggregate
    ON cash.event_outbox (tenant_id, aggregate_type, aggregate_id, created_at);

CREATE TABLE cash.idempotency_records (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    idempotency_key     varchar(160) NOT NULL,
    operation_name      varchar(120) NOT NULL,
    request_hash        char(64) NOT NULL,
    record_status       varchar(20) NOT NULL DEFAULT 'in_progress'
                        CHECK (record_status IN ('in_progress', 'completed', 'failed')),
    response_status     integer,
    response_body       jsonb,
    expires_at          timestamptz NOT NULL DEFAULT (now() + interval '48 hours'),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_idempotency_records_unique UNIQUE (tenant_id, idempotency_key, operation_name),
    CONSTRAINT cash_idempotency_records_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT cash_idempotency_records_operation_not_blank CHECK (btrim(operation_name) <> ''),
    CONSTRAINT cash_idempotency_records_expiration CHECK (expires_at > created_at),
    CONSTRAINT cash_idempotency_records_response_status CHECK (
        response_status IS NULL OR response_status BETWEEN 100 AND 599
    ),
    CONSTRAINT cash_idempotency_records_response_object CHECK (response_body IS NULL OR jsonb_typeof(response_body) = 'object')
);
CREATE INDEX ix_cash_idempotency_expiry
    ON cash.idempotency_records (expires_at);

-- ---------------------------------------------------------------------------
-- 10. Funciones de consulta y bootstrap del tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION cash.calculate_session_expected_cash(
    p_tenant_id uuid,
    p_cash_session_id uuid
)
RETURNS numeric(19,4)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
    v_opening numeric(19,4);
    v_movements numeric(19,4);
BEGIN
    IF cash.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    SELECT s.opening_float_amount
      INTO v_opening
      FROM cash.cash_sessions s
     WHERE s.tenant_id = p_tenant_id
       AND s.id = p_cash_session_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sesion de caja no existe en el tenant actual';
    END IF;

    SELECT COALESCE(SUM(CASE WHEN m.direction = 'in' THEN m.amount ELSE -m.amount END), 0)
      INTO v_movements
      FROM cash.cash_movements m
     WHERE m.tenant_id = p_tenant_id
       AND m.cash_session_id = p_cash_session_id;

    RETURN v_opening + v_movements;
END;
$$;

CREATE OR REPLACE FUNCTION cash.initialize_tenant_cash(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF cash.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO cash.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO cash.cash_expense_categories (
        tenant_id, category_code, display_name, requires_receipt, requires_approval
    ) VALUES
        (p_tenant_id, 'transport', 'Transporte', true, true),
        (p_tenant_id, 'cleaning', 'Aseo y limpieza', true, true),
        (p_tenant_id, 'maintenance', 'Mantenimiento menor', true, true),
        (p_tenant_id, 'supplies', 'Insumos y suministros', true, true),
        (p_tenant_id, 'petty_cash', 'Caja menor', false, true),
        (p_tenant_id, 'other', 'Otros gastos', true, true)
    ON CONFLICT (tenant_id, category_code) DO NOTHING;

    INSERT INTO cash.cash_denominations (
        tenant_id, currency, denomination_code, denomination_type,
        denomination_value, display_order
    ) VALUES
        (p_tenant_id, 'COP', 'COP_COIN_50', 'coin', 50, 10),
        (p_tenant_id, 'COP', 'COP_COIN_100', 'coin', 100, 20),
        (p_tenant_id, 'COP', 'COP_COIN_200', 'coin', 200, 30),
        (p_tenant_id, 'COP', 'COP_COIN_500', 'coin', 500, 40),
        (p_tenant_id, 'COP', 'COP_BILL_1000', 'banknote', 1000, 50),
        (p_tenant_id, 'COP', 'COP_BILL_2000', 'banknote', 2000, 60),
        (p_tenant_id, 'COP', 'COP_BILL_5000', 'banknote', 5000, 70),
        (p_tenant_id, 'COP', 'COP_BILL_10000', 'banknote', 10000, 80),
        (p_tenant_id, 'COP', 'COP_BILL_20000', 'banknote', 20000, 90),
        (p_tenant_id, 'COP', 'COP_BILL_50000', 'banknote', 50000, 100),
        (p_tenant_id, 'COP', 'COP_BILL_100000', 'banknote', 100000, 110)
    ON CONFLICT (tenant_id, currency, denomination_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. Triggers: scope immutable, updated_at y libros append-only
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'cash_registers', 'cash_sessions', 'cash_register_transfers',
        'cash_expense_categories', 'cash_expenses', 'cash_denominations',
        'cash_counts', 'cash_session_reconciliations', 'cash_safes', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON cash.%I FOR EACH ROW EXECUTE FUNCTION cash.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'cash_registers', 'cash_sessions', 'cash_session_cashiers',
        'cash_session_status_history', 'cash_register_status_history', 'cash_register_transfers',
        'cash_movements', 'cash_expense_categories', 'cash_expenses', 'cash_expense_attachments',
        'cash_denominations', 'cash_counts', 'cash_count_lines', 'cash_session_reconciliations',
        'cash_safes', 'cash_safe_movements', 'cash_drawer_events', 'processed_events',
        'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON cash.%I FOR EACH ROW EXECUTE FUNCTION cash.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'cash_registers', 'cash_sessions', 'cash_session_cashiers', 'cash_register_transfers',
        'cash_movements', 'cash_expenses', 'cash_counts', 'cash_session_reconciliations',
        'cash_safes', 'cash_safe_movements'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON cash.%I FOR EACH ROW EXECUTE FUNCTION cash.prevent_scope_change()',
            'trg_' || v_table || '_scope_immutable', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'cash_movements', 'cash_safe_movements', 'cash_session_status_history',
        'cash_register_status_history', 'cash_drawer_events', 'processed_events'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON cash.%I FOR EACH ROW EXECUTE FUNCTION cash.prevent_append_only_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Row Level Security: todas las tablas aisladas por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'cash_registers', 'cash_sessions', 'cash_session_cashiers',
        'cash_session_status_history', 'cash_register_status_history', 'cash_register_transfers',
        'cash_movements', 'cash_expense_categories', 'cash_expenses', 'cash_expense_attachments',
        'cash_denominations', 'cash_counts', 'cash_count_lines', 'cash_session_reconciliations',
        'cash_safes', 'cash_safe_movements', 'cash_drawer_events', 'processed_events',
        'event_outbox', 'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE cash.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE cash.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON cash.%I USING (tenant_id = cash.current_tenant_id()) WITH CHECK (tenant_id = cash.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Comentarios de propiedad, contratos y operacion
-- ---------------------------------------------------------------------------

COMMENT ON TABLE cash.cash_registers IS
'Caja fisica/logica por sucursal. company_id, branch_id y terminal_id son referencias logicas validadas por Organization/Integrations.';
COMMENT ON TABLE cash.cash_sessions IS
'Turno de caja. opening_float_amount es el fondo inicial; expected cash se calcula sumando movimientos in/out del cajon.';
COMMENT ON TABLE cash.cash_movements IS
'Libro append-only del cajon. Una fila representa un movimiento fisico de efectivo; correcciones mediante movimientos compensatorios.';
COMMENT ON TABLE cash.cash_expenses IS
'Gastos menores pagados desde efectivo de una sesion. No sustituye cuentas por pagar ni pagos a proveedores administrados por Finance/Purchasing.';
COMMENT ON TABLE cash.cash_counts IS
'Arqueos de apertura, cierre y conteos sorpresa expresados por denominaciones. El total se reconcilia en application antes de aprobar.';
COMMENT ON TABLE cash.cash_session_reconciliations IS
'Resultado de conciliacion del turno: efectivo esperado contra efectivo contado. Los medios no efectivo se resumen para consulta, no se vuelven a contabilizar.';
COMMENT ON TABLE cash.cash_safes IS
'Cajas fuertes fisicas de una sucursal; no representan cuentas bancarias ni tesoreria contable.';
COMMENT ON TABLE cash.cash_safe_movements IS
'Libro append-only de entradas/salidas de caja fuerte. Los traspasos desde/hacia caja deben coordinarse en una unica transaccion de aplicacion.';
COMMENT ON TABLE cash.cash_drawer_events IS
'Telemetria de apertura/cierre de gaveta. No representa por si sola entrada ni salida monetaria.';
COMMENT ON TABLE cash.event_outbox IS
'Outbox transaccional. El worker reclama eventos con SELECT ... FOR UPDATE SKIP LOCKED y publica despues del commit.';

-- Permisos a registrar en identity.permissions (Identity es propietario):
--   cash.registers.read / cash.registers.manage
--   cash.sessions.open / cash.sessions.read / cash.sessions.close / cash.sessions.cancel
--   cash.sessions.assign_cashier
--   cash.movements.read / cash.movements.create / cash.movements.reverse
--   cash.expenses.read / cash.expenses.create / cash.expenses.approve / cash.expenses.pay
--   cash.counts.read / cash.counts.create / cash.counts.submit / cash.counts.approve
--   cash.reconciliations.read / cash.reconciliations.approve
--   cash.transfers.read / cash.transfers.create / cash.transfers.approve / cash.transfers.post
--   cash.safes.read / cash.safes.manage / cash.safes.move
--   cash.drawer_events.read
-- La aplicacion valida tambien el plan/modulo 'cash' y el alcance del usuario
-- sobre company_id/branch_id/cash_register_id. RLS solo garantiza tenant.
--
-- Eventos sugeridos para crates/contracts/events:
--   cash.session_opened.v1
--   cash.session_closed.v1
--   cash.movement_recorded.v1
--   cash.cash_expense_paid.v1
--   cash.register_transfer_posted.v1
--   cash.safe_movement_recorded.v1
--   cash.drawer_opened.v1
--   cash.session_reconciled.v1
--
-- Consumidores:
--   Payments -> Cash: payments.payment_captured.v1 solo cuando method_family=cash;
--                     payments.refund_succeeded.v1 solo cuando el reembolso se
--                     entrega fisicamente en efectivo.
--   Sales <- Cash: estado de caja/turno cuando el flujo de POS lo requiera.
--   Finance <- Cash: resumen de arqueo, faltantes/sobrantes y gastos menores.
--   Integrations -> Cash: eventos de gaveta/dispositivo mediante contrato.
--
-- REGLAS TRANSACCIONALES QUE DEBE IMPLEMENTAR EL CRATE:
--   1. Apertura: bloquear caja (FOR UPDATE), validar que no exista sesion activa,
--      crear sesion y conteo inicial; el indice parcial impide dos sesiones activas.
--   2. Movimiento: bloquear sesion, verificar status='open', moneda, permisos,
--      limites y saldo esperado cuando no se permite efectivo negativo; insertar
--      movimiento y outbox en la misma transaccion.
--   3. Pago efectivo: consumir el evento de Payments y crear movimiento usando
--      payment_transaction_id + processed_events; unique index evita duplicados.
--   4. Cierre: pasar a closing, impedir nuevos movimientos, calcular esperado,
--      registrar conteo, conciliar, aprobar y cerrar bajo bloqueo de sesion.
--   5. Traslado entre cajas: crear transferencia y dos movimientos (transfer_out
--      y transfer_in) atomicos; validar moneda/sucursal/tenant y sesiones abiertas.
--   6. Caja fuerte: coordinar movimiento del cajon y del safe en una transaccion;
--      no publicar evento hasta el commit.
--   7. Las sumas y estados que dependen de varias filas no se garantizan con CHECK;
--      validar en application bajo bloqueo y usar idempotencia.
--   8. Las claves externas y secretos de dispositivos no se guardan aqui.
--
-- Ejemplo de contexto RLS e inicializacion:
-- BEGIN;
-- SET LOCAL app.tenant_id = 'UUID_DEL_TENANT_AUTORIZADO';
-- SELECT cash.initialize_tenant_cash('UUID_DEL_TENANT_AUTORIZADO'::uuid);
-- COMMIT;
-- ============================================================================

COMMIT;
