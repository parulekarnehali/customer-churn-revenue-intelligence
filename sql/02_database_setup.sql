-- =============================================================================
-- Step 3: PostgreSQL Database Setup
-- Project: Customer Churn & Revenue Intelligence Platform
-- Run this as a superuser (postgres) in psql or DBeaver
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Create the database
--    Run this block OUTSIDE any existing database connection (e.g. connected
--    to the default 'postgres' database first)
-- -----------------------------------------------------------------------------

CREATE DATABASE customer_analytics
    WITH
    OWNER     = postgres
    ENCODING  = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE   = 'en_US.UTF-8'
    TEMPLATE  = template0;

COMMENT ON DATABASE customer_analytics
    IS 'Customer Churn & Revenue Intelligence Platform — Telco dataset';


-- =============================================================================
-- CONNECT TO customer_analytics BEFORE RUNNING ANYTHING BELOW
-- In psql:       \c customer_analytics
-- In DBeaver:    Switch your active connection to customer_analytics
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 2. Create schemas
--    raw      → untouched CSV import, no transformations
--    staging  → cleaned and standardized data
--    dw       → star schema (fact + dimension tables)
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS raw
    AUTHORIZATION postgres;

CREATE SCHEMA IF NOT EXISTS staging
    AUTHORIZATION postgres;

CREATE SCHEMA IF NOT EXISTS dw
    AUTHORIZATION postgres;

COMMENT ON SCHEMA raw     IS 'Raw ingestion layer — source data loaded as-is';
COMMENT ON SCHEMA staging IS 'Cleaned and standardized data, pre-warehouse';
COMMENT ON SCHEMA dw      IS 'Data warehouse — star schema for analytics';


-- -----------------------------------------------------------------------------
-- 3. Create the raw table
--    All columns are TEXT at this stage — no casting, no constraints.
--    The goal is to get the data in exactly as it came from the CSV.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS raw.customer_churn;

CREATE TABLE raw.customer_churn (
    customerid           TEXT,
    gender               TEXT,
    seniorcitizen        TEXT,
    partner              TEXT,
    dependents           TEXT,
    tenure               TEXT,
    phoneservice         TEXT,
    multiplelines        TEXT,
    internetservice      TEXT,
    onlinesecurity       TEXT,
    onlinebackup         TEXT,
    deviceprotection     TEXT,
    techsupport          TEXT,
    streamingtv          TEXT,
    streamingmovies      TEXT,
    contract             TEXT,
    paperlessbilling     TEXT,
    paymentmethod        TEXT,
    monthlycharges       TEXT,
    totalcharges         TEXT,
    churn                TEXT
);

COMMENT ON TABLE raw.customer_churn IS
    'Raw import of Telco-Customer-Churn.csv — no transformations applied';


-- -----------------------------------------------------------------------------
-- 4. Verify schemas were created
-- -----------------------------------------------------------------------------

SELECT
    schema_name,
    schema_owner
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'staging', 'dw')
ORDER BY schema_name;
