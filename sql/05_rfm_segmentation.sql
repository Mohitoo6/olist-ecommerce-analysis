-- =============================================================================
-- 05_rfm_segmentation.sql
-- Business question:
--   Segment Olist's 96K customers into actionable cohorts. The wrinkle: with
--   only 3.1% of customers ever placing a second order, classic RFM
--   (Recency / Frequency / Monetary) breaks down because Frequency is
--   degenerate for ~97% of the base.
--
--   Approach:
--     * Score Recency and Monetary on quintiles (1=worst, 5=best).
--     * Use a binary 'has_repeated' flag instead of Frequency quintiles.
--     * Layer in average review score as a 4th dimension because a 5-star
--       one-time customer is a different reactivation prospect than a
--       1-star one-time customer.
--     * Segment names are stakeholder-friendly: 'Champions', 'Loyal',
--       'At Risk', 'Burnt', 'Hibernating', 'New & Promising', 'Need Attention'.
--
--   Recency anchor: max(order_purchase_timestamp) within the analysis window
--   (= 2018-08-31 effectively). Recency = days since last purchase.
--
-- Output:
--   sql/outputs/05a_rfm_segments.csv     (segment-level summary)
--   sql/outputs/05b_rfm_customers.csv    (per-customer scores; sample only)
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS rfm_scored;

CREATE TEMP TABLE rfm_scored AS
WITH base AS (
    SELECT
        os.customer_unique_id,
        MAX(os.order_purchase_timestamp)        AS last_purchase,
        COUNT(DISTINCT os.order_id)             AS order_frequency,
        SUM(os.gmv)                             AS total_gmv,
        AVG(os.review_score)                    AS avg_review_score
    FROM v_order_satisfaction os
    WHERE os.in_analysis_window
      AND os.gmv IS NOT NULL
    GROUP BY os.customer_unique_id
),
anchored AS (
    SELECT
        b.*,
        EXTRACT(DAY FROM ((SELECT MAX(order_purchase_timestamp) FROM v_orders_clean
                            WHERE in_analysis_window) - b.last_purchase))::int AS recency_days
    FROM base b
),
scored AS (
    SELECT
        a.*,
        -- Lower recency_days = better. NTILE 5 ascending then invert.
        6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
        -- Higher gmv = better.
        NTILE(5) OVER (ORDER BY total_gmv ASC)        AS m_score,
        CASE WHEN order_frequency > 1 THEN 1 ELSE 0 END AS has_repeated
    FROM anchored a
)
SELECT
    *,
    -- Segment definitions: prioritise repeat behaviour, then R+M.
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

-- -----------------------------------------------------------------------------
-- (a) Segment-level summary — what the marketing team will look at first.
-- -----------------------------------------------------------------------------
\echo '=== (a) RFM segment summary ==='
SELECT
    segment,
    COUNT(*)                                                  AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_base,
    ROUND(AVG(recency_days)::numeric,        0)               AS avg_recency_days,
    ROUND(AVG(order_frequency)::numeric,     2)               AS avg_orders,
    ROUND(AVG(total_gmv)::numeric,           2)               AS avg_lifetime_gmv,
    ROUND(SUM(total_gmv)::numeric,           2)               AS segment_total_gmv,
    ROUND(100.0 * SUM(total_gmv) / SUM(SUM(total_gmv)) OVER (), 1)
                                                              AS segment_share_of_gmv,
    ROUND(AVG(avg_review_score)::numeric,    2)               AS avg_review_score
FROM rfm_scored
GROUP BY segment
ORDER BY segment_total_gmv DESC;

-- -----------------------------------------------------------------------------
-- (b) Per-customer detail — first 100 rows just for QA / inspection.
-- The full table can be exported separately if marketing wants to load it
-- into a CRM tool.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== (b) Top 20 highest-value customers by segment ==='
SELECT
    segment,
    LEFT(customer_unique_id, 12) || '...' AS customer_unique_id_short,
    recency_days,
    order_frequency,
    ROUND(total_gmv::numeric, 2)          AS total_gmv,
    ROUND(avg_review_score::numeric, 2)   AS avg_review_score,
    r_score,
    m_score
FROM rfm_scored
ORDER BY total_gmv DESC
LIMIT 20;
