-- =============================================================================
-- Step 6b: Star Schema — ETL (staging → dw)
-- Project: Customer Churn & Revenue Intelligence Platform
-- =============================================================================
-- Run this AFTER 06a_star_schema_ddl.sql has been executed.
-- Populates all dimension tables first, then the fact table.
-- Order matters: fact table depends on all dimension keys.
-- =============================================================================


-- =============================================================================
-- DIMENSION 1: dim_customer
-- =============================================================================

INSERT INTO dw.dim_customer (
    customer_id,
    gender,
    senior_citizen,
    partner,
    dependents,
    household_type,
    senior_segment
)
SELECT DISTINCT
    customer_id,
    gender,
    senior_citizen,
    partner,
    dependents,

    -- Derived: household_type combines partner + dependents
    CASE
        WHEN partner = 'Yes' AND dependents = 'Yes' THEN 'Family'
        WHEN partner = 'Yes' AND dependents = 'No'  THEN 'Couple No Dependents'
        WHEN partner = 'No'  AND dependents = 'Yes' THEN 'Single With Dependents'
        WHEN partner = 'No'  AND dependents = 'No'  THEN 'Single No Dependents'
        ELSE 'Unknown'
    END AS household_type,

    -- Derived: senior_segment
    CASE senior_citizen
        WHEN 'Yes' THEN 'Senior'
        ELSE 'Non-Senior'
    END AS senior_segment

FROM staging.customer_churn
ORDER BY customer_id;


-- Verify
SELECT COUNT(*) AS dim_customer_rows FROM dw.dim_customer;   -- expect 7,043


-- =============================================================================
-- DIMENSION 2: dim_contract
-- =============================================================================

INSERT INTO dw.dim_contract (
    contract_type,
    payment_method,
    paperless_billing,

    -- Derived: payment_category — automatic vs manual
    payment_category,
    contract_length
)
SELECT DISTINCT
    contract_type,
    payment_method,
    paperless_billing,

    CASE
        WHEN payment_method ILIKE '%automatic%' THEN 'Automatic'
        ELSE 'Manual'
    END AS payment_category,

    CASE contract_type
        WHEN 'Month-to-month' THEN 'Monthly'
        WHEN 'One year'       THEN 'Annual'
        WHEN 'Two year'       THEN 'Two-Year'
        ELSE 'Unknown'
    END AS contract_length

FROM staging.customer_churn
ORDER BY contract_type, payment_method;


-- Verify
SELECT COUNT(*) AS dim_contract_rows FROM dw.dim_contract;   -- expect ~12 unique combos
SELECT * FROM dw.dim_contract ORDER BY contract_key;


-- =============================================================================
-- DIMENSION 3: dim_service_plan
-- =============================================================================

INSERT INTO dw.dim_service_plan (
    phone_service,
    multiple_lines,
    internet_service,
    online_security,
    online_backup,
    device_protection,
    tech_support,
    streaming_tv,
    streaming_movies,
    total_addons,
    internet_tier
)
SELECT DISTINCT
    phone_service,
    multiple_lines,
    internet_service,
    online_security,
    online_backup,
    device_protection,
    tech_support,
    streaming_tv,
    streaming_movies,

    -- Count of active add-on services (Yes only, not No/No internet service)
    (
        CASE WHEN multiple_lines     = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN online_security    = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN online_backup      = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN device_protection  = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN tech_support       = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN streaming_tv       = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN streaming_movies   = 'Yes' THEN 1 ELSE 0 END
    ) AS total_addons,

    -- Internet tier simplification
    CASE internet_service
        WHEN 'Fiber optic' THEN 'Fiber Optic'
        WHEN 'DSL'         THEN 'DSL'
        WHEN 'No'          THEN 'No Internet'
        ELSE 'Unknown'
    END AS internet_tier

FROM staging.customer_churn
ORDER BY internet_service, phone_service;


-- Verify
SELECT COUNT(*) AS dim_service_rows FROM dw.dim_service_plan;   -- ~60-80 unique combos
SELECT internet_tier, COUNT(*) FROM dw.dim_service_plan GROUP BY internet_tier;


-- =============================================================================
-- DIMENSION 4: dim_date (tenure-based)
-- =============================================================================

INSERT INTO dw.dim_date (
    date_key,
    tenure_months,
    tenure_bucket,
    tenure_year,
    is_new_customer,
    is_long_term
)
SELECT
    gs.tenure_val                                   AS date_key,
    gs.tenure_val                                   AS tenure_months,

    -- Bucket tenure into 12-month bands
    CASE
        WHEN gs.tenure_val BETWEEN  0 AND 12 THEN '0-12 months'
        WHEN gs.tenure_val BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN gs.tenure_val BETWEEN 25 AND 36 THEN '25-36 months'
        WHEN gs.tenure_val BETWEEN 37 AND 48 THEN '37-48 months'
        WHEN gs.tenure_val BETWEEN 49 AND 60 THEN '49-60 months'
        ELSE '61+ months'
    END                                             AS tenure_bucket,

    -- Year of tenure (1-indexed)
    CEIL(GREATEST(gs.tenure_val, 1) / 12.0)::INTEGER  AS tenure_year,

    -- Flags
    (gs.tenure_val <= 12)                           AS is_new_customer,
    (gs.tenure_val >= 48)                           AS is_long_term

FROM generate_series(0, 72) AS gs(tenure_val);


-- Verify
SELECT COUNT(*) AS dim_date_rows FROM dw.dim_date;   -- expect 73 rows (0 through 72)
SELECT * FROM dw.dim_date ORDER BY date_key LIMIT 15;


-- =============================================================================
-- FACT TABLE: fact_subscription
-- Join staging back to each dimension to get surrogate keys
-- =============================================================================

INSERT INTO dw.fact_subscription (
    customer_key,
    contract_key,
    service_key,
    date_key,
    customer_id,
    tenure_months,
    monthly_charges,
    total_charges,
    estimated_clv,
    mrr_at_risk,
    churn,
    is_churned
)
SELECT
    dc.customer_key,
    dcon.contract_key,
    dsp.service_key,
    dd.date_key,

    s.customer_id,
    s.tenure_months,
    s.monthly_charges,
    s.total_charges,

    -- Estimated CLV: monthly charges * tenure (simple approximation)
    -- NULL when total_charges is NULL (tenure = 0 customers)
    CASE
        WHEN s.total_charges IS NOT NULL
        THEN ROUND(s.monthly_charges * s.tenure_months, 2)
        ELSE NULL
    END                                             AS estimated_clv,

    -- MRR at risk: revenue exposed if this customer churns
    -- Populated only for churned customers
    CASE
        WHEN s.churn = 'Yes' THEN s.monthly_charges
        ELSE NULL
    END                                             AS mrr_at_risk,

    s.churn,
    (s.churn = 'Yes')                               AS is_churned

FROM staging.customer_churn s

-- Lookup customer_key
JOIN dw.dim_customer dc
    ON dc.customer_id = s.customer_id

-- Lookup contract_key
JOIN dw.dim_contract dcon
    ON  dcon.contract_type     = s.contract_type
    AND dcon.payment_method    = s.payment_method
    AND dcon.paperless_billing = s.paperless_billing

-- Lookup service_key
JOIN dw.dim_service_plan dsp
    ON  dsp.phone_service     = s.phone_service
    AND dsp.multiple_lines    = s.multiple_lines
    AND dsp.internet_service  = s.internet_service
    AND dsp.online_security   = s.online_security
    AND dsp.online_backup     = s.online_backup
    AND dsp.device_protection = s.device_protection
    AND dsp.tech_support      = s.tech_support
    AND dsp.streaming_tv      = s.streaming_tv
    AND dsp.streaming_movies  = s.streaming_movies

-- Lookup date_key
JOIN dw.dim_date dd
    ON  dd.date_key = s.tenure_months;


-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Row count (expect 7,043)
SELECT COUNT(*) AS fact_rows FROM dw.fact_subscription;


-- Churn flag consistency — is_churned must match churn column
SELECT
    churn,
    is_churned,
    COUNT(*) AS count
FROM dw.fact_subscription
GROUP BY churn, is_churned
ORDER BY churn;


-- MRR at risk total
SELECT
    ROUND(SUM(mrr_at_risk), 2)      AS total_mrr_at_risk,
    COUNT(*) FILTER (WHERE is_churned) AS churned_customers
FROM dw.fact_subscription;


-- Revenue summary by contract type (quick sanity check)
SELECT
    dcon.contract_type,
    COUNT(*)                                AS customers,
    ROUND(SUM(f.monthly_charges), 2)        AS total_mrr,
    ROUND(AVG(f.monthly_charges), 2)        AS avg_monthly,
    SUM(CASE WHEN f.is_churned THEN 1 ELSE 0 END) AS churned
FROM dw.fact_subscription f
JOIN dw.dim_contract dcon ON dcon.contract_key = f.contract_key
GROUP BY dcon.contract_type
ORDER BY total_mrr DESC;


-- Dimension key integrity check — any orphaned fact rows?
SELECT
    COUNT(*) FILTER (WHERE customer_key NOT IN (SELECT customer_key FROM dw.dim_customer))  AS orphan_customer,
    COUNT(*) FILTER (WHERE contract_key NOT IN (SELECT contract_key FROM dw.dim_contract))  AS orphan_contract,
    COUNT(*) FILTER (WHERE service_key  NOT IN (SELECT service_key  FROM dw.dim_service_plan)) AS orphan_service,
    COUNT(*) FILTER (WHERE date_key     NOT IN (SELECT date_key     FROM dw.dim_date))      AS orphan_date
FROM dw.fact_subscription;
-- All four should return 0


-- Final table summary
SELECT
    'dim_customer'    AS table_name, COUNT(*) AS row_count FROM dw.dim_customer    UNION ALL
SELECT 'dim_contract',               COUNT(*) FROM dw.dim_contract                UNION ALL
SELECT 'dim_service_plan',           COUNT(*) FROM dw.dim_service_plan             UNION ALL
SELECT 'dim_date',                   COUNT(*) FROM dw.dim_date                    UNION ALL
SELECT 'fact_subscription',          COUNT(*) FROM dw.fact_subscription
ORDER BY table_name;
