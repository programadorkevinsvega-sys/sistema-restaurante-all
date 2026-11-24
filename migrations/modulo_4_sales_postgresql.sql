-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 4: SALES (PEDIDOS, CHECKS, VENTAS Y DEVOLUCIONES)
-- Ubicacion del crate: crates/modules/sales
-- Motor: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants)
--   * modulo_1_organization_postgresql.sql (referencias logicas de company/branch)
--   * modulo_3_catalog_postgresql.sql (referencias logicas de productos/menus)
--   * identity puede estar instalado, pero no se crean FK fisicas hacia identity.
--
-- CODIGO DEL MODULO SaaS:
--   platform.modules ya registra el modulo como 'pos_sales'.
--   El schema/crate se llama 'sales'; NO se crea una segunda entrada SaaS.
--
-- RESPONSABILIDAD DE SALES:
--   * Pedidos y su ciclo de vida comercial.
--   * Lineas de pedido con instantaneas de producto, variante y modificadores.
--   * Asignacion temporal de recursos fisicos de comedor a pedidos.
--   * Descuentos efectivamente aplicados a pedidos/ventas (no reglas/promociones).
--   * Checks/cuentas cobrables y ventas finalizadas, incluidos snapshots monetarios.
--   * Desglose de impuestos recibido desde el contrato de Finance.
--   * Devoluciones comerciales y solicitudes de reembolso.
--   * Numeracion documental e idempotencia de comandos/API.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO):
--   * Productos, variantes, menus, listas de precios y modificadores: catalog.
--   * Existencias, reservas y movimientos fisicos de stock: inventory.
--   * Recetas, produccion y consumo de ingredientes: production.
--   * Comandas, estaciones, preparacion y KDS: kitchen.
--   * Autorizacion/captura de pagos, medios de pago y reembolsos monetarios: payments.
--   * Sesiones de caja, apertura/cierre y movimientos de efectivo: cash.
--   * Clientes, promociones y fidelizacion: customers (Sales conserva customer_id
--     como referencia logica y el snapshot necesario en el documento).
--   * Tarifas y calculo fiscal: finance. Sales conserva el resultado fiscal
--     recibido como snapshot, no calcula las tasas.
--   * Areas, mesas y otros recursos fisicos: organization.
--   * Personal, turnos y terminales: workforce / integrations segun contrato.
--   * Auditoria transversal: audit. Este modulo conserva solo historial propio
--     del ciclo de vida de sus agregados.
--
-- LIMITES ENTRE MODULOS:
--   * Sales solo crea FK fisicas a platform.tenants y a tablas de su propio schema.
--   * company_id, branch_id, product_id, variant_id, menu_item_id, customer_id,
--     user_id, terminal_id y referencias a Payments/Finance son UUID logicos.
--   * La existencia, pertenencia al tenant/empresa/sucursal, estado y permisos
--     se validan usando contratos publicos (ports) en application.
--   * Ningun modulo debe leer/escribir tablas privadas de Sales directamente.
--   * No crear FK cruzadas hacia organization, catalog, identity, payments,
--     cash, customers, kitchen, workforce ni finance.
--
-- AISLAMIENTO:
--   * Todas las tablas tenant-scoped tienen tenant_id y RLS.
--   * Cada transaccion autenticada debe ejecutar SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant se deriva del contexto autenticado; nunca confiar en HTTP body.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * Las referencias UUID externas deben validarse en los contratos de modulo.
--
-- IMPORTANTE:
--   * Instalar una sola vez en una base nueva despues de platform y catalog.
--   * Este modulo no crea tablas de pagos/caja ni intenta coordinar una
--     transaccion SQL distribuida. La confirmacion multi-modulo usa Saga/eventos.
--   * En una cuenta de restaurante, una orden puede tener varios checks/ventas
--     (por ejemplo, dividir la cuenta). Cada fila de sales.sales representa
--     un check/venta finalizado; una orden puede originar varios checks.
--   * La venta y sus lineas son snapshots comerciales. No almacenar PAN, CVV,
--     secretos de pago ni credenciales de pasarelas en este schema.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS sales;

COMMENT ON SCHEMA sales IS
'Pedidos, checks, ventas y devoluciones. No administra catalogo maestro, pagos, caja, inventario ni preparacion de cocina.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sales.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sales.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION sales.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id en Sales';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sales.prevent_record_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es inmutable; registre una correccion, anulacion o devolucion',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION sales.prevent_posted_sale_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Una venta finalizada no puede eliminarse fisicamente';
    END IF;

    IF OLD.sale_status = 'posted'
       AND NEW.sale_status NOT IN ('voided', 'partially_returned', 'returned') THEN
        RAISE EXCEPTION 'Una venta posted solo puede pasar a voided, partially_returned o returned';
    END IF;

    IF OLD.sale_status = 'posted'
       AND (
            NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
            OR NEW.company_id IS DISTINCT FROM OLD.company_id
            OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
            OR NEW.order_id IS DISTINCT FROM OLD.order_id
            OR NEW.sale_number IS DISTINCT FROM OLD.sale_number
            OR NEW.business_date IS DISTINCT FROM OLD.business_date
            OR NEW.sold_at IS DISTINCT FROM OLD.sold_at
            OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
            OR NEW.customer_name_snapshot IS DISTINCT FROM OLD.customer_name_snapshot
            OR NEW.customer_tax_id_snapshot IS DISTINCT FROM OLD.customer_tax_id_snapshot
            OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
            OR NEW.subtotal_amount IS DISTINCT FROM OLD.subtotal_amount
            OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
            OR NEW.taxable_base_amount IS DISTINCT FROM OLD.taxable_base_amount
            OR NEW.tax_amount IS DISTINCT FROM OLD.tax_amount
            OR NEW.rounding_amount IS DISTINCT FROM OLD.rounding_amount
            OR NEW.total_amount IS DISTINCT FROM OLD.total_amount
            OR NEW.finance_tax_calculation_id IS DISTINCT FROM OLD.finance_tax_calculation_id
            OR NEW.fiscal_document_reference IS DISTINCT FROM OLD.fiscal_document_reference
            OR NEW.created_by_user_id IS DISTINCT FROM OLD.created_by_user_id
            OR NEW.metadata IS DISTINCT FROM OLD.metadata
       ) THEN
        RAISE EXCEPTION 'Los datos de una venta finalizada no pueden modificarse';
    END IF;

    IF NEW.sale_status = 'voided'
       AND (NEW.voided_at IS NULL OR NEW.void_reason IS NULL OR btrim(NEW.void_reason) = '') THEN
        RAISE EXCEPTION 'Una venta voided requiere fecha y motivo';
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Numeracion transaccional por empresa, sucursal, tipo y fecha operativa
-- ---------------------------------------------------------------------------

CREATE TABLE sales.document_number_counters (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    branch_id           uuid NOT NULL,
    document_type       varchar(20) NOT NULL
                        CHECK (document_type IN ('order', 'sale', 'return')),
    business_date       date NOT NULL,
    last_value          bigint NOT NULL DEFAULT 0 CHECK (last_value >= 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sales_doc_counter_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sales_doc_counter_scope_unique
        UNIQUE (tenant_id, company_id, branch_id, document_type, business_date)
);

COMMENT ON TABLE sales.document_number_counters IS
'Contadores atomicos por empresa/sucursal/tipo/fecha. company_id y branch_id se validan mediante Organization.';

CREATE OR REPLACE FUNCTION sales.next_document_number(
    p_tenant_id uuid,
    p_company_id uuid,
    p_branch_id uuid,
    p_document_type varchar,
    p_business_date date,
    p_prefix varchar DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_next bigint;
    v_prefix text;
BEGIN
    IF sales.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant del contador no coincide con el contexto autenticado';
    END IF;

    IF p_document_type NOT IN ('order', 'sale', 'return') THEN
        RAISE EXCEPTION 'Tipo documental no permitido: %', p_document_type;
    END IF;

    IF p_company_id IS NULL OR p_branch_id IS NULL OR p_business_date IS NULL THEN
        RAISE EXCEPTION 'Empresa, sucursal y fecha operativa son obligatorias';
    END IF;

    INSERT INTO sales.document_number_counters (
        tenant_id, company_id, branch_id, document_type, business_date, last_value
    ) VALUES (
        p_tenant_id, p_company_id, p_branch_id, p_document_type, p_business_date, 1
    )
    ON CONFLICT (tenant_id, company_id, branch_id, document_type, business_date)
    DO UPDATE SET
        last_value = sales.document_number_counters.last_value + 1,
        updated_at = now()
    RETURNING last_value INTO v_next;

    v_prefix := COALESCE(NULLIF(upper(btrim(p_prefix)), ''), upper(p_document_type));
    RETURN v_prefix || '-' || to_char(p_business_date, 'YYYYMMDD') || '-' || lpad(v_next::text, 6, '0');
END;
$$;

COMMENT ON FUNCTION sales.next_document_number(uuid, uuid, uuid, varchar, date, varchar) IS
'Genera consecutivos sin colision mediante UPSERT. Ejecutar dentro de una transaccion con app.tenant_id establecido.';

-- ---------------------------------------------------------------------------
-- 3. Pedidos y lineas de pedido
-- ---------------------------------------------------------------------------

CREATE TABLE sales.orders (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    order_number            varchar(80) NOT NULL,
    business_date           date NOT NULL,
    order_type              varchar(30) NOT NULL
                            CHECK (order_type IN ('dine_in', 'takeaway', 'delivery', 'pickup', 'drive_thru', 'catering', 'other')),
    order_source            varchar(30) NOT NULL DEFAULT 'pos'
                            CHECK (order_source IN ('pos', 'kiosk', 'web', 'mobile', 'phone', 'marketplace', 'table_qr', 'api', 'other')),
    order_status            varchar(30) NOT NULL DEFAULT 'draft'
                            CHECK (order_status IN ('draft', 'open', 'submitted', 'partially_fulfilled', 'completed', 'cancelled', 'voided')),
    customer_id             uuid,
    customer_name_snapshot  varchar(180),
    customer_phone_snapshot varchar(40),
    guest_count             smallint CHECK (guest_count IS NULL OR guest_count BETWEEN 1 AND 500),
    requested_fulfillment_at timestamptz,
    origin_terminal_id      uuid,
    created_by_user_id      uuid,
    assigned_server_user_id uuid,
    currency_code           char(3) NOT NULL,
    subtotal_amount         numeric(19,4) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_amount         numeric(19,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount            numeric(19,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    order_notes             text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    opened_at               timestamptz,
    submitted_at            timestamptz,
    closed_at               timestamptz,
    cancelled_at            timestamptz,
    cancellation_reason     text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz,
    CONSTRAINT orders_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT orders_tenant_branch_id_unique UNIQUE (tenant_id, branch_id, id),
    CONSTRAINT orders_tenant_company_branch_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT orders_number_per_branch_unique UNIQUE (tenant_id, branch_id, order_number),
    CONSTRAINT orders_currency_upper CHECK (currency_code = upper(currency_code)),
    CONSTRAINT orders_total_consistent CHECK (total_amount = subtotal_amount - discount_amount),
    CONSTRAINT orders_discount_not_over_subtotal CHECK (discount_amount <= subtotal_amount),
    CONSTRAINT orders_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT orders_cancel_reason CHECK (
        (order_status NOT IN ('cancelled', 'voided')) OR
        (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> '')
    )
);

CREATE INDEX ix_orders_branch_status_date
    ON sales.orders (tenant_id, branch_id, business_date, order_status)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_orders_customer_created
    ON sales.orders (tenant_id, customer_id, created_at DESC)
    WHERE customer_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_orders_fulfillment_queue
    ON sales.orders (tenant_id, branch_id, requested_fulfillment_at, order_status)
    WHERE order_status IN ('submitted', 'partially_fulfilled') AND deleted_at IS NULL;

CREATE TABLE sales.order_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    order_id                uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    product_id              uuid,
    variant_id              uuid,
    menu_item_id            uuid,
    is_custom_item          boolean NOT NULL DEFAULT false,
    product_code_snapshot   varchar(80),
    product_name_snapshot   varchar(200) NOT NULL,
    variant_name_snapshot   varchar(160),
    unit_code_snapshot      varchar(40),
    tax_category_id         uuid,
    quantity                numeric(18,4) NOT NULL CHECK (quantity > 0),
    unit_price              numeric(19,4) NOT NULL CHECK (unit_price >= 0),
    line_subtotal           numeric(19,4) NOT NULL CHECK (line_subtotal >= 0),
    line_discount           numeric(19,4) NOT NULL DEFAULT 0 CHECK (line_discount >= 0),
    line_total              numeric(19,4) NOT NULL CHECK (line_total >= 0),
    item_note               text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_items_order_line_unique UNIQUE (tenant_id, order_id, line_number),
    CONSTRAINT order_items_tenant_order_id_unique UNIQUE (tenant_id, order_id, id),
    CONSTRAINT order_items_order_fk FOREIGN KEY (tenant_id, order_id)
        REFERENCES sales.orders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT order_items_total_consistent CHECK (line_total = line_subtotal - line_discount),
    CONSTRAINT order_items_discount_not_over_subtotal CHECK (line_discount <= line_subtotal),
    CONSTRAINT order_items_product_shape CHECK (
        (is_custom_item = true AND product_id IS NULL AND variant_id IS NULL)
        OR (is_custom_item = false AND product_id IS NOT NULL)
    ),
    CONSTRAINT order_items_variant_requires_product CHECK (variant_id IS NULL OR product_id IS NOT NULL)
);

CREATE INDEX ix_order_items_order
    ON sales.order_items (tenant_id, order_id, line_number);
CREATE INDEX ix_order_items_product
    ON sales.order_items (tenant_id, product_id, variant_id)
    WHERE product_id IS NOT NULL;

CREATE TABLE sales.order_item_modifiers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    order_item_id           uuid NOT NULL,
    modifier_group_id       uuid,
    modifier_option_id      uuid,
    group_name_snapshot     varchar(140) NOT NULL,
    option_name_snapshot    varchar(160) NOT NULL,
    quantity                numeric(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price_delta        numeric(19,4) NOT NULL DEFAULT 0,
    total_price_delta       numeric(19,4) NOT NULL DEFAULT 0,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_item_modifiers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_item_modifiers_item_fk FOREIGN KEY (tenant_id, order_item_id)
        REFERENCES sales.order_items (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_order_item_modifiers_item
    ON sales.order_item_modifiers (tenant_id, order_item_id);

CREATE TABLE sales.order_discounts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    order_id                uuid NOT NULL,
    discount_source_id      uuid,
    discount_code_snapshot  varchar(80),
    discount_name_snapshot  varchar(140) NOT NULL,
    discount_type           varchar(20) NOT NULL CHECK (discount_type IN ('fixed', 'percentage')),
    discount_value          numeric(19,6) NOT NULL CHECK (discount_value > 0),
    discount_amount         numeric(19,4) NOT NULL CHECK (discount_amount > 0),
    reason                  text,
    authorized_by_user_id   uuid,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_discounts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_discounts_order_fk FOREIGN KEY (tenant_id, order_id)
        REFERENCES sales.orders (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_order_discounts_order
    ON sales.order_discounts (tenant_id, order_id);

-- ---------------------------------------------------------------------------
-- 4. Asignacion temporal de mesas y notas de pedido
-- ---------------------------------------------------------------------------

CREATE TABLE sales.order_table_assignments (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    order_id                uuid NOT NULL,
    resource_id             uuid NOT NULL,
    assigned_by_user_id     uuid,
    assigned_at             timestamptz NOT NULL DEFAULT now(),
    released_by_user_id     uuid,
    released_at             timestamptz,
    notes                   text,
    CONSTRAINT order_table_assignments_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_table_assignment_order_fk FOREIGN KEY (tenant_id, company_id, branch_id, order_id)
        REFERENCES sales.orders (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT order_table_assignment_dates CHECK (released_at IS NULL OR released_at >= assigned_at)
);

CREATE UNIQUE INDEX uq_order_table_active_assignment
    ON sales.order_table_assignments (tenant_id, resource_id)
    WHERE released_at IS NULL;
CREATE INDEX ix_order_table_assignments_order
    ON sales.order_table_assignments (tenant_id, order_id, assigned_at DESC);

COMMENT ON COLUMN sales.order_table_assignments.resource_id IS
'UUID logico de organization.dining_tables. La aplicacion valida que la mesa este activa y pertenezca al mismo tenant, empresa y sucursal del pedido.';

CREATE TABLE sales.order_notes (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    order_id            uuid NOT NULL,
    note_type           varchar(20) NOT NULL DEFAULT 'internal'
                        CHECK (note_type IN ('internal', 'customer', 'kitchen', 'fulfillment')),
    note_text           text NOT NULL,
    author_user_id      uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_notes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_notes_order_fk FOREIGN KEY (tenant_id, order_id)
        REFERENCES sales.orders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT order_notes_not_blank CHECK (btrim(note_text) <> '')
);

CREATE INDEX ix_order_notes_order_date
    ON sales.order_notes (tenant_id, order_id, created_at);

CREATE TABLE sales.order_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    order_id            uuid NOT NULL,
    previous_status     varchar(30),
    new_status          varchar(30) NOT NULL
                        CHECK (new_status IN ('draft', 'open', 'submitted', 'partially_fulfilled', 'completed', 'cancelled', 'voided')),
    changed_by_user_id  uuid,
    change_source       varchar(30) NOT NULL DEFAULT 'application',
    reason              text,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT order_status_history_order_fk FOREIGN KEY (tenant_id, order_id)
        REFERENCES sales.orders (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_order_status_history_order_time
    ON sales.order_status_history (tenant_id, order_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 5. Checks / ventas finalizadas y sus snapshots
-- ---------------------------------------------------------------------------

CREATE TABLE sales.sales (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid NOT NULL,
    branch_id                   uuid NOT NULL,
    order_id                    uuid NOT NULL,
    sale_number                 varchar(80) NOT NULL,
    business_date               date NOT NULL,
    sale_status                 varchar(24) NOT NULL DEFAULT 'posted'
                                CHECK (sale_status IN ('posted', 'voided', 'partially_returned', 'returned')),
    sold_at                     timestamptz NOT NULL DEFAULT now(),
    customer_id                 uuid,
    customer_name_snapshot      varchar(180),
    customer_tax_id_snapshot    varchar(80),
    currency_code               char(3) NOT NULL,
    subtotal_amount             numeric(19,4) NOT NULL CHECK (subtotal_amount >= 0),
    discount_amount             numeric(19,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    taxable_base_amount         numeric(19,4) NOT NULL DEFAULT 0 CHECK (taxable_base_amount >= 0),
    tax_amount                  numeric(19,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    rounding_amount             numeric(19,4) NOT NULL DEFAULT 0,
    total_amount                numeric(19,4) NOT NULL CHECK (total_amount >= 0),
    finance_tax_calculation_id  uuid,
    fiscal_document_reference   uuid,
    created_by_user_id          uuid,
    voided_by_user_id           uuid,
    voided_at                   timestamptz,
    void_reason                 text,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sales_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sales_tenant_branch_id_unique UNIQUE (tenant_id, branch_id, id),
    CONSTRAINT sales_tenant_company_branch_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT sales_tenant_order_id_unique UNIQUE (tenant_id, order_id, id),
    CONSTRAINT sales_number_per_branch_unique UNIQUE (tenant_id, branch_id, sale_number),
    CONSTRAINT sales_order_fk FOREIGN KEY (tenant_id, company_id, branch_id, order_id)
        REFERENCES sales.orders (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT sales_currency_upper CHECK (currency_code = upper(currency_code)),
    CONSTRAINT sales_discount_not_over_subtotal CHECK (discount_amount <= subtotal_amount),
    CONSTRAINT sales_total_consistent CHECK (
        total_amount = taxable_base_amount + tax_amount + rounding_amount
    ),
    CONSTRAINT sales_taxable_base_consistent CHECK (
        taxable_base_amount = subtotal_amount - discount_amount
    ),
    CONSTRAINT sales_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT sales_void_fields CHECK (
        (sale_status <> 'voided') OR
        (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason) <> '')
    )
);

CREATE INDEX ix_sales_branch_date_status
    ON sales.sales (tenant_id, branch_id, business_date, sale_status);
CREATE INDEX ix_sales_order
    ON sales.sales (tenant_id, order_id, sold_at);
CREATE INDEX ix_sales_customer_date
    ON sales.sales (tenant_id, customer_id, sold_at DESC)
    WHERE customer_id IS NOT NULL;

CREATE TABLE sales.sale_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_id                 uuid NOT NULL,
    order_id                uuid NOT NULL,
    order_item_id           uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    product_id              uuid,
    variant_id              uuid,
    product_code_snapshot   varchar(80),
    product_name_snapshot   varchar(200) NOT NULL,
    variant_name_snapshot   varchar(160),
    unit_code_snapshot      varchar(40),
    tax_category_id         uuid,
    tax_code_snapshot       varchar(60),
    tax_rate_snapshot       numeric(9,6) CHECK (tax_rate_snapshot IS NULL OR tax_rate_snapshot >= 0),
    quantity                numeric(18,4) NOT NULL CHECK (quantity > 0),
    unit_price              numeric(19,4) NOT NULL CHECK (unit_price >= 0),
    line_subtotal           numeric(19,4) NOT NULL CHECK (line_subtotal >= 0),
    line_discount           numeric(19,4) NOT NULL DEFAULT 0 CHECK (line_discount >= 0),
    taxable_base_amount     numeric(19,4) NOT NULL CHECK (taxable_base_amount >= 0),
    tax_amount              numeric(19,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    line_total              numeric(19,4) NOT NULL CHECK (line_total >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sale_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sale_items_tenant_sale_id_unique UNIQUE (tenant_id, sale_id, id),
    CONSTRAINT sale_items_sale_order_fk FOREIGN KEY (tenant_id, order_id, sale_id)
        REFERENCES sales.sales (tenant_id, order_id, id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_order_item_fk FOREIGN KEY (tenant_id, order_id, order_item_id)
        REFERENCES sales.order_items (tenant_id, order_id, id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_discount_not_over_subtotal CHECK (line_discount <= line_subtotal),
    CONSTRAINT sale_items_taxable_consistent CHECK (taxable_base_amount = line_subtotal - line_discount),
    CONSTRAINT sale_items_total_consistent CHECK (line_total = taxable_base_amount + tax_amount)
);

CREATE INDEX ix_sale_items_sale
    ON sales.sale_items (tenant_id, sale_id, line_number);
CREATE INDEX ix_sale_items_product
    ON sales.sale_items (tenant_id, product_id, variant_id)
    WHERE product_id IS NOT NULL;

CREATE TABLE sales.sale_item_modifiers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_item_id            uuid NOT NULL,
    modifier_group_id       uuid,
    modifier_option_id      uuid,
    group_name_snapshot     varchar(140) NOT NULL,
    option_name_snapshot    varchar(160) NOT NULL,
    quantity                numeric(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price_delta        numeric(19,4) NOT NULL DEFAULT 0,
    total_price_delta       numeric(19,4) NOT NULL DEFAULT 0,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sale_item_modifiers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sale_item_modifiers_item_fk FOREIGN KEY (tenant_id, sale_item_id)
        REFERENCES sales.sale_items (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_sale_item_modifiers_item
    ON sales.sale_item_modifiers (tenant_id, sale_item_id);

CREATE TABLE sales.sale_discounts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_id                 uuid NOT NULL,
    discount_source_id      uuid,
    discount_code_snapshot  varchar(80),
    discount_name_snapshot  varchar(140) NOT NULL,
    discount_type           varchar(20) NOT NULL CHECK (discount_type IN ('fixed', 'percentage')),
    discount_value          numeric(19,6) NOT NULL CHECK (discount_value > 0),
    discount_amount         numeric(19,4) NOT NULL CHECK (discount_amount > 0),
    reason                  text,
    authorized_by_user_id   uuid,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sale_discounts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sale_discounts_sale_fk FOREIGN KEY (tenant_id, sale_id)
        REFERENCES sales.sales (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_sale_discounts_sale
    ON sales.sale_discounts (tenant_id, sale_id);

CREATE TABLE sales.sale_tax_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_id                 uuid NOT NULL,
    tax_code_snapshot       varchar(60) NOT NULL,
    tax_name_snapshot       varchar(140) NOT NULL,
    jurisdiction_code       varchar(60),
    tax_rate                numeric(9,6) NOT NULL CHECK (tax_rate >= 0),
    taxable_base_amount     numeric(19,4) NOT NULL CHECK (taxable_base_amount >= 0),
    tax_amount              numeric(19,4) NOT NULL CHECK (tax_amount >= 0),
    finance_tax_line_ref    uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sale_tax_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sale_tax_lines_sale_fk FOREIGN KEY (tenant_id, sale_id)
        REFERENCES sales.sales (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_sale_tax_lines_sale
    ON sales.sale_tax_lines (tenant_id, sale_id);

CREATE TABLE sales.sale_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_id             uuid NOT NULL,
    previous_status     varchar(24),
    new_status          varchar(24) NOT NULL
                        CHECK (new_status IN ('posted', 'voided', 'partially_returned', 'returned')),
    changed_by_user_id  uuid,
    change_source       varchar(30) NOT NULL DEFAULT 'application',
    reason              text,
    occurred_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT sale_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT sale_status_history_sale_fk FOREIGN KEY (tenant_id, sale_id)
        REFERENCES sales.sales (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_sale_status_history_sale_time
    ON sales.sale_status_history (tenant_id, sale_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 6. Devoluciones comerciales (el movimiento monetario de reembolso es Payments)
-- ---------------------------------------------------------------------------

CREATE TABLE sales.returns (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid NOT NULL,
    branch_id                   uuid NOT NULL,
    sale_id                     uuid NOT NULL,
    return_number               varchar(80) NOT NULL,
    business_date               date NOT NULL,
    return_status               varchar(24) NOT NULL DEFAULT 'requested'
                                CHECK (return_status IN ('requested', 'approved', 'received', 'completed', 'rejected', 'cancelled')),
    return_reason_code          varchar(50),
    return_reason               text NOT NULL,
    currency_code               char(3) NOT NULL,
    refund_subtotal_amount      numeric(19,4) NOT NULL DEFAULT 0 CHECK (refund_subtotal_amount >= 0),
    refund_tax_amount           numeric(19,4) NOT NULL DEFAULT 0 CHECK (refund_tax_amount >= 0),
    refund_total_amount         numeric(19,4) NOT NULL DEFAULT 0 CHECK (refund_total_amount >= 0),
    payment_refund_request_id   uuid,
    requested_by_user_id        uuid,
    approved_by_user_id         uuid,
    received_by_user_id         uuid,
    completed_by_user_id        uuid,
    requested_at                timestamptz NOT NULL DEFAULT now(),
    approved_at                 timestamptz,
    received_at                 timestamptz,
    completed_at                timestamptz,
    rejection_reason            text,
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT returns_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT returns_tenant_sale_id_unique UNIQUE (tenant_id, sale_id, id),
    CONSTRAINT returns_tenant_company_branch_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT returns_number_per_branch_unique UNIQUE (tenant_id, branch_id, return_number),
    CONSTRAINT returns_sale_fk FOREIGN KEY (tenant_id, company_id, branch_id, sale_id)
        REFERENCES sales.sales (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT returns_currency_upper CHECK (currency_code = upper(currency_code)),
    CONSTRAINT returns_reason_not_blank CHECK (btrim(return_reason) <> ''),
    CONSTRAINT returns_total_consistent CHECK (
        refund_total_amount = refund_subtotal_amount + refund_tax_amount
    ),
    CONSTRAINT returns_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT returns_rejection_reason CHECK (return_status <> 'rejected' OR
        (rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
);

CREATE INDEX ix_returns_sale_date
    ON sales.returns (tenant_id, sale_id, requested_at DESC);
CREATE INDEX ix_returns_branch_status_date
    ON sales.returns (tenant_id, branch_id, business_date, return_status);

CREATE TABLE sales.return_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    sale_id                 uuid NOT NULL,
    return_id               uuid NOT NULL,
    sale_item_id            uuid NOT NULL,
    quantity                numeric(18,4) NOT NULL CHECK (quantity > 0),
    reason                  text,
    inventory_disposition   varchar(24) NOT NULL DEFAULT 'review_required'
                            CHECK (inventory_disposition IN ('review_required', 'restock_requested', 'damaged', 'waste', 'not_restockable')),
    refund_subtotal_amount  numeric(19,4) NOT NULL CHECK (refund_subtotal_amount >= 0),
    refund_tax_amount       numeric(19,4) NOT NULL DEFAULT 0 CHECK (refund_tax_amount >= 0),
    refund_total_amount     numeric(19,4) NOT NULL CHECK (refund_total_amount >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT return_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT return_items_return_fk FOREIGN KEY (tenant_id, sale_id, return_id)
        REFERENCES sales.returns (tenant_id, sale_id, id) ON DELETE RESTRICT,
    CONSTRAINT return_items_sale_item_fk FOREIGN KEY (tenant_id, sale_id, sale_item_id)
        REFERENCES sales.sale_items (tenant_id, sale_id, id) ON DELETE RESTRICT,
    CONSTRAINT return_items_total_consistent CHECK (
        refund_total_amount = refund_subtotal_amount + refund_tax_amount
    )
);

CREATE INDEX ix_return_items_return
    ON sales.return_items (tenant_id, return_id);
CREATE INDEX ix_return_items_sale_item
    ON sales.return_items (tenant_id, sale_item_id);

-- ---------------------------------------------------------------------------
-- 7. Idempotencia para comandos HTTP, POS y reintentos de red
-- ---------------------------------------------------------------------------

CREATE TABLE sales.idempotency_records (
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
    CONSTRAINT idempotency_records_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT idempotency_operation_not_blank CHECK (btrim(operation_code) <> ''),
    CONSTRAINT idempotency_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT idempotency_hash_shape CHECK (request_hash ~ '^[0-9a-fA-F]{64}$'),
    CONSTRAINT idempotency_expiration CHECK (expires_at > created_at),
    CONSTRAINT idempotency_success_shape CHECK (
        processing_status <> 'succeeded' OR
        (resource_type IS NOT NULL AND resource_id IS NOT NULL AND response_status IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_sales_idempotency_scope
    ON sales.idempotency_records (tenant_id, operation_code, idempotency_key);
CREATE INDEX ix_sales_idempotency_expiration
    ON sales.idempotency_records (expires_at);

CREATE OR REPLACE FUNCTION sales.validate_idempotency_record()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_request_hash char(64);
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT ir.request_hash
        INTO v_existing_request_hash
        FROM sales.idempotency_records ir
        WHERE ir.tenant_id = NEW.tenant_id
          AND ir.operation_code = NEW.operation_code
          AND ir.idempotency_key = NEW.idempotency_key;

        IF FOUND AND v_existing_request_hash IS DISTINCT FROM NEW.request_hash THEN
            RAISE EXCEPTION 'La clave idempotente ya fue usada con una solicitud distinta';
        END IF;
    ELSE
        IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
           OR NEW.operation_code IS DISTINCT FROM OLD.operation_code
           OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
           OR NEW.request_hash IS DISTINCT FROM OLD.request_hash
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'Una clave idempotente no puede cambiar su identidad';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_idempotency_validate
BEFORE INSERT OR UPDATE ON sales.idempotency_records
FOR EACH ROW EXECUTE FUNCTION sales.validate_idempotency_record();

-- ---------------------------------------------------------------------------
-- 8. Triggers: updated_at y proteccion de tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'document_number_counters', 'orders',
        'order_items', 'sales', 'returns', 'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON sales.%I FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'document_number_counters', 'orders',
        'order_items', 'order_item_modifiers', 'order_discounts',
        'order_table_assignments', 'order_notes', 'order_status_history',
        'sales', 'sale_items', 'sale_item_modifiers', 'sale_discounts',
        'sale_tax_lines', 'sale_status_history', 'returns', 'return_items',
        'idempotency_records'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON sales.%I FOR EACH ROW EXECUTE FUNCTION sales.prevent_tenant_change()',
            'trg_' || v_table || '_tenant_immutable', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_sales_posted_immutable
BEFORE UPDATE OR DELETE ON sales.sales
FOR EACH ROW EXECUTE FUNCTION sales.prevent_posted_sale_mutation();

-- Los snapshots finalizados y el historial son append-only. Una correccion
-- comercial debe expresarse como anulacion/devolucion o documento adicional.
DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'order_status_history', 'sale_items', 'sale_item_modifiers',
        'sale_discounts', 'sale_tax_lines', 'sale_status_history', 'return_items'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON sales.%I FOR EACH ROW EXECUTE FUNCTION sales.prevent_record_mutation()',
            'trg_' || v_table || '_immutable', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Row Level Security: todas las tablas pertenecen a un tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'document_number_counters', 'orders',
        'order_items', 'order_item_modifiers', 'order_discounts',
        'order_table_assignments', 'order_notes', 'order_status_history',
        'sales', 'sale_items', 'sale_item_modifiers', 'sale_discounts',
        'sale_tax_lines', 'sale_status_history', 'returns', 'return_items',
        'idempotency_records'
    ] LOOP
        EXECUTE format('ALTER TABLE sales.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE sales.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY %I ON sales.%I USING (tenant_id = sales.current_tenant_id()) WITH CHECK (tenant_id = sales.current_tenant_id())',
            'tenant_isolation', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Comentarios de propiedad y contratos de integracion
-- ---------------------------------------------------------------------------

COMMENT ON TABLE sales.orders IS
'Pedido comercial. customer_id, origin_terminal_id y user ids son referencias logicas; el contexto tenant/company/branch se valida en application.';
COMMENT ON TABLE sales.order_items IS
'Lineas del pedido con snapshots de Catalog. No FK a Catalog para mantener independencia de modulos.';
COMMENT ON TABLE sales.order_table_assignments IS
'Asignacion operativa de recursos fisicos a pedidos. Los recursos pertenecen a Organization y se referencian por UUID logico.';
COMMENT ON TABLE sales.sales IS
'Check/venta finalizada e inmutable en sus importes. Un pedido puede generar varios checks para dividir la cuenta.';
COMMENT ON TABLE sales.sale_items IS
'Snapshot comercial de lineas vendidas. Los importes e identificadores maestros se conservan aunque Catalog cambie despues.';
COMMENT ON TABLE sales.sale_tax_lines IS
'Resultado de calculo recibido de Finance y persistido como snapshot; Sales no calcula tasas fiscales.';
COMMENT ON TABLE sales.returns IS
'Devolucion comercial. payment_refund_request_id es referencia logica al flujo de reembolso de Payments.';
COMMENT ON TABLE sales.return_items IS
'Lineas devueltas. inventory_disposition expresa la solicitud comercial; Inventory decide y ejecuta el movimiento de stock.';
COMMENT ON TABLE sales.idempotency_records IS
'Evita duplicar comandos por reintentos. No guardar cuerpos de pago, PAN, CVV ni secretos aqui.';

-- Permisos que deben registrarse en identity.permissions (Identity es propietario):
--   sales.orders.read / sales.orders.create / sales.orders.update
--   sales.orders.submit / sales.orders.cancel / sales.orders.assign_table
--   sales.discounts.apply / sales.discounts.approve
--   sales.checks.create / sales.checks.split / sales.checks.close
--   sales.sales.read / sales.sales.void
--   sales.returns.create / sales.returns.approve / sales.returns.receive
--   sales.dining.manage
-- La aplicacion debe comprobar el plan/modulo 'pos_sales' habilitado en platform
-- y el alcance de usuario (tenant/company/branch) en Identity/Organization.

-- Eventos recomendados para contracts/events (versionar el payload):
--   sales.order_created.v1
--   sales.order_submitted.v1
--   sales.order_cancelled.v1
--   sales.order_item_changed.v1
--   sales.sale_posted.v1
--   sales.sale_voided.v1
--   sales.return_requested.v1
--   sales.return_approved.v1
--   sales.return_completed.v1
-- Consumo esperado:
--   Kitchen: order_submitted/order_item_changed.
--   Inventory: sale_posted/return_completed (reservas y consumos segun politica).
--   Payments: solicitud de cobro/reembolso via puertos/contratos; no FK cruzada.
--   Cash: eventos de cobros/efectivo procesados por Payments/Cash.
--   Customers: actualizacion de historial/puntos mediante eventos.
--   Finance: cotizacion y calculo tributario mediante contrato, guardando snapshots.
--
-- IMPORTANTE DE CONSISTENCIA:
--   Para publicar eventos sin perderlos, integrar Transactional Outbox en el
--   adaptador messaging (o incorporar tabla outbox en un modulo de infraestructura
--   transversal). No publicar el evento antes de confirmar la transaccion local.
--   Idempotencia del consumidor y Saga/compensaciones se implementan en application.

-- ---------------------------------------------------------------------------
-- 11. Ejemplo de uso del contexto RLS y numeracion
-- ---------------------------------------------------------------------------
-- BEGIN;
-- SET LOCAL app.tenant_id = 'UUID_DEL_TENANT_AUTORIZADO';
-- SELECT sales.next_document_number(
--     'UUID_DEL_TENANT_AUTORIZADO'::uuid,
--     'UUID_DE_COMPANY_VALIDADA'::uuid,
--     'UUID_DE_BRANCH_VALIDADA'::uuid,
--     'order',
--     DATE '2026-11-18',
--     'ORD'
-- );
-- COMMIT;
--
-- No se acepta tenant_id desde el body HTTP. La API obtiene el tenant de la
-- identidad/sesion verificada. El backend valida company_id/branch_id con
-- Organization, product_id/variant_id/menu_item_id con Catalog y customer_id
-- con Customers antes de insertar.
-- ============================================================================

COMMIT;
