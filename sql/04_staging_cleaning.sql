-- =============================================================================
-- Step 5: Data Cleaning — raw → staging
-- Project: Customer Churn & Revenue Intelligence Platform
-- =============================================================================
-- This script creates staging.customer_churn by selecting from raw.customer_churn
-- and applying all necessary cleaning transformations.
-- The raw table is never modified.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Create the staging table with correct data types
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS staging.customer_churn;

CREATE TABLE staging.customer_churn (
    -- Identity
    customer_id          VARCHAR(20)     NOT NULL,

    -- Demographics
    gender               VARCHAR(10)     NOT NULL,
    senior_citizen       VARCHAR(3)      NOT NULL,   -- converted from 0/1 to Yes/No
    partner              VARCHAR(3)      NOT NULL,
    dependents           VARCHAR(3)      NOT NULL,

    -- Account info
    tenure_months        INTEGER         NOT NULL,
    contract_type        VARCHAR(30)     NOT NULL,
    paperless_billing    VARCHAR(3)      NOT NULL,
    payment_method       VARCHAR(50)     NOT NULL,

    -- Services
    phone_service        VARCHAR(3)      NOT NULL,
    multiple_lines       VARCHAR(20)     NOT NULL,
    internet_service     VARCHAR(20)     NOT NULL,
    online_security      VARCHAR(20)     NOT NULL,
    online_backup        VARCHAR(20)     NOT NULL,
    device_protection    VARCHAR(20)     NOT NULL,
    tech_support         VARCHAR(20)     NOT NULL,
    streaming_tv         VARCHAR(20)     NOT NULL,
    streaming_movies     VARCHAR(20)     NOT NULL,

    -- Financials
    monthly_charges      NUMERIC(10, 2)  NOT NULL,
    total_charges        NUMERIC(10, 2)  NULL,       -- NULL for tenure = 0 customers

    -- Target
    churn                VARCHAR(3)      NOT NULL,

    -- Audit
    loaded_at            TIMESTAMP       NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE staging.customer_churn IS
    'Cleaned and typed version of raw.customer_churn. Source: IBM Telco Churn dataset.';


-- -----------------------------------------------------------------------------
-- 2. Insert cleaned data
-- -----------------------------------------------------------------------------

INSERT INTO staging.customer_churn (
    customer_id,
    gender,
    senior_citizen,
    partner,
    dependents,
    tenure_months,
    contract_type,
    paperless_billing,
    payment_method,
    phone_service,
    multiple_lines,
    internet_service,
    online_security,
    online_backup,
    device_protection,
    tech_support,
    streaming_tv,
    streaming_movies,
    monthly_charges,
    total_charges,
    churn
)
SELECT
    -- Identity
    TRIM(customerid)                                            AS customer_id,

    -- Demographics
    TRIM(gender)                                               AS gender,

    -- SeniorCitizen: stored as '0'/'1' in raw — convert to Yes/No
    CASE TRIM(seniorcitizen)
        WHEN '1' THEN 'Yes'
        WHEN '0' THEN 'No'
        ELSE NULL
    END                                                        AS senior_citizen,

    TRIM(partner)                                              AS partner,
    TRIM(dependents)                                           AS dependents,

    -- Account info
    CAST(TRIM(tenure) AS INTEGER)                              AS tenure_months,
    TRIM(contract)                                             AS contract_type,
    TRIM(paperlessbilling)                                     AS paperless_billing,
    TRIM(paymentmethod)                                        AS payment_method,

    -- Services
    TRIM(phoneservice)                                         AS phone_service,
    TRIM(multiplelines)                                        AS multiple_lines,
    TRIM(internetservice)                                      AS internet_service,
    TRIM(onlinesecurity)                                       AS online_security,
    TRIM(onlinebackup)                                         AS online_backup,
    TRIM(deviceprotection)                                     AS device_protection,
    TRIM(techsupport)                                          AS tech_support,
    TRIM(streamingtv)                                          AS streaming_tv,
    TRIM(streamingmovies)                                      AS streaming_movies,

    -- Financials
    CAST(TRIM(monthlycharges) AS NUMERIC(10, 2))               AS monthly_charges,

    -- TotalCharges: blank strings → NULL, then cast to numeric
    CASE
        WHEN TRIM(totalcharges) = '' OR totalcharges IS NULL THEN NULL
        ELSE CAST(TRIM(totalcharges) AS NUMERIC(10, 2))
    END                                                        AS total_charges,

    -- Target
    TRIM(churn)                                                AS churn

FROM raw.customer_churn;


-- -----------------------------------------------------------------------------
-- 3. Add primary key constraint
-- -----------------------------------------------------------------------------

ALTER TABLE staging.customer_churn
    ADD CONSTRAINT pk_staging_customer_churn
    PRIMARY KEY (customer_id);


-- -----------------------------------------------------------------------------
-- 4. Add useful indexes for downstream queries
-- -----------------------------------------------------------------------------

CREATE INDEX idx_staging_churn        ON staging.customer_churn (churn);
CREATE INDEX idx_staging_contract     ON staging.customer_churn (contract_type);
CREATE INDEX idx_staging_tenure       ON staging.customer_churn (tenure_months);
CREATE INDEX idx_staging_internet     ON staging.customer_churn (internet_service);
CREATE INDEX idx_staging_payment      ON staging.customer_churn (payment_method);


-- =============================================================================
-- 5. Validation queries — run these after the INSERT to confirm data quality
-- =============================================================================

-- 5a. Row count (expect 7,043)
SELECT COUNT(*) AS total_rows
FROM staging.customer_churn;


-- 5b. NULL check across all columns
SELECT
    COUNT(*) FILTER (WHERE customer_id       IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE gender            IS NULL) AS null_gender,
    COUNT(*) FILTER (WHERE senior_citizen    IS NULL) AS null_senior_citizen,
    COUNT(*) FILTER (WHERE tenure_months     IS NULL) AS null_tenure,
    COUNT(*) FILTER (WHERE contract_type     IS NULL) AS null_contract,
    COUNT(*) FILTER (WHERE monthly_charges   IS NULL) AS null_monthly_charges,
    COUNT(*) FILTER (WHERE total_charges     IS NULL) AS null_total_charges,  -- expect 11
    COUNT(*) FILTER (WHERE churn             IS NULL) AS null_churn
FROM staging.customer_churn;


-- 5c. SeniorCitizen conversion check (should only be Yes/No, no 0/1 left)
SELECT senior_citizen, COUNT(*) AS count
FROM staging.customer_churn
GROUP BY senior_citizen
ORDER BY senior_citizen;


-- 5d. TotalCharges NULL rows — confirm they are all tenure = 0 customers
SELECT
    customer_id,
    tenure_months,
    monthly_charges,
    total_charges
FROM staging.customer_churn
WHERE total_charges IS NULL
ORDER BY customer_id;


-- 5e. Numeric range checks
SELECT
    MIN(tenure_months)    AS min_tenure,
    MAX(tenure_months)    AS max_tenure,
    MIN(monthly_charges)  AS min_monthly,
    MAX(monthly_charges)  AS max_monthly,
    MIN(total_charges)    AS min_total,
    MAX(total_charges)    AS max_total
FROM staging.customer_churn;


-- 5f. Churn distribution (expect ~26% Yes)
SELECT
    churn,
    COUNT(*)                                               AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)    AS pct_of_total
FROM staging.customer_churn
GROUP BY churn
ORDER BY churn;


-- 5g. Contract type breakdown
SELECT
    contract_type,
    COUNT(*)                                               AS customer_count,
    ROUND(AVG(monthly_charges), 2)                        AS avg_monthly_charges,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)    AS pct_of_total
FROM staging.customer_churn
GROUP BY contract_type
ORDER BY contract_type;


-- 5h. Payment method breakdown
SELECT
    payment_method,
    COUNT(*) AS customer_count
FROM staging.customer_churn
GROUP BY payment_method
ORDER BY customer_count DESC;
