-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 6: INVENTORY (BODEGAS, EXISTENCIAS, MOVIMIENTOS, LOTES, RESERVAS,
--                       CONTEOS, TRANSFERENCIAS Y VALORACION)
-- Ubicacion del crate: crates/modules/inventory
-- Motor objetivo: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants y platform.modules)
--   * modulo_1_organization_postgresql.sql (identificadores logicos de empresa/sucursal)
--   * modulo_3_catalog_postgresql.sql (identificadores logicos de productos/variantes/UOM)
--   * modulo_4_sales_postgresql.sql (eventos de ventas/reservas, cuando se integre)
--   * Identity puede instalarse antes o despues: no se crean FK a identity.
--
-- CODIGO DEL MODULO SAAS:
--   platform.modules ya registra el modulo como 'inventory'.
--   Este schema/crate se llama 'inventory'; no se crea una segunda entrada SaaS.
--
-- RESPONSABILIDAD DE INVENTORY:
--   * Bodegas, ubicaciones fisicas y posiciones de almacenamiento.
--   * Articulos inventariables vinculados logicamente a Catalog.
--   * Existencias por empresa, bodega, ubicacion y lote.
--   * Libro de movimientos de inventario append-only.
--   * Reservas de stock, liberaciones y cumplimiento.
--   * Conteos ciclicos/fisicos y diferencias.
--   * Transferencias entre bodegas de una misma empresa.
--   * Lotes, fechas de vencimiento, reglas de reabastecimiento.
--   * Capas de costo FIFO y asignaciones de salida.
--   * Inbox idempotente para eventos externos consumidos por Inventory.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO):
--   * Maestro comercial de productos, SKU, variantes y unidades: catalog.
--   * Proveedores, solicitudes/ordenes/recepciones de compra: procurement.
--   * Recetas, BOM, produccion y consumo/produccion de ingredientes: production.
--   * Pedidos, ventas, devoluciones comerciales: sales.
--   * Comandas y preparacion: kitchen.
--   * Usuarios, roles y permisos: identity.
--   * Contabilidad, asientos y reglas fiscales: finance.
--
-- LIMITES DE MODULOS:
--   * Inventory solo tiene FK fisicas a platform.tenants y a tablas propias.
--   * company_id, branch_id, catalog_product_id, catalog_variant_id,
--     catalog_stock_unit_id, actor_user_id y source_reference_id son referencias
--     logicas; su existencia/alcance se valida mediante puertos publicos
--     de Organization, Catalog, Identity y del modulo productor.
--   * No consulta ni modifica tablas internas de otros modulos.
--   * Las transferencias incluidas son entre bodegas de la misma empresa.
--
-- AISLAMIENTO Y SEGURIDAD:
--   * Todas las tablas de este schema son tenant-scoped y usan RLS.
--   * Establecer SET LOCAL app.tenant_id dentro de cada transaccion autenticada.
--   * El tenant se obtiene del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * RLS no sustituye la autorizacion por empresa/sucursal en la aplicacion.
--
-- INVARIANTES OPERATIVAS:
--   * stock_movements y stock_movement_lines son append-only.
--   * Los saldos se actualizan dentro de la misma transaccion que registra
--     movimientos/reservas; no deben modificarse desde pantallas ni otros crates.
--   * La aplicacion debe bloquear las filas de stock_balances (FOR UPDATE)
--     durante operaciones concurrentes de reserva/consumo/ajuste.
--   * No se permite stock negativo salvo que la politica del tenant lo autorice.
--   * Para FIFO, toda salida costeada debe crear asignaciones a capas de costo.
--   * Un evento entrante se registra en processed_events en la misma transaccion
--     que aplica sus efectos, para garantizar idempotencia.
--
-- IMPORTANTE:
--   * Ejecutar una sola vez sobre la base que ya contiene Platform y Organization.
--   * modulo_1_tenancy_empresa_multisucursal_postgresql.sql es obsoleto; no
--     ejecutarlo junto con modulo_1_organization_postgresql.sql.
--   * Este script define el esquema y restricciones; la logica transaccional
--     de movimientos/reservas/conteos se implementa en application/services
--     del crate inventory y se prueba con concurrencia real.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS inventory;

COMMENT ON SCHEMA inventory IS
'Bodegas, existencias, lotes, reservas, movimientos, conteos, transferencias y valoracion. No administra el catalogo comercial ni compras/ventas.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION inventory.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION inventory.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION inventory.prevent_scope_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_field text;
BEGIN
    FOREACH v_field IN ARRAY ARRAY[
        'tenant_id', 'company_id', 'branch_id', 'warehouse_id',
        'source_warehouse_id', 'destination_warehouse_id',
        'storage_location_id', 'source_location_id', 'destination_location_id',
        'stock_item_id', 'lot_id', 'catalog_product_id', 'catalog_variant_id',
        'catalog_stock_unit_id', 'reservation_id', 'count_id', 'transfer_id',
        'movement_id', 'source_movement_line_id', 'source_reference_id',
        'source_module', 'source_reference_type', 'line_number', 'direction'
    ] LOOP
        IF (to_jsonb(NEW) -> v_field) IS DISTINCT FROM (to_jsonb(OLD) -> v_field) THEN
            RAISE EXCEPTION 'No se permite cambiar % de un registro de Inventory', v_field;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION inventory.prevent_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El libro de inventario %.% es append-only; registre un movimiento compensatorio',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION inventory.prevent_processed_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Los eventos procesados son inmutables; no se permite UPDATE ni DELETE';
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion de inventario por tenant
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.tenant_settings (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    costing_method              varchar(24) NOT NULL DEFAULT 'weighted_average'
                                CHECK (costing_method IN ('weighted_average', 'fifo')),
    allow_negative_stock        boolean NOT NULL DEFAULT false,
    require_lot_for_tracked     boolean NOT NULL DEFAULT true,
    default_reservation_minutes integer NOT NULL DEFAULT 30
                                CHECK (default_reservation_minutes BETWEEN 1 AND 10080),
    allow_cross_branch_reserve  boolean NOT NULL DEFAULT false,
    settings                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_tenant_settings_tenant_unique UNIQUE (tenant_id),
    CONSTRAINT inventory_tenant_settings_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_tenant_settings_json_object CHECK (jsonb_typeof(settings) = 'object')
);

-- ---------------------------------------------------------------------------
-- 2. Bodegas y ubicaciones
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.warehouses (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    branch_id           uuid,
    warehouse_code      varchar(50) NOT NULL,
    name                varchar(160) NOT NULL,
    warehouse_type      varchar(24) NOT NULL DEFAULT 'branch'
                        CHECK (warehouse_type IN ('central', 'branch', 'transit', 'virtual')),
    description         text,
    address_snapshot    jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_default_receiving boolean NOT NULL DEFAULT false,
    is_default_picking   boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT inventory_warehouses_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_warehouses_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_warehouses_code_not_blank CHECK (btrim(warehouse_code) <> ''),
    CONSTRAINT inventory_warehouses_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT inventory_warehouses_address_object CHECK (jsonb_typeof(address_snapshot) = 'object'),
    CONSTRAINT inventory_warehouses_branch_shape CHECK (
        (warehouse_type = 'branch' AND branch_id IS NOT NULL)
        OR (warehouse_type IN ('central', 'transit', 'virtual'))
    )
);

CREATE UNIQUE INDEX uq_inventory_warehouse_code
    ON inventory.warehouses (tenant_id, company_id, lower(warehouse_code))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_inventory_warehouses_branch_active
    ON inventory.warehouses (tenant_id, company_id, branch_id, is_active)
    WHERE deleted_at IS NULL;

CREATE TABLE inventory.storage_locations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    warehouse_id        uuid NOT NULL,
    parent_location_id  uuid,
    location_code       varchar(60) NOT NULL,
    name                varchar(140) NOT NULL,
    location_type       varchar(24) NOT NULL DEFAULT 'storage'
                        CHECK (location_type IN ('receiving', 'storage', 'picking', 'quarantine', 'staging', 'shipping', 'virtual', 'other')),
    is_pickable         boolean NOT NULL DEFAULT true,
    is_receivable       boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    sort_order          integer NOT NULL DEFAULT 0,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT inventory_locations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_locations_scope_id_unique UNIQUE (tenant_id, company_id, warehouse_id, id),
    CONSTRAINT inventory_locations_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_locations_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_locations_parent_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, parent_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_locations_code_not_blank CHECK (btrim(location_code) <> ''),
    CONSTRAINT inventory_locations_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT inventory_locations_not_own_parent CHECK (parent_location_id IS NULL OR parent_location_id <> id),
    CONSTRAINT inventory_locations_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_inventory_location_code
    ON inventory.storage_locations (tenant_id, warehouse_id, lower(location_code))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_inventory_locations_parent
    ON inventory.storage_locations (tenant_id, warehouse_id, parent_location_id, sort_order)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Articulos inventariables (referencias logicas a Catalog)
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    catalog_product_id      uuid NOT NULL,
    catalog_variant_id      uuid NOT NULL,
    catalog_stock_unit_id   uuid NOT NULL,
    stock_item_code         varchar(80) NOT NULL,
    sku_snapshot            varchar(100) NOT NULL,
    name_snapshot           varchar(200) NOT NULL,
    tracking_mode           varchar(16) NOT NULL DEFAULT 'none'
                            CHECK (tracking_mode IN ('none', 'lot')),
    tracks_expiration       boolean NOT NULL DEFAULT false,
    default_shelf_life_days integer CHECK (default_shelf_life_days IS NULL OR default_shelf_life_days BETWEEN 1 AND 36500),
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz,
    CONSTRAINT inventory_stock_items_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_items_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_stock_items_variant_unique UNIQUE (tenant_id, company_id, catalog_variant_id),
    CONSTRAINT inventory_stock_items_code_not_blank CHECK (btrim(stock_item_code) <> ''),
    CONSTRAINT inventory_stock_items_sku_not_blank CHECK (btrim(sku_snapshot) <> ''),
    CONSTRAINT inventory_stock_items_name_not_blank CHECK (btrim(name_snapshot) <> ''),
    CONSTRAINT inventory_stock_items_expiry_requires_lot CHECK (NOT tracks_expiration OR tracking_mode = 'lot')
);

CREATE UNIQUE INDEX uq_inventory_stock_item_code
    ON inventory.stock_items (tenant_id, company_id, lower(stock_item_code))
    WHERE deleted_at IS NULL;
CREATE INDEX ix_inventory_stock_items_product
    ON inventory.stock_items (tenant_id, company_id, catalog_product_id)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_inventory_stock_items_active
    ON inventory.stock_items (tenant_id, company_id, is_active, name_snapshot)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Lotes y vencimientos
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_lots (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    lot_number              varchar(100) NOT NULL,
    supplier_lot_reference  varchar(120),
    manufactured_at         date,
    received_at             timestamptz NOT NULL DEFAULT now(),
    expires_at              date,
    lot_status              varchar(20) NOT NULL DEFAULT 'active'
                            CHECK (lot_status IN ('active', 'quarantined', 'expired', 'recalled', 'closed')),
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_lots_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_lots_item_id_unique UNIQUE (tenant_id, company_id, stock_item_id, id),
    CONSTRAINT inventory_stock_lots_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_lots_number_not_blank CHECK (btrim(lot_number) <> ''),
    CONSTRAINT inventory_stock_lots_dates CHECK (expires_at IS NULL OR manufactured_at IS NULL OR expires_at >= manufactured_at)
);

CREATE UNIQUE INDEX uq_inventory_lot_number
    ON inventory.stock_lots (tenant_id, company_id, stock_item_id, lower(lot_number));
CREATE INDEX ix_inventory_stock_lots_expiration
    ON inventory.stock_lots (tenant_id, company_id, expires_at, lot_status)
    WHERE expires_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Saldos por ubicacion y lote
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_balances (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid NOT NULL,
    warehouse_id        uuid NOT NULL,
    storage_location_id uuid NOT NULL,
    stock_item_id       uuid NOT NULL,
    lot_id              uuid,
    quantity_on_hand    numeric(20,6) NOT NULL DEFAULT 0,
    quantity_reserved   numeric(20,6) NOT NULL DEFAULT 0,
    quantity_quarantined numeric(20,6) NOT NULL DEFAULT 0,
    quantity_available  numeric(20,6) GENERATED ALWAYS AS
                        (quantity_on_hand - quantity_reserved - quantity_quarantined) STORED,
    last_movement_at    timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_balances_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_balances_scope_id_unique UNIQUE (tenant_id, company_id, warehouse_id, storage_location_id, stock_item_id, id),
    CONSTRAINT inventory_stock_balances_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_balances_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_balances_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_balances_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_balances_reserved_nonnegative CHECK (quantity_reserved >= 0),
    CONSTRAINT inventory_stock_balances_quarantine_nonnegative CHECK (quantity_quarantined >= 0),
    CONSTRAINT inventory_stock_balances_reservations_within_positive_stock CHECK (
        quantity_reserved + quantity_quarantined <= GREATEST(quantity_on_hand, 0)
    )
);

CREATE UNIQUE INDEX uq_inventory_balance_without_lot
    ON inventory.stock_balances (tenant_id, warehouse_id, storage_location_id, stock_item_id)
    WHERE lot_id IS NULL;
CREATE UNIQUE INDEX uq_inventory_balance_with_lot
    ON inventory.stock_balances (tenant_id, warehouse_id, storage_location_id, stock_item_id, lot_id)
    WHERE lot_id IS NOT NULL;
CREATE INDEX ix_inventory_balances_item_warehouse
    ON inventory.stock_balances (tenant_id, company_id, stock_item_id, warehouse_id);
CREATE INDEX ix_inventory_balances_available
    ON inventory.stock_balances (tenant_id, warehouse_id, stock_item_id, quantity_available);

-- ---------------------------------------------------------------------------
-- 6. Libro de movimientos (append-only)
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_movements (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    movement_number         varchar(80) NOT NULL,
    movement_type           varchar(32) NOT NULL
                            CHECK (movement_type IN (
                                'opening_balance', 'receipt', 'issue', 'transfer_out', 'transfer_in',
                                'adjustment', 'count_adjustment', 'sale_issue', 'customer_return',
                                'supplier_return', 'production_consumption', 'production_output',
                                'waste', 'quarantine', 'release_quarantine', 'reversal'
                            )),
    movement_status         varchar(16) NOT NULL DEFAULT 'posted'
                            CHECK (movement_status IN ('posted')),
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    source_module           varchar(50),
    source_reference_type   varchar(80),
    source_reference_id     uuid,
    idempotency_key         varchar(160),
    reason_code             varchar(60),
    notes                   text,
    performed_by_user_id    uuid,
    approved_by_user_id     uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_movements_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_movements_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_stock_movements_number_not_blank CHECK (btrim(movement_number) <> ''),
    CONSTRAINT inventory_stock_movements_source_shape CHECK (
        (source_module IS NULL AND source_reference_type IS NULL AND source_reference_id IS NULL)
        OR (
            source_module IS NOT NULL AND btrim(source_module) <> ''
            AND source_reference_type IS NOT NULL AND btrim(source_reference_type) <> ''
            AND source_reference_id IS NOT NULL
        )
    ),
    CONSTRAINT inventory_stock_movements_idempotency_nonblank CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> '')
);

CREATE UNIQUE INDEX uq_inventory_movement_number
    ON inventory.stock_movements (tenant_id, company_id, lower(movement_number));
CREATE UNIQUE INDEX uq_inventory_movement_idempotency
    ON inventory.stock_movements (tenant_id, company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX ix_inventory_movements_type_date
    ON inventory.stock_movements (tenant_id, company_id, movement_type, occurred_at DESC);
CREATE INDEX ix_inventory_movements_source
    ON inventory.stock_movements (tenant_id, source_module, source_reference_type, source_reference_id)
    WHERE source_reference_id IS NOT NULL;

CREATE TABLE inventory.stock_movement_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    movement_id             uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    warehouse_id            uuid NOT NULL,
    storage_location_id     uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    lot_id                  uuid,
    direction               varchar(8) NOT NULL CHECK (direction IN ('in', 'out')),
    quantity                numeric(20,6) NOT NULL CHECK (quantity > 0),
    quantity_delta          numeric(20,6) GENERATED ALWAYS AS
                            (CASE WHEN direction = 'in' THEN quantity ELSE -quantity END) STORED,
    quantity_before         numeric(20,6),
    quantity_after          numeric(20,6),
    unit_cost               numeric(20,6) CHECK (unit_cost IS NULL OR unit_cost >= 0),
    extended_cost           numeric(20,6) CHECK (extended_cost IS NULL OR extended_cost >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_movement_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_movement_lines_item_line_unique UNIQUE (tenant_id, stock_item_id, id),
    CONSTRAINT inventory_stock_movement_lines_movement_line_unique UNIQUE (tenant_id, movement_id, line_number),
    CONSTRAINT inventory_stock_movement_lines_movement_fk FOREIGN KEY (tenant_id, company_id, movement_id)
        REFERENCES inventory.stock_movements (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_movement_lines_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_movement_lines_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_movement_lines_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_movement_lines_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_movement_lines_quantity_snapshots CHECK (
        (quantity_before IS NULL AND quantity_after IS NULL)
        OR (
            quantity_before IS NOT NULL
            AND quantity_after IS NOT NULL
            AND quantity_after = quantity_before + quantity_delta
        )
    )
);

CREATE INDEX ix_inventory_movement_lines_movement
    ON inventory.stock_movement_lines (tenant_id, movement_id, line_number);
CREATE INDEX ix_inventory_movement_lines_item_location
    ON inventory.stock_movement_lines (tenant_id, stock_item_id, warehouse_id, storage_location_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 7. Reservas de inventario
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_reservations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    reservation_number      varchar(80) NOT NULL,
    source_module           varchar(50) NOT NULL,
    source_reference_type   varchar(80) NOT NULL,
    source_reference_id     uuid NOT NULL,
    reservation_status      varchar(20) NOT NULL DEFAULT 'active'
                            CHECK (reservation_status IN ('active', 'partially_fulfilled', 'fulfilled', 'released', 'expired', 'cancelled')),
    reserved_at             timestamptz NOT NULL DEFAULT now(),
    expires_at              timestamptz,
    fulfilled_at            timestamptz,
    released_at             timestamptz,
    notes                   text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_reservations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_reservations_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_stock_reservations_warehouse_id_unique UNIQUE (tenant_id, company_id, warehouse_id, id),
    CONSTRAINT inventory_stock_reservations_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_reservations_number_not_blank CHECK (btrim(reservation_number) <> ''),
    CONSTRAINT inventory_stock_reservations_source_nonblank CHECK (
        btrim(source_module) <> '' AND btrim(source_reference_type) <> ''
    ),
    CONSTRAINT inventory_stock_reservations_expiration CHECK (expires_at IS NULL OR expires_at > reserved_at),
    CONSTRAINT inventory_stock_reservations_terminal_shape CHECK (
        (reservation_status <> 'fulfilled' OR fulfilled_at IS NOT NULL)
        AND (reservation_status NOT IN ('released', 'expired', 'cancelled') OR released_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_inventory_reservation_number
    ON inventory.stock_reservations (tenant_id, company_id, lower(reservation_number));
CREATE UNIQUE INDEX uq_inventory_reservation_source
    ON inventory.stock_reservations (tenant_id, company_id, source_module, source_reference_type, source_reference_id, warehouse_id);
CREATE INDEX ix_inventory_reservations_branch_status
    ON inventory.stock_reservations (tenant_id, branch_id, reservation_status, expires_at);

CREATE TABLE inventory.stock_reservation_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    reservation_id          uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    storage_location_id     uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    lot_id                  uuid,
    quantity_requested      numeric(20,6) NOT NULL CHECK (quantity_requested > 0),
    quantity_reserved       numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    quantity_fulfilled      numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_fulfilled >= 0),
    quantity_released       numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_released >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_reservation_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_reservation_lines_reservation_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, reservation_id)
        REFERENCES inventory.stock_reservations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reservation_lines_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reservation_lines_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reservation_lines_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reservation_lines_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reservation_lines_quantities CHECK (
        quantity_reserved <= quantity_requested
        AND quantity_fulfilled + quantity_released <= quantity_reserved
    )
);

CREATE INDEX ix_inventory_reservation_lines_reservation
    ON inventory.stock_reservation_lines (tenant_id, reservation_id);
CREATE INDEX ix_inventory_reservation_lines_stock_item
    ON inventory.stock_reservation_lines (tenant_id, stock_item_id, warehouse_id);

-- ---------------------------------------------------------------------------
-- 8. Conteos fisicos y ciclicos
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_counts (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid,
    warehouse_id            uuid NOT NULL,
    count_number            varchar(80) NOT NULL,
    count_type              varchar(20) NOT NULL DEFAULT 'cycle'
                            CHECK (count_type IN ('full', 'cycle', 'spot', 'blind')),
    count_status            varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (count_status IN ('draft', 'in_progress', 'submitted', 'approved', 'posted', 'cancelled')),
    snapshot_at             timestamptz NOT NULL DEFAULT now(),
    started_at              timestamptz,
    submitted_at            timestamptz,
    approved_at             timestamptz,
    posted_at               timestamptz,
    cancelled_at            timestamptz,
    notes                   text,
    created_by_user_id      uuid,
    approved_by_user_id     uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_counts_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_counts_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_stock_counts_warehouse_id_unique UNIQUE (tenant_id, company_id, warehouse_id, id),
    CONSTRAINT inventory_stock_counts_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_counts_number_not_blank CHECK (btrim(count_number) <> ''),
    CONSTRAINT inventory_stock_counts_approval_shape CHECK (
        count_status NOT IN ('approved', 'posted') OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL)
    ),
    CONSTRAINT inventory_stock_counts_submit_shape CHECK (
        count_status NOT IN ('submitted', 'approved', 'posted') OR submitted_at IS NOT NULL
    ),
    CONSTRAINT inventory_stock_counts_post_shape CHECK (count_status <> 'posted' OR posted_at IS NOT NULL),
    CONSTRAINT inventory_stock_counts_cancel_shape CHECK (count_status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_inventory_stock_count_number
    ON inventory.stock_counts (tenant_id, company_id, lower(count_number));
CREATE INDEX ix_inventory_stock_counts_warehouse_status
    ON inventory.stock_counts (tenant_id, warehouse_id, count_status, created_at DESC);

CREATE TABLE inventory.stock_count_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    count_id                uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    storage_location_id     uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    lot_id                  uuid,
    expected_quantity       numeric(20,6) NOT NULL CHECK (expected_quantity >= 0),
    counted_quantity        numeric(20,6) CHECK (counted_quantity IS NULL OR counted_quantity >= 0),
    variance_quantity       numeric(20,6) GENERATED ALWAYS AS
                            (counted_quantity - expected_quantity) STORED,
    line_status             varchar(16) NOT NULL DEFAULT 'pending'
                            CHECK (line_status IN ('pending', 'counted', 'recount_required', 'approved', 'posted')),
    counted_by_user_id      uuid,
    counted_at              timestamptz,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_count_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_count_lines_count_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, count_id)
        REFERENCES inventory.stock_counts (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_count_lines_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_count_lines_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_count_lines_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_count_lines_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_count_lines_count_shape CHECK (
        (counted_quantity IS NULL AND counted_at IS NULL)
        OR (counted_quantity IS NOT NULL AND counted_at IS NOT NULL)
    ),
    CONSTRAINT inventory_stock_count_lines_status_shape CHECK (
        (line_status = 'pending' AND counted_quantity IS NULL AND counted_at IS NULL)
        OR (line_status IN ('counted', 'recount_required', 'approved', 'posted')
            AND counted_quantity IS NOT NULL AND counted_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_inventory_count_line_without_lot
    ON inventory.stock_count_lines (tenant_id, count_id, storage_location_id, stock_item_id)
    WHERE lot_id IS NULL;
CREATE UNIQUE INDEX uq_inventory_count_line_with_lot
    ON inventory.stock_count_lines (tenant_id, count_id, storage_location_id, stock_item_id, lot_id)
    WHERE lot_id IS NOT NULL;
CREATE INDEX ix_inventory_count_lines_count_status
    ON inventory.stock_count_lines (tenant_id, count_id, line_status);

-- ---------------------------------------------------------------------------
-- 9. Transferencias entre bodegas de una misma empresa
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_transfers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    transfer_number         varchar(80) NOT NULL,
    source_warehouse_id     uuid NOT NULL,
    destination_warehouse_id uuid NOT NULL,
    transfer_status         varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (transfer_status IN ('draft', 'requested', 'approved', 'in_transit', 'partially_received', 'received', 'cancelled')),
    requested_at            timestamptz NOT NULL DEFAULT now(),
    approved_at             timestamptz,
    dispatched_at           timestamptz,
    received_at             timestamptz,
    cancelled_at            timestamptz,
    requested_by_user_id    uuid,
    approved_by_user_id     uuid,
    dispatched_by_user_id   uuid,
    received_by_user_id     uuid,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_transfers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_transfers_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT inventory_stock_transfers_endpoints_unique UNIQUE (tenant_id, company_id, id, source_warehouse_id, destination_warehouse_id),
    CONSTRAINT inventory_stock_transfers_source_warehouse_fk FOREIGN KEY (tenant_id, company_id, source_warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfers_destination_warehouse_fk FOREIGN KEY (tenant_id, company_id, destination_warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfers_warehouses_different CHECK (source_warehouse_id <> destination_warehouse_id),
    CONSTRAINT inventory_stock_transfers_number_not_blank CHECK (btrim(transfer_number) <> ''),
    CONSTRAINT inventory_stock_transfers_approval_shape CHECK (
        transfer_status NOT IN ('approved', 'in_transit', 'partially_received', 'received')
        OR (approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL)
    ),
    CONSTRAINT inventory_stock_transfers_dispatch_shape CHECK (
        transfer_status NOT IN ('in_transit', 'partially_received', 'received') OR dispatched_at IS NOT NULL
    ),
    CONSTRAINT inventory_stock_transfers_receive_shape CHECK (
        transfer_status NOT IN ('received') OR received_at IS NOT NULL
    ),
    CONSTRAINT inventory_stock_transfers_cancel_shape CHECK (
        transfer_status <> 'cancelled' OR cancelled_at IS NOT NULL
    )
);

CREATE UNIQUE INDEX uq_inventory_transfer_number
    ON inventory.stock_transfers (tenant_id, company_id, lower(transfer_number));
CREATE INDEX ix_inventory_transfers_source_status
    ON inventory.stock_transfers (tenant_id, source_warehouse_id, transfer_status, requested_at DESC);
CREATE INDEX ix_inventory_transfers_destination_status
    ON inventory.stock_transfers (tenant_id, destination_warehouse_id, transfer_status, requested_at DESC);

CREATE TABLE inventory.stock_transfer_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    transfer_id             uuid NOT NULL,
    source_warehouse_id     uuid NOT NULL,
    destination_warehouse_id uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    stock_item_id           uuid NOT NULL,
    lot_id                  uuid,
    source_location_id      uuid NOT NULL,
    destination_location_id uuid NOT NULL,
    quantity_requested      numeric(20,6) NOT NULL CHECK (quantity_requested > 0),
    quantity_dispatched     numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_dispatched >= 0),
    quantity_received       numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
    line_notes              text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_transfer_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_transfer_lines_transfer_line_unique UNIQUE (tenant_id, transfer_id, line_number),
    CONSTRAINT inventory_stock_transfer_lines_transfer_fk FOREIGN KEY (tenant_id, company_id, transfer_id, source_warehouse_id, destination_warehouse_id)
        REFERENCES inventory.stock_transfers (tenant_id, company_id, id, source_warehouse_id, destination_warehouse_id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfer_lines_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfer_lines_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfer_lines_source_location_fk FOREIGN KEY (tenant_id, company_id, source_warehouse_id, source_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfer_lines_destination_location_fk FOREIGN KEY (tenant_id, company_id, destination_warehouse_id, destination_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_transfer_lines_quantities CHECK (
        quantity_dispatched <= quantity_requested AND quantity_received <= quantity_dispatched
    ),
    CONSTRAINT inventory_stock_transfer_lines_locations_different CHECK (source_location_id <> destination_location_id)
);

CREATE INDEX ix_inventory_transfer_lines_transfer
    ON inventory.stock_transfer_lines (tenant_id, transfer_id, line_number);
CREATE INDEX ix_inventory_transfer_lines_item
    ON inventory.stock_transfer_lines (tenant_id, stock_item_id, lot_id);

-- ---------------------------------------------------------------------------
-- 10. Reglas de reabastecimiento
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_reorder_rules (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    storage_location_id     uuid,
    stock_item_id           uuid NOT NULL,
    minimum_quantity        numeric(20,6) NOT NULL DEFAULT 0 CHECK (minimum_quantity >= 0),
    maximum_quantity        numeric(20,6) CHECK (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity),
    reorder_quantity        numeric(20,6) NOT NULL CHECK (reorder_quantity > 0),
    lead_time_days          integer NOT NULL DEFAULT 0 CHECK (lead_time_days BETWEEN 0 AND 3650),
    safety_stock_quantity   numeric(20,6) NOT NULL DEFAULT 0 CHECK (safety_stock_quantity >= 0),
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_reorder_rules_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_reorder_rules_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reorder_rules_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_reorder_rules_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_inventory_reorder_rule_without_location
    ON inventory.stock_reorder_rules (tenant_id, warehouse_id, stock_item_id)
    WHERE storage_location_id IS NULL;
CREATE UNIQUE INDEX uq_inventory_reorder_rule_with_location
    ON inventory.stock_reorder_rules (tenant_id, warehouse_id, storage_location_id, stock_item_id)
    WHERE storage_location_id IS NOT NULL;
CREATE INDEX ix_inventory_reorder_rules_active
    ON inventory.stock_reorder_rules (tenant_id, warehouse_id, is_active, stock_item_id)
    WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 11. Valoracion de inventario: capas FIFO y asignaciones a salidas
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.stock_cost_layers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    warehouse_id            uuid NOT NULL,
    storage_location_id     uuid NOT NULL,
    lot_id                  uuid,
    source_movement_line_id uuid NOT NULL,
    received_quantity       numeric(20,6) NOT NULL CHECK (received_quantity > 0),
    remaining_quantity      numeric(20,6) NOT NULL CHECK (remaining_quantity >= 0),
    unit_cost               numeric(20,6) NOT NULL CHECK (unit_cost >= 0),
    received_at             timestamptz NOT NULL DEFAULT now(),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_stock_cost_layers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_stock_cost_layers_item_id_unique UNIQUE (tenant_id, company_id, stock_item_id, id),
    CONSTRAINT inventory_stock_cost_layers_source_unique UNIQUE (tenant_id, source_movement_line_id),
    CONSTRAINT inventory_stock_cost_layers_item_fk FOREIGN KEY (tenant_id, company_id, stock_item_id)
        REFERENCES inventory.stock_items (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_cost_layers_warehouse_fk FOREIGN KEY (tenant_id, company_id, warehouse_id)
        REFERENCES inventory.warehouses (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_cost_layers_location_fk FOREIGN KEY (tenant_id, company_id, warehouse_id, storage_location_id)
        REFERENCES inventory.storage_locations (tenant_id, company_id, warehouse_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_cost_layers_lot_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, lot_id)
        REFERENCES inventory.stock_lots (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_cost_layers_source_line_fk FOREIGN KEY (tenant_id, stock_item_id, source_movement_line_id)
        REFERENCES inventory.stock_movement_lines (tenant_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_stock_cost_layers_quantity_order CHECK (remaining_quantity <= received_quantity)
);

CREATE INDEX ix_inventory_cost_layers_fifo
    ON inventory.stock_cost_layers (tenant_id, warehouse_id, stock_item_id, received_at, id)
    WHERE remaining_quantity > 0;

CREATE TABLE inventory.stock_cost_layer_allocations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    stock_item_id           uuid NOT NULL,
    cost_layer_id           uuid NOT NULL,
    issue_movement_line_id  uuid NOT NULL,
    allocated_quantity      numeric(20,6) NOT NULL CHECK (allocated_quantity > 0),
    unit_cost               numeric(20,6) NOT NULL CHECK (unit_cost >= 0),
    total_cost              numeric(20,6) NOT NULL CHECK (total_cost >= 0),
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_cost_layer_allocations_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_cost_layer_allocations_layer_fk FOREIGN KEY (tenant_id, company_id, stock_item_id, cost_layer_id)
        REFERENCES inventory.stock_cost_layers (tenant_id, company_id, stock_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT inventory_cost_layer_allocations_issue_fk FOREIGN KEY (tenant_id, stock_item_id, issue_movement_line_id)
        REFERENCES inventory.stock_movement_lines (tenant_id, stock_item_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_inventory_cost_allocations_issue
    ON inventory.stock_cost_layer_allocations (tenant_id, issue_movement_line_id);
CREATE INDEX ix_inventory_cost_allocations_layer
    ON inventory.stock_cost_layer_allocations (tenant_id, cost_layer_id);

-- ---------------------------------------------------------------------------
-- 12. Inbox idempotente de eventos externos
-- ---------------------------------------------------------------------------

CREATE TABLE inventory.processed_events (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    producer            varchar(80) NOT NULL,
    event_id            varchar(160) NOT NULL,
    event_type          varchar(160) NOT NULL,
    schema_version      integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    payload_sha256      char(64) NOT NULL,
    received_at         timestamptz NOT NULL DEFAULT now(),
    processed_at        timestamptz NOT NULL DEFAULT now(),
    result_reference_id uuid,
    CONSTRAINT inventory_processed_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT inventory_processed_events_unique UNIQUE (tenant_id, producer, event_id),
    CONSTRAINT inventory_processed_events_producer_nonblank CHECK (btrim(producer) <> ''),
    CONSTRAINT inventory_processed_events_id_nonblank CHECK (btrim(event_id) <> ''),
    CONSTRAINT inventory_processed_events_type_nonblank CHECK (btrim(event_type) <> ''),
    CONSTRAINT inventory_processed_events_hash_shape CHECK (payload_sha256 ~ '^[0-9a-fA-F]{64}$')
);

CREATE INDEX ix_inventory_processed_events_type_date
    ON inventory.processed_events (tenant_id, event_type, processed_at DESC);

-- ---------------------------------------------------------------------------
-- 13. Triggers de mantenimiento, proteccion de alcance e inmutabilidad
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'warehouses', 'storage_locations', 'stock_items',
        'stock_lots', 'stock_balances', 'stock_reservations',
        'stock_reservation_lines', 'stock_counts', 'stock_count_lines',
        'stock_transfers', 'stock_transfer_lines', 'stock_reorder_rules',
        'stock_cost_layers'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON inventory.%I FOR EACH ROW EXECUTE FUNCTION inventory.set_updated_at()',
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
        'tenant_settings', 'warehouses', 'storage_locations', 'stock_items',
        'stock_lots', 'stock_balances', 'stock_reservations',
        'stock_reservation_lines', 'stock_counts', 'stock_count_lines',
        'stock_transfers', 'stock_transfer_lines', 'stock_reorder_rules',
        'stock_cost_layers'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON inventory.%I FOR EACH ROW EXECUTE FUNCTION inventory.prevent_scope_change()',
            'trg_' || v_table || '_scope_immutable', v_table
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['stock_movements', 'stock_movement_lines', 'stock_cost_layer_allocations'] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON inventory.%I FOR EACH ROW EXECUTE FUNCTION inventory.prevent_ledger_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_processed_events_append_only
BEFORE UPDATE OR DELETE ON inventory.processed_events
FOR EACH ROW EXECUTE FUNCTION inventory.prevent_processed_event_mutation();

-- ---------------------------------------------------------------------------
-- 14. Row-Level Security: aislamiento por tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'warehouses', 'storage_locations', 'stock_items',
        'stock_lots', 'stock_balances', 'stock_movements', 'stock_movement_lines',
        'stock_reservations', 'stock_reservation_lines', 'stock_counts',
        'stock_count_lines', 'stock_transfers', 'stock_transfer_lines',
        'stock_reorder_rules', 'stock_cost_layers', 'stock_cost_layer_allocations',
        'processed_events'
    ] LOOP
        EXECUTE format('ALTER TABLE inventory.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE inventory.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON inventory.%I USING (tenant_id = inventory.current_tenant_id()) WITH CHECK (tenant_id = inventory.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 15. Inicializacion idempotente de inventario por tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION inventory.initialize_tenant_inventory(p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_id uuid;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'tenant_id es obligatorio';
    END IF;

    IF inventory.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado debe coincidir con app.tenant_id autenticado';
    END IF;

    INSERT INTO inventory.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    SELECT id INTO v_id
    FROM inventory.tenant_settings
    WHERE tenant_id = p_tenant_id;

    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 16. Vistas de consulta (no sustituyen permisos ni RLS)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW inventory.v_stock_availability
WITH (security_invoker = true) AS
SELECT
    b.tenant_id,
    b.company_id,
    b.warehouse_id,
    w.branch_id,
    b.storage_location_id,
    b.stock_item_id,
    b.lot_id,
    b.quantity_on_hand,
    b.quantity_reserved,
    b.quantity_quarantined,
    b.quantity_available,
    l.expires_at AS lot_expires_at,
    l.lot_status
FROM inventory.stock_balances b
JOIN inventory.warehouses w
  ON w.tenant_id = b.tenant_id
 AND w.company_id = b.company_id
 AND w.id = b.warehouse_id
LEFT JOIN inventory.stock_lots l
  ON l.tenant_id = b.tenant_id
 AND l.company_id = b.company_id
 AND l.stock_item_id = b.stock_item_id
 AND l.id = b.lot_id;

COMMENT ON VIEW inventory.v_stock_availability IS
'Saldo por ubicacion/lote. Aplicar siempre contexto tenant y autorizacion company/branch en el backend.';

-- ---------------------------------------------------------------------------
-- 17. Comentarios de propiedad e integracion
-- ---------------------------------------------------------------------------

COMMENT ON TABLE inventory.stock_items IS
'Configuracion de un articulo inventariable por empresa. catalog_product_id, catalog_variant_id y catalog_stock_unit_id son referencias logicas a Catalog; SKU/nombre son snapshots para trazabilidad.';
COMMENT ON TABLE inventory.stock_balances IS
'Saldo actual derivado y mantenido transaccionalmente por Inventory. quantity_available es una columna generada; no debe actualizarse directamente.';
COMMENT ON TABLE inventory.stock_movements IS
'Cabecera append-only del libro de inventario. Para corregir un movimiento se registra un movimiento compensatorio de tipo reversal/ajuste, nunca se altera el original.';
COMMENT ON TABLE inventory.stock_movement_lines IS
'Lineas append-only de entradas/salidas. Cada linea representa una variacion positiva (in) o negativa (out) de una ubicacion y lote.';
COMMENT ON TABLE inventory.stock_reservations IS
'Reserva operativa originada por otro modulo (por ejemplo Sales). source_reference_id es una referencia logica al pedido/orden de origen.';
COMMENT ON TABLE inventory.stock_counts IS
'Cabecera de conteo fisico/ciclico. La aprobacion/posteo debe crear movimientos de ajuste en la misma transaccion de aplicacion.';
COMMENT ON TABLE inventory.stock_transfers IS
'Transferencia entre bodegas de la misma empresa. El despacho y la recepcion generan movimientos independientes y el estado in_transit representa mercancia en transito.';
COMMENT ON TABLE inventory.stock_cost_layers IS
'Capa de costo de entrada. Para metodo FIFO, las salidas se vinculan a capas mediante stock_cost_layer_allocations.';
COMMENT ON TABLE inventory.processed_events IS
'Inbox idempotente del modulo. Insertar el event_id y aplicar los efectos de negocio dentro de la misma transaccion.';

-- Permisos que deben registrarse en identity.permissions (Identity es propietario):
--   inventory.dashboard.read
--   inventory.warehouses.read / inventory.warehouses.manage
--   inventory.locations.read / inventory.locations.manage
--   inventory.items.read / inventory.items.configure
--   inventory.stock.read / inventory.stock.adjust
--   inventory.movements.read / inventory.movements.create
--   inventory.reservations.read / inventory.reservations.manage
--   inventory.counts.read / inventory.counts.create / inventory.counts.approve / inventory.counts.post
--   inventory.transfers.read / inventory.transfers.create / inventory.transfers.approve
--   inventory.transfers.dispatch / inventory.transfers.receive
--   inventory.lots.read / inventory.lots.manage
--   inventory.replenishment.read / inventory.replenishment.manage
--   inventory.costing.read
-- La API valida ademas permisos y alcance tenant/company/branch y el modulo SaaS 'inventory'.
--
-- Eventos consumidos desde contracts/events (payload versionado):
--   procurement.receipt_posted.v1
--   sales.sale_completed.v1
--   sales.return_accepted.v1
--   production.materials_consumed.v1
--   production.output_posted.v1
--   kitchen.waste_recorded.v1 (si Kitchen emite ese hecho)
--
-- Eventos publicados por Inventory:
--   inventory.stock_received.v1
--   inventory.stock_issued.v1
--   inventory.stock_reserved.v1
--   inventory.stock_reservation_released.v1
--   inventory.stock_adjusted.v1
--   inventory.transfer_dispatched.v1
--   inventory.transfer_received.v1
--   inventory.stock_below_reorder_point.v1
--   inventory.lot_expiring.v1
--
-- Contratos/puertos esperados en application:
--   CatalogStockItemPort: validar variante/unidad y obtener snapshots.
--   OrganizationWarehouseScopePort: validar empresa/sucursal/estado de bodega.
--   IdentityActorAuthorizationPort: validar usuario, permisos y alcance.
--   ProcurementReceiptPort: aceptar recepcion confirmada, nunca leer tablas ajenas.
--   EventPublisherPort / EventInboxPort: transportar eventos sin acoplarse al broker.
--   ClockPort / IdGeneratorPort: facilitar pruebas y determinismo.
--
-- Reglas obligatorias de aplicacion:
--   * Bloquear stock_balances FOR UPDATE antes de modificar existencias/reservas.
--   * Mantener saldo, movimiento, reserva/cuenta de costo y processed_events en
--     una unica transaccion cuando pertenecen al mismo comando/evento.
--   * Verificar hash del payload cuando llega un event_id ya procesado; si el
--     mismo id llega con hash distinto, rechazar y generar alerta de seguridad.
--   * Reservas: no reservar por encima de quantity_available.
--   * Conteos: no postear dos veces; el posteo crea movimientos compensatorios.
--   * Transferencias: despacho descuenta origen; recepcion ingresa destino.
--   * FIFO: asignar las salidas a capas en orden received_at, bloqueando capas.
--   * Los saldos y el ledger deben reconciliarse periodicamente.
--
-- Integridad de transferencias: cada linea replica los IDs de bodega de su
-- cabecera y las FK compuestas garantizan que sus ubicaciones pertenecen a
-- las bodegas origen/destino exactas de la transferencia.

COMMIT;

-- ============================================================================
-- FIN MODULO 6: INVENTORY
-- ============================================================================
