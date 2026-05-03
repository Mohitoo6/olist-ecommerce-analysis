-- =============================================================================
-- 04_delivery_vs_satisfaction.sql
-- Business question:
--   How tightly does delivery performance drive review scores? The headline
--   hypothesis: a single day late triggers a near-step-function collapse in
--   review score. If true, the operations team's #1 KPI should be on-time
--   delivery rate, not delivery speed.
--
-- Three output sets in one file (separate \copy commands in the runner):
--   (a) Score distribution by on-time vs late.
--   (b) Average review score by signed delay-day buckets — to visualize
--       the cliff and quantify how steep it is.
--   (c) State-level breakdown — which lanes have the worst on-time rate and
--       therefore the most exposure to review damage. Useful to recommend
--       regional fulfillment / freight policy.
--
-- Output:
--   sql/outputs/04a_review_by_ontime.csv
--   sql/outputs/04b_review_by_delay_bucket.csv
--   sql/outputs/04c_delivery_by_state.csv
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- (a) Headline cliff: review score by on-time / late.
-- -----------------------------------------------------------------------------
\echo '=== (a) Review score: on-time vs late ==='
-- NOTE: 8 orders in source have status='delivered' but NULL delivered_customer_date.
-- Those rows have NULL delivered_on_time and we filter them out — including them
-- as 'late' would be incorrect because we don't actually know the delivery date.
SELECT
    CASE WHEN delivered_on_time THEN 'on_time' ELSE 'late' END AS delivery_status,
    COUNT(*)                                                   AS orders,
    ROUND(AVG(review_score)::numeric, 2)                       AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star,
    ROUND(100.0 * AVG(CASE WHEN review_score = 5 THEN 1.0 ELSE 0 END), 1) AS pct_five_star,
    ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END), 1) AS pct_negative
FROM v_order_satisfaction
WHERE order_status = 'delivered'
  AND review_score IS NOT NULL
  AND in_analysis_window
  AND delivered_on_time IS NOT NULL
GROUP BY delivered_on_time
ORDER BY delivered_on_time DESC;

-- -----------------------------------------------------------------------------
-- (b) Cliff visualisation: review score by signed delay-day bucket.
-- Buckets capped at -30/+30 so a few extreme outliers don't waste chart space.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (b) Review score by delay-day bucket ==='
WITH bucketed AS (
    SELECT
        CASE
            WHEN delay_days < -30 THEN -30
            WHEN delay_days >  30 THEN  30
            ELSE FLOOR(delay_days)::int
        END AS delay_day_bucket,
        review_score
    FROM v_order_satisfaction
    WHERE order_status = 'delivered'
      AND review_score IS NOT NULL
      AND in_analysis_window
      AND delay_days IS NOT NULL
)
SELECT
    delay_day_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star
FROM bucketed
GROUP BY delay_day_bucket
ORDER BY delay_day_bucket;

-- -----------------------------------------------------------------------------
-- (c) State-level breakdown — which destinations are most at risk.
-- Includes order share so we can weight the operational priority correctly:
-- a state with bad on-time but only 200 orders is less urgent than SP.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (c) Delivery performance by customer state ==='
SELECT
    customer_state,
    COUNT(*)                                                AS delivered_orders,
    ROUND(AVG(delivery_days)::numeric, 1)                   AS avg_delivery_days,
    ROUND(AVG(estimated_days)::numeric, 1)                  AS avg_estimated_days,
    ROUND(100.0 * AVG(CASE WHEN delivered_on_time THEN 1.0 ELSE 0 END), 1) AS on_time_pct,
    ROUND(AVG(review_score)::numeric, 2)                    AS avg_review_score,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_orders
FROM v_order_satisfaction
WHERE order_status = 'delivered'
  AND in_analysis_window
  AND delivery_days IS NOT NULL
GROUP BY customer_state
ORDER BY delivered_orders DESC;
