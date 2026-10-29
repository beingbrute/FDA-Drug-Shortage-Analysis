-- 03_transform.sql
-- Clean the staging data and load it into the normalised tables.
-- Runs as one transaction: if any step fails, nothing is loaded.
-- Safe to re-run: it empties the final tables first.
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/03_transform.sql'

\set ON_ERROR_STOP on
SET search_path TO fda;

BEGIN;

TRUNCATE record_therapeutic_area, shortage_record, shortage_reason,
         therapeutic_area, drug, company RESTART IDENTITY;

-- Step 1: trimmed, de-duplicated copy of the staging data.
-- The FDA file writes empty values as "", so NULLIF turns them into real NULLs.
CREATE TEMP TABLE stg_clean ON COMMIT DROP AS
SELECT DISTINCT
    NULLIF(trim(generic_name), '')             AS generic_name,
    NULLIF(trim(company_name), '')             AS company_name,
    NULLIF(trim(presentation), '')             AS presentation,
    NULLIF(trim(type_of_update), '')           AS update_type,
    to_date(NULLIF(trim(date_of_update), ''), 'MM/DD/YYYY')       AS date_of_update,
    NULLIF(trim(availability_information), '') AS availability_raw,
    NULLIF(trim(related_information), '')      AS related_information,
    NULLIF(trim(resolved_note), '')            AS resolved_note,
    NULLIF(trim(reason_for_shortage), '')      AS reason_text,
    NULLIF(trim(therapeutic_category), '')     AS therapeutic_category,
    NULLIF(trim(status), '')                   AS status,
    to_date(NULLIF(trim(change_date), ''), 'MM/DD/YYYY')          AS change_date,
    to_date(NULLIF(trim(date_discontinued), ''), 'MM/DD/YYYY')    AS date_discontinued,
    to_date(NULLIF(trim(initial_posting_date), ''), 'MM/DD/YYYY') AS initial_posting_date,
    NULLIF(trim(related_info_link), '')        AS related_info_link
FROM stg_raw;
-- Contact info and the five always-empty link/note columns are not carried over,
-- matching the clean tab in the Google Sheet. Dropping contact info also leaves out
-- the one column on which exact duplicates could differ.

-- Step 2: lookup tables.
INSERT INTO company (company_name)
SELECT DISTINCT company_name FROM stg_clean ORDER BY company_name;

INSERT INTO drug (generic_name)
SELECT DISTINCT generic_name FROM stg_clean ORDER BY generic_name;

INSERT INTO shortage_reason (reason_text)
SELECT DISTINCT reason_text FROM stg_clean WHERE reason_text IS NOT NULL ORDER BY reason_text;

-- "Pediatric; Pulmonary/Allergy" becomes two areas.
INSERT INTO therapeutic_area (area_name)
SELECT DISTINCT trim(area)
FROM stg_clean, unnest(string_to_array(therapeutic_category, ';')) AS area
WHERE trim(area) <> ''
ORDER BY 1;

-- Step 3: main table, with availability standardised.
-- The FDA file has two spelling errors (Unvailable, Limited Availalbility) and one
-- free-text value (Limited Supply Available. Next Delivery ...). The original is kept
-- in availability_raw.
INSERT INTO shortage_record (
    drug_id, company_id, reason_id, presentation, status,
    availability, availability_raw, update_type,
    date_of_update, initial_posting_date, change_date, date_discontinued,
    related_information, resolved_note, related_info_link)
SELECT
    d.drug_id, c.company_id, r.reason_id, s.presentation, s.status,
    CASE
        WHEN s.availability_raw IS NULL                    THEN NULL
        WHEN s.availability_raw ILIKE 'limited%'           THEN 'Limited Availability'
        WHEN s.availability_raw IN ('Unavailable', 'Unvailable') THEN 'Unavailable'
        WHEN s.availability_raw = 'Available'              THEN 'Available'
    END,   -- any other value stays NULL and is caught by chk_current_has_availability
    s.availability_raw, s.update_type,
    s.date_of_update, s.initial_posting_date, s.change_date, s.date_discontinued,
    s.related_information, s.resolved_note, s.related_info_link
FROM stg_clean s
JOIN drug d                 ON d.generic_name = s.generic_name
JOIN company c              ON c.company_name = s.company_name
LEFT JOIN shortage_reason r ON r.reason_text  = s.reason_text
ORDER BY s.generic_name, s.company_name, s.presentation, s.status;

-- Step 4: link each record to its therapeutic areas, matching on the natural key.
INSERT INTO record_therapeutic_area (record_id, area_id)
SELECT DISTINCT sr.record_id, ta.area_id
FROM stg_clean s
JOIN shortage_record sr
  ON  sr.presentation         = s.presentation
  AND sr.status               = s.status
  AND sr.initial_posting_date = s.initial_posting_date
CROSS JOIN LATERAL unnest(string_to_array(s.therapeutic_category, ';')) AS area
JOIN therapeutic_area ta ON ta.area_name = trim(area);

COMMIT;

-- Row counts after loading
SELECT 'company' AS table_name, count(*) AS row_count FROM company
UNION ALL SELECT 'drug', count(*) FROM drug
UNION ALL SELECT 'therapeutic_area', count(*) FROM therapeutic_area
UNION ALL SELECT 'shortage_reason', count(*) FROM shortage_reason
UNION ALL SELECT 'shortage_record', count(*) FROM shortage_record
UNION ALL SELECT 'record_therapeutic_area', count(*) FROM record_therapeutic_area;
