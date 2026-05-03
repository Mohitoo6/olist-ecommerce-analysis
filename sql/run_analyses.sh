#!/usr/bin/env bash
# =============================================================================
# run_analyses.sh
# Business purpose:
#   One-shot runner for all 6 analyses. Saves each query result as both:
#     * a CSV (for downstream Python notebooks / dashboards), and
#     * a markdown preview (.md) for at-a-glance review on GitHub.
#
#   Usage (from the project root):
#     bash sql/run_analyses.sh
#
#   Re-running is safe: each analysis is read-only and writes idempotent
#   files into sql/outputs/.
# =============================================================================

set -euo pipefail

export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
DB="${DB:-olist}"
OUT_DIR="sql/outputs"
mkdir -p "$OUT_DIR"

# Helper: run a single SELECT, save as CSV and markdown preview.
#   $1 = output base name (no extension)
#   $2 = SQL string (a single SELECT statement)
#   $3 = preview row limit for the .md file (default 25)
run_query () {
    local name="$1"
    local sql="$2"
    local preview_n="${3:-25}"

    local csv="$OUT_DIR/${name}.csv"
    local md="$OUT_DIR/${name}_preview.md"

    psql -d "$DB" -v ON_ERROR_STOP=1 -A -F',' -t -c "COPY ($sql) TO STDOUT WITH CSV HEADER" > "$csv"

    # Markdown preview — first N rows only.
    {
        echo "### ${name}"
        echo
        echo "_Source query: see corresponding 0X_*.sql file. Showing first ${preview_n} rows of \`${name}.csv\`._"
        echo
        # Render as a markdown table from the CSV head.
        head -n 1 "$csv" | awk -F',' '{
            printf "| "; for (i=1;i<=NF;i++) printf "%s | ", $i; print ""
            printf "|"; for (i=1;i<=NF;i++) printf "---|"; print ""
        }'
        tail -n +2 "$csv" | head -n "$preview_n" | awk -F',' '{
            printf "| "; for (i=1;i<=NF;i++) printf "%s | ", $i; print ""
        }'
    } > "$md"
    echo "  wrote $csv and $md"
}

echo "=== 03 Revenue by category ==="
run_query "03_revenue_by_category" "$(cat <<'SQL'
WITH item_economics AS (
    SELECT pc.category_en, oi.order_id, oi.seller_id, oi.price, oi.freight_value,
           os.review_score, os.delivered_on_time
    FROM order_items oi
    JOIN v_products_clean pc USING (product_id)
    JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
)
SELECT
    category_en AS category,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(*) AS items_sold,
    COUNT(DISTINCT seller_id) AS sellers_active,
    ROUND(SUM(price), 2) AS gmv_brl,
    ROUND(SUM(freight_value), 2) AS freight_brl,
    ROUND(SUM(price + freight_value), 2) AS revenue_with_freight_brl,
    ROUND(SUM(price)::numeric / COUNT(DISTINCT order_id), 2) AS avg_revenue_per_order_brl,
    ROUND(AVG(price)::numeric, 2) AS avg_item_price_brl,
    ROUND(100.0 * SUM(freight_value) / NULLIF(SUM(price), 0), 1) AS freight_pct_of_gmv,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN delivered_on_time THEN 1.0 ELSE 0 END), 1) AS on_time_pct,
    ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 2) AS pct_of_total_gmv,
    ROUND(100.0 * SUM(SUM(price)) OVER (ORDER BY SUM(price) DESC ROWS UNBOUNDED PRECEDING) / SUM(SUM(price)) OVER (), 2) AS cum_pct_of_gmv
FROM item_economics
GROUP BY category_en
ORDER BY gmv_brl DESC
SQL
)" 30

echo "=== 04a Review by on-time/late ==="
run_query "04a_review_by_ontime" "$(cat <<'SQL'
SELECT
    CASE WHEN delivered_on_time THEN 'on_time' ELSE 'late' END AS delivery_status,
    COUNT(*) AS orders,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * AVG(CASE WHEN review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star,
    ROUND(100.0 * AVG(CASE WHEN review_score = 5 THEN 1.0 ELSE 0 END), 1) AS pct_five_star,
    ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END), 1) AS pct_negative
FROM v_order_satisfaction
WHERE order_status = 'delivered' AND review_score IS NOT NULL AND in_analysis_window
  AND delivered_on_time IS NOT NULL
GROUP BY delivered_on_time
ORDER BY delivered_on_time DESC
SQL
)" 5

echo "=== 04b Review by delay-day bucket ==="
run_query "04b_review_by_delay_bucket" "$(cat <<'SQL'
WITH bucketed AS (
    SELECT
        CASE WHEN delay_days < -30 THEN -30 WHEN delay_days > 30 THEN 30
             ELSE FLOOR(delay_days)::int END AS delay_day_bucket,
        review_score
    FROM v_order_satisfaction
    WHERE order_status = 'delivered' AND review_score IS NOT NULL
      AND in_analysis_window AND delay_days IS NOT NULL
)
SELECT delay_day_bucket, COUNT(*) AS orders,
       ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
       ROUND(100.0 * AVG(CASE WHEN review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star
FROM bucketed
GROUP BY delay_day_bucket
ORDER BY delay_day_bucket
SQL
)" 65

echo "=== 04c Delivery by state ==="
run_query "04c_delivery_by_state" "$(cat <<'SQL'
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(delivery_days)::numeric, 1) AS avg_delivery_days,
    ROUND(AVG(estimated_days)::numeric, 1) AS avg_estimated_days,
    ROUND(100.0 * AVG(CASE WHEN delivered_on_time THEN 1.0 ELSE 0 END), 1) AS on_time_pct,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM v_order_satisfaction
WHERE order_status = 'delivered' AND in_analysis_window AND delivery_days IS NOT NULL
GROUP BY customer_state
ORDER BY delivered_orders DESC
SQL
)" 30

# RFM needs a temp table that lives only inside the session — easier to run
# the full SQL file once to a CSV using a single pipeline.
echo "=== 05 RFM segmentation ==="
psql -d "$DB" -v ON_ERROR_STOP=1 <<'SQL_OUT'
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS public.rfm_scored;
CREATE TABLE public.rfm_scored AS
WITH base AS (
    SELECT customer_unique_id,
           MAX(order_purchase_timestamp) AS last_purchase,
           COUNT(DISTINCT order_id)      AS order_frequency,
           SUM(gmv)                      AS total_gmv,
           AVG(review_score)             AS avg_review_score
    FROM v_order_satisfaction
    WHERE in_analysis_window AND gmv IS NOT NULL
    GROUP BY customer_unique_id
),
anchored AS (
    SELECT b.*,
           EXTRACT(DAY FROM ((SELECT MAX(order_purchase_timestamp) FROM v_orders_clean
                              WHERE in_analysis_window) - b.last_purchase))::int AS recency_days
    FROM base b
),
scored AS (
    SELECT a.*,
           6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
           NTILE(5) OVER (ORDER BY total_gmv ASC)        AS m_score,
           CASE WHEN order_frequency > 1 THEN 1 ELSE 0 END AS has_repeated
    FROM anchored a
)
SELECT *,
    CASE
        WHEN has_repeated = 1 AND r_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN has_repeated = 1 AND r_score >= 3                  THEN 'Loyal'
        WHEN has_repeated = 1                                   THEN 'At Risk Repeaters'
        WHEN r_score >= 4 AND m_score >= 4                      THEN 'New & Promising'
        WHEN r_score >= 4                                       THEN 'Recent One-Timers'
        WHEN r_score <= 2 AND m_score >= 4 AND avg_review_score <= 2.5 THEN 'High-Value Burnt'
        WHEN r_score <= 2 AND m_score >= 4                      THEN 'High-Value Lost'
        WHEN r_score <= 2                                       THEN 'Hibernating'
        ELSE 'Need Attention'
    END AS segment
FROM scored;
SQL_OUT

run_query "05a_rfm_segments" "$(cat <<'SQL'
SELECT
    segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_base,
    ROUND(AVG(recency_days)::numeric, 0) AS avg_recency_days,
    ROUND(AVG(order_frequency)::numeric, 2) AS avg_orders,
    ROUND(AVG(total_gmv)::numeric, 2) AS avg_lifetime_gmv,
    ROUND(SUM(total_gmv)::numeric, 2) AS segment_total_gmv,
    ROUND(100.0 * SUM(total_gmv) / SUM(SUM(total_gmv)) OVER (), 1) AS segment_share_of_gmv,
    ROUND(AVG(avg_review_score)::numeric, 2) AS avg_review_score
FROM public.rfm_scored
GROUP BY segment
ORDER BY segment_total_gmv DESC
SQL
)" 12

echo "=== 06a Seller pareto ==="
run_query "06a_seller_pareto" "$(cat <<'SQL'
WITH item_level AS (
    SELECT oi.seller_id, oi.order_id, oi.price
    FROM order_items oi JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
),
sm AS (
    SELECT seller_id, SUM(price) AS gmv
    FROM item_level GROUP BY seller_id
),
ranked AS (
    SELECT seller_id, gmv,
           ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rnk,
           COUNT(*)    OVER ()                   AS total_sellers,
           SUM(gmv)    OVER ()                   AS total_gmv
    FROM sm
),
buckets AS (
    SELECT CASE
        WHEN rnk <= total_sellers * 0.01 THEN 'Top 1%'
        WHEN rnk <= total_sellers * 0.05 THEN 'Top 5%'
        WHEN rnk <= total_sellers * 0.10 THEN 'Top 10%'
        WHEN rnk <= total_sellers * 0.25 THEN 'Top 25%'
        WHEN rnk <= total_sellers * 0.50 THEN 'Top 50%'
        ELSE 'Bottom 50%' END AS bucket,
        gmv, total_gmv
    FROM ranked
)
SELECT bucket, COUNT(*) AS sellers,
       ROUND(SUM(gmv)::numeric, 2) AS gmv_brl,
       ROUND(100.0 * SUM(gmv) / MAX(total_gmv), 2) AS pct_of_total_gmv
FROM buckets
GROUP BY bucket
ORDER BY CASE bucket WHEN 'Top 1%' THEN 1 WHEN 'Top 5%' THEN 2
                    WHEN 'Top 10%' THEN 3 WHEN 'Top 25%' THEN 4
                    WHEN 'Top 50%' THEN 5 ELSE 6 END
SQL
)" 10

echo "=== 06b Top sellers ==="
run_query "06b_top_sellers" "$(cat <<'SQL'
WITH item_level AS (
    SELECT oi.seller_id, oi.order_id, oi.price, oi.freight_value,
           os.review_score, os.order_status, os.delivered_on_time
    FROM order_items oi JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
)
SELECT LEFT(s.seller_id, 12) || '...' AS seller_id_short,
       s.seller_state,
       COUNT(DISTINCT il.order_id)   AS orders,
       COUNT(*)                      AS items_sold,
       ROUND(SUM(il.price)::numeric, 2) AS gmv_brl,
       ROUND(AVG(il.price)::numeric, 2) AS avg_item_price,
       ROUND(AVG(il.review_score)::numeric, 2) AS avg_review_score,
       ROUND(100.0 * AVG(CASE WHEN il.delivered_on_time THEN 1.0 ELSE 0 END), 1) AS on_time_pct,
       ROUND(100.0 * AVG(CASE WHEN il.review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star
FROM sellers s JOIN item_level il USING (seller_id)
GROUP BY s.seller_id, s.seller_state
ORDER BY gmv_brl DESC
LIMIT 50
SQL
)" 25

echo "=== 06c Risk sellers ==="
run_query "06c_risk_sellers" "$(cat <<'SQL'
WITH item_level AS (
    SELECT oi.seller_id, oi.order_id, oi.price, os.review_score, os.order_status, os.delivered_on_time
    FROM order_items oi JOIN v_order_satisfaction os USING (order_id)
    WHERE os.in_analysis_window
),
sm AS (
    SELECT s.seller_id, s.seller_state,
           COUNT(DISTINCT il.order_id) AS orders,
           SUM(il.price) AS gmv,
           AVG(il.review_score) AS avg_review,
           AVG(CASE WHEN il.delivered_on_time THEN 1.0 ELSE 0 END) AS on_time_rate,
           AVG(CASE WHEN il.review_score = 1 THEN 1.0 ELSE 0 END) AS one_star_rate,
           AVG(CASE WHEN il.order_status = 'canceled' THEN 1.0 ELSE 0 END) AS cancel_rate
    FROM sellers s JOIN item_level il USING (seller_id)
    GROUP BY s.seller_id, s.seller_state
),
ranked AS (
    SELECT sm.*, NTILE(4) OVER (ORDER BY gmv ASC) AS gmv_quartile
    FROM sm
)
SELECT LEFT(seller_id, 12) || '...' AS seller_id_short,
       seller_state, orders,
       ROUND(gmv::numeric, 2) AS gmv_brl,
       ROUND(avg_review::numeric, 2) AS avg_review_score,
       ROUND(100.0 * on_time_rate, 1) AS on_time_pct,
       ROUND(100.0 * one_star_rate, 1) AS pct_one_star,
       ROUND(100.0 * cancel_rate, 2) AS cancellation_pct,
       CASE
         WHEN avg_review < 3.5 AND on_time_rate < 0.80 THEN 'Critical'
         WHEN avg_review < 4.0                          THEN 'Low Reviews'
         WHEN on_time_rate < 0.85                       THEN 'Logistics Risk'
       END AS risk_flag
FROM ranked
WHERE gmv_quartile = 4 AND (avg_review < 4.0 OR on_time_rate < 0.85)
ORDER BY gmv DESC
LIMIT 50
SQL
)" 25

echo "=== 07 Monthly revenue trend ==="
run_query "07_monthly_revenue_trend" "$(cat <<'SQL'
WITH monthly AS (
    SELECT
        purchase_month,
        in_analysis_window,
        COUNT(DISTINCT order_id) AS order_count,
        COUNT(DISTINCT customer_unique_id) AS unique_customers,
        SUM(gmv) AS gmv,
        SUM(freight) AS freight_total,
        SUM(gmv + freight) AS revenue_with_freight,
        AVG(gmv) FILTER (WHERE gmv > 0) AS avg_order_value,
        SUM(item_count) AS items_sold
    FROM v_order_lifecycle
    GROUP BY purchase_month, in_analysis_window
)
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM') AS month,
    in_analysis_window AS in_window,
    order_count,
    unique_customers,
    items_sold,
    ROUND(gmv, 2) AS gmv_brl,
    ROUND(freight_total, 2) AS freight_brl,
    ROUND(revenue_with_freight, 2) AS revenue_with_freight_brl,
    ROUND(avg_order_value::numeric, 2) AS aov_brl,
    ROUND(100.0 * freight_total / NULLIF(gmv, 0), 1) AS freight_pct_of_gmv,
    ROUND(100.0 * (gmv - LAG(gmv) OVER (ORDER BY purchase_month)) / NULLIF(LAG(gmv) OVER (ORDER BY purchase_month), 0), 1) AS mom_gmv_growth_pct
FROM monthly
ORDER BY purchase_month
SQL
)" 30

echo "=== 08a Cohort retention (long) ==="
psql -d "$DB" -v ON_ERROR_STOP=1 <<'SQL_OUT'
DROP TABLE IF EXISTS public.cohort_base;
CREATE TABLE public.cohort_base AS
WITH first_purchase AS (
    SELECT customer_unique_id,
           DATE_TRUNC('month', MIN(order_purchase_timestamp))::date AS cohort_month
    FROM v_orders_clean WHERE in_analysis_window
    GROUP BY customer_unique_id
),
all_orders AS (
    SELECT customer_unique_id,
           DATE_TRUNC('month', order_purchase_timestamp)::date AS order_month
    FROM v_orders_clean WHERE in_analysis_window
)
SELECT fp.cohort_month, fp.customer_unique_id, ao.order_month,
       (EXTRACT(YEAR FROM ao.order_month) - EXTRACT(YEAR FROM fp.cohort_month)) * 12
     + (EXTRACT(MONTH FROM ao.order_month) - EXTRACT(MONTH FROM fp.cohort_month))
       AS months_since_acq
FROM first_purchase fp
JOIN all_orders ao USING (customer_unique_id);
SQL_OUT

run_query "08a_cohort_retention" "$(cat <<'SQL'
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM public.cohort_base
    WHERE months_since_acq = 0 GROUP BY cohort_month
),
active AS (
    SELECT cohort_month, months_since_acq,
           COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM public.cohort_base
    GROUP BY cohort_month, months_since_acq
)
SELECT TO_CHAR(a.cohort_month, 'YYYY-MM') AS cohort_month,
       cs.cohort_customers,
       a.months_since_acq,
       a.active_customers,
       ROUND(100.0 * a.active_customers / cs.cohort_customers, 2) AS retention_pct
FROM active a JOIN cohort_size cs USING (cohort_month)
ORDER BY a.cohort_month, a.months_since_acq
SQL
)" 50

echo "=== 08b Cohort retention pivot ==="
run_query "08b_cohort_retention_pivot" "$(cat <<'SQL'
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM public.cohort_base WHERE months_since_acq = 0 GROUP BY cohort_month
),
retention AS (
    SELECT cohort_month, months_since_acq,
           COUNT(DISTINCT customer_unique_id) AS active
    FROM public.cohort_base
    WHERE months_since_acq BETWEEN 0 AND 12
    GROUP BY cohort_month, months_since_acq
)
SELECT TO_CHAR(r.cohort_month, 'YYYY-MM') AS cohort,
       cs.cohort_customers AS m0_customers,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 1)  / cs.cohort_customers, 2) AS m1_pct,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 2)  / cs.cohort_customers, 2) AS m2_pct,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 3)  / cs.cohort_customers, 2) AS m3_pct,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 6)  / cs.cohort_customers, 2) AS m6_pct,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 9)  / cs.cohort_customers, 2) AS m9_pct,
       ROUND(100.0 * MAX(r.active) FILTER (WHERE months_since_acq = 12) / cs.cohort_customers, 2) AS m12_pct
FROM retention r JOIN cohort_size cs USING (cohort_month)
GROUP BY r.cohort_month, cs.cohort_customers
ORDER BY r.cohort_month
SQL
)" 30

echo ""
echo "All analyses complete. Outputs in $OUT_DIR/"
ls -la "$OUT_DIR"
