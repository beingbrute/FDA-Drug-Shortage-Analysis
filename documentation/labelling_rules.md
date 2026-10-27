# Extraction rules for the AI check

These rules define how two fields are read from a free-text "Related Information" note. They were used in two ways:

1. **Rule-based reference labels:** turned into Google Sheets formulas (REGEXMATCH, REGEXEXTRACT) in the `ai_sample` tab.
2. **AI labels:** given word for word to Qwen3 4B in the prompt (`scripts/ai_extract.py`).

Where the two disagreed, I read the note and decided which was right (see the Notes column in `ai_sample`).

## Field 1: Expected recovery

Allowed values: a month and year written as `Month YYYY` (for example `March 2027`), `TBD`, or `Not stated`.

| Rule | Example (made up) | Label |
|---|---|---|
| 1. A single month and year for recovery, availability, replenishment, next release, or when more lots will be available | "Estimated availability: May 2027" | May 2027 |
| 2. Ignore words like early, mid, late, end | "Recovery: early-February 2027" | February 2027 |
| 3. A range or two months: use the later month | "Estimated recovery: January/February 2027" | February 2027 |
| 4. A quarter: use the last month of that quarter | "Recovery expected in Q1 2027" | March 2027 |
| 5. Both a next-delivery date and an estimated-recovery date: use the estimated-recovery date | "Next Delivery: April 2027; Estimated Recovery: June 2027" | June 2027 |
| 6. Recovery or release is to be decided or not available yet | "Recovery: TBD" / "Next release not available at this time" | TBD |
| 7. Dates about expiry, dating or shelf life are not recovery dates | "Inventory expires March 2027" | Not stated |
| 8. No recovery information at all (distributor names, phone numbers, NDC codes, "check wholesalers") | "Distributed by Example Pharma LLC" | Not stated |

In the formula, rules 2, 3 and 5 are handled by taking the last full "Month YYYY" in the note, and rule 7 by matching full month names only (so "Dec 2026" in an expiry note is not picked up).

## Field 2: Reason stated in the text

Allowed values: `Manufacturing delay`, `Discontinuation`, `Demand increase`, `Other`, `Not stated`.

| Rule | Example (made up) | Label |
|---|---|---|
| 1. The note says there is a manufacturing delay | "Shortage per Manufacturer: Manufacturing Delay" | Manufacturing delay |
| 2. The note says the product is no longer, or not currently, manufactured, or is discontinued | "Product discontinued by the manufacturer" | Discontinuation |
| 3. The note says demand has increased | "Shortage due to increased demand" | Demand increase |
| 4. The note gives some other cause (ingredient shortage, shipping delay, regulatory issue) | "Delayed due to a raw material shortage" | Other |
| 5. No cause is given. Status words (backorder, allocation, limited supply, check wholesalers) and plans ("lots scheduled to meet demand") describe the situation, not the cause | "On allocation" | Not stated |
