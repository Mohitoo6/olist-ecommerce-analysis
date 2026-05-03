-- =============================================================================
-- 07_monthly_revenue_trend.sql
-- Business question:
--   How has Olist's marketplace grown month-over-month, and what does the
--   AOV / order-volume / GMV split look like? This is the chart a director
--   wants on slide 1 — but the raw data has misleading edges (4 orders in
--   Sept 2016, 20 orders in Sept-Oct 2018) that have to be visibly truncated
--   or honestly footnoted.
--
-- Output:
--   sql/outputs/07_monthly_revenue_trend.csv
--   One row per calendar month with order count, GMV, AOV, distinct
--   customers, freight share, and the in_analysis_window flag.
-- =============================================================================

\set ON_ERROR_STOP on

-- For convenience: a small CTE used twice below.
WITH monthly AS (
    SELECT
        purchase_month,
        in_analysis_window,
        COUNT(DISTINCT order_id)              AS order_count,
        COUNT(DISTINCT customer_unique_id)    AS unique_customers,
        SUM(gmv)                              AS gmv,
        SUM(freight)                          AS freight_total,
        SUM(gmv + freight)                    AS revenue_with_freight,
        AVG(gmv) FILTER (WHERE gmv > 0)       AS avg_order_value,
        SUM(item_count)                       AS items_sold
    FROM v_order_lifecycle
    GROUP BY purchase_month, in_analysis_window
)
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM')                    AS month,
    in_analysis_window                                    AS in_window,
    order_count,
    unique_customers,
    items_sold,
    ROUND(gmv,                  2)                        AS gmv_brl,
    ROUND(freight_total,        2)                        AS freight_brl,
    ROUND(revenue_with_freight, 2)                        AS revenue_with_freight_brl,
    ROUND(avg_order_value::numeric, 2)                    AS aov_brl,
    ROUND(100.0 * freight_total / NULLIF(gmv, 0), 1)      AS freight_pct_of_gmv,
    -- Month-over-month GMV growth — only meaningful inside the window.
    ROUND(
        100.0 * (gmv - LAG(gmv) OVER (ORDER BY purchase_month))
              / NULLIF(LAG(gmv) OVER (ORDER BY purchase_month), 0),
        1
    ) AS mom_gmv_growth_pct
FROM monthly
ORDER BY purchase_month;
