# =============================================================================
# Step 4: Load Raw Data into PostgreSQL
# Project: Customer Churn & Revenue Intelligence Platform
# =============================================================================
# This script loads the raw CSV into raw.customer_churn using psycopg2.
# Everything is loaded as text — no type casting at this stage.
# =============================================================================

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
import os

# ── Connection config ─────────────────────────────────────────────────────────
# Update these to match your local PostgreSQL setup
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "customer_analytics",
    "user":     "postgres",
    "password": "your_password_here"   # replace with your postgres password
}

CSV_PATH = "WA_Fn-UseC_-Telco-Customer-Churn.csv"  # update path if needed


# ── 1. Load CSV into a DataFrame ──────────────────────────────────────────────
print("Loading CSV...")
df = pd.read_csv(CSV_PATH, dtype=str)   # dtype=str keeps everything as text
df.columns = df.columns.str.lower().str.replace(" ", "_")

print(f"  Rows loaded : {len(df):,}")
print(f"  Columns     : {list(df.columns)}")


# ── 2. Replace NaN with None (PostgreSQL NULL) ────────────────────────────────
df = df.where(pd.notnull(df), None)


# ── 3. Connect and insert ─────────────────────────────────────────────────────
print("\nConnecting to PostgreSQL...")

try:
    conn   = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()
    print("  Connected successfully.")

    # Truncate first in case you re-run the script
    cursor.execute("TRUNCATE TABLE raw.customer_churn;")
    print("  Truncated raw.customer_churn.")

    # Build list of tuples for bulk insert
    records = [tuple(row) for row in df.itertuples(index=False, name=None)]

    insert_sql = """
        INSERT INTO raw.customer_churn (
            customerid, gender, seniorcitizen, partner, dependents,
            tenure, phoneservice, multiplelines, internetservice,
            onlinesecurity, onlinebackup, deviceprotection, techsupport,
            streamingtv, streamingmovies, contract, paperlessbilling,
            paymentmethod, monthlycharges, totalcharges, churn
        ) VALUES %s
    """

    print(f"  Inserting {len(records):,} records...")
    execute_values(cursor, insert_sql, records, page_size=500)
    conn.commit()
    print("  Commit successful.")

except Exception as e:
    conn.rollback()
    print(f"\nERROR: {e}")
    raise

finally:
    cursor.close()
    conn.close()
    print("  Connection closed.")


# ── 4. Post-load validation ───────────────────────────────────────────────────
print("\nRunning post-load validation...")

conn   = psycopg2.connect(**DB_CONFIG)
cursor = conn.cursor()

# Row count
cursor.execute("SELECT COUNT(*) FROM raw.customer_churn;")
row_count = cursor.fetchone()[0]
print(f"  Rows in raw.customer_churn : {row_count:,}")

# Null check on key columns
key_cols = ["customerid", "tenure", "monthlycharges", "totalcharges", "churn"]
for col in key_cols:
    cursor.execute(
        f"SELECT COUNT(*) FROM raw.customer_churn WHERE {col} IS NULL;"
    )
    null_count = cursor.fetchone()[0]
    print(f"  NULL in {col:<20}: {null_count}")

# Blank string check (totalcharges known issue)
cursor.execute("""
    SELECT COUNT(*)
    FROM raw.customer_churn
    WHERE TRIM(totalcharges) = '' OR totalcharges IS NULL;
""")
blank_tc = cursor.fetchone()[0]
print(f"\n  Blank/NULL totalcharges (expected 11): {blank_tc}")

# Churn distribution
cursor.execute("""
    SELECT churn, COUNT(*) AS count
    FROM raw.customer_churn
    GROUP BY churn
    ORDER BY churn;
""")
print("\n  Churn distribution:")
for row in cursor.fetchall():
    print(f"    {row[0]}: {row[1]:,}")

# Sample rows
cursor.execute("SELECT * FROM raw.customer_churn LIMIT 3;")
cols = [desc[0] for desc in cursor.description]
rows = cursor.fetchall()
print("\n  Sample rows (first 3):")
for row in rows:
    print(dict(zip(cols, row)))

cursor.close()
conn.close()

print("\nStep 4 complete. Raw data loaded and validated.")
print("Next: Step 5 — Data Cleaning into staging.customer_churn")
