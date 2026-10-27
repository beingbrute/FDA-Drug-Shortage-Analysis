# Validation log

| # | Check | Expected | Result | Status |
|---|---|---|---|---|
| 1 | Rows imported from the FDA CSV (downloaded 26 Oct 2026) | 1,606 | 1,606 | Pass |
| 2 | Dates read as MM/DD/YYYY (Initial Posting Date of the first record, 11/03/2025, gives month 11) | 11 | 11 | Pass |
| 3 | Row 1 of the raw import is blank (the CSV starts with an empty line); headers are in row 2 | — | Noted | Info |
| 4 | Exact duplicate rows removed with UNIQUE (Quinapril 10 mg, NDC 65862-618-90) | 1 | 1 | Pass |
| 5 | Records in clean tab after removing duplicates | 1,605 | 1,605 | Pass |
| 6 | Columns dropped: Contact Info (phone numbers) and 7 empty link/note columns | 8 | 8 | Pass |
| 7 | Availability standardised: blanks → "Not stated", 2 typos fixed, 1 long note → "Limited Availability" | 738 / 464 / 263 / 140 (total 1,605) | 738 / 464 / 263 / 140 | Pass |
| 8 | Records with no reason for shortage given (shown as "Not reported") | — | 1,199 of 1,605 (75%) | Info |
| 9 | Products listed in more than one row (flagged, kept) | — | 38 rows (19 products) | Info |
| 10 | Days on FDA list = 26 Oct 2026 minus Initial Posting Date (spot-checked rows 2 and 27: 357 and 2,148 days) | 357 / 2,148 | 357 / 2,148 | Pass |
| 11 | Median days listed for Current shortages / number of distinct drugs | 1,776 / 69 | 1,776 / 69 | Pass |
| 12 | Therapeutic areas in current shortages: 19 areas; Pediatric covers the most drugs (17 of 69) | 19 / 17 | 19 / 17 | Pass |
| 13 | Current shortages by start year: product records add up to 1,141; distinct drugs add up to 82 (> 69, because 11 drugs have products first posted in different years) | 1,141 / 82 | 1,141 / 82 | Pass |
| 14 | Availability is filled only for Current shortages; all 464 "Not stated" rows are Resolved or To Be Discontinued (not applicable, not missing) | 464 | 464 | Pass |
| 15 | Current shortages involve 92 companies; top 3 (Fresenius Kabi, Hospira, Hikma) = 410 of 1,141 product records | 410 (35.9%) | 410 (35.9%) | Pass |
| 16 | Rule-based reference labels for 60 sampled texts (formulas in ai_sample): recovery 25 Not stated / 5 TBD / 30 dates; reason 52 Not stated / 5 Manufacturing delay / 3 Discontinuation | as tested | as tested | Pass |
| 17 | ID type mismatch between tabs (number vs text) caused XLOOKUP #N/A; fixed with TO_TEXT | — | Fixed | Info |
| 18 | Qwen3 vs rules: expected recovery agreement | — | 57 / 60 (95%) | Info |
| 19 | Qwen3 vs rules: reason agreement | — | 60 / 60 (100%) | Info |
| 20 | Qwen3 outputs failing the format check (flagged by the script after one retry) | — | 2 (IDs 4, 48) | Info |
| 21 | Manual review of the 3 recovery disagreements: rules correct in all 3 (2 malformed AI outputs, 1 missed date) | — | Reviewed | Pass |
