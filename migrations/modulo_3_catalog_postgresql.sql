-- ============================================================================
-- RESTAURANT-OS / POS SAAS MULTIEMPRESA Y MULTISUCURSAL
-- MODULO 3: CATALOG (CATALOGO COMERCIAL, PRODUCTOS, MENUS Y PRECIOS)
-- Ubicacion del crate: crates/modules/catalog
-- Motor: PostgreSQL 15+
--
-- REQUIERE:
--   * modulo_0_admin_plataforma_postgresql.sql (platform.tenants)
--   * organization instalado (empresas y sucursales)
--   * identity puede instalarse antes o despues: no se crean FK a identity.
--
-- CODIGO DEL MODULO SAAS:
--   platform.modules ya registra este modulo como 'product_catalog'.
--   Este schema/crate se llama 'catalog'; no se crea una segunda entrada SaaS.
--
-- RESPONSABILIDAD DE CATALOG:
--   * Unidades de medida y conversiones utilizadas por el catalogo.
--   * Categorias y etiquetas.
--   * Productos vendibles/comprables y sus variantes/SKU/codigos de barras.
--   * Datos comerciales descriptivos, medios y atributos de producto.
--   * Clasificacion fiscal del producto (no calcula impuestos ni define tarifas).
--   * Listas de precios y precios por variante.
--   * Menus, secciones, articulos publicados y horarios de disponibilidad.
--   * Grupos/opciones de modificadores y sus recargos comerciales.
--   * Surtido disponible por sucursal (no controla existencias).
--
-- FUERA DE ALCANCE (PROPIETARIO ES OTRO MODULO):
--   * Cantidades, existencias, reservas, lotes, costos y movimientos: inventory.
--   * Proveedores, ordenes y recepciones de compra: procurement.
--   * Recetas, ingredientes, BOM y consumo de produccion: production.
--   * Comandas, tickets, preparacion y pantallas de cocina: kitchen.
--   * Pedidos, ventas, descuentos aplicados y devoluciones: sales.
--   * Cobros, autorizaciones y transacciones: payments.
--   * Tarifas/impuestos calculados sobre una transaccion y contabilidad: finance.
--   * Promociones, cupones y fidelizacion: customers/sales segun contrato.
--
-- LIMITES DE MODULOS:
--   * catalog solo tiene FK a platform.tenants y a tablas propias.
--   * company_id y branch_id son UUID de referencia logica a organization.
--     La existencia, pertenencia al tenant y estado se validan mediante el
--     contrato publico de organization en la capa application; no hay FK
--     fisicas cruzadas que acoplen schemas de negocio.
--   * created_by_id / updated_by_id son referencias logicas a identity.
--   * No consulta ni modifica tablas internas de otros modulos.
--
-- AISLAMIENTO:
--   * Todas las tablas de este schema son tenant-scoped.
--   * RLS usa SET LOCAL app.tenant_id en cada transaccion autenticada.
--   * El tenant se obtiene del contexto autenticado, nunca del body HTTP.
--   * El rol runtime no debe ser owner, superuser ni tener BYPASSRLS.
--
-- IMPORTANTE:
--   * Este script se ejecuta una sola vez en una base nueva despues de
--     platform y organization. No sustituye ni recrea los modulos anteriores.
--   * Tax categories solo clasifican el tratamiento fiscal del producto;
--     tasas y calculos efectivos pertenecen a finance/ventas.
--   * Price lists guardan precios de venta; no costos de compra ni costos
--     promedio/valoracion de inventario.
--   * Surtido por sucursal indica disponibilidad comercial, no stock real.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS catalog;

COMMENT ON SCHEMA catalog IS
'Catalogo comercial del POS: productos, variantes, unidades, clasificacion fiscal, precios, menus y modificadores. No administra existencias ni ventas.';

-- ---------------------------------------------------------------------------
-- 0. Funciones internas del modulo
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION catalog.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION catalog.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION catalog.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'No se permite cambiar tenant_id de un registro de catalog';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Unidades de medida
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.units_of_measure (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    unit_code           varchar(40) NOT NULL,
    name                varchar(100) NOT NULL,
    symbol              varchar(20) NOT NULL,
    dimension_code      varchar(40) NOT NULL,
    decimal_places      smallint NOT NULL DEFAULT 3 CHECK (decimal_places BETWEEN 0 AND 6),
    allows_fraction     boolean NOT NULL DEFAULT true,
    is_base_unit        boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uom_code_not_blank CHECK (btrim(unit_code) <> ''),
    CONSTRAINT uom_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT uom_symbol_not_blank CHECK (btrim(symbol) <> ''),
    CONSTRAINT uom_dimension_not_blank CHECK (btrim(dimension_code) <> ''),
    CONSTRAINT uom_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT uom_tenant_code_unique UNIQUE (tenant_id, unit_code)
);

CREATE INDEX ix_uom_tenant_active
    ON catalog.units_of_measure (tenant_id, is_active, dimension_code);

CREATE TABLE catalog.unit_conversions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    from_unit_id        uuid NOT NULL,
    to_unit_id          uuid NOT NULL,
    conversion_factor   numeric(20,10) NOT NULL CHECK (conversion_factor > 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT unit_conversion_not_identity CHECK (from_unit_id <> to_unit_id),
    CONSTRAINT unit_conversion_from_fk FOREIGN KEY (tenant_id, from_unit_id)
        REFERENCES catalog.units_of_measure (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT unit_conversion_to_fk FOREIGN KEY (tenant_id, to_unit_id)
        REFERENCES catalog.units_of_measure (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT unit_conversion_unique UNIQUE (tenant_id, from_unit_id, to_unit_id)
);

CREATE INDEX ix_unit_conversions_from
    ON catalog.unit_conversions (tenant_id, from_unit_id);

-- ---------------------------------------------------------------------------
-- 2. Categorias y etiquetas
-- ---------------------------------------------------------------------------
CREATE TABLE catalog.categories (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    parent_category_id  uuid,
    category_code       varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    category_kind       varchar(30) NOT NULL DEFAULT 'product'
                        CHECK (category_kind IN ('product', 'beverage', 'food', 'service', 'other')),
    image_object_key    text,
    sort_order          integer NOT NULL DEFAULT 0,
    is_visible_pos      boolean NOT NULL DEFAULT true,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT categories_code_not_blank CHECK (btrim(category_code) <> ''),
    CONSTRAINT categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT categories_not_own_parent CHECK (parent_category_id IS NULL OR parent_category_id <> id),
    CONSTRAINT categories_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT categories_parent_fk FOREIGN KEY (tenant_id, parent_category_id)
        REFERENCES catalog.categories (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_categories_code_per_tenant
    ON catalog.categories (tenant_id, lower(category_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_categories_parent_sort
    ON catalog.categories (tenant_id, parent_category_id, sort_order)
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.tags (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tag_code            varchar(50) NOT NULL,
    name                varchar(100) NOT NULL,
    color_hex           char(7),
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tags_code_not_blank CHECK (btrim(tag_code) <> ''),
    CONSTRAINT tags_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT tags_color_hex CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$'),
    CONSTRAINT tags_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT tags_code_unique UNIQUE (tenant_id, tag_code)
);

-- ---------------------------------------------------------------------------
-- 3. Clasificacion fiscal y alergenos (sin calculo de impuestos)
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.tax_categories (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    tax_category_code   varchar(50) NOT NULL,
    name                varchar(120) NOT NULL,
    treatment           varchar(30) NOT NULL
                        CHECK (treatment IN ('taxable', 'zero_rated', 'exempt', 'excluded', 'not_applicable', 'special')),
    external_tax_code   varchar(80),
    description         text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tax_categories_code_not_blank CHECK (btrim(tax_category_code) <> ''),
    CONSTRAINT tax_categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT tax_categories_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT tax_categories_code_unique UNIQUE (tenant_id, tax_category_code)
);

CREATE TABLE catalog.allergens (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    allergen_code       varchar(50) NOT NULL,
    name                varchar(120) NOT NULL,
    description         text,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT allergens_code_not_blank CHECK (btrim(allergen_code) <> ''),
    CONSTRAINT allergens_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT allergens_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT allergens_code_unique UNIQUE (tenant_id, allergen_code)
);

-- ---------------------------------------------------------------------------
-- 4. Productos y variantes
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.products (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid,
    brand_id            uuid,
    base_unit_id        uuid NOT NULL,
    tax_category_id     uuid,
    product_code        varchar(60) NOT NULL,
    name                varchar(200) NOT NULL,
    short_name          varchar(100),
    description         text,
    product_type        varchar(30) NOT NULL DEFAULT 'goods'
                        CHECK (product_type IN ('goods', 'prepared_food', 'beverage', 'service', 'combo', 'digital', 'other')),
    product_status      varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (product_status IN ('draft', 'active', 'inactive', 'archived')),
    is_sellable         boolean NOT NULL DEFAULT true,
    is_purchasable      boolean NOT NULL DEFAULT true,
    is_weighed_item     boolean NOT NULL DEFAULT false,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_id       uuid,
    updated_by_id       uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT products_code_not_blank CHECK (btrim(product_code) <> ''),
    CONSTRAINT products_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT products_metadata_object CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT products_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT products_tenant_code_unique UNIQUE (tenant_id, product_code),
    CONSTRAINT products_brand_fk FOREIGN KEY (tenant_id, brand_id)
        REFERENCES organization.brands (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT products_base_unit_fk FOREIGN KEY (tenant_id, base_unit_id)
        REFERENCES catalog.units_of_measure (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT products_tax_category_fk FOREIGN KEY (tenant_id, tax_category_id)
        REFERENCES catalog.tax_categories (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_products_tenant_status
    ON catalog.products (tenant_id, product_status, name)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_products_company
    ON catalog.products (tenant_id, company_id)
    WHERE company_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX ix_products_name_search
    ON catalog.products (tenant_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.product_categories (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    category_id         uuid NOT NULL,
    is_primary          boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, product_id, category_id),
    CONSTRAINT product_categories_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT product_categories_category_fk FOREIGN KEY (tenant_id, category_id)
        REFERENCES catalog.categories (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_product_primary_category
    ON catalog.product_categories (tenant_id, product_id)
    WHERE is_primary = true;

CREATE INDEX ix_product_categories_category
    ON catalog.product_categories (tenant_id, category_id, product_id);

CREATE TABLE catalog.product_tags (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    tag_id              uuid NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, product_id, tag_id),
    CONSTRAINT product_tags_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT product_tags_tag_fk FOREIGN KEY (tenant_id, tag_id)
        REFERENCES catalog.tags (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_product_tags_tag
    ON catalog.product_tags (tenant_id, tag_id, product_id);

CREATE TABLE catalog.product_variants (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    sale_unit_id        uuid NOT NULL,
    variant_code        varchar(60) NOT NULL,
    sku                 varchar(100) NOT NULL,
    name                varchar(180) NOT NULL,
    description         text,
    variant_attributes  jsonb NOT NULL DEFAULT '{}'::jsonb,
    unit_quantity       numeric(18,6) NOT NULL DEFAULT 1 CHECK (unit_quantity > 0),
    net_weight          numeric(18,6),
    gross_weight        numeric(18,6),
    is_default          boolean NOT NULL DEFAULT false,
    variant_status      varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (variant_status IN ('active', 'inactive', 'archived')),
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT variants_code_not_blank CHECK (btrim(variant_code) <> ''),
    CONSTRAINT variants_sku_not_blank CHECK (btrim(sku) <> ''),
    CONSTRAINT variants_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT variants_attributes_object CHECK (jsonb_typeof(variant_attributes) = 'object'),
    CONSTRAINT variants_weights_non_negative CHECK (
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0)
    ),
    CONSTRAINT variants_weight_order CHECK (
        net_weight IS NULL OR gross_weight IS NULL OR gross_weight >= net_weight
    ),
    CONSTRAINT variants_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT variants_tenant_product_id_id_unique UNIQUE (tenant_id, product_id, id),
    CONSTRAINT variants_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT variants_sale_unit_fk FOREIGN KEY (tenant_id, sale_unit_id)
        REFERENCES catalog.units_of_measure (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_variants_sku_per_tenant
    ON catalog.product_variants (tenant_id, lower(sku))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_variant_code_per_product
    ON catalog.product_variants (tenant_id, product_id, lower(variant_code))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_default_variant_per_product
    ON catalog.product_variants (tenant_id, product_id)
    WHERE is_default = true AND deleted_at IS NULL;

CREATE INDEX ix_variants_product_status
    ON catalog.product_variants (tenant_id, product_id, variant_status, sort_order)
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.variant_barcodes (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    variant_id          uuid NOT NULL,
    barcode             varchar(100) NOT NULL,
    barcode_type        varchar(20) NOT NULL DEFAULT 'other'
                        CHECK (barcode_type IN ('ean8', 'ean13', 'upc_a', 'upc_e', 'itf14', 'qr', 'internal', 'other')),
    is_primary          boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT variant_barcodes_not_blank CHECK (btrim(barcode) <> ''),
    CONSTRAINT variant_barcodes_variant_fk FOREIGN KEY (tenant_id, variant_id)
        REFERENCES catalog.product_variants (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT variant_barcodes_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_variant_barcode_per_tenant
    ON catalog.variant_barcodes (tenant_id, barcode);

CREATE UNIQUE INDEX uq_variant_primary_barcode
    ON catalog.variant_barcodes (tenant_id, variant_id)
    WHERE is_primary = true;

CREATE INDEX ix_variant_barcodes_variant
    ON catalog.variant_barcodes (tenant_id, variant_id);

-- ---------------------------------------------------------------------------
-- 5. Medios, alergenos e informacion nutricional
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.product_media (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    media_type          varchar(20) NOT NULL DEFAULT 'image'
                        CHECK (media_type IN ('image', 'video', 'document')),
    object_key          text NOT NULL,
    mime_type           varchar(120),
    file_size_bytes     bigint CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    alt_text            varchar(240),
    sort_order          integer NOT NULL DEFAULT 0,
    is_primary          boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT product_media_object_key_not_blank CHECK (btrim(object_key) <> ''),
    CONSTRAINT product_media_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT product_media_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_product_primary_media
    ON catalog.product_media (tenant_id, product_id)
    WHERE is_primary = true;

CREATE INDEX ix_product_media_order
    ON catalog.product_media (tenant_id, product_id, sort_order);

CREATE TABLE catalog.product_allergens (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    allergen_id         uuid NOT NULL,
    is_may_contain      boolean NOT NULL DEFAULT false,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, product_id, allergen_id),
    CONSTRAINT product_allergens_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT product_allergens_allergen_fk FOREIGN KEY (tenant_id, allergen_id)
        REFERENCES catalog.allergens (tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE catalog.variant_nutrition (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    variant_id          uuid NOT NULL,
    serving_quantity    numeric(18,6) NOT NULL CHECK (serving_quantity > 0),
    serving_unit_id     uuid NOT NULL,
    energy_kcal         numeric(12,3) CHECK (energy_kcal IS NULL OR energy_kcal >= 0),
    protein_g           numeric(12,3) CHECK (protein_g IS NULL OR protein_g >= 0),
    carbohydrates_g     numeric(12,3) CHECK (carbohydrates_g IS NULL OR carbohydrates_g >= 0),
    sugars_g            numeric(12,3) CHECK (sugars_g IS NULL OR sugars_g >= 0),
    total_fat_g         numeric(12,3) CHECK (total_fat_g IS NULL OR total_fat_g >= 0),
    saturated_fat_g     numeric(12,3) CHECK (saturated_fat_g IS NULL OR saturated_fat_g >= 0),
    fiber_g             numeric(12,3) CHECK (fiber_g IS NULL OR fiber_g >= 0),
    sodium_mg           numeric(12,3) CHECK (sodium_mg IS NULL OR sodium_mg >= 0),
    source_description text,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, variant_id),
    CONSTRAINT variant_nutrition_variant_fk FOREIGN KEY (tenant_id, variant_id)
        REFERENCES catalog.product_variants (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT variant_nutrition_unit_fk FOREIGN KEY (tenant_id, serving_unit_id)
        REFERENCES catalog.units_of_measure (tenant_id, id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- 6. Listas de precios y precios por variante
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.price_lists (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid,
    branch_id           uuid,
    price_list_code     varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    scope_type          varchar(20) NOT NULL DEFAULT 'tenant'
                        CHECK (scope_type IN ('tenant', 'company', 'branch')),
    currency            char(3) NOT NULL DEFAULT 'COP',
    price_list_status   varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (price_list_status IN ('draft', 'active', 'inactive', 'archived')),
    valid_from          timestamptz,
    valid_until         timestamptz,
    is_default          boolean NOT NULL DEFAULT false,
    created_by_id       uuid,
    updated_by_id       uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT price_lists_code_not_blank CHECK (btrim(price_list_code) <> ''),
    CONSTRAINT price_lists_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT price_lists_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT price_lists_scope_fields CHECK (
        (scope_type = 'tenant' AND company_id IS NULL AND branch_id IS NULL) OR
        (scope_type = 'company' AND company_id IS NOT NULL AND branch_id IS NULL) OR
        (scope_type = 'branch' AND branch_id IS NOT NULL)
    ),
    CONSTRAINT price_lists_dates CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    CONSTRAINT price_lists_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_price_list_code_per_tenant
    ON catalog.price_lists (tenant_id, lower(price_list_code))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_default_tenant_price_list
    ON catalog.price_lists (tenant_id, currency)
    WHERE is_default = true AND scope_type = 'tenant' AND deleted_at IS NULL;

CREATE INDEX ix_price_lists_scope_status
    ON catalog.price_lists (tenant_id, scope_type, company_id, branch_id, price_list_status)
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.price_list_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    price_list_id       uuid NOT NULL,
    variant_id          uuid NOT NULL,
    unit_price          numeric(18,4) NOT NULL CHECK (unit_price >= 0),
    compare_at_price    numeric(18,4) CHECK (compare_at_price IS NULL OR compare_at_price >= 0),
    minimum_quantity    numeric(18,6) NOT NULL DEFAULT 1 CHECK (minimum_quantity > 0),
    maximum_quantity    numeric(18,6),
    valid_from          timestamptz,
    valid_until         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT price_list_items_quantity_range CHECK (
        maximum_quantity IS NULL OR maximum_quantity > minimum_quantity
    ),
    CONSTRAINT price_list_items_dates CHECK (
        valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from
    ),
    CONSTRAINT price_list_items_price_list_fk FOREIGN KEY (tenant_id, price_list_id)
        REFERENCES catalog.price_lists (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT price_list_items_variant_fk FOREIGN KEY (tenant_id, variant_id)
        REFERENCES catalog.product_variants (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT price_list_items_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_price_list_item_quantity_break
    ON catalog.price_list_items (tenant_id, price_list_id, variant_id, minimum_quantity)
    WHERE valid_until IS NULL;

CREATE INDEX ix_price_list_items_lookup
    ON catalog.price_list_items (tenant_id, price_list_id, variant_id, valid_from, valid_until);

-- ---------------------------------------------------------------------------
-- 7. Menus, secciones, publicacion por sucursal y horarios
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.menus (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    company_id          uuid,
    default_price_list_id uuid,
    menu_code           varchar(50) NOT NULL,
    name                varchar(160) NOT NULL,
    description         text,
    menu_type           varchar(30) NOT NULL DEFAULT 'general'
                        CHECK (menu_type IN ('general', 'dine_in', 'takeaway', 'delivery', 'seasonal', 'other')),
    menu_status         varchar(20) NOT NULL DEFAULT 'draft'
                        CHECK (menu_status IN ('draft', 'published', 'inactive', 'archived')),
    locale              varchar(20) NOT NULL DEFAULT 'es-CO',
    timezone            varchar(80) NOT NULL DEFAULT 'America/Bogota',
    valid_from          timestamptz,
    valid_until         timestamptz,
    created_by_id       uuid,
    updated_by_id       uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT menus_code_not_blank CHECK (btrim(menu_code) <> ''),
    CONSTRAINT menus_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT menus_dates CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    CONSTRAINT menus_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT menus_default_price_list_fk FOREIGN KEY (tenant_id, default_price_list_id)
        REFERENCES catalog.price_lists (tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_menu_code_per_tenant
    ON catalog.menus (tenant_id, lower(menu_code))
    WHERE deleted_at IS NULL;

CREATE INDEX ix_menus_status_type
    ON catalog.menus (tenant_id, menu_status, menu_type)
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.menu_sections (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    menu_id             uuid NOT NULL,
    section_code        varchar(50) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    parent_section_id   uuid,
    image_object_key    text,
    sort_order          integer NOT NULL DEFAULT 0,
    is_visible           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT menu_sections_code_not_blank CHECK (btrim(section_code) <> ''),
    CONSTRAINT menu_sections_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT menu_sections_not_own_parent CHECK (parent_section_id IS NULL OR parent_section_id <> id),
    CONSTRAINT menu_sections_tenant_menu_id_unique UNIQUE (tenant_id, menu_id, id),
    CONSTRAINT menu_sections_menu_fk FOREIGN KEY (tenant_id, menu_id)
        REFERENCES catalog.menus (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT menu_sections_parent_fk FOREIGN KEY (tenant_id, menu_id, parent_section_id)
        REFERENCES catalog.menu_sections (tenant_id, menu_id, id) ON DELETE RESTRICT,
    CONSTRAINT menu_sections_code_unique UNIQUE (tenant_id, menu_id, section_code)
);

CREATE INDEX ix_menu_sections_sort
    ON catalog.menu_sections (tenant_id, menu_id, sort_order);

CREATE TABLE catalog.menu_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    menu_id             uuid NOT NULL,
    section_id          uuid NOT NULL,
    variant_id          uuid NOT NULL,
    display_name        varchar(180),
    description_override text,
    sort_order          integer NOT NULL DEFAULT 0,
    is_featured         boolean NOT NULL DEFAULT false,
    is_visible          boolean NOT NULL DEFAULT true,
    item_status         varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (item_status IN ('active', 'inactive', 'temporarily_unavailable')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT menu_items_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT menu_items_section_fk FOREIGN KEY (tenant_id, menu_id, section_id)
        REFERENCES catalog.menu_sections (tenant_id, menu_id, id) ON DELETE CASCADE,
    CONSTRAINT menu_items_variant_fk FOREIGN KEY (tenant_id, variant_id)
        REFERENCES catalog.product_variants (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT menu_items_unique_in_section UNIQUE (tenant_id, menu_id, section_id, variant_id)
);

CREATE INDEX ix_menu_items_menu_order
    ON catalog.menu_items (tenant_id, menu_id, section_id, sort_order)
    WHERE is_visible = true;

CREATE TABLE catalog.menu_branch_assignments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    menu_id             uuid NOT NULL,
    branch_id           uuid NOT NULL,
    assignment_status   varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (assignment_status IN ('active', 'inactive', 'scheduled')),
    valid_from          timestamptz,
    valid_until         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT menu_branch_dates CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    CONSTRAINT menu_branch_menu_fk FOREIGN KEY (tenant_id, menu_id)
        REFERENCES catalog.menus (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT menu_branch_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT menu_branch_unique UNIQUE (tenant_id, menu_id, branch_id)
);

CREATE INDEX ix_menu_branch_branch
    ON catalog.menu_branch_assignments (tenant_id, branch_id, assignment_status);

CREATE TABLE catalog.menu_schedule_rules (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    menu_id             uuid NOT NULL,
    branch_id           uuid,
    weekday_iso         smallint NOT NULL CHECK (weekday_iso BETWEEN 1 AND 7),
    start_time          time NOT NULL,
    end_time            time NOT NULL,
    effective_from      date,
    effective_until     date,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT menu_schedule_time_range CHECK (end_time > start_time),
    CONSTRAINT menu_schedule_date_range CHECK (
        effective_until IS NULL OR effective_from IS NULL OR effective_until >= effective_from
    ),
    CONSTRAINT menu_schedule_menu_fk FOREIGN KEY (tenant_id, menu_id)
        REFERENCES catalog.menus (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT menu_schedule_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE INDEX ix_menu_schedule_lookup
    ON catalog.menu_schedule_rules (tenant_id, menu_id, branch_id, weekday_iso)
    WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 8. Grupos y opciones de modificadores (personalizaciones comerciales)
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.modifier_groups (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    group_code          varchar(60) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    selection_min       smallint NOT NULL DEFAULT 0 CHECK (selection_min >= 0),
    selection_max       smallint NOT NULL DEFAULT 1 CHECK (selection_max >= 1),
    is_required         boolean NOT NULL DEFAULT false,
    allow_multiple      boolean NOT NULL DEFAULT false,
    display_type        varchar(20) NOT NULL DEFAULT 'list'
                        CHECK (display_type IN ('list', 'radio', 'checkbox', 'quantity', 'other')),
    group_status        varchar(20) NOT NULL DEFAULT 'active'
                        CHECK (group_status IN ('active', 'inactive', 'archived')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT modifier_groups_selection_range CHECK (selection_max >= selection_min),
    CONSTRAINT modifier_groups_required_min CHECK (NOT is_required OR selection_min >= 1),
    CONSTRAINT modifier_groups_code_not_blank CHECK (btrim(group_code) <> ''),
    CONSTRAINT modifier_groups_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT modifier_groups_tenant_id_id_unique UNIQUE (tenant_id, id)
);

CREATE UNIQUE INDEX uq_modifier_group_code
    ON catalog.modifier_groups (tenant_id, lower(group_code))
    WHERE deleted_at IS NULL;

CREATE TABLE catalog.modifier_options (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    modifier_group_id   uuid NOT NULL,
    option_code         varchar(60) NOT NULL,
    name                varchar(140) NOT NULL,
    description         text,
    base_price_delta    numeric(18,4) NOT NULL DEFAULT 0 CHECK (base_price_delta >= 0),
    is_default          boolean NOT NULL DEFAULT false,
    is_active           boolean NOT NULL DEFAULT true,
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT modifier_options_code_not_blank CHECK (btrim(option_code) <> ''),
    CONSTRAINT modifier_options_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT modifier_options_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT modifier_options_group_fk FOREIGN KEY (tenant_id, modifier_group_id)
        REFERENCES catalog.modifier_groups (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT modifier_options_code_unique UNIQUE (tenant_id, modifier_group_id, option_code)
);

CREATE UNIQUE INDEX uq_modifier_default_per_group
    ON catalog.modifier_options (tenant_id, modifier_group_id)
    WHERE is_default = true;

CREATE INDEX ix_modifier_options_group_sort
    ON catalog.modifier_options (tenant_id, modifier_group_id, sort_order)
    WHERE is_active = true;

CREATE TABLE catalog.product_modifier_groups (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    product_id          uuid NOT NULL,
    modifier_group_id   uuid NOT NULL,
    selection_min_override smallint,
    selection_max_override smallint,
    is_required_override boolean,
    sort_order          integer NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, product_id, modifier_group_id),
    CONSTRAINT product_modifier_min_nonnegative CHECK (
        selection_min_override IS NULL OR selection_min_override >= 0
    ),
    CONSTRAINT product_modifier_max_positive CHECK (
        selection_max_override IS NULL OR selection_max_override >= 1
    ),
    CONSTRAINT product_modifier_selection_valid CHECK (
        selection_min_override IS NULL OR selection_max_override IS NULL OR
        selection_max_override >= selection_min_override
    ),
    CONSTRAINT product_modifier_product_fk FOREIGN KEY (tenant_id, product_id)
        REFERENCES catalog.products (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT product_modifier_group_fk FOREIGN KEY (tenant_id, modifier_group_id)
        REFERENCES catalog.modifier_groups (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_product_modifier_groups_group
    ON catalog.product_modifier_groups (tenant_id, modifier_group_id, product_id);

CREATE TABLE catalog.price_list_modifier_prices (
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    price_list_id       uuid NOT NULL,
    modifier_option_id  uuid NOT NULL,
    price_delta         numeric(18,4) NOT NULL CHECK (price_delta >= 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, price_list_id, modifier_option_id),
    CONSTRAINT price_list_modifier_price_list_fk FOREIGN KEY (tenant_id, price_list_id)
        REFERENCES catalog.price_lists (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT price_list_modifier_option_fk FOREIGN KEY (tenant_id, modifier_option_id)
        REFERENCES catalog.modifier_options (tenant_id, id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 9. Surtido comercial por sucursal (no es inventario)
-- ---------------------------------------------------------------------------

CREATE TABLE catalog.branch_product_assortments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES platform.tenants(id) ON DELETE RESTRICT,
    branch_id           uuid NOT NULL,
    variant_id          uuid NOT NULL,
    assortment_status   varchar(25) NOT NULL DEFAULT 'available'
                        CHECK (assortment_status IN ('available', 'hidden', 'temporarily_unavailable', 'scheduled')),
    valid_from          timestamptz,
    valid_until         timestamptz,
    availability_note   varchar(240),
    created_by_id       uuid,
    updated_by_id       uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT branch_assortment_dates CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    CONSTRAINT branch_assortment_variant_fk FOREIGN KEY (tenant_id, variant_id)
        REFERENCES catalog.product_variants (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT branch_assortment_tenant_id_id_unique UNIQUE (tenant_id, id),
    CONSTRAINT branch_assortment_unique UNIQUE (tenant_id, branch_id, variant_id)
);

CREATE INDEX ix_branch_assortments_variant_status
    ON catalog.branch_product_assortments (tenant_id, variant_id, assortment_status);

CREATE INDEX ix_branch_assortments_branch_status
    ON catalog.branch_product_assortments (tenant_id, branch_id, assortment_status);

-- ---------------------------------------------------------------------------
-- 10. Triggers updated_at y proteccion tenant_id
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    tbl text;
    updated_tables text[] := ARRAY[
        'units_of_measure', 'unit_conversions', 'brands', 'categories',
        'tax_categories', 'products', 'product_variants', 'variant_nutrition',
        'price_lists', 'price_list_items', 'menus', 'menu_sections',
        'menu_items', 'menu_branch_assignments', 'modifier_groups',
        'modifier_options', 'price_list_modifier_prices',
        'branch_product_assortments'
    ];
    tenant_tables text[] := ARRAY[
        'units_of_measure', 'unit_conversions', 'brands', 'categories', 'tags',
        'tax_categories', 'allergens', 'products', 'product_categories',
        'product_tags', 'product_variants', 'variant_barcodes', 'product_media',
        'product_allergens', 'variant_nutrition', 'price_lists', 'price_list_items',
        'menus', 'menu_sections', 'menu_items', 'menu_branch_assignments',
        'menu_schedule_rules', 'modifier_groups', 'modifier_options',
        'product_modifier_groups', 'price_list_modifier_prices',
        'branch_product_assortments'
    ];
BEGIN
    FOREACH tbl IN ARRAY updated_tables LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON catalog.%I FOR EACH ROW EXECUTE FUNCTION catalog.set_updated_at()',
            'trg_' || tbl || '_updated_at', tbl
        );
    END LOOP;

    FOREACH tbl IN ARRAY tenant_tables LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON catalog.%I FOR EACH ROW EXECUTE FUNCTION catalog.prevent_tenant_change()',
            'trg_' || tbl || '_prevent_tenant_change', tbl
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. Row Level Security: todas las tablas pertenecen a un tenant
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    tbl text;
    tenant_tables text[] := ARRAY[
        'units_of_measure', 'unit_conversions', 'brands', 'categories', 'tags',
        'tax_categories', 'allergens', 'products', 'product_categories',
        'product_tags', 'product_variants', 'variant_barcodes', 'product_media',
        'product_allergens', 'variant_nutrition', 'price_lists', 'price_list_items',
        'menus', 'menu_sections', 'menu_items', 'menu_branch_assignments',
        'menu_schedule_rules', 'modifier_groups', 'modifier_options',
        'product_modifier_groups', 'price_list_modifier_prices',
        'branch_product_assortments'
    ];
BEGIN
    FOREACH tbl IN ARRAY tenant_tables LOOP
        EXECUTE format('ALTER TABLE catalog.%I ENABLE ROW LEVEL SECURITY', tbl);
        EXECUTE format('ALTER TABLE catalog.%I FORCE ROW LEVEL SECURITY', tbl);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON catalog.%I USING (tenant_id = catalog.current_tenant_id()) WITH CHECK (tenant_id = catalog.current_tenant_id())',
            tbl
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Inicializacion idempotente del catalogo para cada tenant
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION catalog.initialize_tenant_catalog(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tenant_id IS NULL OR catalog.current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'El tenant solicitado debe coincidir con app.tenant_id autenticado';
    END IF;

    INSERT INTO catalog.units_of_measure
        (tenant_id, unit_code, name, symbol, dimension_code, decimal_places, allows_fraction, is_base_unit)
    VALUES
        (p_tenant_id, 'unit', 'Unidad', 'und', 'count', 0, false, true),
        (p_tenant_id, 'kg', 'Kilogramo', 'kg', 'mass', 3, true, true),
        (p_tenant_id, 'g', 'Gramo', 'g', 'mass', 3, true, false),
        (p_tenant_id, 'l', 'Litro', 'L', 'volume', 3, true, true),
        (p_tenant_id, 'ml', 'Mililitro', 'ml', 'volume', 3, true, false),
        (p_tenant_id, 'portion', 'Porcion', 'porc', 'serving', 3, true, true),
        (p_tenant_id, 'hour', 'Hora', 'h', 'time', 2, true, true)
    ON CONFLICT (tenant_id, unit_code) DO NOTHING;

    INSERT INTO catalog.unit_conversions
        (tenant_id, from_unit_id, to_unit_id, conversion_factor)
    SELECT p_tenant_id, src.id, dst.id, conv.factor
    FROM (VALUES
        ('kg', 'g', 1000::numeric),
        ('g', 'kg', 0.001::numeric),
        ('l', 'ml', 1000::numeric),
        ('ml', 'l', 0.001::numeric)
    ) AS conv(from_code, to_code, factor)
    JOIN catalog.units_of_measure src
      ON src.tenant_id = p_tenant_id AND src.unit_code = conv.from_code
    JOIN catalog.units_of_measure dst
      ON dst.tenant_id = p_tenant_id AND dst.unit_code = conv.to_code
    ON CONFLICT (tenant_id, from_unit_id, to_unit_id) DO NOTHING;

    INSERT INTO catalog.tax_categories
        (tenant_id, tax_category_code, name, treatment, description)
    VALUES
        (p_tenant_id, 'TAXABLE', 'Gravado', 'taxable', 'Requiere una regla tributaria vigente en el modulo fiscal.'),
        (p_tenant_id, 'ZERO_RATED', 'Tarifa cero', 'zero_rated', 'Clasificacion fiscal de tarifa cero; no define la tasa.'),
        (p_tenant_id, 'EXEMPT', 'Exento', 'exempt', 'Clasificacion fiscal exenta; verificar normativa aplicable.'),
        (p_tenant_id, 'EXCLUDED', 'Excluido', 'excluded', 'Clasificacion fiscal excluida; verificar normativa aplicable.'),
        (p_tenant_id, 'NOT_APPLICABLE', 'No aplica', 'not_applicable', 'Producto o servicio sin clasificacion tributaria aplicable.')
    ON CONFLICT (tenant_id, tax_category_code) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Comentarios de propiedad e integracion
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN catalog.products.company_id IS
'UUID logico de organization.companies. La existencia y pertenencia al tenant se valida llamando al contrato publico de organization.';

COMMENT ON COLUMN catalog.price_lists.company_id IS
'UUID logico de organization.companies para listas con alcance company; validacion mediante el modulo organization.';

COMMENT ON COLUMN catalog.price_lists.branch_id IS
'UUID logico de organization.branches para listas con alcance branch; validacion mediante el modulo organization.';

COMMENT ON COLUMN catalog.menu_branch_assignments.branch_id IS
'UUID logico de organization.branches. La asignacion solo se acepta si la sucursal pertenece al tenant y esta habilitada.';

COMMENT ON COLUMN catalog.menu_schedule_rules.branch_id IS
'UUID logico opcional de organization.branches. NULL significa que la regla aplica a todas las sucursales asignadas al menu.';

COMMENT ON COLUMN catalog.branch_product_assortments.branch_id IS
'UUID logico de organization.branches. Esta tabla controla el surtido comercial y no representa disponibilidad de existencias.';

COMMENT ON COLUMN catalog.products.tax_category_id IS
'Clasificacion fiscal del producto; no contiene una tasa ni sustituye el calculo tributario de finance/sales.';

COMMENT ON COLUMN catalog.products.brand_id IS
'Marca comercial de ORGANIZATION. CATALOG no crea ni administra marcas.';

COMMENT ON COLUMN catalog.product_variants.variant_attributes IS
'Atributos descriptivos de la variante en JSONB (por ejemplo talla, sabor o presentacion). No guardar aqui saldos ni costos de inventario.';

COMMENT ON TABLE catalog.price_list_items IS
'Precio comercial de venta por variante y lista. No debe utilizarse para costos de compra, costo promedio ni valoracion de inventario.';

COMMENT ON TABLE catalog.modifier_groups IS
'Grupos de personalizacion comercial de productos (por ejemplo tamano, acompanamiento o extras). La ejecucion/preparacion pertenece a kitchen/production.';

COMMENT ON TABLE catalog.branch_product_assortments IS
'Indica si una variante forma parte del surtido comercial de una sucursal. La disponibilidad fisica en stock pertenece a inventory.';

COMMENT ON SCHEMA catalog IS
'El modulo SaaS asociado en platform.modules utiliza el codigo product_catalog; el crate de Rust y el schema SQL se denominan catalog.';

COMMIT;

-- ============================================================================
-- NOTAS OPERATIVAS
-- ============================================================================
-- En cada transaccion tenant-scoped, el backend debe establecer el tenant
-- autenticado dentro de la transaccion:
--
-- BEGIN;
-- SET LOCAL app.tenant_id = 'UUID_DEL_TENANT_AUTORIZADO';
-- SELECT id, product_code, name
-- FROM catalog.products
-- WHERE product_status = 'active' AND deleted_at IS NULL;
-- COMMIT;
--
-- No permitir que el cliente HTTP escoja libremente app.tenant_id.
-- Al aprovisionar un tenant, inicializar sus unidades y clasificaciones fiscales:
--   BEGIN;
--   SET LOCAL app.tenant_id = 'UUID_DEL_TENANT_AUTORIZADO';
--   SELECT catalog.initialize_tenant_catalog('UUID_DEL_TENANT_AUTORIZADO');
--   COMMIT;
-- La aplicacion debe validar company_id/branch_id con organization y verificar
-- permisos con identity antes de escribir o exponer registros.
-- Codigos de permisos que deben registrarse en identity.permissions (el
-- modulo identity es propietario de ese catalogo):
--   catalog.products.read / catalog.products.create / catalog.products.update
--   catalog.products.archive / catalog.variants.manage / catalog.categories.manage
--   catalog.prices.read / catalog.prices.manage / catalog.menus.manage
--   catalog.modifiers.manage / catalog.assortments.manage
-- Los ciclos de horarios que cruzan medianoche se representan con dos reglas.
-- Los precios con periodos solapados deben validarse en application; no se
-- permiten duplicados de precio abierto para la misma cantidad minima/lista.
-- ============================================================================
