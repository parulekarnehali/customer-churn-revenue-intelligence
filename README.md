# Customer Churn & Revenue Intelligence Platform

> An end-to-end analytics project covering data ingestion, warehouse design, SQL analysis, Python EDA, and a Tableau story dashboard — built on the IBM Telco Customer Churn dataset.

**[View Live Dashboard on Tableau Public](<insert-your-tableau-public-link-here>)**

---

## Project Summary

This project answers a core business question: *which customers are likely to leave, what revenue is at risk, and where should retention efforts focus?*

It is structured as a full analytics pipeline — from raw CSV to a stakeholder-ready Tableau story — using the same layered approach used in production data environments.

| Metric | Value |
|--------|-------|
| Total Customers | 7,043 |
| Overall Churn Rate | 26.5% |
| Monthly Recurring Revenue (MRR) | $456.1K |
| MRR at Risk | $139.1K |
| High-Risk Customers | 970 |
| Average Customer Lifetime Value | $2,279.6 |
| Average Tenure | 32.4 months |

---

## Repository Structure

```
customer-churn-revenue-intelligence/
│
├── data/
│   └── WA_Fn-UseC_-Telco-Customer-Churn.csv     # Source dataset (Kaggle / IBM)
│
├── sql/
│   ├── 02_database_setup.sql                     # DB + schema creation (raw, staging, dw)
│   ├── 04_staging_cleaning.sql                   # Cleaning and type casting into staging layer
│   ├── 06a_star_schema_ddl.sql                   # Star schema DDL (dim + fact tables)
│   ├── 06b_star_schema_etl.sql                   # ETL from staging into dw schema
│   └── 07_sql_analyses.sql                       # 20 analytical queries across 6 sections
│
├── python/
│   ├── 01_data_inspection.py                     # Initial data profiling (12 checks)
│   ├── 03_load_raw_data.py                       # CSV loader into raw.customer_churn
│   ├── 05_staging_validation.py                  # Row count, type, and distribution checks
│   └── 08_eda_analysis.py                        # EDA with distributions, correlations, charts
│
├── eda_charts/
│   ├── 01_distributions.png
│   ├── 02_churn_by_category.png
│   ├── 03_boxplots_charges.png
│   ├── 04_outlier_detection.png
│   ├── 05_correlation_heatmap.png
│   ├── 06_tenure_vs_charges_scatter.png
│   └── 07_addon_stickiness.png
│
├── dashboard/
│   └── Customer_Churn_Revenue_Intelligence.twbx  # Tableau packaged workbook
│
├── docs/
│   └── Customer_Churn_Dashboard_Documentation.docx
│
└── README.md
```

---

## Pipeline Architecture

```
Raw CSV
   |
   v
[raw.customer_churn]          -- Unmodified source, audit trail
   |
   v
[staging.customer_churn]      -- Cleaned: types cast, blanks handled, SeniorCitizen normalized
   |
   v
[dw schema - Star Schema]     -- dim_customer, dim_contract, dim_service_plan, dim_date, fact_subscription
   |
   v
[Tableau Desktop]             -- Connected to dw schema via PostgreSQL
   |
   v
[Tableau Public]              -- Published story dashboard
```

The three-schema design (raw > staging > dw) mirrors production data warehouse patterns. Raw is the audit trail, staging is where all transformations happen, and dw is the query layer.

---

## Star Schema

```
                   dim_customer
                        |
dim_contract ---- fact_subscription ---- dim_service_plan
                        |
                     dim_date
```

| Table | Rows | Description |
|-------|------|-------------|
| dim_customer | 7,043 | Demographics: gender, senior citizen, partner, dependents |
| dim_contract | ~12 | Unique contract type + payment method combinations |
| dim_service_plan | ~65 | Unique service flag combinations across 8 service types |
| dim_date | 73 | Tenure values 0-72, bucketed into cohort ranges |
| fact_subscription | 7,043 | One row per customer with all measures and FK keys |

---

## Key Data Findings (from inspection and EDA)

**Three data quality issues found and handled:**

1. `TotalCharges` is stored as text with 11 blank rows where `tenure = 0`. Converted to NUMERIC; blanks set to NULL (not 0, to avoid corrupting revenue aggregations).
2. `SeniorCitizen` is 0/1 integer while all other binary columns are Yes/No. Normalized to Yes/No in the staging layer.
3. No duplicate customer records. Dataset is already deduplicated at the customer level.

---

## Key Business Findings

**Contract type is the strongest churn predictor:**
- Month-to-month: 42.7% churn rate
- One-year: 11.3% churn rate
- Two-year: 2.8% churn rate
- Month-to-month contracts account for $120,847 of the $139.1K total MRR at risk

**Internet service drives churn:**
- Fiber optic customers churn at ~30%, nearly double the DSL rate
- Month-to-month + fiber optic combination: 57.9% churn rate
- Fiber optic customers pay the highest monthly charges despite churning most

**Payment method matters:**
- Electronic check payers churn at 45.3%
- Automatic payment methods (bank transfer, credit card auto) churn at ~15%

**Add-on services reduce churn significantly:**
- 0 add-ons: 37.7% churn
- 3 add-ons: 31.3% churn
- 6+ add-ons: 5.3% churn
- The inverse relationship holds across all 8 service types

**Early tenure is the highest-risk window:**
- 0-12 month customers churn at ~47%
- Churn decreases steadily with tenure
- Customers past 37 months are significantly more stable

**Retention opportunity:**
- 970 high-risk customers on month-to-month contracts
- 125 are Priority 1 (immediate outreach)
- Retaining this group represents $47.8K/month in recoverable MRR

---

## SQL Analyses (07_sql_analyses.sql)

The analytical SQL file covers 20 queries across 6 sections:

| Section | Focus | SQL Techniques |
|---------|-------|----------------|
| 1 | Executive KPIs | FILTER, NULLIF, aggregations |
| 2 | Churn analysis | Multi-table JOINs, conditional aggregation |
| 3 | Revenue analysis | SUM, AVG, revenue segmentation |
| 4 | Customer segmentation | NTILE, CTEs, CROSS JOIN |
| 5 | Window functions | ROW_NUMBER, RANK, NTILE, LAG, LEAD, PERCENTILE_CONT, moving average |
| 6 | CTE analyses | Multi-step CTEs, UNION ALL, nested WITH blocks |

---

## Python EDA Charts

| Chart | Insight |
|-------|---------|
| Distributions by churn status | Churned customers cluster in low-tenure, high-charge range |
| Churn rate by category | Month-to-month and electronic check stand out immediately |
| Box plots by contract type | Two-year customers have tighter, lower charge distributions |
| Outlier detection (IQR) | No extreme outliers -- data is clean for Tableau |
| Correlation heatmap | Month-to-month and fiber optic are the two strongest churn predictors |
| Tenure vs charges scatter | Churned customers concentrate in top-left: short tenure, high charges |
| Add-on stickiness | Every additional service reduces churn linearly |

---

## Tableau Dashboard Tabs

| Tab | Description |
|-----|-------------|
| Overview | KPI summary: churn rate, MRR, MRR at risk, avg CLV, avg tenure. Churn by contract type and MRR at risk breakdown. |
| Churn | Churn rate by contract type, internet service, payment method, tenure bucket, and a contract x internet cross-tab. Filterable by demographics and tenure. |
| Revenue | MRR and avg CLV by contract type and internet tier. Monthly charges distribution and revenue concentration scatter. |
| Segments | Risk segmentation (Churned / High / Medium / Low). Household type, senior vs non-senior, churn by add-on count, segment revenue table. |
| Services | Subscriber vs non-subscriber churn across 8 service types. Service adoption rates and avg monthly charges by internet type and contract. |
| Explorer & Retention | Actionable retention view. 970 high-risk customers, $47.8K/month MRR at risk. Customer-level detail table with priority flags and estimated revenue recovery. |

---

## Tools and Technologies

| Layer | Tool |
|-------|------|
| Database | PostgreSQL (local) |
| Data modeling | Star schema (dw schema) |
| ETL / cleaning | SQL (T-SQL style), Python (Pandas) |
| EDA | Python: Pandas, NumPy, Matplotlib, Seaborn, SciPy |
| Visualization | Tableau Desktop, Tableau Public |
| Dataset | IBM Telco Customer Churn (public, via Kaggle) |

---

## How to Reproduce This Project

**Prerequisites:** PostgreSQL installed locally, Python 3.8+, Tableau Desktop

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/customer-churn-revenue-intelligence.git
cd customer-churn-revenue-intelligence

# 2. Install Python dependencies
pip install pandas numpy matplotlib seaborn scipy psycopg2-binary

# 3. Run data inspection
python python/01_data_inspection.py

# 4. Set up the database (run in DBeaver or psql connected to postgres)
# Open sql/02_database_setup.sql, run CREATE DATABASE first, then switch to customer_analytics and run the rest

# 5. Load raw data (update password in script first)
python python/03_load_raw_data.py

# 6. Run staging cleaning (in DBeaver connected to customer_analytics)
# sql/04_staging_cleaning.sql

# 7. Validate staging
python python/05_staging_validation.py

# 8. Build star schema
# sql/06a_star_schema_ddl.sql, then sql/06b_star_schema_etl.sql

# 9. Run SQL analyses
# sql/07_sql_analyses.sql

# 10. Run Python EDA
python python/08_eda_analysis.py

# 11. Open Tableau and connect to customer_analytics > dw schema
# Open dashboard/Customer_Churn_Revenue_Intelligence.twbx
```

---

## Author

**Nehali Parulekar** -- Data Analyst | BI Developer

Dover, PA | [LinkedIn](<https://www.linkedin.com/in/nehalip/>) | [Tableau Portfolio](<http://public.tableau.com/app/profile/nehalip>) | nehaliparulekar0395@gmail.com
