"""
Hypothesis test: are pediatric drugs in current shortage more likely to have at least
one product that is fully unavailable than other drugs in current shortage?

Connects as analyst_user, the read-only role, because the analysis needs only the
reporting views. The password is asked for when the script runs; it is not stored.

Unit of analysis: the drug (69 drugs in current shortage), not the product record.
Records of the same drug share a manufacturer and a shortage cause, so they are not
independent; testing 1,141 records would overstate the evidence.

Test: Fisher's exact test (two-sided), because one cell of the 2x2 table is very small.

Run from the project folder:
    python database/scripts/hypothesis_test.py
Needs: pip install "psycopg[binary]" pandas scipy tabulate
"""

import getpass
import os
from datetime import date
from pathlib import Path

import pandas as pd
import psycopg
from scipy.stats import fisher_exact

ALPHA = 0.05
OUT = Path("database/documentation/hypothesis_test.md")

conn_info = dict(
    host=os.environ.get("PGHOST", "localhost"),
    port=os.environ.get("PGPORT", "5432"),
    dbname="fda_shortages",
    user="analyst_user",
    password=os.environ.get("PGPASSWORD") or getpass.getpass("Password for analyst_user: "),
)

with psycopg.connect(**conn_info) as conn, conn.cursor() as cur:
    cur.execute("""
        SELECT generic_name, current_records, unavailable_records, therapeutic_areas
        FROM fda.v_drug_summary
    """)
    df = pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])

df["group"] = df["therapeutic_areas"].fillna("").str.contains("Pediatric").map(
    {True: "Pediatric", False: "Other"})
df["has_unavailable"] = df["unavailable_records"] > 0

table = (pd.crosstab(df["group"], df["has_unavailable"])
           .reindex(index=["Pediatric", "Other"], columns=[True, False], fill_value=0))
table.columns = ["At least one unavailable", "None unavailable"]
table["Drugs"] = table.sum(axis=1)
table["Share with unavailable"] = (table["At least one unavailable"] / table["Drugs"]).map("{:.0%}".format)

odds_ratio, p_value = fisher_exact(table[["At least one unavailable", "None unavailable"]].values,
                                   alternative="two-sided")
significant = p_value < ALPHA

print(f"Drugs in current shortage: {len(df)}\n")
print(table.to_string(), "\n")
print(f"Fisher's exact test (two-sided): odds ratio = {odds_ratio:.2f}, p-value = {p_value:.3f}")
conclusion = (
    f"p = {p_value:.3f} is below {ALPHA}: the difference is statistically significant."
    if significant else
    f"p = {p_value:.3f} is above {ALPHA}: there is no statistically significant difference. "
    "The data does not show that pediatric drugs are more likely to be fully unavailable."
)
print(conclusion)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(f"""# Hypothesis test: pediatric drugs and full unavailability

Run on {date.today():%d %B %Y} against the `fda_shortages` database (FDA list downloaded 26 October 2026),
as `analyst_user` through the `v_drug_summary` view.

**Question:** among drugs in current shortage, are pediatric drugs more likely than other drugs
to have at least one product that is fully unavailable?

- **Null hypothesis:** the share of drugs with an unavailable product is the same in both groups.
- **Alternative:** the shares differ (two-sided).
- **Unit:** the drug ({len(df)} drugs). Product records of the same drug are not independent.
- **Test:** Fisher's exact test, significance level {ALPHA}. One group has very few drugs
  without an unavailable product, so a chi-square test would be unreliable.

## Result

{table.to_markdown()}

Odds ratio = {odds_ratio:.2f}, p-value = {p_value:.3f}.

**{conclusion}**

## Limits

- The FDA list is not a random sample of drugs, so the result describes this list, not all drugs.
- With {len(df)} drugs the test can detect only large differences; a real but small difference could be missed.
- "Pediatric" means the FDA lists Pediatric among the drug's therapeutic areas in at least one current record.
""", encoding="utf-8")
print(f"\nSaved {OUT}")
