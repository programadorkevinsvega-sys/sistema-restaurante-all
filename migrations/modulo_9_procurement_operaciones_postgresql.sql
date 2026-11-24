-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 9: PROCUREMENT (APROBACIONES, RECEPCIONES Y DEVOLUCIONES)
-- Extension operativa del schema PostgreSQL procurement
-- PostgreSQL 15+
--
-- Requiere modulo_7_procurement_postgresql.sql. No crea otro dominio, schema,
-- proveedor, requisicion, orden, recepcion, inbox ni outbox.
-- ============================================================================

BEGIN;

DO $$
BEGIN
    IF to_regclass('procurement.purchase_requests') IS NULL
       OR to_regclass('procurement.purchase_orders') IS NULL
       OR to_regclass('procurement.goods_receipts') IS NULL THEN
        RAISE EXCEPTION 'Instale primero modulo_7_procurement_postgresql.sql';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion operativa de Procurement por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.tenant_settings (
    tenant_id                       uuid PRIMARY KEY REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    require_requisition_approval    boolean NOT NULL DEFAULT true,
    require_purchase_order_approval boolean NOT NULL DEFAULT true,
    allow_over_receipt               boolean NOT NULL DEFAULT false,
    over_receipt_tolerance_pct      numeric(7,4) NOT NULL DEFAULT 0
                                    CHECK (over_receipt_tolerance_pct BETWEEN 0 AND 100),
    require_receipt_inspection      boolean NOT NULL DEFAULT false,
    default_receipt_tolerance_pct   numeric(7,4) NOT NULL DEFAULT 0
                                    CHECK (default_receipt_tolerance_pct BETWEEN 0 AND 100),
    settings                        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_tenant_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Aprobaciones por etapas e historial de solicitudes
-- ---------------------------------------------------------------------------

ALTER TABLE procurement.purchase_requests
    ADD COLUMN requested_for_user_id uuid,
    ADD COLUMN purpose varchar(220),
    ADD COLUMN estimated_subtotal numeric(20,4) NOT NULL DEFAULT 0 CHECK (estimated_subtotal >= 0),
    ADD COLUMN estimated_tax numeric(20,4) NOT NULL DEFAULT 0 CHECK (estimated_tax >= 0),
    ADD COLUMN deleted_at timestamptz;

ALTER TABLE procurement.purchase_requests
    DROP CONSTRAINT IF EXISTS purchase_requests_request_status_check,
    DROP CONSTRAINT IF EXISTS purchase_requests_status_shape;

ALTER TABLE procurement.purchase_requests
    ADD CONSTRAINT purchase_requests_status_allowed CHECK (
        request_status IN (
            'draft', 'submitted', 'in_review', 'approved', 'partially_ordered',
            'ordered', 'rejected', 'changes_requested', 'cancelled', 'closed'
        )
    ),
    ADD CONSTRAINT purchase_requests_status_shape CHECK (
        (request_status NOT IN ('submitted', 'in_review', 'approved', 'partially_ordered',
                                'ordered', 'rejected', 'changes_requested', 'closed')
         OR submitted_at IS NOT NULL)
        AND (request_status NOT IN ('approved', 'partially_ordered', 'ordered', 'closed')
             OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (request_status <> 'rejected'
             OR (rejected_at IS NOT NULL AND rejected_by_user_id IS NOT NULL
                 AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND (request_status <> 'cancelled'
             OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL
                 AND btrim(cancellation_reason) <> ''))
    );

ALTER TABLE procurement.purchase_request_lines
    ALTER COLUMN catalog_variant_id DROP NOT NULL,
    ADD COLUMN line_type varchar(20) NOT NULL DEFAULT 'goods'
        CHECK (line_type IN ('goods', 'service', 'asset', 'expense', 'other')),
    ADD COLUMN inventory_stock_item_id uuid,
    ADD COLUMN unit_code_snapshot varchar(40),
    ADD COLUMN unit_name_snapshot varchar(100),
    ADD COLUMN preferred_supplier_id uuid,
    ADD COLUMN specification text,
    ADD COLUMN is_capex boolean NOT NULL DEFAULT false,
    ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT purchase_request_lines_item_reference CHECK (
        line_type <> 'goods'
        OR catalog_variant_id IS NOT NULL
        OR inventory_stock_item_id IS NOT NULL
    ),
    ADD CONSTRAINT purchase_request_lines_metadata_object CHECK (jsonb_typeof(metadata) = 'object');

ALTER TABLE procurement.purchase_request_approvals
    ADD COLUMN step_number integer NOT NULL DEFAULT 1 CHECK (step_number > 0),
    ADD COLUMN approval_stage varchar(24) NOT NULL DEFAULT 'department'
        CHECK (approval_stage IN ('department', 'budget', 'procurement', 'executive', 'other')),
    ADD COLUMN idempotency_key varchar(160),
    ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE procurement.purchase_request_approvals
    DROP CONSTRAINT IF EXISTS purchase_request_approvals_action_check,
    ADD CONSTRAINT purchase_request_approvals_action_allowed CHECK (
        action IN ('submitted', 'approved', 'rejected', 'returned', 'cancelled',
                   'ordered', 'changes_requested', 'delegated', 'commented')
    ),
    ADD CONSTRAINT purchase_request_approvals_idempotency_not_blank
        CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> ''),
    ADD CONSTRAINT purchase_request_approvals_metadata_object CHECK (jsonb_typeof(metadata) = 'object');

CREATE UNIQUE INDEX uq_procurement_request_approval_idempotency
    ON procurement.purchase_request_approvals (tenant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX ix_procurement_request_approval_steps
    ON procurement.purchase_request_approvals
       (tenant_id, purchase_request_id, step_number, occurred_at DESC);

CREATE TABLE procurement.purchase_request_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    purchase_request_id uuid NOT NULL,
    previous_status     varchar(24),
    new_status          varchar(24) NOT NULL CHECK (new_status IN (
        'draft', 'submitted', 'in_review', 'approved', 'partially_ordered',
        'ordered', 'rejected', 'changes_requested', 'cancelled', 'closed'
    )),
    reason              text,
    changed_by_user_id  uuid,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    correlation_id      uuid,
    CONSTRAINT procurement_request_status_history_request_fk
        FOREIGN KEY (tenant_id, purchase_request_id)
        REFERENCES procurement.purchase_requests (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_request_status_history_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_request_status_history
    ON procurement.purchase_request_status_history
       (tenant_id, purchase_request_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- 3. Ordenes consolidadas, aprobaciones y entregas programadas
-- ---------------------------------------------------------------------------

CREATE TABLE procurement.purchase_order_requests (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    purchase_order_id   uuid NOT NULL,
    purchase_request_id uuid NOT NULL,
    linked_at           timestamptz NOT NULL DEFAULT now(),
    linked_by_user_id   uuid,
    CONSTRAINT procurement_po_requests_order_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_po_requests_request_fk
        FOREIGN KEY (tenant_id, company_id, purchase_request_id)
        REFERENCES procurement.purchase_requests (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_po_requests_pair_unique
        UNIQUE (tenant_id, company_id, purchase_order_id, purchase_request_id),
    CONSTRAINT procurement_po_requests_id_unique UNIQUE (tenant_id, id)
);

INSERT INTO procurement.purchase_order_requests
    (tenant_id, company_id, purchase_order_id, purchase_request_id)
SELECT tenant_id, company_id, id, purchase_request_id
FROM procurement.purchase_orders
WHERE purchase_request_id IS NOT NULL
ON CONFLICT (tenant_id, company_id, purchase_order_id, purchase_request_id) DO NOTHING;

ALTER TABLE procurement.purchase_orders
    DROP CONSTRAINT IF EXISTS purchase_orders_source_request_fk,
    ADD CONSTRAINT purchase_orders_request_association_fk
        FOREIGN KEY (tenant_id, company_id, id, purchase_request_id)
        REFERENCES procurement.purchase_order_requests
            (tenant_id, company_id, purchase_order_id, purchase_request_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE procurement.purchase_order_lines
    ADD COLUMN supplier_quote_line_id uuid,
    ADD COLUMN supplier_quote_id uuid,
    ADD COLUMN line_type varchar(20) NOT NULL DEFAULT 'goods'
        CHECK (line_type IN ('goods', 'service', 'asset', 'expense', 'other')),
    ADD COLUMN inventory_stock_item_id uuid,
    ADD COLUMN quantity_cancelled numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_cancelled >= 0),
    ADD COLUMN quantity_received numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
    ADD COLUMN quantity_returned numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_returned >= 0),
    ADD COLUMN unit_code_snapshot varchar(40),
    ADD COLUMN unit_name_snapshot varchar(100),
    ADD COLUMN discount_rate numeric(7,4) NOT NULL DEFAULT 0 CHECK (discount_rate BETWEEN 0 AND 100),
    ADD COLUMN tax_rate_snapshot numeric(7,4)
        CHECK (tax_rate_snapshot IS NULL OR tax_rate_snapshot BETWEEN 0 AND 100),
    ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE procurement.purchase_order_lines
    ALTER COLUMN catalog_variant_id DROP NOT NULL,
    DROP CONSTRAINT IF EXISTS purchase_order_lines_request_fk,
    ADD CONSTRAINT purchase_order_lines_item_reference CHECK (
        line_type <> 'goods'
        OR catalog_variant_id IS NOT NULL
        OR inventory_stock_item_id IS NOT NULL
    ),
    ADD CONSTRAINT purchase_order_lines_quantity_bounds CHECK (
        quantity_cancelled <= ordered_quantity
        AND quantity_returned <= quantity_received
    ),
    ADD CONSTRAINT purchase_order_lines_quote_pair CHECK (
        (supplier_quote_id IS NULL) = (supplier_quote_line_id IS NULL)
    ),
    ADD CONSTRAINT purchase_order_lines_metadata_object CHECK (jsonb_typeof(metadata) = 'object');

UPDATE procurement.purchase_order_lines pol
   SET quantity_received = COALESCE(received.total_quantity, 0)
  FROM (
      SELECT grl.tenant_id, grl.company_id, grl.purchase_order_line_id,
             SUM(grl.quantity_received) AS total_quantity
        FROM procurement.goods_receipt_lines grl
        JOIN procurement.goods_receipts gr
          ON gr.tenant_id = grl.tenant_id
         AND gr.company_id = grl.company_id
         AND gr.id = grl.goods_receipt_id
       WHERE gr.receipt_status = 'posted'
       GROUP BY grl.tenant_id, grl.company_id, grl.purchase_order_line_id
  ) received
 WHERE pol.tenant_id = received.tenant_id
   AND pol.company_id = received.company_id
   AND pol.id = received.purchase_order_line_id;

CREATE TABLE procurement.purchase_order_line_schedules (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    purchase_order_id       uuid NOT NULL,
    purchase_order_line_id  uuid NOT NULL,
    schedule_number         integer NOT NULL CHECK (schedule_number > 0),
    scheduled_delivery_date date NOT NULL,
    scheduled_quantity      numeric(20,6) NOT NULL CHECK (scheduled_quantity > 0),
    delivery_branch_id      uuid,
    delivery_warehouse_id   uuid,
    schedule_status         varchar(20) NOT NULL DEFAULT 'open'
                            CHECK (schedule_status IN ('open', 'partially_received', 'received', 'cancelled')),
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_po_schedules_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id)
        REFERENCES procurement.purchase_order_lines
            (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_po_schedules_unique
        UNIQUE (tenant_id, purchase_order_line_id, schedule_number),
    CONSTRAINT procurement_po_schedules_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_po_schedules_date
    ON procurement.purchase_order_line_schedules
       (tenant_id, company_id, scheduled_delivery_date, schedule_status);

CREATE TABLE procurement.purchase_order_approval_actions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    purchase_order_id   uuid NOT NULL,
    step_number         integer NOT NULL CHECK (step_number > 0),
    approval_stage      varchar(24) NOT NULL DEFAULT 'management'
                        CHECK (approval_stage IN ('management', 'finance', 'procurement', 'executive', 'other')),
    approver_user_id    uuid NOT NULL,
    decision            varchar(24) NOT NULL
                        CHECK (decision IN ('approved', 'rejected', 'changes_requested', 'delegated', 'commented')),
    comments            text,
    decided_at          timestamptz NOT NULL DEFAULT now(),
    idempotency_key     varchar(160),
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT procurement_po_approval_order_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_po_approval_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT procurement_po_approval_idempotency_not_blank
        CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> ''),
    CONSTRAINT procurement_po_approval_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_procurement_po_approval_idempotency
    ON procurement.purchase_order_approval_actions (tenant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX ix_procurement_po_approval_steps
    ON procurement.purchase_order_approval_actions
       (tenant_id, purchase_order_id, step_number, decided_at DESC);

ALTER TABLE procurement.purchase_order_status_history
    DROP CONSTRAINT IF EXISTS purchase_order_status_history_new_status_check,
    ADD CONSTRAINT purchase_order_status_history_status_allowed CHECK (
        new_status IN ('draft', 'pending_approval', 'approved', 'issued', 'sent',
                       'acknowledged', 'partially_received', 'received',
                       'changes_requested', 'rejected', 'cancelled', 'closed')
    );

ALTER TABLE procurement.purchase_orders
    ADD COLUMN order_type varchar(24) NOT NULL DEFAULT 'standard'
        CHECK (order_type IN ('standard', 'blanket_release', 'service', 'capex', 'emergency', 'other')),
    ADD COLUMN supplier_quote_id uuid,
    ADD COLUMN supplier_agreement_id uuid,
    ADD COLUMN procurement_sourcing_request_id uuid,
    ADD COLUMN exchange_rate numeric(20,10) CHECK (exchange_rate IS NULL OR exchange_rate > 0),
    ADD COLUMN supplier_name_snapshot varchar(220),
    ADD COLUMN supplier_tax_id_snapshot varchar(100),
    ADD COLUMN supplier_address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN ship_to_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN bill_to_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN payment_terms_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN delivery_terms text,
    ADD COLUMN sent_at timestamptz,
    ADD COLUMN acknowledged_at timestamptz,
    ADD COLUMN other_charges_amount numeric(20,4) NOT NULL DEFAULT 0 CHECK (other_charges_amount >= 0),
    ADD COLUMN tax_included boolean NOT NULL DEFAULT false,
    ADD COLUMN requested_by_user_id uuid,
    ADD COLUMN supplier_notes text,
    ADD COLUMN internal_notes text,
    ADD COLUMN rejection_reason text;

ALTER TABLE procurement.supplier_agreements
    ADD CONSTRAINT procurement_supplier_agreements_company_supplier_id_unique
        UNIQUE (tenant_id, company_id, supplier_id, id);

ALTER TABLE procurement.supplier_quote_lines
    ADD CONSTRAINT procurement_supplier_quote_lines_quote_id_unique
        UNIQUE (tenant_id, quote_id, id);

ALTER TABLE procurement.purchase_orders
    ADD CONSTRAINT procurement_purchase_orders_sourcing_request_fk
        FOREIGN KEY (tenant_id, company_id, procurement_sourcing_request_id)
        REFERENCES procurement.sourcing_requests (tenant_id, company_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT procurement_purchase_orders_supplier_quote_fk
        FOREIGN KEY (tenant_id, procurement_sourcing_request_id, supplier_id, supplier_quote_id)
        REFERENCES procurement.supplier_quotes
            (tenant_id, sourcing_request_id, supplier_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT procurement_purchase_orders_supplier_agreement_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id, supplier_agreement_id)
        REFERENCES procurement.supplier_agreements
            (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT procurement_purchase_orders_quote_scope_id_unique
        UNIQUE (tenant_id, company_id, id, supplier_quote_id);

ALTER TABLE procurement.purchase_orders
    DROP CONSTRAINT IF EXISTS purchase_orders_order_status_check,
    DROP CONSTRAINT IF EXISTS purchase_orders_status_shape,
    ADD CONSTRAINT purchase_orders_status_allowed CHECK (
        order_status IN ('draft', 'pending_approval', 'approved', 'issued', 'sent',
                         'acknowledged', 'partially_received', 'received',
                         'changes_requested', 'rejected', 'cancelled', 'closed')
    ),
    ADD CONSTRAINT purchase_orders_status_shape CHECK (
        (order_status NOT IN ('approved', 'issued', 'sent', 'acknowledged',
                              'partially_received', 'received', 'closed')
         OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (order_status NOT IN ('issued', 'sent', 'acknowledged',
                                  'partially_received', 'received', 'closed')
             OR (issued_at IS NOT NULL AND issued_by_user_id IS NOT NULL))
        AND (order_status <> 'sent' OR sent_at IS NOT NULL)
        AND (order_status <> 'acknowledged' OR acknowledged_at IS NOT NULL)
        AND (order_status <> 'received' OR received_at IS NOT NULL)
        AND (order_status <> 'rejected'
             OR (rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND jsonb_typeof(supplier_address_snapshot) = 'object'
        AND jsonb_typeof(ship_to_snapshot) = 'object'
        AND jsonb_typeof(bill_to_snapshot) = 'object'
        AND jsonb_typeof(payment_terms_snapshot) = 'object'
    );

CREATE INDEX ix_procurement_po_quote
    ON procurement.purchase_orders (tenant_id, supplier_quote_id)
    WHERE supplier_quote_id IS NOT NULL;

ALTER TABLE procurement.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_request_association_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_request_id)
        REFERENCES procurement.purchase_order_requests
            (tenant_id, company_id, purchase_order_id, purchase_request_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT purchase_order_lines_supplier_quote_order_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, supplier_quote_id)
        REFERENCES procurement.purchase_orders
            (tenant_id, company_id, id, supplier_quote_id) ON DELETE RESTRICT,
    ADD CONSTRAINT purchase_order_lines_supplier_quote_line_fk
        FOREIGN KEY (tenant_id, supplier_quote_id, supplier_quote_line_id)
        REFERENCES procurement.supplier_quote_lines
            (tenant_id, quote_id, id) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- 4. Recepciones, inspecciones, discrepancias y devoluciones
-- ---------------------------------------------------------------------------

ALTER TABLE procurement.goods_receipts
    ADD COLUMN supplier_delivery_note varchar(100),
    ADD COLUMN receiving_location_id uuid,
    ADD COLUMN requires_inventory_posting boolean NOT NULL DEFAULT false,
    ADD COLUMN inventory_movement_id uuid,
    ADD COLUMN carrier_name varchar(160),
    ADD COLUMN vehicle_reference varchar(100),
    ADD COLUMN seal_reference varchar(100),
    ADD COLUMN temperature_c numeric(8,3),
    ADD COLUMN delivery_condition varchar(20) NOT NULL DEFAULT 'acceptable'
        CHECK (delivery_condition IN ('acceptable', 'damaged', 'temperature_issue', 'incomplete', 'other')),
    ADD COLUMN received_by_user_id uuid,
    ADD COLUMN idempotency_key varchar(160),
    ADD COLUMN voided_at timestamptz,
    ADD COLUMN void_reason text,
    ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT procurement_goods_receipts_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    ADD CONSTRAINT procurement_goods_receipts_idempotency_not_blank
        CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> '');

ALTER TABLE procurement.goods_receipts
    DROP CONSTRAINT IF EXISTS goods_receipts_receipt_status_check,
    DROP CONSTRAINT IF EXISTS goods_receipts_post_shape,
    DROP CONSTRAINT IF EXISTS goods_receipts_cancel_shape,
    ADD CONSTRAINT procurement_goods_receipts_status_allowed CHECK (
        receipt_status IN ('draft', 'pending_inventory', 'posted', 'cancelled', 'voided')
    ),
    ADD CONSTRAINT procurement_goods_receipts_status_shape CHECK (
        (receipt_status <> 'draft'
         OR (posted_at IS NULL AND inventory_movement_id IS NULL))
        AND (receipt_status <> 'pending_inventory'
             OR (posted_at IS NOT NULL AND posted_by_user_id IS NOT NULL
                 AND inventory_movement_id IS NULL AND requires_inventory_posting))
        AND (receipt_status <> 'posted'
             OR (posted_at IS NOT NULL AND posted_by_user_id IS NOT NULL
                 AND (inventory_movement_id IS NOT NULL OR NOT requires_inventory_posting)))
        AND (receipt_status <> 'cancelled'
             OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL
                 AND btrim(cancellation_reason) <> ''))
        AND (receipt_status <> 'voided'
             OR (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason) <> ''))
    ),
    ADD CONSTRAINT procurement_goods_receipts_company_id_unique
        UNIQUE (tenant_id, company_id, id),
    ADD CONSTRAINT procurement_goods_receipts_supplier_id_unique
        UNIQUE (tenant_id, company_id, supplier_id, id),
    ADD CONSTRAINT procurement_goods_receipts_order_id_unique
        UNIQUE (tenant_id, company_id, purchase_order_id, id);

ALTER TABLE procurement.goods_receipts
    ALTER COLUMN requires_inventory_posting SET DEFAULT true;

ALTER TABLE procurement.goods_receipt_lines
    ADD COLUMN line_type varchar(20) NOT NULL DEFAULT 'goods'
        CHECK (line_type IN ('goods', 'service', 'asset', 'expense', 'other')),
    ADD COLUMN catalog_variant_id uuid,
    ADD COLUMN inventory_stock_item_id uuid,
    ADD COLUMN item_description_snapshot varchar(240),
    ADD COLUMN quantity_expected numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_expected >= 0),
    ADD COLUMN unit_id uuid,
    ADD COLUMN unit_code_snapshot varchar(40),
    ADD COLUMN unit_name_snapshot varchar(100),
    ADD COLUMN manufacture_date date,
    ADD COLUMN unit_cost_snapshot numeric(20,6) CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0),
    ADD COLUMN inventory_stock_lot_id uuid;

UPDATE procurement.goods_receipt_lines grl
   SET line_type = pol.line_type,
       catalog_variant_id = pol.catalog_variant_id,
       inventory_stock_item_id = pol.inventory_stock_item_id,
       item_description_snapshot = pol.item_description,
       quantity_expected = allocation.allocated_quantity,
       unit_id = pol.unit_id
  FROM procurement.purchase_order_lines pol
  JOIN procurement.purchase_order_allocations allocation
    ON allocation.tenant_id = pol.tenant_id
   AND allocation.company_id = pol.company_id
   AND allocation.purchase_order_id = pol.purchase_order_id
   AND allocation.purchase_order_line_id = pol.id
 WHERE pol.tenant_id = grl.tenant_id
   AND pol.company_id = grl.company_id
   AND pol.purchase_order_id = grl.purchase_order_id
   AND pol.id = grl.purchase_order_line_id
   AND allocation.id = grl.allocation_id;

ALTER TABLE procurement.goods_receipt_lines
    DROP CONSTRAINT IF EXISTS goods_receipt_lines_inspection_status_check,
    DROP CONSTRAINT IF EXISTS goods_receipt_lines_inspection_shape,
    ADD CONSTRAINT procurement_receipt_lines_inspection_status_allowed CHECK (
        inspection_status IN ('pending', 'pending_inspection', 'accepted',
                              'partially_rejected', 'rejected', 'quarantined')
    ),
    ADD CONSTRAINT procurement_receipt_lines_inspection_shape CHECK (
        (inspection_status IN ('pending', 'pending_inspection', 'quarantined')
         AND quantity_accepted = 0 AND quantity_rejected = 0)
        OR (inspection_status = 'accepted'
            AND quantity_accepted = quantity_received AND quantity_rejected = 0)
        OR (inspection_status = 'partially_rejected'
            AND quantity_accepted > 0 AND quantity_rejected > 0
            AND quantity_accepted + quantity_rejected = quantity_received)
        OR (inspection_status = 'rejected'
            AND quantity_accepted = 0 AND quantity_rejected = quantity_received)
    ),
    ADD CONSTRAINT procurement_receipt_lines_item_reference CHECK (
        line_type <> 'goods'
        OR catalog_variant_id IS NOT NULL
        OR inventory_stock_item_id IS NOT NULL
    ),
    ADD CONSTRAINT procurement_receipt_lines_description_not_blank CHECK (
        item_description_snapshot IS NULL OR btrim(item_description_snapshot) <> ''
    ),
    ADD CONSTRAINT procurement_receipt_lines_expiry CHECK (
        expires_on IS NULL OR manufacture_date IS NULL OR expires_on >= manufacture_date
    ),
    ADD CONSTRAINT procurement_receipt_lines_company_receipt_id_unique
        UNIQUE (tenant_id, company_id, goods_receipt_id, id),
    ADD CONSTRAINT procurement_receipt_lines_return_scope_unique
        UNIQUE (tenant_id, company_id, goods_receipt_id, purchase_order_id,
                purchase_order_line_id, id);

CREATE UNIQUE INDEX uq_procurement_receipt_idempotency
    ON procurement.goods_receipts (tenant_id, company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE procurement.goods_receipt_inspections (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    goods_receipt_id    uuid NOT NULL,
    goods_receipt_line_id uuid NOT NULL,
    inspection_type     varchar(24) NOT NULL
                        CHECK (inspection_type IN ('quantity', 'quality', 'temperature',
                                                   'packaging', 'documentation', 'other')),
    inspection_result   varchar(20) NOT NULL
                        CHECK (inspection_result IN ('passed', 'failed', 'conditional', 'not_applicable')),
    measured_value      numeric(20,6),
    expected_value      numeric(20,6),
    measurement_unit    varchar(40),
    inspector_user_id   uuid NOT NULL,
    inspected_at        timestamptz NOT NULL DEFAULT now(),
    notes               text,
    evidence_keys       jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_receipt_inspections_evidence_array CHECK (jsonb_typeof(evidence_keys) = 'array'),
    CONSTRAINT procurement_receipt_inspections_line_fk
        FOREIGN KEY (tenant_id, company_id, goods_receipt_id, goods_receipt_line_id)
        REFERENCES procurement.goods_receipt_lines
            (tenant_id, company_id, goods_receipt_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_receipt_inspections_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_receipt_inspections_line
    ON procurement.goods_receipt_inspections
       (tenant_id, goods_receipt_line_id, inspected_at DESC);

CREATE TABLE procurement.goods_receipt_discrepancies (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    goods_receipt_id    uuid NOT NULL,
    goods_receipt_line_id uuid,
    discrepancy_type    varchar(28) NOT NULL
                        CHECK (discrepancy_type IN ('shortage', 'overage', 'damaged', 'wrong_item',
                            'wrong_uom', 'quality_failure', 'temperature', 'documentation', 'other')),
    severity            varchar(16) NOT NULL DEFAULT 'medium'
                        CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    quantity_affected   numeric(20,6) CHECK (quantity_affected IS NULL OR quantity_affected >= 0),
    description         text NOT NULL,
    resolution_status   varchar(20) NOT NULL DEFAULT 'open'
                        CHECK (resolution_status IN ('open', 'under_review', 'accepted',
                            'credit_requested', 'returned', 'closed')),
    resolution_notes    text,
    reported_by_user_id uuid NOT NULL,
    resolved_by_user_id uuid,
    resolved_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_receipt_discrepancy_description_not_blank CHECK (btrim(description) <> ''),
    CONSTRAINT procurement_receipt_discrepancy_resolution_shape CHECK (
        resolution_status NOT IN ('accepted', 'credit_requested', 'returned', 'closed')
        OR (resolved_at IS NOT NULL AND resolved_by_user_id IS NOT NULL)
    ),
    CONSTRAINT procurement_receipt_discrepancy_receipt_fk
        FOREIGN KEY (tenant_id, company_id, goods_receipt_id)
        REFERENCES procurement.goods_receipts (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_receipt_discrepancy_line_fk
        FOREIGN KEY (tenant_id, company_id, goods_receipt_id, goods_receipt_line_id)
        REFERENCES procurement.goods_receipt_lines
            (tenant_id, company_id, goods_receipt_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_receipt_discrepancy_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_receipt_discrepancies_open
    ON procurement.goods_receipt_discrepancies
       (tenant_id, company_id, resolution_status, severity, created_at DESC);

CREATE TABLE procurement.goods_receipt_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    goods_receipt_id    uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL CHECK (new_status IN (
        'draft', 'pending_inventory', 'posted', 'cancelled', 'voided'
    )),
    changed_by_user_id  uuid,
    reason              text,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    correlation_id      uuid,
    CONSTRAINT procurement_receipt_status_history_receipt_fk
        FOREIGN KEY (tenant_id, company_id, goods_receipt_id)
        REFERENCES procurement.goods_receipts (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_receipt_status_history_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_receipt_status_history
    ON procurement.goods_receipt_status_history
       (tenant_id, goods_receipt_id, changed_at DESC);

CREATE TABLE procurement.supplier_returns (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid,
    supplier_id             uuid NOT NULL,
    purchase_order_id       uuid,
    goods_receipt_id        uuid,
    return_number           varchar(80) NOT NULL,
    return_status           varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (return_status IN ('draft', 'pending_approval', 'approved', 'sent',
                                'acknowledged', 'completed', 'rejected', 'cancelled')),
    return_reason           varchar(32) NOT NULL
                            CHECK (return_reason IN ('damaged', 'wrong_item', 'quality_failure',
                                'expired', 'over_delivery', 'recall', 'other')),
    currency                char(3) NOT NULL DEFAULT 'COP',
    estimated_credit_amount numeric(20,4) NOT NULL DEFAULT 0 CHECK (estimated_credit_amount >= 0),
    requested_by_user_id    uuid NOT NULL,
    approved_by_user_id     uuid,
    approved_at             timestamptz,
    sent_at                 timestamptz,
    completed_at            timestamptz,
    rejected_at             timestamptz,
    rejection_reason        text,
    cancelled_at            timestamptz,
    cancellation_reason     text,
    supplier_rma_reference  varchar(100),
    inventory_movement_id   uuid,
    notes                   text,
    idempotency_key         varchar(160),
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_supplier_returns_number_not_blank CHECK (btrim(return_number) <> ''),
    CONSTRAINT procurement_supplier_returns_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT procurement_supplier_returns_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT procurement_supplier_returns_status_shape CHECK (
        (return_status NOT IN ('approved', 'sent', 'acknowledged', 'completed')
         OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
        AND (return_status NOT IN ('sent', 'acknowledged', 'completed') OR sent_at IS NOT NULL)
        AND (return_status <> 'completed'
             OR (completed_at IS NOT NULL AND inventory_movement_id IS NOT NULL))
        AND (return_status <> 'rejected'
             OR (rejected_at IS NOT NULL AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> ''))
        AND (return_status <> 'cancelled'
             OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> ''))
    ),
    CONSTRAINT procurement_supplier_returns_supplier_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id)
        REFERENCES procurement.supplier_company_profiles (tenant_id, company_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_returns_order_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id, purchase_order_id)
        REFERENCES procurement.purchase_orders (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_returns_receipt_fk
        FOREIGN KEY (tenant_id, company_id, supplier_id, goods_receipt_id)
        REFERENCES procurement.goods_receipts (tenant_id, company_id, supplier_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_returns_receipt_order_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, goods_receipt_id)
        REFERENCES procurement.goods_receipts (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_returns_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT procurement_supplier_returns_id_order_unique
        UNIQUE (tenant_id, company_id, id, purchase_order_id),
    CONSTRAINT procurement_supplier_returns_id_receipt_unique
        UNIQUE (tenant_id, company_id, id, goods_receipt_id),
    CONSTRAINT procurement_supplier_returns_number_unique UNIQUE (tenant_id, company_id, return_number),
    CONSTRAINT procurement_supplier_returns_idempotency_not_blank
        CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> '')
);

CREATE UNIQUE INDEX uq_procurement_supplier_return_idempotency
    ON procurement.supplier_returns (tenant_id, company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX ix_procurement_supplier_returns_status
    ON procurement.supplier_returns (tenant_id, company_id, supplier_id, return_status, created_at DESC);

CREATE TABLE procurement.supplier_return_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    supplier_return_id      uuid NOT NULL,
    purchase_order_id       uuid,
    purchase_order_line_id  uuid,
    goods_receipt_id        uuid,
    goods_receipt_line_id   uuid,
    line_number             integer NOT NULL CHECK (line_number > 0),
    catalog_variant_id      uuid,
    inventory_stock_item_id uuid,
    item_description_snapshot varchar(240) NOT NULL,
    quantity                numeric(20,6) NOT NULL CHECK (quantity > 0),
    unit_id                 uuid,
    unit_cost_snapshot      numeric(20,6) CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0),
    reason_detail           text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_supplier_return_lines_item_reference
        CHECK (catalog_variant_id IS NOT NULL OR inventory_stock_item_id IS NOT NULL),
    CONSTRAINT procurement_supplier_return_lines_description_not_blank
        CHECK (btrim(item_description_snapshot) <> ''),
    CONSTRAINT procurement_supplier_return_lines_order_pair
        CHECK ((purchase_order_id IS NULL) = (purchase_order_line_id IS NULL)),
    CONSTRAINT procurement_supplier_return_lines_receipt_pair
        CHECK ((goods_receipt_id IS NULL) = (goods_receipt_line_id IS NULL)),
    CONSTRAINT procurement_supplier_return_lines_receipt_order_pair
        CHECK (goods_receipt_line_id IS NULL
               OR (purchase_order_id IS NOT NULL AND purchase_order_line_id IS NOT NULL)),
    CONSTRAINT procurement_supplier_return_lines_source_required
        CHECK (purchase_order_line_id IS NOT NULL OR goods_receipt_line_id IS NOT NULL),
    CONSTRAINT procurement_supplier_return_lines_return_fk
        FOREIGN KEY (tenant_id, company_id, supplier_return_id)
        REFERENCES procurement.supplier_returns (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_lines_return_order_fk
        FOREIGN KEY (tenant_id, company_id, supplier_return_id, purchase_order_id)
        REFERENCES procurement.supplier_returns (tenant_id, company_id, id, purchase_order_id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_lines_return_receipt_fk
        FOREIGN KEY (tenant_id, company_id, supplier_return_id, goods_receipt_id)
        REFERENCES procurement.supplier_returns (tenant_id, company_id, id, goods_receipt_id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_lines_order_line_fk
        FOREIGN KEY (tenant_id, company_id, purchase_order_id, purchase_order_line_id)
        REFERENCES procurement.purchase_order_lines (tenant_id, company_id, purchase_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_lines_receipt_line_fk
        FOREIGN KEY (tenant_id, company_id, goods_receipt_id, purchase_order_id,
                     purchase_order_line_id, goods_receipt_line_id)
        REFERENCES procurement.goods_receipt_lines
            (tenant_id, company_id, goods_receipt_id, purchase_order_id,
             purchase_order_line_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_lines_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT procurement_supplier_return_lines_number_unique
        UNIQUE (tenant_id, supplier_return_id, line_number)
);

CREATE INDEX ix_procurement_supplier_return_lines_item
    ON procurement.supplier_return_lines (tenant_id, inventory_stock_item_id)
    WHERE inventory_stock_item_id IS NOT NULL;

CREATE TABLE procurement.supplier_return_status_history (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    supplier_return_id  uuid NOT NULL,
    previous_status     varchar(20),
    new_status          varchar(20) NOT NULL CHECK (new_status IN (
        'draft', 'pending_approval', 'approved', 'sent', 'acknowledged',
        'completed', 'rejected', 'cancelled'
    )),
    reason              text,
    changed_by_user_id  uuid,
    changed_at          timestamptz NOT NULL DEFAULT now(),
    correlation_id      uuid,
    CONSTRAINT procurement_supplier_return_history_return_fk
        FOREIGN KEY (tenant_id, company_id, supplier_return_id)
        REFERENCES procurement.supplier_returns (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT procurement_supplier_return_history_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_supplier_return_history
    ON procurement.supplier_return_status_history
       (tenant_id, supplier_return_id, changed_at DESC);

CREATE TABLE procurement.purchase_documents (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    document_type       varchar(28) NOT NULL
                        CHECK (document_type IN ('request_attachment', 'purchase_order_pdf',
                            'supplier_confirmation', 'delivery_note', 'packing_list',
                            'inspection_evidence', 'return_authorization', 'other')),
    entity_type         varchar(28) NOT NULL
                        CHECK (entity_type IN ('purchase_request', 'purchase_order',
                            'goods_receipt', 'supplier_return', 'supplier_invoice')),
    entity_id           uuid NOT NULL,
    file_name           varchar(255) NOT NULL,
    mime_type           varchar(120),
    file_size_bytes     bigint CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    storage_key         text NOT NULL,
    checksum_sha256     char(64),
    uploaded_by_user_id uuid NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT procurement_purchase_documents_file_name_not_blank CHECK (btrim(file_name) <> ''),
    CONSTRAINT procurement_purchase_documents_storage_key_not_blank CHECK (btrim(storage_key) <> ''),
    CONSTRAINT procurement_purchase_documents_checksum CHECK (
        checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-fA-F]{64}$'
    ),
    CONSTRAINT procurement_purchase_documents_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_procurement_purchase_documents_entity
    ON procurement.purchase_documents (tenant_id, company_id, entity_type, entity_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 5. Triggers, tenant guards y RLS de las nuevas tablas
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION procurement.guard_purchase_request_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_request_id uuid;
    v_status varchar(24);
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.purchase_request_id IS DISTINCT FROM NEW.purchase_request_id THEN
        RAISE EXCEPTION 'No se permite mover una linea entre solicitudes';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
        v_request_id := OLD.purchase_request_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
        v_request_id := NEW.purchase_request_id;
    END IF;

    SELECT request_status INTO v_status
      FROM procurement.purchase_requests
     WHERE tenant_id = v_tenant_id AND id = v_request_id;

    IF v_status NOT IN ('draft', 'changes_requested') THEN
        RAISE EXCEPTION 'Las lineas solo se editan en solicitudes draft o changes_requested';
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.guard_purchase_order_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_company_id uuid;
    v_order_id uuid;
    v_status varchar(24);
BEGIN
    IF TG_OP = 'UPDATE'
       AND (OLD.company_id IS DISTINCT FROM NEW.company_id
            OR OLD.purchase_order_id IS DISTINCT FROM NEW.purchase_order_id) THEN
        RAISE EXCEPTION 'No se permite mover una linea entre ordenes o empresas';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
        v_company_id := OLD.company_id;
        v_order_id := OLD.purchase_order_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
        v_company_id := NEW.company_id;
        v_order_id := NEW.purchase_order_id;
    END IF;

    SELECT order_status INTO v_status
      FROM procurement.purchase_orders
     WHERE tenant_id = v_tenant_id AND company_id = v_company_id AND id = v_order_id;

    IF TG_OP IN ('INSERT', 'DELETE') THEN
        IF v_status NOT IN ('draft', 'changes_requested') THEN
            RAISE EXCEPTION 'Solo se agregan o eliminan lineas de ordenes draft o changes_requested';
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;

    IF v_status NOT IN ('draft', 'changes_requested')
       AND (to_jsonb(NEW) - ARRAY['quantity_received', 'quantity_returned',
                                  'quantity_cancelled', 'updated_at'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['quantity_received', 'quantity_returned',
                                  'quantity_cancelled', 'updated_at']) THEN
        RAISE EXCEPTION 'Una orden aprobada solo permite actualizar contadores de recepcion, devolucion o cancelacion';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.guard_goods_receipt_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_company_id uuid;
    v_receipt_id uuid;
    v_status varchar(20);
BEGIN
    IF TG_OP = 'UPDATE'
       AND (OLD.id IS DISTINCT FROM NEW.id
            OR OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
            OR OLD.company_id IS DISTINCT FROM NEW.company_id
            OR OLD.goods_receipt_id IS DISTINCT FROM NEW.goods_receipt_id) THEN
        RAISE EXCEPTION 'No se permite mover o reidentificar lineas/inspecciones de una recepcion';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
        v_company_id := OLD.company_id;
        v_receipt_id := OLD.goods_receipt_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
        v_company_id := NEW.company_id;
        v_receipt_id := NEW.goods_receipt_id;
    END IF;

    SELECT receipt_status INTO v_status
      FROM procurement.goods_receipts
     WHERE tenant_id = v_tenant_id AND company_id = v_company_id AND id = v_receipt_id;

    IF v_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Lineas e inspecciones solo se editan mientras la recepcion esta en draft';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.guard_purchase_order_request_link()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status varchar(24);
    v_request_status varchar(24);
BEGIN
    SELECT order_status INTO v_order_status
      FROM procurement.purchase_orders
     WHERE tenant_id = NEW.tenant_id
       AND company_id = NEW.company_id
       AND id = NEW.purchase_order_id;

    SELECT request_status INTO v_request_status
      FROM procurement.purchase_requests
     WHERE tenant_id = NEW.tenant_id
       AND company_id = NEW.company_id
       AND id = NEW.purchase_request_id;

    IF v_order_status IS DISTINCT FROM 'draft'
       OR v_request_status IS NULL
       OR v_request_status NOT IN ('approved', 'partially_ordered') THEN
        RAISE EXCEPTION 'Solo se vinculan solicitudes aprobadas a ordenes en draft';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.guard_supplier_return_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_company_id uuid;
    v_return_id uuid;
    v_status varchar(20);
    v_header_purchase_order_id uuid;
    v_header_receipt_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.supplier_return_id IS DISTINCT FROM NEW.supplier_return_id THEN
        RAISE EXCEPTION 'No se permite mover una linea entre devoluciones';
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
        v_company_id := OLD.company_id;
        v_return_id := OLD.supplier_return_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
        v_company_id := NEW.company_id;
        v_return_id := NEW.supplier_return_id;
    END IF;

    SELECT return_status, purchase_order_id, goods_receipt_id
      INTO v_status, v_header_purchase_order_id, v_header_receipt_id
      FROM procurement.supplier_returns
     WHERE tenant_id = v_tenant_id AND company_id = v_company_id AND id = v_return_id;

    IF v_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Las lineas solo se editan mientras la devolucion esta en draft';
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NEW.purchase_order_id IS DISTINCT FROM v_header_purchase_order_id
           OR NEW.goods_receipt_id IS DISTINCT FROM v_header_receipt_id THEN
            RAISE EXCEPTION 'Las lineas deben conservar la orden y recepcion de la devolucion';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE TRIGGER trg_purchase_request_lines_draft_guard
BEFORE INSERT OR UPDATE OR DELETE ON procurement.purchase_request_lines
FOR EACH ROW EXECUTE FUNCTION procurement.guard_purchase_request_line_mutation();

CREATE TRIGGER trg_purchase_order_requests_append_only
BEFORE UPDATE OR DELETE ON procurement.purchase_order_requests
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_purchase_order_requests_status_guard
BEFORE INSERT ON procurement.purchase_order_requests
FOR EACH ROW EXECUTE FUNCTION procurement.guard_purchase_order_request_link();

CREATE TRIGGER trg_purchase_order_lines_draft_guard
BEFORE INSERT OR UPDATE OR DELETE ON procurement.purchase_order_lines
FOR EACH ROW EXECUTE FUNCTION procurement.guard_purchase_order_line_mutation();

CREATE TRIGGER trg_goods_receipt_lines_draft_guard
BEFORE INSERT OR UPDATE OR DELETE ON procurement.goods_receipt_lines
FOR EACH ROW EXECUTE FUNCTION procurement.guard_goods_receipt_child_mutation();

CREATE TRIGGER trg_goods_receipt_inspections_draft_guard
BEFORE INSERT OR UPDATE OR DELETE ON procurement.goods_receipt_inspections
FOR EACH ROW EXECUTE FUNCTION procurement.guard_goods_receipt_child_mutation();

CREATE TRIGGER trg_supplier_return_lines_draft_guard
BEFORE INSERT OR UPDATE OR DELETE ON procurement.supplier_return_lines
FOR EACH ROW EXECUTE FUNCTION procurement.guard_supplier_return_line_mutation();

CREATE TRIGGER trg_purchase_request_status_history_append_only
BEFORE UPDATE OR DELETE ON procurement.purchase_request_status_history
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_purchase_order_approval_actions_append_only
BEFORE UPDATE OR DELETE ON procurement.purchase_order_approval_actions
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_goods_receipt_status_history_append_only
BEFORE UPDATE OR DELETE ON procurement.goods_receipt_status_history
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

CREATE TRIGGER trg_supplier_return_status_history_append_only
BEFORE UPDATE OR DELETE ON procurement.supplier_return_status_history
FOR EACH ROW EXECUTE FUNCTION procurement.prevent_append_only_mutation();

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'purchase_order_line_schedules', 'goods_receipt_discrepancies',
        'supplier_returns', 'supplier_return_lines'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_set_updated_at BEFORE UPDATE ON procurement.%I FOR EACH ROW EXECUTE FUNCTION procurement.set_updated_at()',
            v_table, v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'purchase_request_status_history', 'purchase_order_requests',
        'purchase_order_line_schedules', 'purchase_order_approval_actions',
        'goods_receipt_inspections', 'goods_receipt_discrepancies',
        'goods_receipt_status_history', 'supplier_returns', 'supplier_return_lines',
        'supplier_return_status_history', 'purchase_documents'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_prevent_tenant_change BEFORE UPDATE ON procurement.%I FOR EACH ROW EXECUTE FUNCTION procurement.prevent_tenant_change()',
            v_table, v_table
        );
        EXECUTE format(
            'ALTER TABLE procurement.%I ENABLE ROW LEVEL SECURITY',
            v_table
        );
        EXECUTE format(
            'ALTER TABLE procurement.%I FORCE ROW LEVEL SECURITY',
            v_table
        );
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON procurement.%I USING (tenant_id = procurement.current_tenant_id()) WITH CHECK (tenant_id = procurement.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION procurement.initialize_tenant_procurement_operations(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM procurement.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO procurement.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

COMMENT ON TABLE procurement.purchase_request_status_history IS
'Historial append-only de cambios de estado de solicitudes de compra.';
COMMENT ON TABLE procurement.purchase_order_requests IS
'Relacion muchos-a-muchos para consolidar varias solicitudes aprobadas en una orden de compra.';
COMMENT ON TABLE procurement.goods_receipt_inspections IS
'Inspecciones documentales, de cantidad, temperatura, empaque o calidad; no registran existencias.';
COMMENT ON TABLE procurement.goods_receipt_discrepancies IS
'Diferencias detectadas durante la recepcion y el seguimiento de su resolucion.';
COMMENT ON TABLE procurement.supplier_returns IS
'Devoluciones documentales a proveedores. Inventory registra el movimiento fisico de salida.';
COMMENT ON TABLE procurement.purchase_documents IS
'Metadatos y referencia a almacenamiento externo. entity_id es polimorfico y se valida mediante el servicio Procurement.';
COMMENT ON TABLE procurement.event_outbox IS
'Outbox compartido por las operaciones de Procurement; esta extension no crea un outbox paralelo.';

-- inventory recibe los eventos de recepcion/devolucion publicados en
-- procurement.event_outbox. Reutilice tambien procurement.processed_events.

COMMIT;

-- ============================================================================
-- FIN MODULO 9: EXTENSION DE PROCUREMENT
-- ============================================================================
