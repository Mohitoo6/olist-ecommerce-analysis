-- =============================================================================
-- 01_schema_setup.sql
-- Business purpose:
--   Create the staging schema for the Olist Brazilian e-commerce dataset.
--   Tables mirror the source CSVs as faithfully as possible so we can reload
--   from raw files at any time. Cleaning, derived tables, and analysis views
--   live in 02_data_cleaning.sql onwards. Keeping load and transform separate
--   makes the pipeline auditable for stakeholders.
--
-- Design choices:
--   * Foreign keys are NOT enforced on the staging tables. Source data has
--     legitimate orphans (e.g., 775 orders missing review rows, sellers in
--     order_items with no row in sellers). Enforcing FKs at load time would
--     reject otherwise-valid data and obscure the data quality story.
--     We surface integrity issues explicitly in 02_data_cleaning.sql instead.
--   * order_reviews has no enforced PK because review_id is non-unique
--     (~800 collisions in source) — these are real duplicates we want to keep
--     and analyse, not throw away.
--   * Zip codes stored as TEXT, not INT. Brazilian CEPs have leading zeros
--     and treating them numerically corrupts the join key.
-- =============================================================================

DROP TABLE IF EXISTS order_reviews        CASCADE;
DROP TABLE IF EXISTS order_payments       CASCADE;
DROP TABLE IF EXISTS order_items          CASCADE;
DROP TABLE IF EXISTS orders               CASCADE;
DROP TABLE IF EXISTS customers            CASCADE;
DROP TABLE IF EXISTS sellers              CASCADE;
DROP TABLE IF EXISTS products             CASCADE;
DROP TABLE IF EXISTS category_translation CASCADE;
DROP TABLE IF EXISTS geolocation          CASCADE;

-- -----------------------------------------------------------------------------
-- customers
-- One row per customer-per-order. customer_id is a per-order surrogate;
-- customer_unique_id identifies the actual person across orders. Junior
-- analysts who use customer_id for retention will report a 0% repeat rate.
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,
    customer_unique_id       TEXT NOT NULL,
    customer_zip_code_prefix TEXT NOT NULL,
    customer_city            TEXT,
    customer_state           CHAR(2)
);

CREATE INDEX idx_customers_unique_id ON customers (customer_unique_id);
CREATE INDEX idx_customers_zip       ON customers (customer_zip_code_prefix);

-- -----------------------------------------------------------------------------
-- sellers
-- -----------------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT NOT NULL,
    seller_city            TEXT,
    seller_state           CHAR(2)
);

CREATE INDEX idx_sellers_zip ON sellers (seller_zip_code_prefix);

-- -----------------------------------------------------------------------------
-- products
-- product_category_name uses the original Portuguese; English translation is
-- joined in via category_translation. ~610 products have a NULL category and
-- are bucketed as 'unknown' in the cleaning step.
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        INT,    -- typo preserved from source
    product_description_lenght INT,    -- typo preserved from source
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE INDEX idx_products_category ON products (product_category_name);

-- -----------------------------------------------------------------------------
-- category_translation
-- Source has 71 rows but the products table contains 73 distinct categories.
-- Two categories are untranslated ('pc_gamer' and a long Portuguese kitchen
-- category) — we add manual translations in cleaning.
-- -----------------------------------------------------------------------------
CREATE TABLE category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

-- -----------------------------------------------------------------------------
-- orders
-- The lifecycle timestamps tell the operational story:
--   purchase  → approved  → carrier  → delivered  vs. estimated
-- estimated_delivery_date is what the customer was promised at checkout.
-- 2,965 rows have NULL delivered_customer_date because they were cancelled
-- or are still in transit at snapshot time.
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL,
    order_status                  TEXT NOT NULL,
    order_purchase_timestamp      TIMESTAMP NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL
);

CREATE INDEX idx_orders_customer  ON orders (customer_id);
CREATE INDEX idx_orders_purchase  ON orders (order_purchase_timestamp);
CREATE INDEX idx_orders_status    ON orders (order_status);

-- -----------------------------------------------------------------------------
-- order_items
-- One row per item-line. Multi-item orders are common (~11% of orders).
-- 1.3% of orders have items from multiple sellers, which makes
-- "delivery time" ambiguous at the order grain (we use order-level dates).
-- -----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_id            TEXT NOT NULL,
    order_item_id       INT  NOT NULL,
    product_id          TEXT NOT NULL,
    seller_id           TEXT NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price               NUMERIC(10,2) NOT NULL,
    freight_value       NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE INDEX idx_order_items_seller  ON order_items (seller_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);

-- -----------------------------------------------------------------------------
-- order_payments
-- Composite payments are common: a customer can split one order across
-- voucher + credit_card, producing multiple rows. ~3% of orders have
-- multiple payment rows; 3 records have payment_type = 'not_defined'.
-- -----------------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id              TEXT NOT NULL,
    payment_sequential    INT  NOT NULL,
    payment_type          TEXT NOT NULL,
    payment_installments  INT  NOT NULL,
    payment_value         NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- -----------------------------------------------------------------------------
-- order_reviews
-- review_id is NOT unique in source data (re-reviews and duplicates exist).
-- We keep all rows and rely on (order_id, review_creation_date) for grain
-- when needed. review_comment_message is NULL for ~59% of reviews.
-- -----------------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id                TEXT NOT NULL,
    order_id                 TEXT NOT NULL,
    review_score             INT  NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP NOT NULL,
    review_answer_timestamp  TIMESTAMP NOT NULL
);

CREATE INDEX idx_reviews_order ON order_reviews (order_id);
CREATE INDEX idx_reviews_score ON order_reviews (review_score);

-- -----------------------------------------------------------------------------
-- geolocation
-- ~1M rows for ~19K zip prefixes (multiple lat/lng readings per zip).
-- We aggregate to a single centroid per zip in the cleaning step before
-- joining to customers/sellers; raw rows are kept here for traceability.
-- -----------------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             NUMERIC(10,7),
    geolocation_lng             NUMERIC(10,7),
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);

CREATE INDEX idx_geolocation_zip ON geolocation (geolocation_zip_code_prefix);

-- -----------------------------------------------------------------------------
-- Comments on tables — visible via \d+ and useful for downstream tools (dbt,
-- BI catalogs). Stakeholders skimming the schema get one-line context.
-- -----------------------------------------------------------------------------
COMMENT ON TABLE customers            IS 'One row per customer-per-order. Use customer_unique_id for repeat-purchase analysis.';
COMMENT ON TABLE sellers              IS 'Marketplace sellers. ~3K rows; top 100 generate 45% of GMV.';
COMMENT ON TABLE products             IS 'Product catalogue. ~610 rows have NULL category — bucketed as unknown downstream.';
COMMENT ON TABLE category_translation IS 'PT→EN category lookup. Source covers 71 of 73 categories; 2 manual additions in cleaning.';
COMMENT ON TABLE orders               IS 'One row per order. 2.9K orders never delivered (cancelled / in-transit at snapshot).';
COMMENT ON TABLE order_items          IS 'Item-level grain. 1.3% of orders span multiple sellers.';
COMMENT ON TABLE order_payments       IS 'Payment grain — orders may split across multiple payment methods.';
COMMENT ON TABLE order_reviews        IS '1-5 stars + optional comment. review_id NOT unique in source.';
COMMENT ON TABLE geolocation          IS 'Raw lat/lng per zip prefix. Aggregate to centroid before joining.';
