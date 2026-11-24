-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 5: KITCHEN (COMANDAS, ESTACIONES, PREPARACION Y KDS)
-- Ubicacion del crate: crates/modules/kitchen
-- Motor: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants)
--   * modulo_1_organization_postgresql.sql (referencias logicas de company/branch/station)
--   * modulo_3_catalog_postgresql.sql (referencias logicas de producto/categoria/menu)
--   * modulo_4_sales_postgresql.sql (referencias logicas de order/order_item y eventos)
--
-- REGISTRO SaaS:
--   El modulo 0 registra actualmente 'menu_production' como paquete comercial
--   que incluye preparacion. Este crate/schema se llama 'kitchen'. No se crea
--   ni modifica una entrada de platform.modules desde este modulo.
--
-- RESPONSABILIDAD DE KITCHEN:
--   * Configuracion operativa de estaciones fisicas de ORGANIZATION.
--   * Dispositivos/pantallas KDS por estacion.
--   * Reglas de enrutamiento de lineas de pedido hacia estaciones.
--   * Comandas/tickets operativos derivados de eventos de Sales.
--   * Cursos/tiempos de servicio, lineas, modificadores e instrucciones snapshot.
--   * Tareas de preparacion por estacion y su ciclo de vida.
--   * Historial de estados, notas, acciones bump/recall y temporizadores.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO):
--   * Pedidos, cuentas, ventas y devoluciones: sales.
--   * Productos, variantes, menus, modificadores comerciales: catalog.
--   * Recetas, ingredientes, escandallos y ordenes de produccion: production.
--   * Existencias, reservas y movimientos de inventario: inventory.
--   * Areas/mesas fisicas: organization; asignaciones/ocupacion: sales.
--   * Estaciones fisicas: organization.
--   * Usuarios, roles y permisos: identity.
--   * Dispositivos/terminales de POS y provisionamiento: integrations/workforce.
--   * Publicacion y transporte de eventos: adapters/messaging.
--
-- LIMITES DE MODULOS:
--   * Kitchen solo crea FK fisicas a platform.tenants y a tablas de su schema.
--   * source_order_id, source_order_item_id, product_id, variant_id,
--     menu_item_id, category_id, station_id, company_id, branch_id, user_id
--     y device references externos son UUID logicos, validados por contracts.
--   * Kitchen no consulta ni modifica tablas privadas de Sales/Catalog/
--     Organization/Identity/Inventory/Production.
--   * Una comanda es una proyeccion operativa de cocina, NO una copia del pedido
--     comercial ni una segunda venta. Se alimenta con eventos versionados.
--
-- AISLAMIENTO:
--   * Todas las tablas tenant-scoped tienen tenant_id y RLS FORCE.
--   * Cada transaccion autenticada ejecuta SET LOCAL app.tenant_id = '<uuid>'.
--   * El tenant se deriva del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * La autorizacion por company/branch y los permisos de Identity se validan
--     adicionalmente en la capa application; RLS aqui aísla por tenant.
--
-- IMPORTANTE:
--   * Ejecutar una sola vez en base nueva, despues de Platform, Organization,
--     Catalog y Sales. No ejecuta de nuevo scripts anteriores.
--   * No almacenar credenciales/secretos de dispositivos en claro. Guardar
--     solamente hashes de secretos de vinculacion.
--   * Las transiciones de estado y concurrencia se coordinan en application
--     con UPDATE condicional/versionado; el historial es append-only.
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS kitchen;

COMMENT ON SCHEMA kitchen IS
'Configuracion operativa de estaciones, comandas, tareas de preparacion, pantallas KDS y despacho. No administra estaciones fisicas, pedidos comerciales, productos, recetas ni existencias.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kitchen.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION kitchen.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION kitchen.prevent_scope_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.company_id IS DISTINCT FROM OLD.company_id
       OR NEW.branch_id IS DISTINCT FROM OLD.branch_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant/company/branch en Kitchen';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION kitchen.prevent_record_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una nueva accion o transicion',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion operativa de cocina por sucursal
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.branch_settings (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id               uuid NOT NULL,
    branch_id                uuid NOT NULL,
    timezone                 varchar(80) NOT NULL DEFAULT 'America/Bogota',
    routing_mode             varchar(20) NOT NULL DEFAULT 'rules'
                             CHECK (routing_mode IN ('rules', 'manual', 'hybrid')),
    auto_accept_tickets      boolean NOT NULL DEFAULT false,
    allow_manual_tickets     boolean NOT NULL DEFAULT true,
    default_prep_target_min  smallint NOT NULL DEFAULT 15 CHECK (default_prep_target_min BETWEEN 1 AND 720),
    warning_before_due_min   smallint NOT NULL DEFAULT 5 CHECK (warning_before_due_min BETWEEN 0 AND 240),
    display_refresh_seconds  smallint NOT NULL DEFAULT 3 CHECK (display_refresh_seconds BETWEEN 1 AND 60),
    settings                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_branch_settings_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT kitchen_branch_settings_branch_unique UNIQUE (tenant_id, branch_id),
    CONSTRAINT kitchen_branch_settings_settings_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE INDEX ix_kitchen_branch_settings_company
    ON kitchen.branch_settings (tenant_id, company_id, branch_id);

-- ---------------------------------------------------------------------------
-- 2. Configuracion operativa de estaciones y dispositivos KDS
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.station_settings (
    tenant_id        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id       uuid NOT NULL,
    branch_id        uuid NOT NULL,
    station_id       uuid NOT NULL,
    display_order    integer NOT NULL DEFAULT 0,
    color_hex        char(7),
    is_expediter     boolean NOT NULL DEFAULT false,
    max_active_tasks smallint CHECK (max_active_tasks IS NULL OR max_active_tasks BETWEEN 1 AND 500),
    is_enabled       boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_station_settings_pk PRIMARY KEY (tenant_id, station_id),
    CONSTRAINT kitchen_station_settings_scope_unique
        UNIQUE (tenant_id, company_id, branch_id, station_id),
    CONSTRAINT kitchen_station_settings_color_shape
        CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE INDEX ix_kitchen_station_settings_branch_enabled
    ON kitchen.station_settings (tenant_id, branch_id, is_enabled, display_order);

CREATE TABLE kitchen.station_devices (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id            uuid NOT NULL,
    branch_id             uuid NOT NULL,
    station_id            uuid NOT NULL,
    device_code           varchar(80) NOT NULL,
    display_name          varchar(120) NOT NULL,
    device_type           varchar(20) NOT NULL DEFAULT 'kds'
                          CHECK (device_type IN ('kds', 'printer', 'expo_display', 'bump_bar', 'other')),
    pairing_secret_hash   text,
    device_status         varchar(20) NOT NULL DEFAULT 'pending'
                          CHECK (device_status IN ('pending', 'active', 'disabled', 'revoked')),
    last_seen_at          timestamptz,
    settings              jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    revoked_at            timestamptz,
    CONSTRAINT kitchen_station_devices_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT kitchen_station_devices_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT kitchen_station_devices_station_fk FOREIGN KEY (tenant_id, company_id, branch_id, station_id)
        REFERENCES kitchen.station_settings (tenant_id, company_id, branch_id, station_id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_station_devices_code_not_blank CHECK (btrim(device_code) <> ''),
    CONSTRAINT kitchen_station_devices_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT kitchen_station_devices_settings_object CHECK (jsonb_typeof(settings) = 'object'),
    CONSTRAINT kitchen_station_devices_revocation CHECK (
        (device_status = 'revoked' AND revoked_at IS NOT NULL)
        OR (device_status <> 'revoked' AND revoked_at IS NULL)
    )
);

CREATE UNIQUE INDEX uq_kitchen_device_code
    ON kitchen.station_devices (tenant_id, branch_id, lower(device_code));
CREATE INDEX ix_kitchen_station_devices_station_status
    ON kitchen.station_devices (tenant_id, station_id, device_status);

-- ---------------------------------------------------------------------------
-- 3. Reglas para dirigir articulos a estaciones
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.routing_rules (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id       uuid NOT NULL,
    branch_id        uuid NOT NULL,
    station_id       uuid NOT NULL,
    rule_code        varchar(60) NOT NULL,
    name             varchar(140) NOT NULL,
    match_type       varchar(20) NOT NULL
                     CHECK (match_type IN ('product', 'category', 'menu_item', 'all')),
    product_id       uuid,
    category_id      uuid,
    menu_item_id     uuid,
    order_type       varchar(30)
                     CHECK (order_type IS NULL OR order_type IN ('dine_in', 'takeaway', 'delivery', 'pickup', 'drive_thru', 'catering', 'other')),
    priority         integer NOT NULL DEFAULT 100,
    is_active        boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_routing_rules_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT kitchen_routing_rules_station_fk FOREIGN KEY (tenant_id, company_id, branch_id, station_id)
        REFERENCES kitchen.station_settings (tenant_id, company_id, branch_id, station_id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_routing_rules_code_not_blank CHECK (btrim(rule_code) <> ''),
    CONSTRAINT kitchen_routing_rules_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT kitchen_routing_rules_match_shape CHECK (
        (match_type = 'product' AND product_id IS NOT NULL AND category_id IS NULL AND menu_item_id IS NULL)
        OR (match_type = 'category' AND product_id IS NULL AND category_id IS NOT NULL AND menu_item_id IS NULL)
        OR (match_type = 'menu_item' AND product_id IS NULL AND category_id IS NULL AND menu_item_id IS NOT NULL)
        OR (match_type = 'all' AND product_id IS NULL AND category_id IS NULL AND menu_item_id IS NULL)
    )
);

CREATE UNIQUE INDEX uq_kitchen_routing_rule_code
    ON kitchen.routing_rules (tenant_id, branch_id, lower(rule_code));
CREATE INDEX ix_kitchen_routing_rules_lookup
    ON kitchen.routing_rules (tenant_id, branch_id, is_active, match_type, priority DESC);
CREATE INDEX ix_kitchen_routing_rules_product
    ON kitchen.routing_rules (tenant_id, product_id, priority DESC)
    WHERE product_id IS NOT NULL AND is_active = true;
CREATE INDEX ix_kitchen_routing_rules_category
    ON kitchen.routing_rules (tenant_id, category_id, priority DESC)
    WHERE category_id IS NOT NULL AND is_active = true;

-- ---------------------------------------------------------------------------
-- 4. Comandas/tickets operativos recibidos desde Sales
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.tickets (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id              uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id             uuid NOT NULL,
    branch_id              uuid NOT NULL,
    source_order_id        uuid NOT NULL,
    source_order_number    varchar(80) NOT NULL,
    source_event_id        uuid,
    ticket_number          varchar(80) NOT NULL,
    ticket_sequence        smallint NOT NULL DEFAULT 1 CHECK (ticket_sequence > 0),
    order_type             varchar(30) NOT NULL
                           CHECK (order_type IN ('dine_in', 'takeaway', 'delivery', 'pickup', 'drive_thru', 'catering', 'other')),
    order_source           varchar(30) NOT NULL DEFAULT 'pos'
                           CHECK (order_source IN ('pos', 'kiosk', 'web', 'mobile', 'phone', 'marketplace', 'table_qr', 'api', 'other')),
    ticket_status          varchar(24) NOT NULL DEFAULT 'queued'
                           CHECK (ticket_status IN ('queued', 'in_progress', 'partially_ready', 'ready', 'dispatched', 'completed', 'on_hold', 'cancelled')),
    priority               smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    customer_label         varchar(180),
    table_label            varchar(80),
    guest_count            smallint CHECK (guest_count IS NULL OR guest_count BETWEEN 1 AND 500),
    ticket_note_snapshot   text,
    received_at            timestamptz NOT NULL DEFAULT now(),
    requested_ready_at     timestamptz,
    started_at             timestamptz,
    ready_at               timestamptz,
    dispatched_at          timestamptz,
    completed_at            timestamptz,
    cancelled_at           timestamptz,
    cancellation_reason    text,
    metadata               jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_tickets_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT kitchen_tickets_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT kitchen_tickets_branch_number_unique UNIQUE (tenant_id, branch_id, ticket_number),
    CONSTRAINT kitchen_tickets_source_sequence_unique UNIQUE (tenant_id, source_order_id, ticket_sequence),
    CONSTRAINT kitchen_tickets_order_number_not_blank CHECK (btrim(source_order_number) <> ''),
    CONSTRAINT kitchen_tickets_ticket_number_not_blank CHECK (btrim(ticket_number) <> ''),
    CONSTRAINT kitchen_tickets_cancel_shape CHECK (
        (ticket_status <> 'cancelled') OR
        (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> '')
    ),
    CONSTRAINT kitchen_tickets_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_kitchen_ticket_source_event
    ON kitchen.tickets (tenant_id, source_event_id)
    WHERE source_event_id IS NOT NULL;
CREATE INDEX ix_kitchen_tickets_branch_queue
    ON kitchen.tickets (tenant_id, branch_id, ticket_status, priority, received_at)
    WHERE ticket_status IN ('queued', 'in_progress', 'partially_ready', 'on_hold');
CREATE INDEX ix_kitchen_tickets_due_queue
    ON kitchen.tickets (tenant_id, branch_id, requested_ready_at)
    WHERE ticket_status IN ('queued', 'in_progress', 'partially_ready');
CREATE INDEX ix_kitchen_tickets_source_order
    ON kitchen.tickets (tenant_id, source_order_id, ticket_sequence);

-- ---------------------------------------------------------------------------
-- 5. Cursos/tiempos de servicio dentro de una comanda
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.ticket_courses (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id        uuid NOT NULL,
    branch_id         uuid NOT NULL,
    ticket_id         uuid NOT NULL,
    course_number     smallint NOT NULL CHECK (course_number > 0),
    name              varchar(100) NOT NULL,
    course_status     varchar(20) NOT NULL DEFAULT 'held'
                      CHECK (course_status IN ('held', 'fired', 'in_progress', 'ready', 'completed', 'cancelled')),
    fire_at           timestamptz,
    started_at        timestamptz,
    ready_at          timestamptz,
    completed_at      timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_courses_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, ticket_id, id),
    CONSTRAINT kitchen_ticket_courses_ticket_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id)
        REFERENCES kitchen.tickets (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_courses_number_unique UNIQUE (tenant_id, ticket_id, course_number),
    CONSTRAINT kitchen_ticket_courses_name_not_blank CHECK (btrim(name) <> '')
);

CREATE INDEX ix_kitchen_ticket_courses_status
    ON kitchen.ticket_courses (tenant_id, branch_id, course_status, fire_at);

-- ---------------------------------------------------------------------------
-- 6. Lineas snapshot de preparacion y sus modificadores
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.ticket_items (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    ticket_id               uuid NOT NULL,
    course_id               uuid,
    source_order_item_id    uuid NOT NULL,
    source_line_number      integer,
    product_id              uuid,
    variant_id              uuid,
    menu_item_id            uuid,
    product_name_snapshot   varchar(200) NOT NULL,
    variant_name_snapshot   varchar(160),
    sku_snapshot            varchar(80),
    quantity                numeric(18,4) NOT NULL CHECK (quantity > 0),
    quantity_ready          numeric(18,4) NOT NULL DEFAULT 0 CHECK (quantity_ready >= 0),
    quantity_cancelled      numeric(18,4) NOT NULL DEFAULT 0 CHECK (quantity_cancelled >= 0),
    item_status             varchar(24) NOT NULL DEFAULT 'queued'
                            CHECK (item_status IN ('queued', 'acknowledged', 'preparing', 'partially_ready', 'ready', 'served', 'on_hold', 'cancelled')),
    priority                smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    item_note_snapshot      text,
    allergy_note_snapshot   text,
    sequence_number         integer NOT NULL DEFAULT 1 CHECK (sequence_number > 0),
    started_at              timestamptz,
    ready_at                timestamptz,
    served_at               timestamptz,
    cancelled_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_items_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, ticket_id, id),
    CONSTRAINT kitchen_ticket_items_ticket_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id)
        REFERENCES kitchen.tickets (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_items_course_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, course_id)
        REFERENCES kitchen.ticket_courses (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_items_line_unique UNIQUE (tenant_id, ticket_id, source_order_item_id, sequence_number),
    CONSTRAINT kitchen_ticket_items_quantity_consistency CHECK (quantity_ready + quantity_cancelled <= quantity),
    CONSTRAINT kitchen_ticket_items_name_not_blank CHECK (btrim(product_name_snapshot) <> '')
);

CREATE INDEX ix_kitchen_ticket_items_queue
    ON kitchen.ticket_items (tenant_id, branch_id, ticket_id, item_status, priority);
CREATE INDEX ix_kitchen_ticket_items_source_line
    ON kitchen.ticket_items (tenant_id, source_order_item_id);
CREATE INDEX ix_kitchen_ticket_items_course
    ON kitchen.ticket_items (tenant_id, ticket_id, course_id, sequence_number);

CREATE TABLE kitchen.ticket_item_modifiers (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id               uuid NOT NULL,
    branch_id                uuid NOT NULL,
    ticket_id                uuid NOT NULL,
    ticket_item_id           uuid NOT NULL,
    source_modifier_id       uuid,
    group_name_snapshot      varchar(140) NOT NULL,
    option_name_snapshot     varchar(160) NOT NULL,
    quantity                 numeric(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    preparation_instruction  text,
    is_removed               boolean NOT NULL DEFAULT false,
    created_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_item_modifiers_item_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id)
        REFERENCES kitchen.ticket_items (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_item_modifiers_group_not_blank CHECK (btrim(group_name_snapshot) <> ''),
    CONSTRAINT kitchen_ticket_item_modifiers_option_not_blank CHECK (btrim(option_name_snapshot) <> '')
);

CREATE INDEX ix_kitchen_ticket_item_modifiers_item
    ON kitchen.ticket_item_modifiers (tenant_id, ticket_item_id);

-- ---------------------------------------------------------------------------
-- 7. Tareas de preparacion asignadas a estaciones
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.item_station_tasks (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id            uuid NOT NULL,
    branch_id             uuid NOT NULL,
    ticket_id             uuid NOT NULL,
    ticket_item_id        uuid NOT NULL,
    station_id            uuid NOT NULL,
    task_code             varchar(50) NOT NULL DEFAULT 'prepare',
    task_sequence         smallint NOT NULL DEFAULT 1 CHECK (task_sequence > 0),
    task_status           varchar(24) NOT NULL DEFAULT 'queued'
                          CHECK (task_status IN ('queued', 'accepted', 'preparing', 'paused', 'ready', 'bumped', 'cancelled')),
    quantity_required     numeric(18,4) NOT NULL CHECK (quantity_required > 0),
    quantity_completed    numeric(18,4) NOT NULL DEFAULT 0 CHECK (quantity_completed >= 0),
    assigned_at           timestamptz NOT NULL DEFAULT now(),
    accepted_at           timestamptz,
    started_at            timestamptz,
    paused_at             timestamptz,
    ready_at              timestamptz,
    bumped_at             timestamptz,
    cancelled_at          timestamptz,
    cancellation_reason   text,
    due_at                timestamptz,
    assigned_user_id      uuid,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_item_station_tasks_scope_id_unique UNIQUE (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, id),
    CONSTRAINT kitchen_item_station_tasks_item_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id)
        REFERENCES kitchen.ticket_items (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_item_station_tasks_station_fk FOREIGN KEY (tenant_id, company_id, branch_id, station_id)
        REFERENCES kitchen.station_settings (tenant_id, company_id, branch_id, station_id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_item_station_tasks_unique UNIQUE (tenant_id, ticket_item_id, station_id, task_code, task_sequence),
    CONSTRAINT kitchen_item_station_tasks_code_not_blank CHECK (btrim(task_code) <> ''),
    CONSTRAINT kitchen_item_station_tasks_quantity_consistency CHECK (quantity_completed <= quantity_required),
    CONSTRAINT kitchen_item_station_tasks_cancel_shape CHECK (
        task_status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND btrim(cancellation_reason) <> '')
    )
);

CREATE INDEX ix_kitchen_tasks_station_queue
    ON kitchen.item_station_tasks (tenant_id, branch_id, station_id, task_status, due_at, assigned_at)
    WHERE task_status IN ('queued', 'accepted', 'preparing', 'paused');
CREATE INDEX ix_kitchen_tasks_ticket_item
    ON kitchen.item_station_tasks (tenant_id, ticket_id, ticket_item_id, task_sequence);

-- ---------------------------------------------------------------------------
-- 8. Notas operativas y trazabilidad de estados
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.ticket_notes (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id        uuid NOT NULL,
    branch_id         uuid NOT NULL,
    ticket_id         uuid NOT NULL,
    ticket_item_id    uuid,
    note_type         varchar(24) NOT NULL DEFAULT 'instruction'
                      CHECK (note_type IN ('instruction', 'allergy', 'priority', 'chef', 'cancellation', 'handoff', 'other')),
    visibility        varchar(20) NOT NULL DEFAULT 'kitchen'
                      CHECK (visibility IN ('kitchen', 'expo', 'internal')),
    note_text         text NOT NULL,
    created_by_user_id uuid,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_notes_ticket_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id)
        REFERENCES kitchen.tickets (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_notes_item_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id)
        REFERENCES kitchen.ticket_items (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_notes_not_blank CHECK (btrim(note_text) <> '')
);

CREATE INDEX ix_kitchen_ticket_notes_ticket
    ON kitchen.ticket_notes (tenant_id, ticket_id, created_at);

CREATE TABLE kitchen.ticket_status_history (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id        uuid NOT NULL,
    branch_id         uuid NOT NULL,
    ticket_id         uuid NOT NULL,
    previous_status   varchar(24),
    new_status        varchar(24) NOT NULL,
    reason_code       varchar(60),
    reason            text,
    actor_user_id     uuid,
    device_id         uuid,
    occurred_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_status_history_ticket_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id)
        REFERENCES kitchen.tickets (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_status_history_status CHECK (
        new_status IN ('queued', 'in_progress', 'partially_ready', 'ready', 'dispatched', 'completed', 'on_hold', 'cancelled')
    )
);

CREATE INDEX ix_kitchen_ticket_status_history_ticket
    ON kitchen.ticket_status_history (tenant_id, ticket_id, occurred_at DESC);

CREATE TABLE kitchen.ticket_item_status_history (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id        uuid NOT NULL,
    branch_id         uuid NOT NULL,
    ticket_id         uuid NOT NULL,
    ticket_item_id    uuid NOT NULL,
    previous_status   varchar(24),
    new_status        varchar(24) NOT NULL,
    reason            text,
    actor_user_id     uuid,
    occurred_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_ticket_item_status_history_item_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id)
        REFERENCES kitchen.ticket_items (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_ticket_item_status_history_status CHECK (
        new_status IN ('queued', 'acknowledged', 'preparing', 'partially_ready', 'ready', 'served', 'on_hold', 'cancelled')
    )
);

CREATE INDEX ix_kitchen_ticket_item_status_history_item
    ON kitchen.ticket_item_status_history (tenant_id, ticket_item_id, occurred_at DESC);

CREATE TABLE kitchen.task_status_history (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id         uuid NOT NULL,
    branch_id          uuid NOT NULL,
    ticket_id          uuid NOT NULL,
    ticket_item_id     uuid NOT NULL,
    station_task_id    uuid NOT NULL,
    previous_status    varchar(24),
    new_status         varchar(24) NOT NULL,
    reason             text,
    actor_user_id      uuid,
    device_id          uuid,
    occurred_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_task_status_history_task_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, station_task_id)
        REFERENCES kitchen.item_station_tasks (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_task_status_history_status CHECK (
        new_status IN ('queued', 'accepted', 'preparing', 'paused', 'ready', 'bumped', 'cancelled')
    )
);

CREATE INDEX ix_kitchen_task_status_history_task
    ON kitchen.task_status_history (tenant_id, station_task_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Acciones KDS (bump/recall/hold) y temporizadores de preparacion
-- ---------------------------------------------------------------------------

CREATE TABLE kitchen.bump_actions (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id         uuid NOT NULL,
    branch_id          uuid NOT NULL,
    station_id         uuid NOT NULL,
    ticket_id          uuid NOT NULL,
    ticket_item_id     uuid,
    station_task_id    uuid,
    device_id          uuid,
    action_type        varchar(20) NOT NULL
                       CHECK (action_type IN ('accept', 'start', 'pause', 'resume', 'ready', 'bump', 'recall', 'hold', 'unhold', 'cancel')),
    action_payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
    actor_user_id      uuid,
    occurred_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_bump_actions_station_fk FOREIGN KEY (tenant_id, company_id, branch_id, station_id)
        REFERENCES kitchen.station_settings (tenant_id, company_id, branch_id, station_id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_bump_actions_ticket_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id)
        REFERENCES kitchen.tickets (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_bump_actions_item_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id)
        REFERENCES kitchen.ticket_items (tenant_id, company_id, branch_id, ticket_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_bump_actions_task_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, station_task_id)
        REFERENCES kitchen.item_station_tasks (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_bump_actions_device_fk FOREIGN KEY (tenant_id, company_id, branch_id, device_id)
        REFERENCES kitchen.station_devices (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_bump_actions_payload_object CHECK (jsonb_typeof(action_payload) = 'object'),
    CONSTRAINT kitchen_bump_actions_task_requires_item CHECK (station_task_id IS NULL OR ticket_item_id IS NOT NULL)
);

CREATE INDEX ix_kitchen_bump_actions_ticket
    ON kitchen.bump_actions (tenant_id, ticket_id, occurred_at DESC);
CREATE INDEX ix_kitchen_bump_actions_station
    ON kitchen.bump_actions (tenant_id, station_id, occurred_at DESC);

CREATE TABLE kitchen.task_timers (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id         uuid NOT NULL,
    branch_id          uuid NOT NULL,
    ticket_id          uuid NOT NULL,
    ticket_item_id     uuid NOT NULL,
    station_task_id    uuid NOT NULL,
    timer_type         varchar(24) NOT NULL DEFAULT 'preparation'
                       CHECK (timer_type IN ('preparation', 'plating', 'hold', 'custom')),
    timer_status       varchar(20) NOT NULL DEFAULT 'running'
                       CHECK (timer_status IN ('running', 'paused', 'completed', 'cancelled', 'expired')),
    started_at         timestamptz NOT NULL DEFAULT now(),
    target_at          timestamptz NOT NULL,
    paused_at          timestamptz,
    completed_at       timestamptz,
    cancelled_at       timestamptz,
    created_by_user_id uuid,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT kitchen_task_timers_task_fk FOREIGN KEY (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, station_task_id)
        REFERENCES kitchen.item_station_tasks (tenant_id, company_id, branch_id, ticket_id, ticket_item_id, id) ON DELETE RESTRICT,
    CONSTRAINT kitchen_task_timers_target_after_start CHECK (target_at > started_at),
    CONSTRAINT kitchen_task_timers_completion CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT kitchen_task_timers_cancelled CHECK (cancelled_at IS NULL OR cancelled_at >= started_at)
);

CREATE INDEX ix_kitchen_task_timers_active
    ON kitchen.task_timers (tenant_id, branch_id, timer_status, target_at)
    WHERE timer_status IN ('running', 'paused');
CREATE INDEX ix_kitchen_task_timers_task
    ON kitchen.task_timers (tenant_id, station_task_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 10. Triggers de actualizacion, inmutabilidad y proteccion de alcance
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'branch_settings', 'station_settings', 'station_devices', 'routing_rules',
        'tickets', 'ticket_courses', 'ticket_items', 'item_station_tasks', 'task_timers'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON kitchen.%I FOR EACH ROW EXECUTE FUNCTION kitchen.set_updated_at()',
            'trg_' || v_table || '_updated_at', v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'branch_settings', 'station_settings', 'station_devices', 'routing_rules',
        'tickets', 'ticket_courses', 'ticket_items', 'ticket_item_modifiers',
        'item_station_tasks', 'ticket_notes', 'ticket_status_history',
        'ticket_item_status_history', 'task_status_history', 'bump_actions', 'task_timers'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON kitchen.%I FOR EACH ROW EXECUTE FUNCTION kitchen.prevent_scope_change()',
            'trg_' || v_table || '_scope_immutable', v_table
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'ticket_notes', 'ticket_status_history', 'ticket_item_status_history',
        'task_status_history', 'bump_actions'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON kitchen.%I FOR EACH ROW EXECUTE FUNCTION kitchen.prevent_record_mutation()',
            'trg_' || v_table || '_append_only', v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. Row Level Security: aislamiento por tenant en todas las tablas
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'branch_settings', 'station_settings', 'station_devices', 'routing_rules',
        'tickets', 'ticket_courses', 'ticket_items', 'ticket_item_modifiers',
        'item_station_tasks', 'ticket_notes', 'ticket_status_history',
        'ticket_item_status_history', 'task_status_history', 'bump_actions', 'task_timers'
    ] LOOP
        EXECUTE format('ALTER TABLE kitchen.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE kitchen.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON kitchen.%I USING (tenant_id = kitchen.current_tenant_id()) WITH CHECK (tenant_id = kitchen.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Inicializacion idempotente de la configuracion de una sucursal
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kitchen.initialize_branch_kitchen(
    p_tenant_id uuid,
    p_company_id uuid,
    p_branch_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_id uuid;
BEGIN
    IF p_tenant_id IS NULL OR p_company_id IS NULL OR p_branch_id IS NULL THEN
        RAISE EXCEPTION 'tenant, company y branch son obligatorios';
    END IF;

    IF kitchen.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado debe coincidir con app.tenant_id autenticado';
    END IF;

    INSERT INTO kitchen.branch_settings (tenant_id, company_id, branch_id)
    VALUES (p_tenant_id, p_company_id, p_branch_id)
    ON CONFLICT (tenant_id, branch_id) DO NOTHING;

    SELECT id INTO v_id
    FROM kitchen.branch_settings
    WHERE tenant_id = p_tenant_id
      AND company_id = p_company_id
      AND branch_id = p_branch_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La configuracion existente de la sucursal pertenece a otra empresa';
    END IF;

    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Comentarios de propiedad, seguridad e integracion
-- ---------------------------------------------------------------------------

COMMENT ON TABLE kitchen.tickets IS
'Comanda operativa de cocina, derivada de Sales. source_order_id es referencia logica; no duplica ni sustituye el pedido comercial.';
COMMENT ON TABLE kitchen.ticket_items IS
'Snapshot operativo de la linea enviada a cocina. Los IDs de Sales/Catalog son referencias logicas y sus nombres/cantidades se congelan al recibir el evento.';
COMMENT ON TABLE kitchen.station_settings IS
'Configuracion de uso de cocina para una estacion fisica de Organization. station_id es una referencia logica validada por el contrato de Organization.';
COMMENT ON COLUMN kitchen.station_settings.is_enabled IS
'Habilita o deshabilita la estacion para el flujo de Kitchen; no cambia el estado fisico de la estacion en Organization.';
COMMENT ON TABLE kitchen.routing_rules IS
'Enrutamiento de lineas snapshot hacia estaciones. product_id/category_id/menu_item_id son referencias logicas a Catalog.';
COMMENT ON TABLE kitchen.item_station_tasks IS
'Tarea de preparacion por estacion para una linea de comanda. No administra recetas ni movimientos de inventario.';
COMMENT ON TABLE kitchen.station_devices IS
'Dispositivo KDS/impresora vinculado a una estacion. pairing_secret_hash debe contener solo el hash de un secreto aleatorio, nunca el secreto original.';
COMMENT ON TABLE kitchen.bump_actions IS
'Bitacora append-only de acciones de dispositivos/usuarios en KDS: aceptar, iniciar, pausar, marcar listo, bump, recall y hold.';
COMMENT ON TABLE kitchen.task_timers IS
'Temporizadores operativos de preparacion. No sustituyen el historial de estados ni deben calcularse con el reloj del navegador.';

-- Permisos que deben registrarse en identity.permissions (Identity es propietario):
--   organization.stations.read / organization.stations.manage
--   kitchen.station_settings.read / kitchen.station_settings.manage
--   kitchen.devices.read / kitchen.devices.manage
--   kitchen.routing.read / kitchen.routing.manage
--   kitchen.tickets.read / kitchen.tickets.accept / kitchen.tickets.hold
--   kitchen.tickets.fire / kitchen.tickets.cancel / kitchen.tickets.recall
--   kitchen.items.start / kitchen.items.pause / kitchen.items.ready / kitchen.items.bump
--   kitchen.expedite / kitchen.notes.create
-- La app valida ademas alcance tenant/company/branch y el modulo SaaS 'menu_production'.
--
-- Eventos consumidos desde contracts/events (payload versionado):
--   sales.order_submitted.v1
--   sales.order_item_changed.v1
--   sales.order_cancelled.v1
--   sales.order_fulfillment_requested.v1 (si se incorpora en Sales)
-- Eventos publicados mediante adapters/messaging (no se crea un outbox local):
--   kitchen.ticket_received.v1
--   kitchen.ticket_started.v1
--   kitchen.ticket_item_started.v1
--   kitchen.ticket_item_ready.v1
--   kitchen.ticket_ready.v1
--   kitchen.ticket_dispatched.v1
--   kitchen.ticket_cancelled.v1
--
-- Contratos/puertos esperados en application:
--   SalesOrderSnapshotPort: validar/obtener snapshot desde el evento, no leer SQL de Sales.
--   OrganizationBranchPort: validar tenant/company/branch y estado operativo.
--   OrganizationStationPort: validar tenant/company/branch y estado de station_id.
--   CatalogRoutingDataPort: resolver datos de enrutamiento si el evento no los incluye.
--   IdentityActorAuthorizationPort: validar usuario, permisos y scope.
--   EventPublisherPort: publicar eventos sin acoplarse a RabbitMQ/NATS.
--
-- La entrega al broker debe usar Outbox/Inbox en la capa compartida de messaging
-- cuando se requiera entrega confiable; este schema no escribe en tablas ajenas.

COMMIT;

-- ============================================================================
-- FIN MODULO 5: KITCHEN
-- ============================================================================
