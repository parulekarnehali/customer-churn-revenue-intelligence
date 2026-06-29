# =============================================================================
# Step 2: Raw Data Inspection
# Project: Customer Churn & Revenue Intelligence Platform
# Dataset: IBM Telco Customer Churn
# =============================================================================

import pandas as pd
import numpy as np

# ── 1. Load the raw CSV ──────────────────────────────────────────────────────
# Update the path to wherever you saved the file
CSV_PATH = "WA_Fn-UseC_-Telco-Customer-Churn.csv"

df = pd.read_csv(CSV_PATH)

print("=" * 60)
print("1. BASIC SHAPE")
print("=" * 60)
print(f"Rows    : {df.shape[0]:,}")
print(f"Columns : {df.shape[1]}")


# ── 2. Column names and data types ───────────────────────────────────────────
print("\n" + "=" * 60)
print("2. COLUMN NAMES & DATA TYPES")
print("=" * 60)
print(df.dtypes.to_string())


# ── 3. First look at the data ────────────────────────────────────────────────
print("\n" + "=" * 60)
print("3. FIRST 5 ROWS")
print("=" * 60)
print(df.head().to_string())


# ── 4. Missing values ────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("4. MISSING VALUES")
print("=" * 60)
missing = df.isnull().sum()
missing_pct = (df.isnull().sum() / len(df) * 100).round(2)
missing_df = pd.DataFrame({
    "Missing Count": missing,
    "Missing %": missing_pct
})
missing_df = missing_df[missing_df["Missing Count"] > 0]

if missing_df.empty:
    print("No nulls detected at pandas level.")
    print("NOTE: Check for blank strings that pandas reads as non-null.")
else:
    print(missing_df.to_string())


# ── 5. Blank string check (common in this dataset) ───────────────────────────
print("\n" + "=" * 60)
print("5. BLANK STRING CHECK (space or empty string)")
print("=" * 60)
for col in df.columns:
    blank_count = (df[col].astype(str).str.strip() == "").sum()
    if blank_count > 0:
        print(f"  {col}: {blank_count} blank/whitespace values")

blank_total = sum(
    (df[col].astype(str).str.strip() == "").sum()
    for col in df.columns
)
if blank_total == 0:
    print("No blank strings found.")


# ── 6. Duplicate records ─────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("6. DUPLICATE RECORDS")
print("=" * 60)
dup_rows = df.duplicated().sum()
dup_customer_ids = df.duplicated(subset=["customerID"]).sum()
print(f"Fully duplicate rows      : {dup_rows}")
print(f"Duplicate customerID rows : {dup_customer_ids}")


# ── 7. Unique values in categorical columns ──────────────────────────────────
print("\n" + "=" * 60)
print("7. CATEGORICAL COLUMNS — UNIQUE VALUES")
print("=" * 60)
cat_cols = df.select_dtypes(include="object").columns.tolist()
print(f"Detected {len(cat_cols)} object-type columns:\n")

for col in cat_cols:
    unique_vals = df[col].unique()
    print(f"  {col} ({len(unique_vals)} unique): {sorted(unique_vals.astype(str))}")


# ── 8. Numeric columns — summary stats ───────────────────────────────────────
print("\n" + "=" * 60)
print("8. NUMERIC COLUMNS — SUMMARY STATISTICS")
print("=" * 60)
num_cols = df.select_dtypes(include=[np.number]).columns.tolist()
print(f"Detected {len(num_cols)} numeric columns:\n")
print(df[num_cols].describe().round(2).to_string())


# ── 9. TotalCharges — known data quality issue ───────────────────────────────
# TotalCharges is loaded as object (string) due to blank values in raw data.
# This is the key data quality issue to fix in Step 5.
print("\n" + "=" * 60)
print("9. TotalCharges — DATA TYPE INVESTIGATION")
print("=" * 60)
print(f"dtype         : {df['TotalCharges'].dtype}")
print(f"Sample values : {df['TotalCharges'].head(10).tolist()}")

# Try coercing to numeric and flag failures
tc_numeric = pd.to_numeric(df["TotalCharges"], errors="coerce")
coerce_failures = tc_numeric.isnull().sum()
print(f"\nValues that cannot be converted to numeric: {coerce_failures}")
print("These are the rows to investigate:")
print(df[tc_numeric.isnull()][["customerID", "tenure", "MonthlyCharges", "TotalCharges"]].to_string())


# ── 10. Churn distribution ───────────────────────────────────────────────────
print("\n" + "=" * 60)
print("10. TARGET VARIABLE — Churn DISTRIBUTION")
print("=" * 60)
churn_dist = df["Churn"].value_counts()
churn_pct  = df["Churn"].value_counts(normalize=True).mul(100).round(2)
churn_summary = pd.DataFrame({
    "Count": churn_dist,
    "Percentage": churn_pct
})
print(churn_summary.to_string())


# ── 11. Key business columns — spot check ────────────────────────────────────
print("\n" + "=" * 60)
print("11. KEY BUSINESS COLUMNS — SPOT CHECK")
print("=" * 60)

key_cols = [
    "Contract", "PaymentMethod", "InternetService",
    "tenure", "MonthlyCharges"
]
for col in key_cols:
    if col in df.columns:
        if df[col].dtype == "object":
            print(f"\n  {col}:")
            print(df[col].value_counts().to_string())
        else:
            print(f"\n  {col}: min={df[col].min()}, max={df[col].max()}, "
                  f"mean={df[col].mean():.2f}, median={df[col].median():.2f}")


# ── 12. Summary of findings ──────────────────────────────────────────────────
print("\n" + "=" * 60)
print("12. INSPECTION SUMMARY — ISSUES TO FIX IN STEP 5")
print("=" * 60)
print("""
Known issues in this dataset:
  1. TotalCharges is type 'object' (string) — contains blank values for
     new customers with tenure = 0. Must convert to numeric after handling blanks.
  2. SeniorCitizen is stored as 0/1 integer — should be mapped to Yes/No
     for consistency with other binary columns.
  3. No true NULLs exist — blanks appear as empty strings or whitespace.
  4. All Yes/No columns use consistent capitalization — no standardization needed.
  5. No duplicate customerIDs detected (expected: each row = one customer).

Next step: Step 3 — Create PostgreSQL database and schema structure.
""")
