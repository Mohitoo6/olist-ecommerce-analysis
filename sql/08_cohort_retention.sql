-- =============================================================================
-- 08_cohort_retention.sql
-- Business question:
--   For each acquisition month, what % of customers return to make another
--   purchase in months 1, 2, 3, 6, 12? A cohort heatmap is the single best
--   visualization for telling the retention story — and given Olist's 3.1%
--   overall repeat rate, the heatmap will be sparse, which IS the finding.
--
--   We use customer_unique_id (not customer_id), and only count second+
--   orders. The "cohort month" of a customer is the month of their first
--   ever purchase. Months are integer offsets from cohort month.
--
-- Output:
--   sql/outputs/08a_cohort_retention.csv      (long format, one row per cohort × offset)
--   sql/outputs/08b_cohort_retention_pivot.csv (wide format for heatmap rendering)
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS cohort_base;

CREATE TEMP TABLE cohort_base AS
WITH first_purchase AS (
    SELECT
        customer_unique_id,
        DATE_TRUNC('month', MIN(order_purchase_timestamp))::date AS cohort_month
    FROM v_orders_clean
    WHERE in_analysis_window
    GROUP BY customer_unique_id
),
all_orders AS (
    SELECT
        oc.customer_unique_id,
        DATE_TRUNC('month', oc.order_purchase_timestamp)::date AS order_month
    FROM v_orders_clean oc
    WHERE oc.in_analysis_window
)
SELECT
    fp.cohort_month,
    fp.customer_unique_id,
    ao.order_month,
    -- Months between cohort and order. 0 = first month (acquisition itself).
    (EXTRACT(YEAR  FROM ao.order_month) - EXTRACT(YEAR  FROM fp.cohort_month)) * 12
  + (EXTRACT(MONTH FROM ao.order_month) - EXTRACT(MONTH FROM fp.cohort_month))
        AS months_since_acq
FROM first_purchase fp
JOIN all_orders ao USING (customer_unique_id);

-- -----------------------------------------------------------------------------
-- (a) Long-format retention table: customers active per cohort × offset.
-- -----------------------------------------------------------------------------
\echo '=== (a) Cohort retention (long format) ==='
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM cohort_base
    WHERE months_since_acq = 0
    GROUP BY cohort_month
),
active AS (
    SELECT cohort_month, months_since_acq,
           COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM cohort_base
    GROUP BY cohort_month, months_since_acq
)
SELECT
    TO_CHAR(a.cohort_month, 'YYYY-MM')  AS cohort_month,
    cs.cohort_customers,
    a.months_since_acq,
    a.active_customers,
    ROUND(100.0 * a.active_customers / cs.cohort_customers, 2) AS retention_pct
FROM active a
JOIN cohort_size cs USING (cohort_month)
ORDER BY a.cohort_month, a.months_since_acq;

-- -----------------------------------------------------------------------------
-- (b) Wide-format pivot for the classic heatmap rendering. Months 0-12.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (b) Cohort retention pivot (M0–M12) ==='
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM cohort_base
    WHERE months_since_acq = 0
    GROUP BY cohort_month
),
retention AS (
    SELECT
        cohort_month,
        months_since_acq,
        COUNT(DISTINCT customer_unique_id) AS active
    FROM cohort_base
    WHERE months_since_acq BETWEEN 0 AND 12
    GROUP BY cohort_month, months_since_acq
)
SELECT
    TO_CHAR(r.cohort_month, 'YYYY-MM') AS cohort,
    cs.cohort_customers                AS m0_customers,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 1)  / cs.cohort_customers, 2) AS m1_pct,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 2)  / cs.cohort_customers, 2) AS m2_pct,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 3)  / cs.cohort_customers, 2) AS m3_pct,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 6)  / cs.cohort_customers, 2) AS m6_pct,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 9)  / cs.cohort_customers, 2) AS m9_pct,
    ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 12) / cs.cohort_customers, 2) AS m12_pct
FROM retention r
JOIN cohort_size cs USING (cohort_month)
GROUP BY r.cohort_month, cs.cohort_customers
ORDER BY r.cohort_month;
