-- =============================================================================
-- load_data.sql
-- Business purpose:
--   Bulk-load all 9 source CSVs into the staging tables created by
--   01_schema_setup.sql. Idempotent: TRUNCATE before each \copy so the
--   loader can be re-run without dedup work.
--
--   Run with:
--     psql -d olist -v ON_ERROR_STOP=1 -f load_data.sql
--   from the project root, so the relative paths to data/raw/ resolve.
-- =============================================================================

\set ON_ERROR_STOP on

TRUNCATE customers, sellers, products, category_translation,
         orders, order_items, order_payments, order_reviews, geolocation
RESTART IDENTITY;

\echo 'Loading customers...'
\copy customers FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading sellers...'
\copy sellers FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading products...'
\copy products FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading category_translation (file has UTF-8 BOM)...'
\copy category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\echo 'Loading orders...'
\copy orders FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order_items...'
\copy order_items FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order_payments...'
\copy order_payments FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order_reviews...'
\copy order_reviews FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading geolocation (1M rows, this is the slowest)...'
\copy geolocation FROM 'data/raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true);

ANALYZE;

-- ---------------------------------------------------------------------------
-- Row count verification — values match the data exploration done before
-- schema design. Any deviation here means a load problem, not a code bug.
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Row counts after load ==='
SELECT 'customers'            AS table_name, COUNT(*) AS rows FROM customers
UNION ALL SELECT 'sellers',              COUNT(*) FROM sellers
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM order_reviews
UNION ALL SELECT 'geolocation',          COUNT(*) FROM geolocation
ORDER BY table_name;
