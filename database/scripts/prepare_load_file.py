"""
Make a load-ready copy of a raw FDA file for PostgreSQL. The raw file is never changed.

Two problems in the FDA export stop PostgreSQL's COPY from reading it:
  1. The file starts and ends with a blank line.
  2. A few values contain an inch mark (") that is not escaped as "" inside a quoted
     CSV field, e.g. Glass Syringe (20 G x 1 1/2"). Google Sheets tolerates this;
     PostgreSQL does not.

Run from the project folder.
Initial load (26 Oct 2026 file, output database/data/fda_load_ready.csv):
    python database/scripts/prepare_load_file.py
Refresh with a newer download (output database/data/<file name>_load_ready.csv):
    python database/scripts/prepare_load_file.py data/raw/fda_drug_shortages_2026-10-29.csv
"""

import csv
import io
import re
import sys
from pathlib import Path

EXPECTED_COLUMNS = 22

if len(sys.argv) > 1:
    RAW = Path(sys.argv[1])
    OUT = Path("database/data") / f"{RAW.stem}_load_ready.csv"
else:
    RAW = Path("data/raw/fda_drug_shortages_2026-10-26.csv")
    OUT = Path("database/data/fda_load_ready.csv")

if not RAW.exists():
    sys.exit(f"Raw file not found: {RAW}. Run this from the project folder.")

text = RAW.read_text(encoding="utf-8")

# 1. Remove blank lines at the start and end of the file.
leading_lines = len(text) - len(text.lstrip("\r\n"))
leading_lines = text[:leading_lines].count("\n")
text = text.strip("\r\n") + "\n"

# 2. Escape lone quotes inside fields: a quote that is not next to a comma,
#    a line break or another quote cannot be a field boundary or an escaped quote.
lone_quote = re.compile(r'(?<![,\n"])"(?![,\n"])')
fixes = [text.count("\n", 0, m.start()) + 1 + leading_lines for m in lone_quote.finditer(text)]
text = lone_quote.sub('""', text)

# Check the result with a strict CSV parser: it fails on any remaining malformed quote.
rows = list(csv.reader(io.StringIO(text), strict=True))
bad = [i for i, r in enumerate(rows, start=1) if len(r) != EXPECTED_COLUMNS]
if bad:
    sys.exit(f"Rows with the wrong number of columns: {bad[:10]}")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text, encoding="utf-8", newline="\n")

print(f"Input: {RAW}")
print(f"Escaped {len(fixes)} lone quote(s) on raw file lines: {fixes}")
print(f"Records (excluding header): {len(rows) - 1}, all with {EXPECTED_COLUMNS} columns")
print(f"Saved {OUT}")
