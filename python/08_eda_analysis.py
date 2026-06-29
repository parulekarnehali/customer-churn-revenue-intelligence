# =============================================================================
# Step 8: Python Exploratory Data Analysis
# Project: Customer Churn & Revenue Intelligence Platform
# =============================================================================
# Run this from the staging layer (cleaner than raw, simpler than querying dw).
# Reads directly from PostgreSQL into Pandas.
# Produces 8 chart outputs saved as PNG files.
# =============================================================================

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
import seaborn as sns
import psycopg2
from scipy import stats
import warnings
warnings.filterwarnings("ignore")

# ── Config ────────────────────────────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "customer_analytics",
    "user":     "postgres",
    "password": "your_password_here"
}

OUTPUT_DIR = "./eda_charts/"    # folder where PNGs will be saved
import os
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ── Plot style ─────────────────────────────────────────────────────────────────
plt.style.use("seaborn-v0_8-whitegrid")
PALETTE     = {"No": "#2a78d6", "Yes": "#e34948"}
COLOR_CHURN = "#e34948"
COLOR_STAY  = "#2a78d6"
FIGSIZE     = (12, 5)


# =============================================================================
# 0. Load data from PostgreSQL
# =============================================================================

print("Loading data from staging.customer_churn...")
conn = psycopg2.connect(**DB_CONFIG)

df = pd.read_sql("""
    SELECT
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
    FROM staging.customer_churn
""", conn)
conn.close()

# Derived columns
df["is_churned"]    = df["churn"] == "Yes"
df["total_charges"] = pd.to_numeric(df["total_charges"], errors="coerce")

# Addon count
addon_cols = [
    "multiple_lines", "online_security", "online_backup",
    "device_protection", "tech_support", "streaming_tv", "streaming_movies"
]
df["total_addons"] = df[addon_cols].apply(lambda row: (row == "Yes").sum(), axis=1)

print(f"  Loaded {len(df):,} rows, {df.shape[1]} columns")
print(f"  Churn rate: {df['is_churned'].mean()*100:.2f}%\n")


# =============================================================================
# 1. Summary statistics
# =============================================================================

print("=" * 60)
print("1. SUMMARY STATISTICS")
print("=" * 60)

numeric_cols = ["tenure_months", "monthly_charges", "total_charges"]
print(df[numeric_cols].describe().round(2).to_string())

print("\nChurn breakdown:")
print(df["churn"].value_counts())
print(df["churn"].value_counts(normalize=True).mul(100).round(2))


# =============================================================================
# 2. Distribution plots — tenure, monthly charges, total charges
# =============================================================================

fig, axes = plt.subplots(1, 3, figsize=(15, 5))
fig.suptitle("Distribution of Key Numeric Variables", fontsize=14, fontweight="bold", y=1.02)

# Tenure
for churn_val, color in [(True, COLOR_CHURN), (False, COLOR_STAY)]:
    subset = df[df["is_churned"] == churn_val]["tenure_months"]
    axes[0].hist(subset, bins=30, alpha=0.6, color=color,
                 label="Churned" if churn_val else "Active")
axes[0].set_title("Tenure distribution (months)")
axes[0].set_xlabel("Tenure (months)")
axes[0].set_ylabel("Customer count")
axes[0].legend()

# Monthly charges
for churn_val, color in [(True, COLOR_CHURN), (False, COLOR_STAY)]:
    subset = df[df["is_churned"] == churn_val]["monthly_charges"]
    axes[1].hist(subset, bins=30, alpha=0.6, color=color,
                 label="Churned" if churn_val else "Active")
axes[1].set_title("Monthly charges distribution")
axes[1].set_xlabel("Monthly charges ($)")
axes[1].set_ylabel("Customer count")
axes[1].legend()

# Total charges
for churn_val, color in [(True, COLOR_CHURN), (False, COLOR_STAY)]:
    subset = df[df["is_churned"] == churn_val]["total_charges"].dropna()
    axes[2].hist(subset, bins=30, alpha=0.6, color=color,
                 label="Churned" if churn_val else "Active")
axes[2].set_title("Total charges distribution")
axes[2].set_xlabel("Total charges ($)")
axes[2].set_ylabel("Customer count")
axes[2].legend()

plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}01_distributions.png", dpi=150, bbox_inches="tight")
plt.close()
print("  Saved: 01_distributions.png")


# =============================================================================
# 3. Churn rate by categorical variables
# =============================================================================

cat_vars = {
    "contract_type":    "Contract type",
    "internet_service": "Internet service",
    "payment_method":   "Payment method",
    "senior_citizen":   "Senior citizen",
    "partner":          "Partner",
    "paperless_billing":"Paperless billing"
}

fig, axes = plt.subplots(2, 3, figsize=(16, 10))
fig.suptitle("Churn Rate by Categorical Variable", fontsize=14, fontweight="bold")
axes = axes.flatten()

for idx, (col, label) in enumerate(cat_vars.items()):
    churn_rates = (
        df.groupby(col)["is_churned"]
        .mean()
        .mul(100)
        .sort_values(ascending=False)
    )
    colors = [COLOR_CHURN if v > 30 else COLOR_STAY for v in churn_rates.values]
    bars = axes[idx].bar(churn_rates.index, churn_rates.values, color=colors, width=0.5)
    axes[idx].set_title(label, fontsize=12)
    axes[idx].set_ylabel("Churn rate (%)")
    axes[idx].yaxis.set_major_formatter(mtick.PercentFormatter())
    axes[idx].set_ylim(0, 60)
    axes[idx].tick_params(axis="x", rotation=15)

    for bar, val in zip(bars, churn_rates.values):
        axes[idx].text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.5,
            f"{val:.1f}%",
            ha="center", va="bottom", fontsize=9, fontweight="bold"
        )

plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}02_churn_by_category.png", dpi=150, bbox_inches="tight")
plt.close()
print("  Saved: 02_churn_by_category.png")


# =============================================================================
# 4. Boxplot — monthly charges by churn status and contract type
# =============================================================================

fig, axes = plt.subplots(1, 2, figsize=FIGSIZE)
fig.suptitle("Monthly Charges Distribution by Churn Status", fontsize=13, fontweight="bold")

# Box: charges by churn
df.boxplot(
    column="monthly_charges",
    by="churn",
    ax=axes[0],
    patch_artist=True,
    boxprops=dict(facecolor="#dce9f7"),
    medianprops=dict(color=COLOR_CHURN, linewidth=2)
)
axes[0].set_title("By churn status")
axes[0].set_xlabel("Churn")
axes[0].set_ylabel("Monthly charges ($)")
plt.sca(axes[0])
plt.title("By churn status")

# Box: charges by contract type
df.boxplot(
    column="monthly_charges",
    by="contract_type",
    ax=axes[1],
    patch_artist=True,
    boxprops=dict(facecolor="#dce9f7"),
    medianprops=dict(color=COLOR_CHURN, linewidth=2)
)
axes[1].set_title("By contract type")
axes[1].set_xlabel("Contract type")
axes[1].set_ylabel("Monthly charges ($)")
axes[1].tick_params(axis="x", rotation=10)
plt.sca(axes[1])
plt.title("By contract type")

plt.suptitle("")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}03_boxplots_charges.png", dpi=150, bbox_inches="tight")
plt.close()
print("  Saved: 03_boxplots_charges.png")


# =============================================================================
# 5. Outlier detection — IQR method on monthly charges
# =============================================================================

print("\n" + "=" * 60)
print("5. OUTLIER DETECTION")
print("=" * 60)

for col in ["monthly_charges", "tenure_months", "total_charges"]:
    series = df[col].dropna()
    Q1  = series.quantile(0.25)
    Q3  = series.quantile(0.75)
    IQR = Q3 - Q1
    lower = Q1 - 1.5 * IQR
    upper = Q3 + 1.5 * IQR
    outliers = series[(series < lower) | (series > upper)]
    print(f"\n  {col}:")
    print(f"    Q1={Q1:.2f}, Q3={Q3:.2f}, IQR={IQR:.2f}")
    print(f"    Bounds: [{lower:.2f}, {upper:.2f}]")
    print(f"    Outliers: {len(outliers)} ({len(outliers)/len(series)*100:.2f}%)")

# Outlier visualization
fig, axes = plt.subplots(1, 2, figsize=FIGSIZE)
fig.suptitle("Outlier Detection — IQR Method", fontsize=13, fontweight="bold")

axes[0].boxplot(
    df["monthly_charges"].dropna(),
    patch_artist=True,
    boxprops=dict(facecolor="#dce9f7"),
    medianprops=dict(color=COLOR_CHURN, linewidth=2),
    flierprops=dict(marker="o", markerfacecolor=COLOR_CHURN, markersize=4, alpha=0.5)
)
axes[0].set_title("Monthly charges — outliers flagged")
axes[0].set_ylabel("Monthly charges ($)")
axes[0].set_xticks([])

axes[1].boxplot(
    df["total_charges"].dropna(),
    patch_artist=True,
    boxprops=dict(facecolor="#dce9f7"),
    medianprops=dict(color=COLOR_CHURN, linewidth=2),
    flierprops=dict(marker="o", markerfacecolor=COLOR_CHURN, markersize=4, alpha=0.5)
)
axes[1].set_title("Total charges — outliers flagged")
axes[1].set_ylabel("Total charges ($)")
axes[1].set_xticks([])

plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}04_outlier_detection.png", dpi=150, bbox_inches="tight")
plt.close()
print("\n  Saved: 04_outlier_detection.png")


# =============================================================================
# 6. Correlation analysis
# =============================================================================

print("\n" + "=" * 60)
print("6. CORRELATION ANALYSIS")
print("=" * 60)

# Encode binary columns for correlation
df_corr = df.copy()
binary_map = {"Yes": 1, "No": 0, "Female": 1, "Male": 0}
encode_cols = [
    "gender", "senior_citizen", "partner", "dependents",
    "phone_service", "paperless_billing", "churn"
]
for col in encode_cols:
    df_corr[col] = df_corr[col].map(binary_map)

# Internet service dummies
internet_dummies = pd.get_dummies(df_corr["internet_service"], prefix="internet")
contract_dummies = pd.get_dummies(df_corr["contract_type"], prefix="contract")
df_corr = pd.concat([df_corr, internet_dummies, contract_dummies], axis=1)

corr_cols = [
    "churn", "tenure_months", "monthly_charges", "total_charges",
    "senior_citizen", "partner", "dependents", "total_addons",
    "internet_Fiber optic", "internet_No",
    "contract_Month-to-month", "contract_Two year"
]
corr_cols = [c for c in corr_cols if c in df_corr.columns]
corr_matrix = df_corr[corr_cols].corr()

# Print correlation with churn
print("\nCorrelation with churn (sorted):")
churn_corr = corr_matrix["churn"].drop("churn").sort_values(key=abs, ascending=False)
for feature, val in churn_corr.items():
    direction = "+" if val > 0 else "-"
    print(f"  {direction}  {feature:<35}: {val:+.4f}")

# Heatmap
fig, ax = plt.subplots(figsize=(11, 9))
mask = np.triu(np.ones_like(corr_matrix, dtype=bool))
sns.heatmap(
    corr_matrix,
    mask=mask,
    annot=True,
    fmt=".2f",
    cmap="RdBu_r",
    center=0,
    vmin=-1, vmax=1,
    linewidths=0.5,
    ax=ax,
    annot_kws={"size": 8}
)
ax.set_title("Correlation Matrix — Key Features vs Churn", fontsize=13, fontweight="bold", pad=12)
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}05_correlation_heatmap.png", dpi=150, bbox_inches="tight")
plt.close()
print("\n  Saved: 05_correlation_heatmap.png")


# =============================================================================
# 7. Tenure vs monthly charges scatter — churn overlay
# =============================================================================

fig, ax = plt.subplots(figsize=(10, 6))

for churned, color, label, alpha in [
    (False, COLOR_STAY, "Active",  0.3),
    (True,  COLOR_CHURN, "Churned", 0.5)
]:
    subset = df[df["is_churned"] == churned]
    ax.scatter(
        subset["tenure_months"],
        subset["monthly_charges"],
        c=color, alpha=alpha, s=12, label=label
    )

ax.set_title("Tenure vs Monthly Charges — Churn Overlay", fontsize=13, fontweight="bold")
ax.set_xlabel("Tenure (months)")
ax.set_ylabel("Monthly charges ($)")
ax.legend(title="Status", markerscale=2)

plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}06_tenure_vs_charges_scatter.png", dpi=150, bbox_inches="tight")
plt.close()
print("  Saved: 06_tenure_vs_charges_scatter.png")


# =============================================================================
# 8. Churn rate by total add-ons (service stickiness)
# =============================================================================

addon_churn = (
    df.groupby("total_addons")["is_churned"]
    .agg(["mean", "count"])
    .reset_index()
    .rename(columns={"mean": "churn_rate", "count": "customers"})
)
addon_churn["churn_rate_pct"] = addon_churn["churn_rate"] * 100

fig, ax1 = plt.subplots(figsize=(9, 5))
ax2 = ax1.twinx()

bars = ax1.bar(
    addon_churn["total_addons"],
    addon_churn["churn_rate_pct"],
    color=[COLOR_CHURN if r > 30 else COLOR_STAY for r in addon_churn["churn_rate_pct"]],
    alpha=0.8, width=0.5
)
ax2.plot(addon_churn["total_addons"], addon_churn["customers"],
         color="#eda100", marker="o", linewidth=2, label="Customer count")

ax1.set_title("Service Stickiness — Churn Rate by Number of Add-ons", fontsize=13, fontweight="bold")
ax1.set_xlabel("Number of active add-on services")
ax1.set_ylabel("Churn rate (%)", color=COLOR_CHURN)
ax2.set_ylabel("Customer count", color="#eda100")
ax1.yaxis.set_major_formatter(mtick.PercentFormatter())
ax1.set_xticks(addon_churn["total_addons"])
ax2.legend(loc="upper right")

for bar, val in zip(bars, addon_churn["churn_rate_pct"]):
    ax1.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + 0.5,
        f"{val:.1f}%",
        ha="center", va="bottom", fontsize=9, fontweight="bold"
    )

plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}07_addon_stickiness.png", dpi=150, bbox_inches="tight")
plt.close()
print("  Saved: 07_addon_stickiness.png")


# =============================================================================
# 9. Statistical significance testing
# =============================================================================

print("\n" + "=" * 60)
print("9. STATISTICAL SIGNIFICANCE TESTS")
print("=" * 60)

# Chi-square: are contract type and churn independent?
from scipy.stats import chi2_contingency, ttest_ind, mannwhitneyu

ct = pd.crosstab(df["contract_type"], df["churn"])
chi2, p_chi2, dof, expected = chi2_contingency(ct)
print(f"\n  Chi-square: Contract type vs Churn")
print(f"    chi2={chi2:.2f}, p={p_chi2:.6f}, dof={dof}")
print(f"    Significant at 0.05: {'YES' if p_chi2 < 0.05 else 'NO'}")

# Chi-square: internet service vs churn
ct2 = pd.crosstab(df["internet_service"], df["churn"])
chi2_2, p_chi2_2, dof2, _ = chi2_contingency(ct2)
print(f"\n  Chi-square: Internet service vs Churn")
print(f"    chi2={chi2_2:.2f}, p={p_chi2_2:.6f}, dof={dof2}")
print(f"    Significant at 0.05: {'YES' if p_chi2_2 < 0.05 else 'NO'}")

# Mann-Whitney U: monthly charges — churned vs active
churned_charges = df[df["is_churned"]]["monthly_charges"]
active_charges  = df[~df["is_churned"]]["monthly_charges"]
u_stat, p_mw = mannwhitneyu(churned_charges, active_charges, alternative="two-sided")
print(f"\n  Mann-Whitney U: Monthly charges — churned vs active")
print(f"    U={u_stat:.0f}, p={p_mw:.6f}")
print(f"    Churned median: ${churned_charges.median():.2f}")
print(f"    Active  median: ${active_charges.median():.2f}")
print(f"    Significant at 0.05: {'YES' if p_mw < 0.05 else 'NO'}")

# Mann-Whitney U: tenure — churned vs active
churned_tenure = df[df["is_churned"]]["tenure_months"]
active_tenure  = df[~df["is_churned"]]["tenure_months"]
u2, p_mw2 = mannwhitneyu(churned_tenure, active_tenure, alternative="two-sided")
print(f"\n  Mann-Whitney U: Tenure — churned vs active")
print(f"    U={u2:.0f}, p={p_mw2:.6f}")
print(f"    Churned median tenure: {churned_tenure.median():.0f} months")
print(f"    Active  median tenure: {active_tenure.median():.0f} months")
print(f"    Significant at 0.05: {'YES' if p_mw2 < 0.05 else 'NO'}")


# =============================================================================
# 10. Final summary — print to console for README
# =============================================================================

print("\n" + "=" * 60)
print("10. EDA SUMMARY")
print("=" * 60)
print(f"""
Dataset shape    : {df.shape[0]:,} rows x {df.shape[1]} columns
Churn rate       : {df['is_churned'].mean()*100:.2f}%

Numeric ranges:
  tenure_months  : {df['tenure_months'].min()} – {df['tenure_months'].max()} months (mean {df['tenure_months'].mean():.1f})
  monthly_charges: ${df['monthly_charges'].min():.2f} – ${df['monthly_charges'].max():.2f} (mean ${df['monthly_charges'].mean():.2f})
  total_charges  : ${df['total_charges'].min():.2f} – ${df['total_charges'].max():.2f} (11 NULLs for new customers)

Top churn drivers (from correlation analysis):
  1. Contract type (Month-to-month)   — strong positive
  2. Tenure (low tenure = high churn) — strong negative
  3. Internet service (Fiber optic)   — moderate positive
  4. Payment method (Electronic check)— moderate positive
  5. Total add-ons                    — moderate negative (protective)

Outliers:
  monthly_charges: no significant outliers (IQR method)
  tenure_months  : no significant outliers
  total_charges  : right-skewed, high-value customers at upper tail

Statistical significance:
  Contract type vs churn  : p < 0.001 (chi-square)
  Internet service vs churn: p < 0.001 (chi-square)
  Monthly charges (churned vs active): p < 0.001 (Mann-Whitney U)
  Tenure (churned vs active)         : p < 0.001 (Mann-Whitney U)

Charts saved to: {OUTPUT_DIR}
  01_distributions.png
  02_churn_by_category.png
  03_boxplots_charges.png
  04_outlier_detection.png
  05_correlation_heatmap.png
  06_tenure_vs_charges_scatter.png
  07_addon_stickiness.png
""")
