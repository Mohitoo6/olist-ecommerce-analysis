-- =============================================================================
-- 03_revenue_by_category.sql
-- Business question:
--   Which product categories drive Olist's marketplace? We don't just want
--   GMV — we want the category-level economics: AOV, freight share, average
--   review score, and seller concentration. A high-revenue category with
--   bad reviews is a different problem from a low-revenue category with
--   great reviews; both deserve attention.
--
--   Restricted to in_analysis_window orders (2017-01 to 2018-08) so the
--   sparse 2016 / late-2018 tails don't distort the picture.
--
-- Output:
--   sql/outputs/03_revenue_by_category.csv
-- =============================================================================

\set ON_ERROR_STOP on

WITH item_economics AS (
    SELECT
        pc.category_en,
        oi.order_id,
        oi.seller_id,
        oi.price,
        oi.freight_value,
        os.review_score,
        os.delivered_on_time
    FROM order_items oi
    JOIN v_products_clean     pc USING (product_id)
    JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
)
SELECT
    category_en                                              AS category,
    COUNT(DISTINCT order_id)                                 AS orders,
    COUNT(*)                                                 AS items_sold,
    COUNT(DISTINCT seller_id)                                AS sellers_active,
    ROUND(SUM(price),                  2)                    AS gmv_brl,
    ROUND(SUM(freight_value),          2)                    AS freight_brl,
    ROUND(SUM(price + freight_value),  2)                    AS revenue_with_freight_brl,
    ROUND(SUM(price)::numeric / COUNT(DISTINCT order_id), 2) AS avg_revenue_per_order_brl,
    ROUND(AVG(price)::numeric, 2)                            AS avg_item_price_brl,
    ROUND(100.0 * SUM(freight_value) / NULLIF(SUM(price), 0), 1) AS freight_pct_of_gmv,
    ROUND(AVG(review_score)::numeric, 2)                     AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN delivered_on_time THEN 1.0 ELSE 0 END), 1) AS on_time_pct,
    -- Cumulative GMV share — the Pareto curve. Top N categories driving X%.
    ROUND(
        100.0 * SUM(price) / SUM(SUM(price)) OVER (),
        2
    ) AS pct_of_total_gmv,
    ROUND(
        100.0 * SUM(SUM(price)) OVER (ORDER BY SUM(price) DESC ROWS UNBOUNDED PRECEDING)
              / SUM(SUM(price)) OVER (),
        2
    ) AS cum_pct_of_gmv
FROM item_economics
GROUP BY category_en
ORDER BY gmv_brl DESC;
