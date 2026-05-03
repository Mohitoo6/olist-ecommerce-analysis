-- =============================================================================
-- 06_seller_performance.sql
-- Business question:
--   How concentrated is GMV among Olist's 3K sellers, and where is the
--   platform's strategic risk? Specifically:
--     (1) The Pareto curve — what share of revenue comes from the top X%?
--     (2) Are top-revenue sellers also top-quality sellers, or is there a
--         cluster of high-revenue / mediocre-review sellers (a churn risk)?
--     (3) Which sellers are 'silent failures' — low review score *and*
--         high cancellation rate — that should be put on a quality plan?
--
-- Outputs:
--   sql/outputs/06a_seller_pareto.csv       — concentration buckets
--   sql/outputs/06b_top_sellers.csv         — top 50 by GMV
--   sql/outputs/06c_risk_sellers.csv        — high-revenue + low-quality flags
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS seller_metrics;

CREATE TEMP TABLE seller_metrics AS
WITH item_level AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        oi.price,
        oi.freight_value,
        os.review_score,
        os.order_status,
        os.delivered_on_time
    FROM order_items oi
    JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
)
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT il.order_id)                       AS orders,
    COUNT(*)                                          AS items_sold,
    ROUND(SUM(il.price)::numeric,         2)          AS gmv_brl,
    ROUND(SUM(il.freight_value)::numeric, 2)          AS freight_brl,
    ROUND(AVG(il.price)::numeric,         2)          AS avg_item_price,
    ROUND(AVG(il.review_score)::numeric,  2)          AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN il.review_score = 1 THEN 1.0 ELSE 0 END), 1)
        AS pct_one_star,
    ROUND(100.0 * AVG(CASE WHEN il.delivered_on_time THEN 1.0 ELSE 0 END), 1)
        AS on_time_pct,
    ROUND(100.0 * AVG(CASE WHEN il.order_status = 'canceled' THEN 1.0 ELSE 0 END), 2)
        AS cancellation_pct
FROM sellers s
JOIN item_level il USING (seller_id)
GROUP BY s.seller_id, s.seller_state;

-- -----------------------------------------------------------------------------
-- (a) Pareto buckets — top 1%, 5%, 10%, 25%, 50%, 100% of sellers.
-- -----------------------------------------------------------------------------
\echo '=== (a) Seller Pareto concentration ==='
WITH ranked AS (
    SELECT
        seller_id,
        gmv_brl,
        ROW_NUMBER() OVER (ORDER BY gmv_brl DESC)              AS rnk,
        COUNT(*)    OVER ()                                    AS total_sellers,
        SUM(gmv_brl) OVER ()                                   AS total_gmv,
        SUM(gmv_brl) OVER (ORDER BY gmv_brl DESC ROWS UNBOUNDED PRECEDING) AS cum_gmv
    FROM seller_metrics
),
buckets AS (
    SELECT
        CASE
            WHEN rnk <= total_sellers * 0.01 THEN 'Top 1%'
            WHEN rnk <= total_sellers * 0.05 THEN 'Top 5%'
            WHEN rnk <= total_sellers * 0.10 THEN 'Top 10%'
            WHEN rnk <= total_sellers * 0.25 THEN 'Top 25%'
            WHEN rnk <= total_sellers * 0.50 THEN 'Top 50%'
            ELSE 'Bottom 50%'
        END AS bucket,
        gmv_brl,
        total_gmv
    FROM ranked
)
SELECT
    bucket,
    COUNT(*)                                                       AS sellers,
    ROUND(SUM(gmv_brl)::numeric, 2)                                AS gmv_brl,
    ROUND(100.0 * SUM(gmv_brl) / MAX(total_gmv), 2)                AS pct_of_total_gmv
FROM buckets
GROUP BY bucket
ORDER BY CASE bucket
    WHEN 'Top 1%'     THEN 1
    WHEN 'Top 5%'     THEN 2
    WHEN 'Top 10%'    THEN 3
    WHEN 'Top 25%'    THEN 4
    WHEN 'Top 50%'    THEN 5
    ELSE 6 END;

-- -----------------------------------------------------------------------------
-- (b) Top 50 sellers by GMV with their quality KPIs.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (b) Top 50 sellers by GMV ==='
SELECT
    LEFT(seller_id, 12) || '...' AS seller_id_short,
    seller_state,
    orders,
    items_sold,
    gmv_brl,
    avg_item_price,
    avg_review_score,
    on_time_pct,
    pct_one_star
FROM seller_metrics
ORDER BY gmv_brl DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- (c) Risk sellers — high-revenue + low-quality.
-- A 'risk seller' here is one in the top revenue quartile whose review
-- score is below 4.0 OR on-time rate is below 85%. These are the sellers
-- whose churn would hurt most AND whose buyers are most likely to leave
-- bad reviews of Olist itself.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (c) Risk sellers (top quartile GMV with quality issues) ==='
WITH ranked AS (
    SELECT
        sm.*,
        NTILE(4) OVER (ORDER BY gmv_brl ASC) AS gmv_quartile
    FROM seller_metrics sm
)
SELECT
    LEFT(seller_id, 12) || '...' AS seller_id_short,
    seller_state,
    orders,
    gmv_brl,
    avg_review_score,
    on_time_pct,
    pct_one_star,
    cancellation_pct,
    CASE
        WHEN avg_review_score < 3.5 AND on_time_pct < 80 THEN 'Critical'
        WHEN avg_review_score < 4.0                      THEN 'Low Reviews'
        WHEN on_time_pct < 85                            THEN 'Logistics Risk'
    END AS risk_flag
FROM ranked
WHERE gmv_quartile = 4   -- top-quartile GMV
  AND (avg_review_score < 4.0 OR on_time_pct < 85)
ORDER BY gmv_brl DESC
LIMIT 50;
