-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 8: PRODUCTION (RECETAS, ESCANDALLOS, PLANIFICACION Y PRODUCCION)
-- Ubicacion del crate: crates/modules/production
-- Schema PostgreSQL: production
-- Motor objetivo: PostgreSQL 15+
--
-- RESPONSABILIDAD EXCLUSIVA DE PRODUCTION
--   * Recetas, versiones, fichas tecnicas y listas de materiales (BOM).
--   * Componentes, sub-recetas, rendimientos, mermas tecnicas y pasos.
--   * Centros de trabajo, rutas y operaciones de produccion.
--   * Ordenes/lotes de produccion y seguimiento de su ciclo de vida.
--   * Registro de materiales solicitados/consumidos y productos obtenidos.
--   * Reportes de rendimiento, desperdicio y controles de calidad.
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO)
--   * Productos, variantes, unidades comerciales y modificadores: catalog.
--   * Existencias, reservas, lotes fisicos y movimientos de stock: inventory.
--   * Comandas, KDS y preparacion bajo demanda de una orden de cliente: kitchen.
--   * Pedidos y ventas: sales.
--   * Proveedores, cotizaciones y acuerdos: procurement.
--   * Ordenes de compra y recepcion de proveedores: procurement.
--   * Contabilidad y valoracion financiera oficial: finance.
--
-- LIMITES DE MODULOS
--   * Production solo crea FK fisicas a platform.tenants y a tablas propias.
--   * company_id, branch_id, catalog_product_id, catalog_variant_id,
--     catalog_unit_id, inventory_stock_item_id, inventory_lot_id,
--     inventory_movement_id y actor_user_id son UUID logicos externos.
--   * La existencia y alcance de referencias externas se valida mediante
--     puertos/contratos publicos de Organization, Catalog, Inventory e Identity.
--   * Production no consulta ni modifica tablas privadas de otros modulos.
--   * Inventory sigue siendo el unico propietario del ledger y los saldos.
--     Production guarda referencias a movimientos de Inventory, no los duplica.
--   * Kitchen sigue siendo propietario de comandas/KDS; Production administra
--     lotes y preparaciones planificadas o por lotes, no tareas de cada ticket.
--
-- AISLAMIENTO Y SEGURIDAD
--   * Todas las tablas son tenant-scoped y tienen RLS + FORCE RLS.
--   * Cada transaccion autenticada debe ejecutar SET LOCAL app.tenant_id.
--   * El tenant procede del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--   * RLS por tenant no reemplaza autorizacion por company/branch en Rust.
--
-- INSTALACION
--   * Requiere modulo_0_admin_plataforma_postgresql.sql (platform.tenants).
--   * Requiere el Catalog y el Inventory instalados para uso funcional, aunque
--     no se crean FK fisicas cruzadas a esos esquemas.
--   * Ejecutar una sola vez. No recrea ni modifica objetos de otros modulos.
--
-- NOTA SaaS
--   * 'menu_production' es un paquete comercial de Platform; no es propietario
--     del schema ni reemplaza los permisos tecnicos de Production. Esta
--     migracion no modifica platform.modules, plan_modules ni sus dependencias.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS production;

COMMENT ON SCHEMA production IS
'Recetas versionadas, escandallos, centros/rutas de trabajo, ordenes y lotes de produccion, consumos, rendimientos, mermas y calidad. No administra existencias ni comandas KDS.';

-- ---------------------------------------------------------------------------
-- 0. Funciones del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION production.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION production.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION production.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id de un registro de Production';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION production.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El registro %.% es append-only; registre una compensacion o un nuevo evento',
        TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

-- Una version publicada no puede alterar su contenido. Solo se permite pasar
-- de active a retired, sin cambiar sus datos tecnicos.
CREATE OR REPLACE FUNCTION production.guard_recipe_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.version_status <> 'draft' OR NEW.published_at IS NOT NULL THEN
            RAISE EXCEPTION 'Las versiones de receta deben crearse en estado draft';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.version_status <> 'draft' THEN
            RAISE EXCEPTION 'Solo se pueden eliminar versiones de receta en draft';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.version_status = 'draft' THEN
        IF NEW.version_status = 'active' THEN
            NEW.published_at := COALESCE(NEW.published_at, now());
            NEW.effective_from := COALESCE(NEW.effective_from, now());
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.version_status = 'active'
       AND NEW.version_status = 'retired'
       AND (to_jsonb(NEW) - ARRAY['version_status', 'effective_to', 'updated_at'])
           = (to_jsonb(OLD) - ARRAY['version_status', 'effective_to', 'updated_at']) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Una version publicada de receta es inmutable; cree una nueva version';
END;
$$;

-- Los componentes/alternativas/pasos solo se pueden editar mientras la version
-- de receta asociada permanezca en draft.
CREATE OR REPLACE FUNCTION production.guard_recipe_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant_id uuid;
    v_recipe_version_id uuid;
    v_component_id uuid;
    v_version_status varchar(16);
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_tenant_id := OLD.tenant_id;
    ELSE
        v_tenant_id := NEW.tenant_id;
    END IF;

    IF TG_TABLE_NAME = 'recipe_component_alternatives' THEN
        IF TG_OP = 'DELETE' THEN
            v_component_id := OLD.component_id;
        ELSE
            v_component_id := NEW.component_id;
        END IF;

        IF TG_OP = 'UPDATE' AND OLD.component_id IS DISTINCT FROM NEW.component_id THEN
            RAISE EXCEPTION 'No se permite mover una alternativa a otro componente';
        END IF;

        SELECT c.recipe_version_id
          INTO v_recipe_version_id
          FROM production.recipe_components c
         WHERE c.tenant_id = v_tenant_id
           AND c.id = v_component_id;
    ELSE
        IF TG_OP = 'DELETE' THEN
            v_recipe_version_id := OLD.recipe_version_id;
        ELSE
            v_recipe_version_id := NEW.recipe_version_id;
        END IF;

        IF TG_OP = 'UPDATE'
           AND (OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
                OR OLD.recipe_version_id IS DISTINCT FROM NEW.recipe_version_id) THEN
            RAISE EXCEPTION 'No se permite mover componentes/pasos entre versiones de receta';
        END IF;
    END IF;

    SELECT rv.version_status
      INTO v_version_status
      FROM production.recipe_versions rv
     WHERE rv.tenant_id = v_tenant_id
       AND rv.id = v_recipe_version_id;

    IF v_version_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Los componentes y pasos solo se editan en versiones de receta draft';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Configuracion y clasificacion de recetas
-- ---------------------------------------------------------------------------

CREATE TABLE production.tenant_settings (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    default_yield_tolerance_pct numeric(7,4) NOT NULL DEFAULT 3.0000
                                CHECK (default_yield_tolerance_pct BETWEEN 0 AND 100),
    require_recipe_approval     boolean NOT NULL DEFAULT true,
    require_quality_release     boolean NOT NULL DEFAULT false,
    allow_overproduction        boolean NOT NULL DEFAULT false,
    default_batch_rounding      varchar(16) NOT NULL DEFAULT 'nearest'
                                CHECK (default_batch_rounding IN ('up', 'down', 'nearest')),
    settings                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_tenant_settings_tenant_unique UNIQUE (tenant_id),
    CONSTRAINT production_tenant_settings_id_tenant_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_tenant_settings_json_object CHECK (jsonb_typeof(settings) = 'object')
);

CREATE TABLE production.recipe_categories (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    parent_category_id  uuid,
    category_code       varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    sort_order          integer NOT NULL DEFAULT 0,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_recipe_categories_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipe_categories_code_unique UNIQUE (tenant_id, category_code),
    CONSTRAINT production_recipe_categories_parent_fk FOREIGN KEY (tenant_id, parent_category_id)
        REFERENCES production.recipe_categories (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipe_categories_code_not_blank CHECK (btrim(category_code) <> ''),
    CONSTRAINT production_recipe_categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT production_recipe_categories_not_own_parent CHECK (parent_category_id IS NULL OR parent_category_id <> id)
);

CREATE INDEX ix_production_recipe_categories_parent
    ON production.recipe_categories (tenant_id, parent_category_id, sort_order)
    WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 2. Recetas y versiones
-- ---------------------------------------------------------------------------

CREATE TABLE production.recipes (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id                  uuid,
    branch_id                   uuid,
    category_id                 uuid,
    recipe_code                 varchar(70) NOT NULL,
    name                        varchar(200) NOT NULL,
    description                 text,
    recipe_type                 varchar(24) NOT NULL DEFAULT 'prepared_item'
                                CHECK (recipe_type IN ('prepared_item', 'sub_recipe', 'sauce', 'dough', 'beverage', 'prep_batch', 'other')),
    output_catalog_product_id   uuid,
    output_catalog_variant_id   uuid,
    output_inventory_item_id    uuid,
    default_output_unit_id      uuid,
    recipe_status               varchar(16) NOT NULL DEFAULT 'draft'
                                CHECK (recipe_status IN ('draft', 'active', 'inactive', 'archived')),
    metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id          uuid,
    updated_by_user_id          uuid,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz,
    CONSTRAINT production_recipes_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipes_category_fk FOREIGN KEY (tenant_id, category_id)
        REFERENCES production.recipe_categories (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipes_branch_scope CHECK (branch_id IS NULL OR company_id IS NOT NULL),
    CONSTRAINT production_recipes_code_not_blank CHECK (btrim(recipe_code) <> ''),
    CONSTRAINT production_recipes_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT production_recipes_output_variant_shape CHECK (
        output_catalog_variant_id IS NULL OR output_catalog_product_id IS NOT NULL
    ),
    CONSTRAINT production_recipes_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_production_recipe_global_code
    ON production.recipes (tenant_id, lower(recipe_code))
    WHERE company_id IS NULL AND branch_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_production_recipe_company_code
    ON production.recipes (tenant_id, company_id, lower(recipe_code))
    WHERE company_id IS NOT NULL AND branch_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_production_recipe_branch_code
    ON production.recipes (tenant_id, company_id, branch_id, lower(recipe_code))
    WHERE branch_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_production_recipes_company_status
    ON production.recipes (tenant_id, company_id, branch_id, recipe_status, name)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_production_recipes_category
    ON production.recipes (tenant_id, category_id, recipe_type)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_production_recipes_output_variant
    ON production.recipes (tenant_id, output_catalog_variant_id)
    WHERE output_catalog_variant_id IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE production.recipe_versions (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    recipe_id               uuid NOT NULL,
    version_number          integer NOT NULL CHECK (version_number > 0),
    version_status          varchar(16) NOT NULL DEFAULT 'draft'
                            CHECK (version_status IN ('draft', 'active', 'retired')),
    yield_quantity          numeric(20,6) NOT NULL CHECK (yield_quantity > 0),
    yield_unit_id           uuid NOT NULL,
    expected_yield_pct      numeric(7,4) NOT NULL DEFAULT 100
                            CHECK (expected_yield_pct > 0 AND expected_yield_pct <= 100),
    standard_prep_minutes   integer CHECK (standard_prep_minutes IS NULL OR standard_prep_minutes >= 0),
    effective_from          timestamptz,
    effective_to            timestamptz,
    instructions            text,
    allergen_snapshot       jsonb NOT NULL DEFAULT '[]'::jsonb,
    nutrition_snapshot      jsonb NOT NULL DEFAULT '{}'::jsonb,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id      uuid,
    approved_by_user_id     uuid,
    published_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_recipe_versions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipe_versions_recipe_number_unique UNIQUE (tenant_id, recipe_id, version_number),
    CONSTRAINT production_recipe_versions_recipe_id_unique UNIQUE (tenant_id, recipe_id, id),
    CONSTRAINT production_recipe_versions_recipe_fk FOREIGN KEY (tenant_id, recipe_id)
        REFERENCES production.recipes (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipe_versions_effective_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT production_recipe_versions_published_shape CHECK (
        (version_status = 'draft' AND published_at IS NULL)
        OR (version_status IN ('active', 'retired') AND published_at IS NOT NULL)
    ),
    CONSTRAINT production_recipe_versions_allergen_array CHECK (jsonb_typeof(allergen_snapshot) = 'array'),
    CONSTRAINT production_recipe_versions_nutrition_object CHECK (jsonb_typeof(nutrition_snapshot) = 'object'),
    CONSTRAINT production_recipe_versions_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_production_one_active_recipe_version
    ON production.recipe_versions (tenant_id, recipe_id)
    WHERE version_status = 'active';
CREATE INDEX ix_production_recipe_versions_history
    ON production.recipe_versions (tenant_id, recipe_id, version_number DESC);

-- ---------------------------------------------------------------------------
-- 3. BOM / escandallo, alternativas y pasos de preparacion
-- ---------------------------------------------------------------------------

CREATE TABLE production.recipe_components (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    recipe_version_id       uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    component_type          varchar(20) NOT NULL
                            CHECK (component_type IN ('stock_item', 'sub_recipe', 'packaging')),
    inventory_stock_item_id uuid,
    sub_recipe_version_id   uuid,
    component_unit_id       uuid NOT NULL,
    quantity_required       numeric(20,6) NOT NULL CHECK (quantity_required > 0),
    expected_scrap_pct      numeric(7,4) NOT NULL DEFAULT 0
                            CHECK (expected_scrap_pct BETWEEN 0 AND 100),
    is_optional             boolean NOT NULL DEFAULT false,
    is_alternative_allowed  boolean NOT NULL DEFAULT false,
    preparation_notes       text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_recipe_components_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipe_components_version_id_unique UNIQUE (tenant_id, recipe_version_id, id),
    CONSTRAINT production_recipe_components_line_unique UNIQUE (tenant_id, recipe_version_id, line_number),
    CONSTRAINT production_recipe_components_version_fk FOREIGN KEY (tenant_id, recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipe_components_subrecipe_fk FOREIGN KEY (tenant_id, sub_recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipe_components_type_shape CHECK (
        (component_type IN ('stock_item', 'packaging')
            AND inventory_stock_item_id IS NOT NULL AND sub_recipe_version_id IS NULL)
        OR
        (component_type = 'sub_recipe'
            AND inventory_stock_item_id IS NULL AND sub_recipe_version_id IS NOT NULL)
    ),
    CONSTRAINT production_recipe_components_no_direct_recursion CHECK (
        sub_recipe_version_id IS NULL OR sub_recipe_version_id <> recipe_version_id
    )
);

CREATE INDEX ix_production_recipe_components_version
    ON production.recipe_components (tenant_id, recipe_version_id, line_number);
CREATE INDEX ix_production_recipe_components_stock_item
    ON production.recipe_components (tenant_id, inventory_stock_item_id)
    WHERE inventory_stock_item_id IS NOT NULL;
CREATE INDEX ix_production_recipe_components_subrecipe
    ON production.recipe_components (tenant_id, sub_recipe_version_id)
    WHERE sub_recipe_version_id IS NOT NULL;

CREATE TABLE production.recipe_component_alternatives (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    component_id            uuid NOT NULL,
    alternative_stock_item_id uuid NOT NULL,
    alternative_unit_id     uuid NOT NULL,
    conversion_factor       numeric(20,10) NOT NULL DEFAULT 1 CHECK (conversion_factor > 0),
    priority                smallint NOT NULL DEFAULT 1 CHECK (priority > 0),
    substitution_notes      text,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_recipe_component_alternatives_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipe_component_alternatives_component_item_unique UNIQUE (tenant_id, component_id, alternative_stock_item_id),
    CONSTRAINT production_recipe_component_alternatives_component_fk FOREIGN KEY (tenant_id, component_id)
        REFERENCES production.recipe_components (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_production_component_alternatives_component
    ON production.recipe_component_alternatives (tenant_id, component_id, priority)
    WHERE is_active = true;

CREATE TABLE production.recipe_steps (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    recipe_version_id       uuid NOT NULL,
    step_number             integer NOT NULL CHECK (step_number > 0),
    title                   varchar(180) NOT NULL,
    instructions            text NOT NULL,
    target_temperature_c    numeric(8,3),
    target_duration_seconds integer CHECK (target_duration_seconds IS NULL OR target_duration_seconds >= 0),
    equipment_reference     varchar(120),
    is_critical             boolean NOT NULL DEFAULT false,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_recipe_steps_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_recipe_steps_number_unique UNIQUE (tenant_id, recipe_version_id, step_number),
    CONSTRAINT production_recipe_steps_version_fk FOREIGN KEY (tenant_id, recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_recipe_steps_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT production_recipe_steps_instructions_not_blank CHECK (btrim(instructions) <> '')
);

CREATE INDEX ix_production_recipe_steps_version
    ON production.recipe_steps (tenant_id, recipe_version_id, step_number);

-- ---------------------------------------------------------------------------
-- 4. Centros de trabajo y rutas de produccion
-- ---------------------------------------------------------------------------

CREATE TABLE production.work_centers (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid,
    work_center_code        varchar(60) NOT NULL,
    name                    varchar(160) NOT NULL,
    work_center_type        varchar(24) NOT NULL DEFAULT 'general'
                            CHECK (work_center_type IN ('prep', 'hot_kitchen', 'cold_kitchen', 'bakery', 'beverage', 'packaging', 'quality', 'general')),
    capacity_per_hour       numeric(14,4) CHECK (capacity_per_hour IS NULL OR capacity_per_hour > 0),
    capacity_unit_id        uuid,
    is_active               boolean NOT NULL DEFAULT true,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_work_centers_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_work_centers_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT production_work_centers_code_not_blank CHECK (btrim(work_center_code) <> ''),
    CONSTRAINT production_work_centers_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT production_work_centers_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_production_work_center_global_code
    ON production.work_centers (tenant_id, company_id, lower(work_center_code))
    WHERE branch_id IS NULL;
CREATE UNIQUE INDEX uq_production_work_center_branch_code
    ON production.work_centers (tenant_id, company_id, branch_id, lower(work_center_code))
    WHERE branch_id IS NOT NULL;
CREATE INDEX ix_production_work_centers_branch_active
    ON production.work_centers (tenant_id, company_id, branch_id, is_active);

CREATE TABLE production.routing_templates (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    recipe_version_id       uuid NOT NULL,
    routing_code            varchar(60) NOT NULL,
    name                    varchar(160) NOT NULL,
    routing_status          varchar(16) NOT NULL DEFAULT 'draft'
                            CHECK (routing_status IN ('draft', 'active', 'inactive')),
    is_default              boolean NOT NULL DEFAULT false,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_routing_templates_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_routing_templates_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT production_routing_templates_company_version_id_unique UNIQUE (tenant_id, company_id, recipe_version_id, id),
    CONSTRAINT production_routing_templates_code_unique UNIQUE (tenant_id, company_id, routing_code),
    CONSTRAINT production_routing_templates_version_id_unique UNIQUE (tenant_id, recipe_version_id, id),
    CONSTRAINT production_routing_templates_recipe_version_fk FOREIGN KEY (tenant_id, recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_routing_templates_code_not_blank CHECK (btrim(routing_code) <> ''),
    CONSTRAINT production_routing_templates_name_not_blank CHECK (btrim(name) <> '')
);

CREATE UNIQUE INDEX uq_production_default_routing_per_recipe
    ON production.routing_templates (tenant_id, company_id, recipe_version_id)
    WHERE is_default = true AND routing_status = 'active';

CREATE TABLE production.routing_steps (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    routing_template_id     uuid NOT NULL,
    work_center_id          uuid NOT NULL,
    step_number             integer NOT NULL CHECK (step_number > 0),
    operation_code          varchar(60) NOT NULL,
    operation_name          varchar(160) NOT NULL,
    setup_minutes           numeric(10,2) NOT NULL DEFAULT 0 CHECK (setup_minutes >= 0),
    run_minutes_per_unit    numeric(12,6) NOT NULL DEFAULT 0 CHECK (run_minutes_per_unit >= 0),
    wait_minutes            numeric(10,2) NOT NULL DEFAULT 0 CHECK (wait_minutes >= 0),
    instructions            text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_routing_steps_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_routing_steps_number_unique UNIQUE (tenant_id, routing_template_id, step_number),
    CONSTRAINT production_routing_steps_routing_fk FOREIGN KEY (tenant_id, company_id, routing_template_id)
        REFERENCES production.routing_templates (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_routing_steps_work_center_fk FOREIGN KEY (tenant_id, company_id, work_center_id)
        REFERENCES production.work_centers (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_routing_steps_code_not_blank CHECK (btrim(operation_code) <> ''),
    CONSTRAINT production_routing_steps_name_not_blank CHECK (btrim(operation_name) <> '')
);

CREATE INDEX ix_production_routing_steps_work_center
    ON production.routing_steps (tenant_id, work_center_id, routing_template_id, step_number);

-- ---------------------------------------------------------------------------
-- 5. Ordenes de produccion y materiales planificados
-- ---------------------------------------------------------------------------

CREATE TABLE production.production_orders (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    order_number            varchar(80) NOT NULL,
    order_type              varchar(24) NOT NULL DEFAULT 'make_to_stock'
                            CHECK (order_type IN ('make_to_stock', 'make_to_order', 'prep_batch', 'rework')),
    order_status            varchar(20) NOT NULL DEFAULT 'draft'
                            CHECK (order_status IN ('draft', 'planned', 'released', 'in_progress', 'paused', 'completed', 'cancelled', 'failed')),
    priority                smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    recipe_id               uuid NOT NULL,
    recipe_version_id       uuid NOT NULL,
    routing_template_id     uuid,
    output_catalog_product_id uuid,
    output_catalog_variant_id uuid,
    output_inventory_item_id uuid,
    output_unit_id          uuid NOT NULL,
    planned_quantity        numeric(20,6) NOT NULL CHECK (planned_quantity > 0),
    started_quantity        numeric(20,6) NOT NULL DEFAULT 0 CHECK (started_quantity >= 0),
    completed_quantity      numeric(20,6) NOT NULL DEFAULT 0 CHECK (completed_quantity >= 0),
    scheduled_start_at      timestamptz,
    due_at                  timestamptz,
    started_at              timestamptz,
    completed_at            timestamptz,
    source_module           varchar(60),
    source_reference_type   varchar(80),
    source_reference_id     uuid,
    idempotency_key         varchar(160),
    notes                   text,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_user_id      uuid,
    approved_by_user_id     uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_orders_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_orders_company_id_unique UNIQUE (tenant_id, company_id, id),
    CONSTRAINT production_orders_company_branch_id_unique UNIQUE (tenant_id, company_id, branch_id, id),
    CONSTRAINT production_orders_version_id_unique UNIQUE (tenant_id, id, recipe_version_id),
    CONSTRAINT production_orders_number_unique UNIQUE (tenant_id, company_id, order_number),
    CONSTRAINT production_orders_recipe_fk FOREIGN KEY (tenant_id, recipe_id)
        REFERENCES production.recipes (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_orders_recipe_version_fk FOREIGN KEY (tenant_id, recipe_id, recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, recipe_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_orders_routing_fk FOREIGN KEY (tenant_id, company_id, recipe_version_id, routing_template_id)
        REFERENCES production.routing_templates (tenant_id, company_id, recipe_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_orders_source_shape CHECK (
        (source_module IS NULL AND source_reference_type IS NULL AND source_reference_id IS NULL)
        OR (source_module IS NOT NULL AND source_reference_type IS NOT NULL AND source_reference_id IS NOT NULL)
    ),
    CONSTRAINT production_orders_idempotency_not_blank CHECK (idempotency_key IS NULL OR btrim(idempotency_key) <> ''),
    CONSTRAINT production_orders_dates CHECK (due_at IS NULL OR scheduled_start_at IS NULL OR due_at >= scheduled_start_at),
    CONSTRAINT production_orders_completion_time CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT production_orders_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE UNIQUE INDEX uq_production_order_idempotency
    ON production.production_orders (tenant_id, company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX ix_production_orders_branch_queue
    ON production.production_orders (tenant_id, company_id, branch_id, order_status, priority, due_at);
CREATE INDEX ix_production_orders_recipe_date
    ON production.production_orders (tenant_id, recipe_id, created_at DESC);
CREATE INDEX ix_production_orders_source
    ON production.production_orders (tenant_id, source_module, source_reference_type, source_reference_id)
    WHERE source_reference_id IS NOT NULL;

CREATE TABLE production.production_order_materials (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    production_order_id     uuid NOT NULL,
    recipe_component_id     uuid,
    recipe_version_id       uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    inventory_stock_item_id uuid NOT NULL,
    inventory_lot_id        uuid,
    component_unit_id       uuid NOT NULL,
    planned_quantity        numeric(20,6) NOT NULL CHECK (planned_quantity > 0),
    reserved_quantity       numeric(20,6) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
    issued_quantity         numeric(20,6) NOT NULL DEFAULT 0 CHECK (issued_quantity >= 0),
    returned_quantity       numeric(20,6) NOT NULL DEFAULT 0 CHECK (returned_quantity >= 0),
    expected_scrap_pct      numeric(7,4) NOT NULL DEFAULT 0 CHECK (expected_scrap_pct BETWEEN 0 AND 100),
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_order_materials_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_order_materials_order_id_unique UNIQUE (tenant_id, production_order_id, id),
    CONSTRAINT production_order_materials_line_unique UNIQUE (tenant_id, production_order_id, line_number),
    CONSTRAINT production_order_materials_order_fk FOREIGN KEY (tenant_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_order_materials_order_version_fk FOREIGN KEY (tenant_id, production_order_id, recipe_version_id)
        REFERENCES production.production_orders (tenant_id, id, recipe_version_id) ON DELETE RESTRICT,
    CONSTRAINT production_order_materials_component_fk FOREIGN KEY (tenant_id, recipe_version_id, recipe_component_id)
        REFERENCES production.recipe_components (tenant_id, recipe_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_order_materials_return_limit CHECK (returned_quantity <= issued_quantity),
    CONSTRAINT production_order_materials_quantities_nonnegative CHECK (reserved_quantity >= 0 AND issued_quantity >= 0 AND returned_quantity >= 0)
);

CREATE INDEX ix_production_order_materials_item
    ON production.production_order_materials (tenant_id, inventory_stock_item_id, production_order_id);

-- ---------------------------------------------------------------------------
-- 6. Lotes de produccion y transacciones de materiales
-- ---------------------------------------------------------------------------

CREATE TABLE production.production_batches (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    branch_id               uuid NOT NULL,
    production_order_id     uuid NOT NULL,
    batch_code              varchar(80) NOT NULL,
    inventory_stock_item_id uuid NOT NULL,
    inventory_lot_id        uuid,
    batch_status            varchar(16) NOT NULL DEFAULT 'open'
                            CHECK (batch_status IN ('open', 'in_progress', 'released', 'quarantined', 'closed', 'rejected')),
    planned_quantity        numeric(20,6) NOT NULL CHECK (planned_quantity > 0),
    produced_quantity       numeric(20,6) NOT NULL DEFAULT 0 CHECK (produced_quantity >= 0),
    started_at              timestamptz,
    completed_at            timestamptz,
    metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_batches_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_batches_order_id_unique UNIQUE (tenant_id, production_order_id, id),
    CONSTRAINT production_batches_order_branch_fk
        FOREIGN KEY (tenant_id, company_id, branch_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, company_id, branch_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_batches_order_code_unique UNIQUE (tenant_id, production_order_id, batch_code),
    CONSTRAINT production_batches_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT production_batches_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE INDEX ix_production_batches_status
    ON production.production_batches (tenant_id, company_id, branch_id, batch_status, created_at DESC);
CREATE INDEX ix_production_batches_inventory_lot
    ON production.production_batches (tenant_id, inventory_lot_id)
    WHERE inventory_lot_id IS NOT NULL;

CREATE TABLE production.material_transactions (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    production_order_id     uuid NOT NULL,
    transaction_number      varchar(80) NOT NULL,
    transaction_type        varchar(16) NOT NULL CHECK (transaction_type IN ('issue', 'return')),
    transaction_status      varchar(16) NOT NULL DEFAULT 'pending'
                            CHECK (transaction_status IN ('pending', 'posted', 'failed', 'cancelled')),
    inventory_movement_id   uuid,
    idempotency_key         varchar(160) NOT NULL,
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    posted_at               timestamptz,
    failure_reason          text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_material_transactions_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_material_transactions_order_id_unique UNIQUE (tenant_id, id, production_order_id),
    CONSTRAINT production_material_transactions_number_unique UNIQUE (tenant_id, company_id, transaction_number),
    CONSTRAINT production_material_transactions_idempotency_unique UNIQUE (tenant_id, company_id, idempotency_key),
    CONSTRAINT production_material_transactions_order_fk FOREIGN KEY (tenant_id, company_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_material_transactions_posted_shape CHECK (
        (transaction_status = 'posted' AND inventory_movement_id IS NOT NULL AND posted_at IS NOT NULL)
        OR (transaction_status <> 'posted' AND posted_at IS NULL)
    ),
    CONSTRAINT production_material_transactions_failure_shape CHECK (
        transaction_status <> 'failed' OR failure_reason IS NOT NULL
    )
);

CREATE INDEX ix_production_material_transactions_order
    ON production.material_transactions (tenant_id, production_order_id, occurred_at DESC);
CREATE INDEX ix_production_material_transactions_inventory_movement
    ON production.material_transactions (tenant_id, inventory_movement_id)
    WHERE inventory_movement_id IS NOT NULL;

CREATE TABLE production.material_transaction_lines (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    production_order_id         uuid NOT NULL,
    material_transaction_id     uuid NOT NULL,
    order_material_id           uuid NOT NULL,
    inventory_stock_item_id     uuid NOT NULL,
    inventory_lot_id            uuid,
    inventory_movement_line_id  uuid,
    quantity                    numeric(20,6) NOT NULL CHECK (quantity > 0),
    unit_id                     uuid NOT NULL,
    unit_cost_snapshot          numeric(20,6) CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0),
    created_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_material_transaction_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_material_transaction_lines_transaction_fk FOREIGN KEY (tenant_id, material_transaction_id, production_order_id)
        REFERENCES production.material_transactions (tenant_id, id, production_order_id) ON DELETE RESTRICT,
    CONSTRAINT production_material_transaction_lines_order_material_fk FOREIGN KEY (tenant_id, production_order_id, order_material_id)
        REFERENCES production.production_order_materials (tenant_id, production_order_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_production_material_transaction_lines_item
    ON production.material_transaction_lines (tenant_id, inventory_stock_item_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 7. Reportes de salida/rendimiento y desperdicio
-- ---------------------------------------------------------------------------

CREATE TABLE production.output_reports (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    production_order_id     uuid NOT NULL,
    report_number           varchar(80) NOT NULL,
    report_status           varchar(16) NOT NULL DEFAULT 'draft'
                            CHECK (report_status IN ('draft', 'posted', 'void')),
    inventory_movement_id   uuid,
    reported_at             timestamptz NOT NULL DEFAULT now(),
    posted_at               timestamptz,
    notes                   text,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_output_reports_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_output_reports_order_id_unique UNIQUE (tenant_id, id, production_order_id),
    CONSTRAINT production_output_reports_number_unique UNIQUE (tenant_id, company_id, report_number),
    CONSTRAINT production_output_reports_order_fk FOREIGN KEY (tenant_id, company_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_output_reports_posted_shape CHECK (
        (report_status = 'posted' AND inventory_movement_id IS NOT NULL AND posted_at IS NOT NULL)
        OR (report_status <> 'posted' AND posted_at IS NULL)
    )
);

CREATE INDEX ix_production_output_reports_order
    ON production.output_reports (tenant_id, production_order_id, reported_at DESC);

CREATE TABLE production.output_report_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    production_order_id     uuid NOT NULL,
    output_report_id        uuid NOT NULL,
    production_batch_id     uuid,
    line_number             integer NOT NULL CHECK (line_number > 0),
    inventory_stock_item_id uuid NOT NULL,
    inventory_lot_id        uuid,
    output_unit_id          uuid NOT NULL,
    quantity_produced       numeric(20,6) NOT NULL CHECK (quantity_produced > 0),
    quantity_accepted       numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_accepted >= 0),
    quantity_rejected       numeric(20,6) NOT NULL DEFAULT 0 CHECK (quantity_rejected >= 0),
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_output_report_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_output_report_lines_number_unique UNIQUE (tenant_id, output_report_id, line_number),
    CONSTRAINT production_output_report_lines_report_fk FOREIGN KEY (tenant_id, output_report_id, production_order_id)
        REFERENCES production.output_reports (tenant_id, id, production_order_id) ON DELETE RESTRICT,
    CONSTRAINT production_output_report_lines_batch_fk FOREIGN KEY (tenant_id, production_order_id, production_batch_id)
        REFERENCES production.production_batches (tenant_id, production_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_output_report_lines_quantity_balance CHECK (
        quantity_accepted + quantity_rejected <= quantity_produced
    )
);

CREATE INDEX ix_production_output_report_lines_stock_item
    ON production.output_report_lines (tenant_id, inventory_stock_item_id, created_at DESC);

CREATE TABLE production.waste_reports (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    production_order_id     uuid NOT NULL,
    report_number           varchar(80) NOT NULL,
    waste_status            varchar(16) NOT NULL DEFAULT 'draft'
                            CHECK (waste_status IN ('draft', 'posted', 'void')),
    waste_stage             varchar(20) NOT NULL
                            CHECK (waste_stage IN ('preparation', 'processing', 'quality_reject', 'finished_output', 'expiry', 'other')),
    inventory_movement_id   uuid,
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    posted_at               timestamptz,
    reason                  text NOT NULL,
    created_by_user_id      uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_waste_reports_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_waste_reports_order_id_unique UNIQUE (tenant_id, id, production_order_id),
    CONSTRAINT production_waste_reports_number_unique UNIQUE (tenant_id, company_id, report_number),
    CONSTRAINT production_waste_reports_order_fk FOREIGN KEY (tenant_id, company_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, company_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_waste_reports_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT production_waste_reports_posted_shape CHECK (
        (waste_status = 'posted' AND inventory_movement_id IS NOT NULL AND posted_at IS NOT NULL)
        OR (waste_status <> 'posted' AND posted_at IS NULL)
    )
);

CREATE INDEX ix_production_waste_reports_order
    ON production.waste_reports (tenant_id, production_order_id, occurred_at DESC);

CREATE TABLE production.waste_report_lines (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    waste_report_id         uuid NOT NULL,
    line_number             integer NOT NULL CHECK (line_number > 0),
    inventory_stock_item_id uuid NOT NULL,
    inventory_lot_id        uuid,
    quantity                numeric(20,6) NOT NULL CHECK (quantity > 0),
    unit_id                 uuid NOT NULL,
    reason_code             varchar(50),
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_waste_report_lines_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_waste_report_lines_number_unique UNIQUE (tenant_id, waste_report_id, line_number),
    CONSTRAINT production_waste_report_lines_report_fk FOREIGN KEY (tenant_id, waste_report_id)
        REFERENCES production.waste_reports (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_production_waste_report_lines_stock_item
    ON production.waste_report_lines (tenant_id, inventory_stock_item_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 8. Especificaciones y controles de calidad
-- ---------------------------------------------------------------------------

CREATE TABLE production.quality_specifications (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    recipe_version_id       uuid,
    specification_code      varchar(70) NOT NULL,
    name                    varchar(180) NOT NULL,
    inspection_stage        varchar(20) NOT NULL
                            CHECK (inspection_stage IN ('in_process', 'finished_product', 'packaging', 'storage')),
    value_type              varchar(16) NOT NULL
                            CHECK (value_type IN ('numeric', 'text', 'boolean')),
    target_numeric          numeric(20,6),
    minimum_numeric         numeric(20,6),
    maximum_numeric         numeric(20,6),
    expected_text           text,
    expected_boolean        boolean,
    unit_id                 uuid,
    is_required             boolean NOT NULL DEFAULT true,
    is_critical             boolean NOT NULL DEFAULT false,
    is_active               boolean NOT NULL DEFAULT true,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_quality_specifications_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_quality_specifications_code_unique UNIQUE (tenant_id, company_id, specification_code),
    CONSTRAINT production_quality_specifications_recipe_fk FOREIGN KEY (tenant_id, recipe_version_id)
        REFERENCES production.recipe_versions (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_quality_specifications_numeric_range CHECK (
        minimum_numeric IS NULL OR maximum_numeric IS NULL OR minimum_numeric <= maximum_numeric
    ),
    CONSTRAINT production_quality_specifications_value_shape CHECK (
        (value_type = 'numeric' AND expected_text IS NULL AND expected_boolean IS NULL)
        OR (value_type = 'text' AND target_numeric IS NULL AND minimum_numeric IS NULL AND maximum_numeric IS NULL AND expected_boolean IS NULL)
        OR (value_type = 'boolean' AND target_numeric IS NULL AND minimum_numeric IS NULL AND maximum_numeric IS NULL AND expected_text IS NULL)
    ),
    CONSTRAINT production_quality_specifications_code_not_blank CHECK (btrim(specification_code) <> ''),
    CONSTRAINT production_quality_specifications_name_not_blank CHECK (btrim(name) <> '')
);

CREATE INDEX ix_production_quality_specifications_recipe
    ON production.quality_specifications (tenant_id, recipe_version_id, inspection_stage)
    WHERE is_active = true;

CREATE TABLE production.quality_checks (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id              uuid NOT NULL,
    production_order_id     uuid NOT NULL,
    production_batch_id     uuid,
    inspection_stage        varchar(20) NOT NULL
                            CHECK (inspection_stage IN ('in_process', 'finished_product', 'packaging', 'storage')),
    check_status            varchar(16) NOT NULL DEFAULT 'in_progress'
                            CHECK (check_status IN ('in_progress', 'passed', 'failed', 'conditional', 'cancelled')),
    inspected_by_user_id    uuid,
    started_at              timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_quality_checks_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_quality_checks_order_fk FOREIGN KEY (tenant_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_quality_checks_batch_fk FOREIGN KEY (tenant_id, production_order_id, production_batch_id)
        REFERENCES production.production_batches (tenant_id, production_order_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_quality_checks_dates CHECK (completed_at IS NULL OR completed_at >= started_at)
);

CREATE INDEX ix_production_quality_checks_order
    ON production.quality_checks (tenant_id, production_order_id, check_status, started_at DESC);
CREATE INDEX ix_production_quality_checks_batch
    ON production.quality_checks (tenant_id, production_batch_id, check_status)
    WHERE production_batch_id IS NOT NULL;

CREATE TABLE production.quality_check_results (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    quality_check_id        uuid NOT NULL,
    specification_id        uuid NOT NULL,
    result_numeric          numeric(20,6),
    result_text             text,
    result_boolean          boolean,
    passed                  boolean NOT NULL,
    measured_at             timestamptz NOT NULL DEFAULT now(),
    measured_by_user_id     uuid,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_quality_check_results_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_quality_check_results_check_spec_unique UNIQUE (tenant_id, quality_check_id, specification_id),
    CONSTRAINT production_quality_check_results_check_fk FOREIGN KEY (tenant_id, quality_check_id)
        REFERENCES production.quality_checks (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_quality_check_results_spec_fk FOREIGN KEY (tenant_id, specification_id)
        REFERENCES production.quality_specifications (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT production_quality_check_results_single_value CHECK (
        num_nonnulls(result_numeric, result_text, result_boolean) = 1
    )
);

CREATE INDEX ix_production_quality_check_results_spec
    ON production.quality_check_results (tenant_id, specification_id, measured_at DESC);

-- ---------------------------------------------------------------------------
-- 9. Historial operativo e integracion por eventos
-- ---------------------------------------------------------------------------

CREATE TABLE production.order_status_history (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    production_order_id     uuid NOT NULL,
    previous_status         varchar(20),
    new_status              varchar(20) NOT NULL,
    changed_at              timestamptz NOT NULL DEFAULT now(),
    changed_by_user_id      uuid,
    reason                  text,
    correlation_id          uuid,
    CONSTRAINT production_order_status_history_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_order_status_history_order_fk FOREIGN KEY (tenant_id, production_order_id)
        REFERENCES production.production_orders (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_production_order_status_history_order
    ON production.order_status_history (tenant_id, production_order_id, changed_at DESC);

CREATE TABLE production.processed_events (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                uuid NOT NULL,
    event_type              varchar(160) NOT NULL,
    schema_version          integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    aggregate_type          varchar(80),
    aggregate_id            uuid,
    payload_sha256          bytea NOT NULL,
    processed_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_processed_events_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_processed_events_event_unique UNIQUE (tenant_id, event_id),
    CONSTRAINT production_processed_events_hash_length CHECK (octet_length(payload_sha256) = 32)
);

CREATE INDEX ix_production_processed_events_type
    ON production.processed_events (tenant_id, event_type, processed_at DESC);

CREATE TABLE production.event_outbox (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    event_id                uuid NOT NULL DEFAULT gen_random_uuid(),
    aggregate_type          varchar(80) NOT NULL,
    aggregate_id            uuid NOT NULL,
    event_type              varchar(160) NOT NULL,
    schema_version          integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    payload                 jsonb NOT NULL,
    occurred_at             timestamptz NOT NULL DEFAULT now(),
    available_at            timestamptz NOT NULL DEFAULT now(),
    published_at            timestamptz,
    publish_attempts        integer NOT NULL DEFAULT 0 CHECK (publish_attempts >= 0),
    last_error              text,
    CONSTRAINT production_event_outbox_tenant_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT production_event_outbox_event_unique UNIQUE (tenant_id, event_id),
    CONSTRAINT production_event_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX ix_production_outbox_pending
    ON production.event_outbox (tenant_id, available_at, occurred_at)
    WHERE published_at IS NULL;
CREATE INDEX ix_production_outbox_aggregate
    ON production.event_outbox (tenant_id, aggregate_type, aggregate_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 10. Triggers: updated_at, scope, versionado e inmutabilidad
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'recipe_categories', 'recipes', 'recipe_versions',
        'recipe_components', 'recipe_steps', 'work_centers', 'routing_templates',
        'routing_steps', 'production_orders', 'production_order_materials',
        'production_batches', 'material_transactions', 'output_reports',
        'waste_reports', 'quality_specifications', 'quality_checks'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_set_updated_at BEFORE UPDATE ON production.%I FOR EACH ROW EXECUTE FUNCTION production.set_updated_at()',
            v_table, v_table
        );
        EXECUTE format(
            'CREATE TRIGGER trg_%I_prevent_tenant_change BEFORE UPDATE ON production.%I FOR EACH ROW EXECUTE FUNCTION production.prevent_tenant_change()',
            v_table, v_table
        );
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'recipe_component_alternatives', 'material_transaction_lines',
        'output_report_lines', 'waste_report_lines', 'quality_check_results',
        'order_status_history', 'processed_events', 'event_outbox'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_prevent_tenant_change BEFORE UPDATE ON production.%I FOR EACH ROW EXECUTE FUNCTION production.prevent_tenant_change()',
            v_table, v_table
        );
    END LOOP;
END;
$$;

CREATE TRIGGER trg_recipe_versions_guard_mutation
BEFORE INSERT OR UPDATE OR DELETE ON production.recipe_versions
FOR EACH ROW EXECUTE FUNCTION production.guard_recipe_version_mutation();

CREATE TRIGGER trg_recipe_components_guard_draft
BEFORE INSERT OR UPDATE OR DELETE ON production.recipe_components
FOR EACH ROW EXECUTE FUNCTION production.guard_recipe_child_mutation();

CREATE TRIGGER trg_recipe_steps_guard_draft
BEFORE INSERT OR UPDATE OR DELETE ON production.recipe_steps
FOR EACH ROW EXECUTE FUNCTION production.guard_recipe_child_mutation();

CREATE TRIGGER trg_recipe_component_alternatives_guard_draft
BEFORE INSERT OR UPDATE OR DELETE ON production.recipe_component_alternatives
FOR EACH ROW EXECUTE FUNCTION production.guard_recipe_child_mutation();

CREATE TRIGGER trg_order_status_history_append_only
BEFORE UPDATE OR DELETE ON production.order_status_history
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

CREATE TRIGGER trg_material_transaction_lines_append_only
BEFORE UPDATE OR DELETE ON production.material_transaction_lines
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

CREATE TRIGGER trg_output_report_lines_append_only
BEFORE UPDATE OR DELETE ON production.output_report_lines
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

CREATE TRIGGER trg_waste_report_lines_append_only
BEFORE UPDATE OR DELETE ON production.waste_report_lines
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

CREATE TRIGGER trg_quality_check_results_append_only
BEFORE UPDATE OR DELETE ON production.quality_check_results
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

CREATE TRIGGER trg_processed_events_append_only
BEFORE UPDATE OR DELETE ON production.processed_events
FOR EACH ROW EXECUTE FUNCTION production.prevent_append_only_mutation();

-- ---------------------------------------------------------------------------
-- 11. Inicializacion idempotente por tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION production.initialize_tenant_production(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM production.current_tenant_id() THEN
        RAISE EXCEPTION 'El tenant solicitado no coincide con app.tenant_id';
    END IF;

    INSERT INTO production.tenant_settings (tenant_id)
    VALUES (p_tenant_id)
    ON CONFLICT (tenant_id) DO NOTHING;

    INSERT INTO production.recipe_categories (tenant_id, category_code, name, sort_order)
    VALUES
        (p_tenant_id, 'PREP', 'Preparaciones base', 10),
        (p_tenant_id, 'SAUCE', 'Salsas y aderezos', 20),
        (p_tenant_id, 'DOUGH', 'Masas y panificacion', 30),
        (p_tenant_id, 'PROTEIN', 'Proteinas preparadas', 40),
        (p_tenant_id, 'SIDE', 'Acompanamientos', 50),
        (p_tenant_id, 'BEVERAGE', 'Bebidas preparadas', 60),
        (p_tenant_id, 'OTHER', 'Otras preparaciones', 90)
    ON CONFLICT (tenant_id, category_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. RLS en todas las tablas tenant-scoped
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'tenant_settings', 'recipe_categories', 'recipes', 'recipe_versions',
        'recipe_components', 'recipe_component_alternatives', 'recipe_steps',
        'work_centers', 'routing_templates', 'routing_steps', 'production_orders',
        'production_order_materials', 'production_batches', 'material_transactions',
        'material_transaction_lines', 'output_reports', 'output_report_lines',
        'waste_reports', 'waste_report_lines', 'quality_specifications',
        'quality_checks', 'quality_check_results', 'order_status_history',
        'processed_events', 'event_outbox'
    ] LOOP
        EXECUTE format('ALTER TABLE production.%I ENABLE ROW LEVEL SECURITY', v_table);
        EXECUTE format('ALTER TABLE production.%I FORCE ROW LEVEL SECURITY', v_table);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON production.%I USING (tenant_id = production.current_tenant_id()) WITH CHECK (tenant_id = production.current_tenant_id())',
            v_table
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Comentarios de propiedad y limites
-- ---------------------------------------------------------------------------

COMMENT ON TABLE production.recipes IS
'Identidad de una receta/ficha tecnica con alcance tenant, empresa o sucursal. La aplicacion resuelve la receta especifica de sucursal antes de heredar la de empresa o tenant.';
COMMENT ON COLUMN production.recipes.branch_id IS
'Referencia logica a Organization. NULL representa alcance de tenant o empresa; una receta de sucursal requiere company_id.';
COMMENT ON TABLE production.recipe_versions IS
'Version inmutable tras publicacion. Una modificacion tecnica requiere crear una nueva version draft.';
COMMENT ON TABLE production.recipe_components IS
'BOM/escandallo. inventory_stock_item_id y component_unit_id son referencias logicas a Inventory y Catalog.';
COMMENT ON TABLE production.production_orders IS
'Orden para producir un lote/preparacion. No es una comanda de Kitchen ni una orden de compra de Procurement.';
COMMENT ON TABLE production.production_order_materials IS
'Plan de materiales de una orden. No reserva ni descuenta existencias; la operacion efectiva se solicita a Inventory.';
COMMENT ON TABLE production.material_transactions IS
'Referencia de Production a movimientos de issue/return creados por Inventory. Inventory conserva el ledger oficial.';
COMMENT ON TABLE production.output_reports IS
'Informe de productos obtenidos. La entrada fisica al stock se registra en Inventory y se referencia aqui.';
COMMENT ON TABLE production.waste_reports IS
'Informe operativo de merma/desperdicio. La baja fisica de stock corresponde a un movimiento de Inventory.';
COMMENT ON TABLE production.processed_events IS
'Inbox idempotente. Registrar event_id y hash del payload en la misma transaccion que aplica la consecuencia.';
COMMENT ON TABLE production.event_outbox IS
'Outbox transaccional para publicar eventos de recetas y produccion despues de confirmar la transaccion.';

COMMIT;

-- ============================================================================
-- GUIA DE INTEGRACION PARA RUST / CONTRATOS
-- ============================================================================
-- Permisos a registrar mediante una migracion PROPIA de Identity:
--   production.recipes.read / production.recipes.create / production.recipes.update
--   production.recipes.publish / production.recipes.retire
--   production.orders.read / production.orders.create / production.orders.approve
--   production.orders.release / production.orders.pause / production.orders.complete
--   production.materials.plan / production.materials.issue / production.materials.return
--   production.outputs.report / production.waste.report
--   production.quality.read / production.quality.inspect / production.quality.release
--   production.work_centers.manage / production.routings.manage
--
-- Puertos/contratos recomendados:
--   CatalogProductPort: validar producto/variante/unidad y obtener snapshots.
--   InventoryStockItemPort: validar stock_item, reservar/emitir/devolver materiales,
--       recibir producto terminado y registrar mermas mediante comandos idempotentes.
--   OrganizationScopePort: validar company_id y branch_id del tenant.
--   IdentityAuthorizationPort: validar actor, permiso y alcance.
--   EventPublisherPort / EventInboxPort: outbox/inbox con contratos versionados.
--   ClockPort / IdGeneratorPort: pruebas deterministas.
--
-- Eventos publicados sugeridos:
--   production.recipe_published.v1
--   production.order_released.v1
--   production.materials_issue_requested.v1
--   production.output_reported.v1
--   production.waste_reported.v1
--   production.quality_check_completed.v1
--   production.batch_released.v1
--
-- Eventos consumidos sugeridos:
--   inventory.materials_issued.v1
--   inventory.materials_returned.v1
--   inventory.finished_goods_received.v1
--   catalog.product_archived.v1 (para bloquear recetas nuevas que usen productos archivados)
--   organization.branch_suspended.v1
--
-- INVARIANTES QUE DEBE IMPLEMENTAR application/domain:
--   * Validar tenant, company y branch mediante sus contratos publicos.
--   * Resolver recetas por alcance: sucursal, empresa y luego tenant; validar
--     que una orden de produccion solo use una receta accesible para su sucursal.
--   * Validar que recipe_id y recipe_version_id pertenecen a la misma receta.
--   * Solo publicar una version completa; la version activa es inmutable.
--   * Detectar ciclos de sub-recetas en el grafo BOM antes de publicar una version.
--     Hacerlo transaccionalmente y serializar publicaciones por tenant/receta para
--     evitar ciclos introducidos por dos publicaciones concurrentes.
--   * Convertir unidades con Catalog; no asumir que kg, g, l, ml y unidades son
--     intercambiables sin conversion/dimension valida.
--   * Al liberar una orden, congelar el snapshot de BOM en production_order_materials.
--   * No actualizar existencias desde Production. Toda reserva, emision, devolucion,
--     entrada de producto terminado o merma fisica se solicita a Inventory.
--   * Usar Saga/compensaciones si Production e Inventory quedan en servicios distintos.
--   * Materializar inventario_movement_id solo cuando Inventory confirme el movimiento.
--   * Aplicar idempotencia por tenant + idempotency_key y validar hash de eventos.
--   * Una falla de calidad puede poner un lote en cuarentena; no liberar stock
--     terminado hasta obtener la aprobacion requerida.
--   * Los reportes posted no se corrigen editandolos: se registra reverso/ajuste
--     compensatorio y un nuevo reporte.
--   * Validar que el routing_template pertenece a la recipe_version de la orden.
--   * RLS por tenant no reemplaza la autorizacion por empresa/sucursal.
--
-- MODULO 0 / CATALOGO SaaS:
--   'menu_production' es un paquete comercial. La separacion entre Catalog,
--   Production y Kitchen se mantiene en los schemas, permisos y contratos,
--   independientemente de como Platform empaquete la suscripcion.
--
-- ORDEN RECOMENDADO:
--   Platform -> Organization -> Catalog -> Inventory -> Production.
--   Identity puede instalarse antes; se integra por contratos y referencias UUID.
-- ============================================================================
-- FIN MODULO 8: PRODUCTION
-- ============================================================================
