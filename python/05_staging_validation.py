# =============================================================================
# Step 5: Staging Validation — Python
# Project: Customer Churn & Revenue Intelligence Platform
# =============================================================================
# Compares raw vs staging to confirm all cleaning rules were applied correctly.
# Run this AFTER 04_staging_cleaning.sql has been executed.
# =============================================================================

import psycopg2
import pandas as pd

# ── Connection config ─────────────────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "customer_analytics",
    "user":     "postgres",
    "password": "your_password_here"   # replace with your postgres password
}

conn   = psycopg2.connect(**DB_CONFIG)
cursor = conn.cursor()

print("=" * 60)
print("STAGING VALIDATION REPORT")
print("=" * 60)


# ── 1. Row count comparison ───────────────────────────────────────────────────
cursor.execute("SELECT COUNT(*) FROM raw.customer_churn;")
raw_count = cursor.fetchone()[0]

cursor.execute("SELECT COUNT(*) FROM staging.customer_churn;")
stg_count = cursor.fetchone()[0]

print(f"\n1. ROW COUNTS")
print(f"   raw.customer_churn     : {raw_count:,}")
print(f"   staging.customer_churn : {stg_count:,}")
print(f"   Match                  : {'YES' if raw_count == stg_count else 'NO — investigate'}")


# ── 2. SeniorCitizen conversion ───────────────────────────────────────────────
print(f"\n2. SeniorCitizen CONVERSION (0/1 → Yes/No)")

cursor.execute("""
    SELECT seniorcitizen, COUNT(*) AS count
    FROM raw.customer_churn
    GROUP BY seniorcitizen
    ORDER BY seniorcitizen;
""")
print("   Raw values:")
for row in cursor.fetchall():
    print(f"     {row[0]} : {row[1]:,}")

cursor.execute("""
    SELECT senior_citizen, COUNT(*) AS count
    FROM staging.customer_churn
    GROUP BY senior_citizen
    ORDER BY senior_citizen;
""")
print("   Staging values (should be Yes/No only):")
for row in cursor.fetchall():
    print(f"     {row[0]} : {row[1]:,}")


# ── 3. TotalCharges blank → NULL conversion ───────────────────────────────────
print(f"\n3. TotalCharges BLANK → NULL")

cursor.execute("""
    SELECT COUNT(*)
    FROM raw.customer_churn
    WHERE TRIM(totalcharges) = '' OR totalcharges IS NULL;
""")
raw_blanks = cursor.fetchone()[0]

cursor.execute("""
    SELECT COUNT(*)
    FROM staging.customer_churn
    WHERE total_charges IS NULL;
""")
stg_nulls = cursor.fetchone()[0]

print(f"   Blank strings in raw   : {raw_blanks} (expected 11)")
print(f"   NULLs in staging       : {stg_nulls}  (expected 11)")
print(f"   Conversion correct     : {'YES' if raw_blanks == stg_nulls else 'NO — investigate'}")

# Show those 11 rows
cursor.execute("""
    SELECT customer_id, tenure_months, monthly_charges, total_charges
    FROM staging.customer_churn
    WHERE total_charges IS NULL
    ORDER BY customer_id;
""")
print("   NULL total_charges rows (all should have tenure_months = 0):")
for row in cursor.fetchall():
    print(f"     customer_id={row[0]}, tenure={row[1]}, monthly={row[2]}, total={row[3]}")


# ── 4. Data type confirmation ─────────────────────────────────────────────────
print(f"\n4. DATA TYPES IN STAGING")
cursor.execute("""
    SELECT column_name, data_type, character_maximum_length, numeric_precision, numeric_scale
    FROM information_schema.columns
    WHERE table_schema = 'staging'
      AND table_name   = 'customer_churn'
    ORDER BY ordinal_position;
""")
print(f"   {'Column':<22} {'Type':<20} {'Detail'}")
print(f"   {'-'*22} {'-'*20} {'-'*20}")
for row in cursor.fetchall():
    col, dtype, char_len, num_prec, num_scale = row
    if char_len:
        detail = f"max len {char_len}"
    elif num_prec:
        detail = f"precision {num_prec}, scale {num_scale}"
    else:
        detail = ""
    print(f"   {col:<22} {dtype:<20} {detail}")


# ── 5. Numeric range sanity check ─────────────────────────────────────────────
print(f"\n5. NUMERIC RANGE SANITY CHECK")
cursor.execute("""
    SELECT
        MIN(tenure_months)    AS min_tenure,
        MAX(tenure_months)    AS max_tenure,
        ROUND(AVG(tenure_months), 1) AS avg_tenure,
        MIN(monthly_charges)  AS min_monthly,
        MAX(monthly_charges)  AS max_monthly,
        ROUND(AVG(monthly_charges), 2) AS avg_monthly,
        MIN(total_charges)    AS min_total,
        MAX(total_charges)    AS max_total
    FROM staging.customer_churn;
""")
row = cursor.fetchone()
print(f"   tenure_months  : min={row[0]}, max={row[1]}, avg={row[2]}")
print(f"   monthly_charges: min={row[3]}, max={row[4]}, avg={row[5]}")
print(f"   total_charges  : min={row[6]}, max={row[7]}")


# ── 6. Churn distribution ─────────────────────────────────────────────────────
print(f"\n6. CHURN DISTRIBUTION")
cursor.execute("""
    SELECT
        churn,
        COUNT(*) AS count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
    FROM staging.customer_churn
    GROUP BY churn
    ORDER BY churn;
""")
for row in cursor.fetchall():
    print(f"   {row[0]:<5}: {row[1]:,}  ({row[2]}%)")


# ── 7. No leftover 0/1 values in any Yes/No column ───────────────────────────
print(f"\n7. YES/NO COLUMN AUDIT (no 0 or 1 values should remain)")
yes_no_cols = [
    "senior_citizen", "partner", "dependents",
    "phone_service", "paperless_billing", "churn"
]
all_clean = True
for col in yes_no_cols:
    cursor.execute(f"""
        SELECT COUNT(*) FROM staging.customer_churn
        WHERE {col} NOT IN ('Yes', 'No');
    """)
    bad = cursor.fetchone()[0]
    status = "OK" if bad == 0 else f"ISSUE — {bad} unexpected values"
    print(f"   {col:<22}: {status}")
    if bad > 0:
        all_clean = False

print(f"\n   All Yes/No columns clean: {'YES' if all_clean else 'NO — check above'}")


# ── 8. Whitespace audit ───────────────────────────────────────────────────────
print(f"\n8. WHITESPACE AUDIT (leading/trailing spaces)")
cursor.execute("""
    SELECT
        COUNT(*) FILTER (WHERE customer_id   != TRIM(customer_id))   AS id_ws,
        COUNT(*) FILTER (WHERE gender        != TRIM(gender))        AS gender_ws,
        COUNT(*) FILTER (WHERE contract_type != TRIM(contract_type)) AS contract_ws,
        COUNT(*) FILTER (WHERE payment_method!= TRIM(payment_method))AS payment_ws
    FROM staging.customer_churn;
""")
row = cursor.fetchone()
labels = ["customer_id", "gender", "contract_type", "payment_method"]
issues = sum(1 for v in row if v > 0)
for label, val in zip(labels, row):
    print(f"   {label:<22}: {'OK' if val == 0 else f'{val} rows have whitespace'}")
print(f"\n   Whitespace issues found: {issues}")


# ── Summary ───────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("SUMMARY")
print("=" * 60)
print("""
  staging.customer_churn is ready when:
    Row count matches raw         : 7,043
    SeniorCitizen → Yes/No        : confirmed
    TotalCharges blanks → NULL    : 11 rows
    All types correctly cast      : confirmed
    No leftover 0/1 in Yes/No cols: confirmed
    No whitespace in key columns  : confirmed

  Next: Step 6 — Build star schema in the dw schema
""")

cursor.close()
conn.close()
