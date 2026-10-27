# US Drug Shortages: Summary of Findings

**Data:** FDA Drug Shortages list, downloaded 26 October 2026 (1,606 records; 1,605 after removing one exact duplicate).
**Tools:** Google Sheets (QUERY, FILTER, UNIQUE, SPLIT, FLATTEN, COUNTUNIQUEIFS, pivot table, charts).

## Headline numbers

| Measure | Value |
|---|---|
| Drugs in current shortage | 69 |
| Current product records (each strength and pack size of a drug is a separate record) | 1,141 |
| Median time a current shortage has been on the FDA list | 4.9 years (1,776 days) |
| Current products fully unavailable | 23.0% (263) |
| Records with no reason for the shortage | 74.7% (1,199 of 1,605) |
| Share of current product records from the top 3 companies | 35.9% (410 of 1,141) |

## What the data shows

**1. Most current shortages are long-running.** The median current shortage has been listed for 4.9 years, and 4 drugs have been short since 2012. More current shortages began in 2023 (20 drugs) than in any other year.

**2. Pediatric medicines are the most widely affected.** 17 of the 69 drugs in current shortage include Pediatric among their therapeutic areas. Anesthesia has the most product records (351) but covers only 10 drugs, because a few anesthesia drugs come in many strengths and pack sizes. Counting records alone would have hidden the pediatric picture.

**3. The reason field is mostly unusable.** Three in four records give no reason. Of the 406 that do, the most common answer is "Other" (37.4%), followed by increased demand (26.8%) and a shortage of an active ingredient (14.8%). The real reason is often written in the free-text notes instead, which is what the AI extraction check in this project looks at.

**4. Supply problems are concentrated.** 92 companies have products in current shortage, but Fresenius Kabi (158 records), Hospira (157) and Hikma (95) account for 36% of them.

**5. A shortage can still show "Available".** Among current shortages, 738 product records are marked Available, 140 Limited Availability and 263 Unavailable. "Available" means that particular company can supply that product, even though the drug is short nationally.

## Data quality notes

- One exact duplicate row was removed (Quinapril 10 mg tablets).
- 19 products appear in two rows with different statuses (for example Current and To Be Discontinued). They are kept and flagged.
- Availability is filled in only for current shortages. The 464 blanks are all resolved or discontinued products, so they are "not applicable", not missing.
- Two spelling errors in availability values were standardised.
- Every check is listed in `validation_log.md`.

## Limits

- The FDA list holds current and recently resolved shortages. Older shortages that were resolved and removed are not in it, so the "start year" chart shows when today's shortages began, not how many shortages started each year.
- The data covers the United States only.
- Product counts depend on how many strengths and pack sizes a drug has, so distinct-drug counts are shown alongside them.
