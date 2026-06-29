-- =============================================================================
-- Step 7: SQL Analyses
-- Project: Customer Churn & Revenue Intelligence Platform
-- Schema: dw (star schema)
-- =============================================================================
-- All queries run against the dw schema.
-- Organized into 6 sections matching dashboard pages in Tableau (Step 9).
-- =============================================================================


-- =============================================================================
-- SECTION 1: EXECUTIVE SUMMARY KPIs
-- These are the headline numbers for the Executive Summary dashboard page.
-- =============================================================================

-- 1a. Top-line KPI summary
SELECT
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE NOT is_churned)                          AS active_customers,
    COUNT(*) FILTER (WHERE is_churned)                              AS churned_customers,
    ROUND(
        COUNT(*) FILTER (WHERE is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(SUM(monthly_charges), 2)                                  AS total_mrr,
    ROUND(SUM(monthly_charges) FILTER (WHERE NOT is_churned), 2)    AS active_mrr,
    ROUND(SUM(mrr_at_risk), 2)                                      AS mrr_at_risk,
    ROUND(AVG(tenure_months), 1)                                    AS avg_tenure_months,
    ROUND(AVG(monthly_charges), 2)                                  AS avg_monthly_charges,
    ROUND(
        SUM(estimated_clv) FILTER (WHERE NOT is_churned) /
        NULLIF(COUNT(*) FILTER (WHERE NOT is_churned), 0), 2
    )                                                               AS avg_clv_active
FROM dw.fact_subscription;


-- 1b. MRR at risk as a percentage of total MRR
WITH mrr AS (
    SELECT
        SUM(monthly_charges)                    AS total_mrr,
        SUM(monthly_charges) FILTER (WHERE is_churned) AS at_risk_mrr
    FROM dw.fact_subscription
)
SELECT
    ROUND(total_mrr, 2)                         AS total_mrr,
    ROUND(at_risk_mrr, 2)                       AS mrr_at_risk,
    ROUND(at_risk_mrr * 100.0 / total_mrr, 2)  AS pct_mrr_at_risk
FROM mrr;


-- =============================================================================
-- SECTION 2: CHURN ANALYSIS
-- Answers: Why are customers leaving? Which segments churn most?
-- =============================================================================

-- 2a. Churn rate by contract type
-- Key insight: Month-to-month contracts churn significantly more
SELECT
    dc.contract_type,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges,
    ROUND(SUM(f.mrr_at_risk), 2)                                    AS mrr_at_risk
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
GROUP BY dc.contract_type
ORDER BY churn_rate_pct DESC;


-- 2b. Churn rate by internet service type
-- Key insight: Fiber optic customers churn at nearly double the rate of DSL
SELECT
    sp.internet_service,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY sp.internet_service
ORDER BY churn_rate_pct DESC;


-- 2c. Churn rate by payment method
-- Key insight: Electronic check payers churn at the highest rate
SELECT
    dc.payment_method,
    dc.payment_category,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
GROUP BY dc.payment_method, dc.payment_category
ORDER BY churn_rate_pct DESC;


-- 2d. Churn rate by tenure bucket
-- Key insight: Newest customers (0-12 months) churn at the highest rate
SELECT
    dd.tenure_bucket,
    dd.is_new_customer,
    dd.is_long_term,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges
FROM dw.fact_subscription f
JOIN dw.dim_date dd ON dd.date_key = f.date_key
GROUP BY dd.tenure_bucket, dd.is_new_customer, dd.is_long_term
ORDER BY MIN(dd.tenure_months);


-- 2e. Churn rate by senior citizen status
SELECT
    dc.senior_segment,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges
FROM dw.fact_subscription f
JOIN dw.dim_customer dc ON dc.customer_key = f.customer_key
GROUP BY dc.senior_segment
ORDER BY churn_rate_pct DESC;


-- 2f. Churn by number of add-on services
-- Key insight: Customers with more add-ons tend to churn less (stickier)
SELECT
    sp.total_addons,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY sp.total_addons
ORDER BY sp.total_addons;


-- 2g. Multi-factor churn breakdown: contract + internet service
-- Useful for identifying the riskiest customer combinations
SELECT
    dc.contract_type,
    sp.internet_service,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(SUM(f.mrr_at_risk), 2)                                    AS mrr_at_risk
FROM dw.fact_subscription f
JOIN dw.dim_contract dc      ON dc.contract_key = f.contract_key
JOIN dw.dim_service_plan sp  ON sp.service_key  = f.service_key
GROUP BY dc.contract_type, sp.internet_service
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- SECTION 3: REVENUE ANALYSIS
-- Answers: Where does revenue come from? What is at risk?
-- =============================================================================

-- 3a. Revenue by contract type
SELECT
    dc.contract_type,
    dc.contract_length,
    COUNT(*)                                                        AS customers,
    ROUND(SUM(f.monthly_charges), 2)                                AS total_mrr,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges,
    ROUND(SUM(f.total_charges), 2)                                  AS total_lifetime_revenue,
    ROUND(SUM(f.mrr_at_risk), 2)                                    AS mrr_at_risk,
    ROUND(
        SUM(f.mrr_at_risk) * 100.0 / NULLIF(SUM(f.monthly_charges), 0), 2
    )                                                               AS pct_mrr_at_risk
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
GROUP BY dc.contract_type, dc.contract_length
ORDER BY total_mrr DESC;


-- 3b. Revenue by internet service tier
SELECT
    sp.internet_tier,
    COUNT(*)                                                        AS customers,
    ROUND(SUM(f.monthly_charges), 2)                                AS total_mrr,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges,
    ROUND(SUM(f.mrr_at_risk), 2)                                    AS mrr_at_risk
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY sp.internet_tier
ORDER BY total_mrr DESC;


-- 3c. Revenue by payment category (automatic vs manual)
SELECT
    dc.payment_category,
    COUNT(*)                                                        AS customers,
    ROUND(SUM(f.monthly_charges), 2)                                AS total_mrr,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned_customers,
    ROUND(SUM(f.mrr_at_risk), 2)                                    AS mrr_at_risk
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
GROUP BY dc.payment_category
ORDER BY total_mrr DESC;


-- 3d. Average tenure and CLV by contract type
SELECT
    dc.contract_type,
    ROUND(AVG(f.tenure_months), 1)                                  AS avg_tenure_months,
    ROUND(AVG(f.estimated_clv), 2)                                  AS avg_estimated_clv,
    ROUND(MAX(f.estimated_clv), 2)                                  AS max_clv,
    ROUND(MIN(f.estimated_clv) FILTER (WHERE f.estimated_clv > 0), 2) AS min_clv
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
GROUP BY dc.contract_type
ORDER BY avg_estimated_clv DESC;


-- =============================================================================
-- SECTION 4: CUSTOMER SEGMENTATION
-- Answers: Who are our best customers? Who is at risk?
-- =============================================================================

-- 4a. High-value active customers
-- Definition: top 20% by monthly charges, not churned, tenure >= 12 months
WITH ranked AS (
    SELECT
        f.customer_id,
        f.monthly_charges,
        f.tenure_months,
        f.estimated_clv,
        dc_cust.gender,
        dc_cust.senior_segment,
        dc_cust.household_type,
        dc.contract_type,
        sp.internet_tier,
        sp.total_addons,
        NTILE(5) OVER (ORDER BY f.monthly_charges DESC)             AS charge_quintile
    FROM dw.fact_subscription f
    JOIN dw.dim_customer     dc_cust ON dc_cust.customer_key = f.customer_key
    JOIN dw.dim_contract     dc      ON dc.contract_key      = f.contract_key
    JOIN dw.dim_service_plan sp      ON sp.service_key       = f.service_key
    WHERE NOT f.is_churned
      AND f.tenure_months >= 12
)
SELECT
    customer_id,
    monthly_charges,
    tenure_months,
    estimated_clv,
    gender,
    senior_segment,
    household_type,
    contract_type,
    internet_tier,
    total_addons,
    charge_quintile
FROM ranked
WHERE charge_quintile = 1
ORDER BY estimated_clv DESC
LIMIT 50;


-- 4b. At-risk customers
-- Definition: churned OR (month-to-month + tenure <= 12 + monthly_charges > avg)
WITH avg_charge AS (
    SELECT AVG(monthly_charges) AS avg_mc FROM dw.fact_subscription
)
SELECT
    f.customer_id,
    f.churn                                                         AS churned,
    f.tenure_months,
    f.monthly_charges,
    f.mrr_at_risk,
    dc.contract_type,
    dc.payment_method,
    sp.internet_service,
    sp.total_addons,
    CASE
        WHEN f.is_churned                              THEN 'Churned'
        WHEN dc.contract_type = 'Month-to-month'
             AND f.tenure_months <= 12
             AND f.monthly_charges > avg_mc.avg_mc    THEN 'High Risk'
        WHEN dc.contract_type = 'Month-to-month'
             AND f.tenure_months <= 12                THEN 'Medium Risk'
        ELSE 'Low Risk'
    END                                                             AS risk_segment
FROM dw.fact_subscription f
JOIN dw.dim_contract     dc     ON dc.contract_key  = f.contract_key
JOIN dw.dim_service_plan sp     ON sp.service_key   = f.service_key
CROSS JOIN avg_charge
WHERE f.is_churned
   OR (dc.contract_type = 'Month-to-month' AND f.tenure_months <= 12)
ORDER BY f.monthly_charges DESC;


-- 4c. Segment summary: household type vs churn
SELECT
    dc_cust.household_type,
    COUNT(*)                                                        AS total_customers,
    COUNT(*) FILTER (WHERE f.is_churned)                            AS churned,
    ROUND(
        COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
    )                                                               AS churn_rate_pct,
    ROUND(AVG(f.monthly_charges), 2)                                AS avg_monthly_charges,
    ROUND(SUM(f.monthly_charges), 2)                                AS total_mrr
FROM dw.fact_subscription f
JOIN dw.dim_customer dc_cust ON dc_cust.customer_key = f.customer_key
GROUP BY dc_cust.household_type
ORDER BY churn_rate_pct DESC;


-- =============================================================================
-- SECTION 5: WINDOW FUNCTIONS
-- Demonstrates ROW_NUMBER, RANK, LAG, LEAD, running totals, percentiles
-- =============================================================================

-- 5a. ROW_NUMBER — rank customers by CLV within each contract type
SELECT
    f.customer_id,
    dc.contract_type,
    f.monthly_charges,
    f.tenure_months,
    f.estimated_clv,
    f.churn,
    ROW_NUMBER() OVER (
        PARTITION BY dc.contract_type
        ORDER BY f.estimated_clv DESC
    )                                                               AS clv_rank_within_contract
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
ORDER BY dc.contract_type, clv_rank_within_contract
LIMIT 30;


-- 5b. RANK — rank customers by monthly charges overall, handle ties
SELECT
    f.customer_id,
    f.monthly_charges,
    f.tenure_months,
    f.churn,
    dc.contract_type,
    RANK()   OVER (ORDER BY f.monthly_charges DESC)                 AS charge_rank,
    DENSE_RANK() OVER (ORDER BY f.monthly_charges DESC)             AS charge_dense_rank,
    NTILE(4) OVER (ORDER BY f.monthly_charges DESC)                 AS charge_quartile
FROM dw.fact_subscription f
JOIN dw.dim_contract dc ON dc.contract_key = f.contract_key
ORDER BY charge_rank
LIMIT 20;


-- 5c. Running total MRR by tenure month (cumulative revenue picture)
WITH tenure_mrr AS (
    SELECT
        dd.tenure_months,
        dd.tenure_bucket,
        COUNT(*)                                AS customers,
        ROUND(SUM(f.monthly_charges), 2)        AS mrr
    FROM dw.fact_subscription f
    JOIN dw.dim_date dd ON dd.date_key = f.date_key
    GROUP BY dd.tenure_months, dd.tenure_bucket
)
SELECT
    tenure_months,
    tenure_bucket,
    customers,
    mrr,
    SUM(mrr)      OVER (ORDER BY tenure_months)                     AS running_total_mrr,
    SUM(customers) OVER (ORDER BY tenure_months)                    AS running_total_customers,
    ROUND(
        mrr * 100.0 / SUM(mrr) OVER (), 2
    )                                                               AS pct_of_total_mrr
FROM tenure_mrr
ORDER BY tenure_months;


-- 5d. LAG / LEAD — compare each tenure bucket's churn rate to adjacent buckets
WITH bucket_churn AS (
    SELECT
        dd.tenure_bucket,
        MIN(dd.tenure_months)                                       AS min_tenure,
        COUNT(*)                                                    AS total_customers,
        COUNT(*) FILTER (WHERE f.is_churned)                        AS churned,
        ROUND(
            COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
        )                                                           AS churn_rate_pct
    FROM dw.fact_subscription f
    JOIN dw.dim_date dd ON dd.date_key = f.date_key
    GROUP BY dd.tenure_bucket
)
SELECT
    tenure_bucket,
    total_customers,
    churned,
    churn_rate_pct,
    LAG(churn_rate_pct)  OVER (ORDER BY min_tenure)                 AS prev_bucket_churn_pct,
    LEAD(churn_rate_pct) OVER (ORDER BY min_tenure)                 AS next_bucket_churn_pct,
    churn_rate_pct -
        LAG(churn_rate_pct) OVER (ORDER BY min_tenure)              AS churn_rate_change
FROM bucket_churn
ORDER BY min_tenure;


-- 5e. Percentile distribution of monthly charges
SELECT
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY monthly_charges)::NUMERIC, 2) AS p25_monthly,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY monthly_charges)::NUMERIC, 2) AS median_monthly,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY monthly_charges)::NUMERIC, 2) AS p75_monthly,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY monthly_charges)::NUMERIC, 2) AS p90_monthly,
    ROUND(AVG(monthly_charges)::NUMERIC, 2)                         AS mean_monthly,
    ROUND(STDDEV(monthly_charges)::NUMERIC, 2)                      AS stddev_monthly
FROM dw.fact_subscription;


-- 5f. Moving average of monthly charges across tenure (3-month window)
WITH tenure_avg AS (
    SELECT
        f.tenure_months,
        ROUND(AVG(f.monthly_charges), 2)        AS avg_monthly_charges,
        COUNT(*)                                AS customers
    FROM dw.fact_subscription f
    GROUP BY f.tenure_months
)
SELECT
    tenure_months,
    customers,
    avg_monthly_charges,
    ROUND(
        AVG(avg_monthly_charges) OVER (
            ORDER BY tenure_months
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                                               AS moving_avg_3m
FROM tenure_avg
ORDER BY tenure_months;


-- =============================================================================
-- SECTION 6: CTE-BASED ANALYTICAL QUERIES
-- Demonstrates multi-step reasoning with Common Table Expressions
-- =============================================================================

-- 6a. Full customer risk profile
-- Multi-step CTE: calculate metrics, assign risk, then summarize
WITH customer_metrics AS (
    SELECT
        f.customer_id,
        f.tenure_months,
        f.monthly_charges,
        f.estimated_clv,
        f.is_churned,
        f.mrr_at_risk,
        dc.contract_type,
        dc.payment_category,
        sp.internet_tier,
        sp.total_addons,
        dd.tenure_bucket,
        dd.is_new_customer,
        NTILE(5) OVER (ORDER BY f.monthly_charges DESC)             AS value_quintile
    FROM dw.fact_subscription f
    JOIN dw.dim_contract     dc ON dc.contract_key = f.contract_key
    JOIN dw.dim_service_plan sp ON sp.service_key  = f.service_key
    JOIN dw.dim_date         dd ON dd.date_key      = f.date_key
),
risk_labels AS (
    SELECT
        *,
        CASE
            WHEN is_churned                                         THEN 'Churned'
            WHEN contract_type = 'Month-to-month'
             AND is_new_customer
             AND value_quintile <= 2                                THEN 'High Risk'
            WHEN contract_type = 'Month-to-month'
             AND is_new_customer                                    THEN 'Medium Risk'
            WHEN contract_type != 'Month-to-month'
             AND value_quintile = 1                                 THEN 'High Value'
            ELSE 'Stable'
        END                                                         AS risk_segment
    FROM customer_metrics
)
SELECT
    risk_segment,
    COUNT(*)                                                        AS customers,
    ROUND(AVG(monthly_charges), 2)                                  AS avg_monthly_charges,
    ROUND(SUM(monthly_charges), 2)                                  AS total_mrr,
    ROUND(AVG(tenure_months), 1)                                    AS avg_tenure,
    ROUND(AVG(total_addons), 1)                                     AS avg_addons,
    ROUND(SUM(mrr_at_risk), 2)                                      AS mrr_at_risk
FROM risk_labels
GROUP BY risk_segment
ORDER BY total_mrr DESC;


-- 6b. Top 10 customer segments by revenue (contract + internet + payment)
WITH segment_revenue AS (
    SELECT
        dc.contract_type,
        sp.internet_tier,
        dc.payment_category,
        COUNT(*)                                AS customers,
        ROUND(SUM(f.monthly_charges), 2)        AS total_mrr,
        ROUND(AVG(f.monthly_charges), 2)        AS avg_monthly,
        COUNT(*) FILTER (WHERE f.is_churned)    AS churned,
        ROUND(
            COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2
        )                                       AS churn_rate_pct,
        ROUND(SUM(f.mrr_at_risk), 2)            AS mrr_at_risk
    FROM dw.fact_subscription f
    JOIN dw.dim_contract     dc ON dc.contract_key = f.contract_key
    JOIN dw.dim_service_plan sp ON sp.service_key  = f.service_key
    GROUP BY dc.contract_type, sp.internet_tier, dc.payment_category
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY total_mrr DESC)                 AS revenue_rank
    FROM segment_revenue
)
SELECT
    revenue_rank,
    contract_type,
    internet_tier,
    payment_category,
    customers,
    total_mrr,
    avg_monthly,
    churned,
    churn_rate_pct,
    mrr_at_risk
FROM ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;


-- 6c. Churn cohort analysis — which tenure bucket loses the most revenue?
WITH cohort AS (
    SELECT
        dd.tenure_bucket,
        MIN(dd.tenure_months)                       AS sort_key,
        COUNT(*)                                    AS total_customers,
        COUNT(*) FILTER (WHERE f.is_churned)        AS churned_customers,
        ROUND(SUM(f.monthly_charges), 2)            AS total_mrr,
        ROUND(SUM(f.mrr_at_risk), 2)                AS mrr_at_risk,
        ROUND(AVG(f.estimated_clv), 2)              AS avg_clv
    FROM dw.fact_subscription f
    JOIN dw.dim_date dd ON dd.date_key = f.date_key
    GROUP BY dd.tenure_bucket
),
with_pct AS (
    SELECT
        *,
        ROUND(churned_customers * 100.0 / NULLIF(total_customers, 0), 2) AS churn_rate_pct,
        ROUND(mrr_at_risk * 100.0 / NULLIF(SUM(mrr_at_risk) OVER (), 0), 2) AS pct_of_total_risk
    FROM cohort
)
SELECT
    tenure_bucket,
    total_customers,
    churned_customers,
    churn_rate_pct,
    total_mrr,
    mrr_at_risk,
    pct_of_total_risk,
    avg_clv
FROM with_pct
ORDER BY sort_key;


-- 6d. Service stickiness analysis
-- Which services are associated with lower churn?
SELECT
    'Tech Support'      AS service_name,
    tech_support        AS subscribed,
    COUNT(*)            AS customers,
    ROUND(COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY tech_support

UNION ALL

SELECT
    'Online Security',
    online_security,
    COUNT(*),
    ROUND(COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2)
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY online_security

UNION ALL

SELECT
    'Online Backup',
    online_backup,
    COUNT(*),
    ROUND(COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2)
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY online_backup

UNION ALL

SELECT
    'Device Protection',
    device_protection,
    COUNT(*),
    ROUND(COUNT(*) FILTER (WHERE f.is_churned) * 100.0 / COUNT(*), 2)
FROM dw.fact_subscription f
JOIN dw.dim_service_plan sp ON sp.service_key = f.service_key
GROUP BY device_protection

ORDER BY service_name, subscribed;
