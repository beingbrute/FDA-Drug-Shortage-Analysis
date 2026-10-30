"""
Prepare the input data for the oncology shortage brief.

Two FDA sources, filtered to the drugs the FDA shortage list tags as Oncology and
currently in shortage:
  1. FDA Drug Shortages list (29 Oct 2026 download): one row per current product record.
  2. FDA NDC Directory, product file (30 Oct 2026 download): one row per marketed product.
     FDA names this file .xls, but it is tab-separated text, so it is read as text here.

Output: oncology_brief/data/oncology_inputs.xlsx with two sheets, shortage_onc and ndc_onc.
The scoring model itself is built in Excel on top of these two sheets.

Run from the project folder:
    python oncology_brief/scripts/prepare_oncology_inputs.py
Needs: pip install pandas openpyxl
"""

import csv
import io
import re
import sys
from pathlib import Path

import pandas as pd

SHORTAGE_FILE = Path("data/raw/fda_drug_shortages_2026-10-29.csv")
NDC_FILE = Path("data/raw/ndc/ndc_product_2026-10-30.xls")
OUT = Path("oncology_brief/data/oncology_inputs.xlsx")

# NDC substance name(s) and form for each oncology drug on the shortage list.
# Methotrexate injection is listed under two substance names in the NDC Directory.
DRUG_MAP = {
    "Azacitidine Injection": (["AZACITIDINE"], "injection"),
    "Carboplatin Injection": (["CARBOPLATIN"], "injection"),
    "Dexamethasone Sodium Phosphate Injection": (["DEXAMETHASONE SODIUM PHOSPHATE"], "injection"),
    "Flurazepam Hydrochloride Capsule": (["FLURAZEPAM HYDROCHLORIDE"], "capsule"),
    "Ifosfamide Injection": (["IFOSFAMIDE"], "injection"),
    "Methotrexate Sodium Injection": (["METHOTREXATE SODIUM", "METHOTREXATE"], "injection"),
    "Pentostatin Injection": (["PENTOSTATIN"], "injection"),
    "Streptozocin Powder, For Solution": (["STREPTOZOCIN"], "injection"),
}

for f in (SHORTAGE_FILE, NDC_FILE):
    if not f.exists():
        sys.exit(f"File not found: {f}. Run this from the project folder.")

# --- 1. Shortage records ---------------------------------------------------------
# Same fixes as database/scripts/prepare_load_file.py: blank lines, unescaped inch marks.
text = SHORTAGE_FILE.read_text(encoding="utf-8").strip("\r\n") + "\n"
text = re.sub(r'(?<![,\n"])"(?![,\n"])', '""', text)
sh = pd.read_csv(io.StringIO(text), dtype=str, keep_default_na=False)
sh.columns = [c.strip() for c in sh.columns]
sh = sh.apply(lambda s: s.str.strip()).drop_duplicates()

current_onc = sh[(sh["Status"] == "Current")
                 & sh["Therapeutic Category"].str.contains("Oncology")]

def clean_availability(v):
    if v.lower().startswith("limited"):
        return "Limited Availability"
    if v in ("Unavailable", "Unvailable"):
        return "Unavailable"
    return v

shortage_onc = pd.DataFrame({
    "Drug": current_onc["Generic Name"],
    "Company": current_onc["Company Name"],
    "Presentation": current_onc["Presentation"],
    "Availability": current_onc["Availability Information"].map(clean_availability),
    "Reason": current_onc["Reason for Shortage"].replace("", "Not stated"),
    "Initial Posting Date": pd.to_datetime(current_onc["Initial Posting Date"], format="%m/%d/%Y").dt.date,
    "Date of Update": pd.to_datetime(current_onc["Date of Update"], format="%m/%d/%Y").dt.date,
    "Therapeutic Category": current_onc["Therapeutic Category"],
}).sort_values(["Drug", "Company", "Presentation"])

missing = set(shortage_onc["Drug"]) - set(DRUG_MAP)
if missing:
    sys.exit(f"Oncology drugs on the shortage list with no NDC mapping: {missing}")

# --- 2. NDC products ---------------------------------------------------------------
ndc = pd.read_csv(NDC_FILE, sep="\t", dtype=str, encoding="latin-1",
                  quoting=csv.QUOTE_NONE, keep_default_na=False)
ndc = ndc[ndc["PRODUCTTYPENAME"] == "HUMAN PRESCRIPTION DRUG"]
sub = ndc["SUBSTANCENAME"].str.upper()
form = ndc["DOSAGEFORMNAME"].str.upper()

parts = []
for drug, (substances, kind) in DRUG_MAP.items():
    if kind == "capsule":
        form_ok = form.str.contains("CAPSULE")
    else:
        form_ok = form.str.contains("INJECTION") | form.str.contains("POWDER, FOR SOLUTION")
    rows = ndc[sub.isin(substances) & form_ok].copy()
    rows.insert(0, "Drug", drug)
    parts.append(rows)

ndc_onc = pd.concat(parts)[[
    "Drug", "PRODUCTNDC", "PROPRIETARYNAME", "NONPROPRIETARYNAME", "DOSAGEFORMNAME",
    "MARKETINGCATEGORYNAME", "APPLICATIONNUMBER", "LABELERNAME", "SUBSTANCENAME",
    "ACTIVE_NUMERATOR_STRENGTH", "ACTIVE_INGRED_UNIT", "STARTMARKETINGDATE",
]].sort_values(["Drug", "LABELERNAME", "PRODUCTNDC"])

# --- 3. Save -----------------------------------------------------------------------
OUT.parent.mkdir(parents=True, exist_ok=True)
with pd.ExcelWriter(OUT) as xl:
    shortage_onc.to_excel(xl, sheet_name="shortage_onc", index=False)
    ndc_onc.to_excel(xl, sheet_name="ndc_onc", index=False)

print(f"Current oncology shortage records: {len(shortage_onc)} across {shortage_onc['Drug'].nunique()} drugs")
print(f"Marketed NDC products for those drugs: {len(ndc_onc)}")
print(ndc_onc.groupby("Drug").agg(products=("PRODUCTNDC", "nunique"),
                                  labelers=("LABELERNAME", "nunique")).to_string())
print(f"Saved {OUT}")
