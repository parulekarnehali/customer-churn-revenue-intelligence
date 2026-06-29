-- =============================================================================
-- Step 6a: Star Schema — DDL
-- Project: Customer Churn & Revenue Intelligence Platform
-- Schema: dw
-- =============================================================================
-- Run this connected to customer_analytics database.
-- Creates all dimension tables first, then the fact table with FK constraints.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- DIMENSION 1: dim_customer
-- Descriptive attributes about the customer as a person
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS dw.fact_subscription;   -- drop fact first (has FKs)
DROP TABLE IF EXISTS dw.dim_customer;
DROP TABLE IF EXISTS dw.dim_contract;
DROP TABLE IF EXISTS dw.dim_service_plan;
DROP TABLE IF EXISTS dw.dim_date;

CREATE TABLE dw.dim_customer (
    customer_key         SERIAL          PRIMARY KEY,
    customer_id          VARCHAR(20)     NOT NULL UNIQUE,   -- natural key
    gender               VARCHAR(10)     NOT NULL,
    senior_citizen       VARCHAR(3)      NOT NULL,
    partner              VARCHAR(3)      NOT NULL,
    dependents           VARCHAR(3)      NOT NULL,

    -- Derived segments
    household_type       VARCHAR(30)     NOT NULL,  -- e.g. 'Single No Dependents'
    senior_segment       VARCHAR(20)     NOT NULL   -- 'Senior' / 'Non-Senior'
);

COMMENT ON TABLE dw.dim_customer IS
    'Customer demographic dimension. One row per customer.';


-- -----------------------------------------------------------------------------
-- DIMENSION 2: dim_contract
-- Contract and billing attributes
-- -----------------------------------------------------------------------------

CREATE TABLE dw.dim_contract (
    contract_key         SERIAL          PRIMARY KEY,
    contract_type        VARCHAR(30)     NOT NULL,
    payment_method       VARCHAR(50)     NOT NULL,
    paperless_billing    VARCHAR(3)      NOT NULL,

    -- Derived
    payment_category     VARCHAR(20)     NOT NULL,  -- 'Automatic' / 'Manual'
    contract_length      VARCHAR(20)     NOT NULL   -- 'Monthly' / 'Annual' / 'Two-Year'
);

COMMENT ON TABLE dw.dim_contract IS
    'Contract and payment dimension. One row per unique contract+payment combination.';


-- -----------------------------------------------------------------------------
-- DIMENSION 3: dim_service_plan
-- All service subscriptions the customer has
-- -----------------------------------------------------------------------------

CREATE TABLE dw.dim_service_plan (
    service_key          SERIAL          PRIMARY KEY,
    phone_service        VARCHAR(3)      NOT NULL,
    multiple_lines       VARCHAR(20)     NOT NULL,
    internet_service     VARCHAR(20)     NOT NULL,
    online_security      VARCHAR(20)     NOT NULL,
    online_backup        VARCHAR(20)     NOT NULL,
    device_protection    VARCHAR(20)     NOT NULL,
    tech_support         VARCHAR(20)     NOT NULL,
    streaming_tv         VARCHAR(20)     NOT NULL,
    streaming_movies     VARCHAR(20)     NOT NULL,

    -- Derived
    total_addons         INTEGER         NOT NULL,  -- count of active add-on services
    internet_tier        VARCHAR(20)     NOT NULL   -- 'No Internet' / 'DSL' / 'Fiber Optic'
);

COMMENT ON TABLE dw.dim_service_plan IS
    'Service subscription dimension. One row per unique combination of services.';


-- -----------------------------------------------------------------------------
-- DIMENSION 4: dim_date
-- Tenure-based date dimension (months as the grain)
-- Note: This dataset has no real calendar dates, so we use tenure as a proxy.
-- -----------------------------------------------------------------------------

CREATE TABLE dw.dim_date (
    date_key             INTEGER         PRIMARY KEY,   -- same as tenure_months value
    tenure_months        INTEGER         NOT NULL,
    tenure_bucket        VARCHAR(20)     NOT NULL,      -- '0-12', '13-24', etc.
    tenure_year          INTEGER         NOT NULL,      -- year 1, 2, 3, 4, 5, 6
    is_new_customer      BOOLEAN         NOT NULL,      -- tenure <= 12
    is_long_term         BOOLEAN         NOT NULL       -- tenure >= 48
);

COMMENT ON TABLE dw.dim_date IS
    'Tenure-based date dimension. date_key = tenure_months value (0-72).';


-- -----------------------------------------------------------------------------
-- FACT TABLE: fact_subscription
-- One row per customer. Stores measurable values and FK references.
-- -----------------------------------------------------------------------------

CREATE TABLE dw.fact_subscription (
    subscription_key     SERIAL          PRIMARY KEY,

    -- Foreign keys to dimensions
    customer_key         INTEGER         NOT NULL REFERENCES dw.dim_customer    (customer_key),
    contract_key         INTEGER         NOT NULL REFERENCES dw.dim_contract    (contract_key),
    service_key          INTEGER         NOT NULL REFERENCES dw.dim_service_plan(service_key),
    date_key             INTEGER         NOT NULL REFERENCES dw.dim_date        (date_key),

    -- Natural key (for traceability back to staging)
    customer_id          VARCHAR(20)     NOT NULL,

    -- Measures
    tenure_months        INTEGER         NOT NULL,
    monthly_charges      NUMERIC(10, 2)  NOT NULL,
    total_charges        NUMERIC(10, 2)  NULL,          -- NULL for tenure = 0

    -- Derived measures
    estimated_clv        NUMERIC(12, 2)  NULL,          -- monthly_charges * tenure_months
    mrr_at_risk          NUMERIC(10, 2)  NULL,          -- monthly_charges if churned, else NULL

    -- Target flag
    churn                VARCHAR(3)      NOT NULL,
    is_churned           BOOLEAN         NOT NULL,       -- TRUE/FALSE version of churn

    -- Audit
    loaded_at            TIMESTAMP       NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE dw.fact_subscription IS
    'Subscription fact table. Grain = one row per customer. All measures are current-state.';


-- -----------------------------------------------------------------------------
-- Indexes on the fact table for query performance
-- -----------------------------------------------------------------------------

CREATE INDEX idx_fact_customer_key  ON dw.fact_subscription (customer_key);
CREATE INDEX idx_fact_contract_key  ON dw.fact_subscription (contract_key);
CREATE INDEX idx_fact_service_key   ON dw.fact_subscription (service_key);
CREATE INDEX idx_fact_date_key      ON dw.fact_subscription (date_key);
CREATE INDEX idx_fact_is_churned    ON dw.fact_subscription (is_churned);
CREATE INDEX idx_fact_customer_id   ON dw.fact_subscription (customer_id);


-- -----------------------------------------------------------------------------
-- Verify all tables were created
-- -----------------------------------------------------------------------------

SELECT
    table_schema,
    table_name,
    obj_description(
        (table_schema || '.' || table_name)::regclass, 'pg_class'
    ) AS description
FROM information_schema.tables
WHERE table_schema = 'dw'
ORDER BY table_name;
