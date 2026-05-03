-- =============================================================================
-- 02_data_cleaning.sql
-- Business purpose:
--   Stage cleaned, analysis-ready views on top of raw tables. Decisions made
--   here are documented inline so any reviewer can challenge them. Cleaning
--   is implemented as VIEWs (not new tables) so the staging layer remains the
--   single source of truth and re-running is free.
--
-- Decisions in this file:
--   1. Date-tail truncation. The raw orders span 2016-09 to 2018-10 but
--      only 2017-01 → 2018-08 has meaningful volume (>= ~800 orders/mo).
--      Sept 2016 (4 orders) and Sept-Oct 2018 (20 orders combined) would
--      visually destroy any time-series chart, so we expose a flag.
--   2. NULL-category bucketing. 610 products carry a NULL category. We map
--      these to 'unknown' rather than dropping them — they account for
--      ~R$140K of GMV and dropping silently misleads stakeholders.
--   3. Untranslated categories. The translation table covers 71 of 73
--      product categories. We add manual translations for 'pc_gamer' and
--      'portateis_cozinha_e_preparadores_de_alimentos' so English reports
--      are complete.
--   4. Geolocation centroid. Raw geolocation has ~1M rows for ~19K zips
--      (multiple readings per zip). We aggregate to a single mean lat/lng
--      per zip prefix for clean joins.
--   5. Order-grain payments. Some orders span multiple payment rows
--      (vouchers + card splits). For order-level analysis we sum
--      payment_value and take the dominant payment_type.
--   6. 'Pure' delivered orders. Many analyses (delivery time, satisfaction)
--      should only consider orders that actually reached the customer.
--      We expose a clean view that filters status = 'delivered' and has
--      a non-null delivered_customer_date.
-- =============================================================================

\set ON_ERROR_STOP on

DROP VIEW IF EXISTS v_order_satisfaction CASCADE;
DROP VIEW IF EXISTS v_order_lifecycle    CASCADE;
DROP VIEW IF EXISTS v_orders_clean       CASCADE;
DROP VIEW IF EXISTS v_payments_by_order  CASCADE;
DROP VIEW IF EXISTS v_products_clean     CASCADE;
DROP VIEW IF EXISTS v_geolocation_clean  CASCADE;

-- -----------------------------------------------------------------------------
-- Patch the translation table for the 2 untranslated categories.
-- Done idempotently with INSERT ... ON CONFLICT so re-running is safe.
-- -----------------------------------------------------------------------------
INSERT INTO category_translation (product_category_name, product_category_name_english) VALUES
    ('pc_gamer',                                          'pc_gamer'),
    ('portateis_cozinha_e_preparadores_de_alimentos',     'kitchen_portables_and_food_preparers')
ON CONFLICT (product_category_name) DO NOTHING;

-- -----------------------------------------------------------------------------
-- v_products_clean
-- Adds 'unknown' bucket for the 610 NULL-category rows and joins English name.
-- -----------------------------------------------------------------------------
CREATE VIEW v_products_clean AS
SELECT
    p.product_id,
    COALESCE(p.product_category_name, 'unknown')               AS category_pt,
    COALESCE(t.product_category_name_english, 'unknown')       AS category_en,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.product_photos_qty,
    -- Volume in cm^3 — used as a proxy for shipping difficulty.
    (p.product_length_cm::numeric * p.product_height_cm * p.product_width_cm) AS product_volume_cm3
FROM products p
LEFT JOIN category_translation t USING (product_category_name);

COMMENT ON VIEW v_products_clean IS
    'Products with NULL category mapped to ''unknown'' and PT→EN translation joined.';

-- -----------------------------------------------------------------------------
-- v_geolocation_clean
-- Mean centroid per zip prefix. Some zips have an obvious "majority city"
-- and one or two stray readings; mean lat/lng is robust enough for the
-- state/region-level analysis this project does (we aren't routing trucks).
-- -----------------------------------------------------------------------------
CREATE VIEW v_geolocation_clean AS
SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    AVG(geolocation_lat)        AS lat,
    AVG(geolocation_lng)        AS lng,
    -- MODE() picks the most common city/state for the zip — safer than MAX().
    MODE() WITHIN GROUP (ORDER BY geolocation_city)  AS city,
    MODE() WITHIN GROUP (ORDER BY geolocation_state) AS state
FROM geolocation
GROUP BY geolocation_zip_code_prefix;

COMMENT ON VIEW v_geolocation_clean IS
    'One row per zip prefix; lat/lng = mean of all source readings, city/state = mode.';

-- -----------------------------------------------------------------------------
-- v_payments_by_order
-- Collapses multi-payment orders to one row. dominant_payment_type is the
-- type with the largest payment_value (e.g., card-with-voucher gets labelled
-- credit_card, which matches how Olist's finance team reports it).
-- -----------------------------------------------------------------------------
CREATE VIEW v_payments_by_order AS
WITH ranked AS (
    SELECT
        order_id,
        payment_type,
        payment_value,
        payment_installments,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS rn
    FROM order_payments
    WHERE payment_type <> 'not_defined'   -- 3 rows; meaningless to keep
)
SELECT
    p.order_id,
    SUM(p.payment_value)                    AS total_payment_value,
    MAX(p.payment_installments)             AS max_installments,
    COUNT(*)                                AS payment_record_count,
    MAX(r.payment_type) FILTER (WHERE r.rn = 1) AS dominant_payment_type
FROM order_payments p
JOIN ranked r USING (order_id, payment_type)
WHERE p.payment_type <> 'not_defined'
GROUP BY p.order_id;

COMMENT ON VIEW v_payments_by_order IS
    'One row per order; sums payment_value across split payments and picks dominant method.';

-- -----------------------------------------------------------------------------
-- v_orders_clean
-- Adds the time-window flag and pre-computes derived date columns used by
-- almost every downstream analysis: delivery_days, delay_days, on_time flag.
-- We compute these once here rather than recomputing in every analysis file.
-- -----------------------------------------------------------------------------
CREATE VIEW v_orders_clean AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Calendar buckets used by the trend / cohort analyses.
    DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
    DATE_TRUNC('week',  o.order_purchase_timestamp)::date AS purchase_week,

    -- Delivery time (only meaningful for delivered orders).
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0
        AS delivery_days,
    EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp)) / 86400.0
        AS estimated_days,
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) / 86400.0
        AS delay_days,

    -- Did Olist meet the date promised at checkout?
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN TRUE
        ELSE FALSE
    END AS delivered_on_time,

    -- Time-window flag. True for the 20 months of meaningful volume (>=800/mo).
    CASE
        WHEN o.order_purchase_timestamp >= '2017-01-01'
         AND o.order_purchase_timestamp <  '2018-09-01'
        THEN TRUE ELSE FALSE
    END AS in_analysis_window
FROM orders o
JOIN customers c USING (customer_id);

COMMENT ON VIEW v_orders_clean IS
    'Orders enriched with customer_unique_id, derived delivery metrics, and analysis-window flag.';

-- -----------------------------------------------------------------------------
-- v_order_lifecycle
-- Order grain with one canonical row including item count, gmv, freight,
-- and payment summary. Avoids re-deriving these in every analysis.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_lifecycle AS
SELECT
    oc.*,
    COALESCE(item_agg.item_count,     0) AS item_count,
    COALESCE(item_agg.distinct_sellers, 0) AS distinct_sellers,
    COALESCE(item_agg.gmv,            0) AS gmv,            -- sum of item prices
    COALESCE(item_agg.freight,        0) AS freight,        -- sum of freight values
    pay.total_payment_value,
    pay.dominant_payment_type,
    pay.max_installments
FROM v_orders_clean oc
LEFT JOIN (
    SELECT
        order_id,
        COUNT(*)                  AS item_count,
        COUNT(DISTINCT seller_id) AS distinct_sellers,
        SUM(price)                AS gmv,
        SUM(freight_value)        AS freight
    FROM order_items
    GROUP BY order_id
) item_agg USING (order_id)
LEFT JOIN v_payments_by_order pay USING (order_id);

COMMENT ON VIEW v_order_lifecycle IS
    'One canonical row per order with item, freight, and payment aggregates.';

-- -----------------------------------------------------------------------------
-- v_order_satisfaction
-- Joins reviews onto the cleaned order view. Where an order has multiple
-- reviews (rare — ~775 orders), we keep the most recent score, since later
-- reviews tend to reflect the resolved customer experience.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_satisfaction AS
WITH latest_review AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score,
        review_creation_date,
        review_answer_timestamp,
        EXTRACT(EPOCH FROM (review_answer_timestamp - review_creation_date)) / 86400.0
            AS review_response_days
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC
)
SELECT
    ol.*,
    lr.review_score,
    lr.review_creation_date,
    lr.review_response_days
FROM v_order_lifecycle ol
LEFT JOIN latest_review lr USING (order_id);

COMMENT ON VIEW v_order_satisfaction IS
    'Order lifecycle + latest review score. Use this for the delivery-vs-satisfaction analysis.';

-- -----------------------------------------------------------------------------
-- Sanity checks — print the headline numbers we'll quote in the README.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Sanity checks after cleaning ==='

\echo ''
\echo '-- Row counts in cleaned views --'
SELECT 'v_orders_clean'        AS view, COUNT(*) FROM v_orders_clean
UNION ALL SELECT 'v_order_lifecycle',    COUNT(*) FROM v_order_lifecycle
UNION ALL SELECT 'v_order_satisfaction', COUNT(*) FROM v_order_satisfaction
UNION ALL SELECT 'v_products_clean',     COUNT(*) FROM v_products_clean
UNION ALL SELECT 'v_geolocation_clean',  COUNT(*) FROM v_geolocation_clean
UNION ALL SELECT 'v_payments_by_order',  COUNT(*) FROM v_payments_by_order;

\echo ''
\echo '-- In-window orders (2017-01 to 2018-08): expect ~98K --'
SELECT
    COUNT(*) FILTER (WHERE in_analysis_window) AS in_window_orders,
    COUNT(*) FILTER (WHERE NOT in_analysis_window) AS out_window_orders
FROM v_orders_clean;

\echo ''
\echo '-- Delivery on-time rate (delivered orders only): expect ~93% --'
SELECT
    COUNT(*) FILTER (WHERE delivered_on_time)                         AS on_time,
    COUNT(*) FILTER (WHERE NOT delivered_on_time)                     AS late,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE delivered_on_time)
        / NULLIF(COUNT(*) FILTER (WHERE delivered_on_time IS NOT NULL), 0),
        2
    ) AS on_time_pct
FROM v_orders_clean
WHERE order_status = 'delivered';

\echo ''
\echo '-- Untranslated categories should now be 0 --'
SELECT COUNT(*) AS untranslated_categories
FROM products p
LEFT JOIN category_translation t USING (product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name_english IS NULL;
