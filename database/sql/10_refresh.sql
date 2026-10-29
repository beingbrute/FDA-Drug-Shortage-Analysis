-- 10_refresh.sql
-- Apply a newer FDA download to the database:
--   records no longer on the list are deleted, changed records are updated,
--   new records are inserted. The audit trigger logs every change.
-- Before running: python database/scripts/prepare_load_file.py data/raw/<new file>.csv
-- For each new download, edit the TWO lines marked EDIT (file name and \copy path).
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/10_refresh.sql'

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO fda;

-- EDIT 1 of 2: the raw file name (keep this comment on its own line; psql would add it to the name)
\set source_file 'fda_drug_shortages_2026-10-29.csv'

BEGIN;

-- 1. Start a refresh and tag every change in this transaction with its ID.
INSERT INTO refresh_log (source_file, records_before)
VALUES (:'source_file', (SELECT count(*) FROM shortage_record))
RETURNING refresh_id \gset
SELECT set_config('fda.refresh_id', :'refresh_id', true) AS refresh_id;

-- 2. Load the new file into its own staging table, as text.
DROP TABLE IF EXISTS stg_refresh;
CREATE TABLE stg_refresh (LIKE stg_raw);
-- EDIT 2 of 2: the load-ready file made by prepare_load_file.py
\copy stg_refresh FROM 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/data/fda_drug_shortages_2026-10-29_load_ready.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 3. Clean it the same way as 03_transform.sql.
CREATE TEMP TABLE new_clean ON COMMIT DROP AS
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
FROM stg_refresh;

-- 4. Add any new companies, drugs, reasons and areas (existing ones are skipped).
INSERT INTO company (company_name)
SELECT DISTINCT company_name FROM new_clean ON CONFLICT (company_name) DO NOTHING;
INSERT INTO drug (generic_name)
SELECT DISTINCT generic_name FROM new_clean ON CONFLICT (generic_name) DO NOTHING;
INSERT INTO shortage_reason (reason_text)
SELECT DISTINCT reason_text FROM new_clean WHERE reason_text IS NOT NULL
ON CONFLICT (reason_text) DO NOTHING;
INSERT INTO therapeutic_area (area_name)
SELECT DISTINCT trim(area)
FROM new_clean, unnest(string_to_array(therapeutic_category, ';')) AS area
WHERE trim(area) <> ''
ON CONFLICT (area_name) DO NOTHING;

-- 5. Records with IDs and standardised availability, ready to compare.
CREATE TEMP TABLE new_records ON COMMIT DROP AS
SELECT d.drug_id, c.company_id, r.reason_id, n.presentation, n.status,
       CASE
           WHEN n.availability_raw IS NULL                          THEN NULL
           WHEN n.availability_raw ILIKE 'limited%'                 THEN 'Limited Availability'
           WHEN n.availability_raw IN ('Unavailable', 'Unvailable') THEN 'Unavailable'
           WHEN n.availability_raw = 'Available'                    THEN 'Available'
       END AS availability,
       n.availability_raw, n.update_type, n.date_of_update, n.initial_posting_date,
       n.change_date, n.date_discontinued, n.related_information, n.resolved_note,
       n.related_info_link, n.therapeutic_category
FROM new_clean n
JOIN drug d                 ON d.generic_name = n.generic_name
JOIN company c              ON c.company_name = n.company_name
LEFT JOIN shortage_reason r ON r.reason_text  = n.reason_text;

-- 6. Delete records that are no longer on the FDA list (key: presentation, status, posting date).
DELETE FROM shortage_record s
WHERE NOT EXISTS (
    SELECT 1 FROM new_records n
    WHERE n.presentation = s.presentation
      AND n.status = s.status
      AND n.initial_posting_date = s.initial_posting_date);

-- 7. Update records whose values changed. IS DISTINCT FROM treats two NULLs as equal.
UPDATE shortage_record s
SET drug_id = n.drug_id, company_id = n.company_id, reason_id = n.reason_id,
    availability = n.availability, availability_raw = n.availability_raw,
    update_type = n.update_type, date_of_update = n.date_of_update,
    change_date = n.change_date, date_discontinued = n.date_discontinued,
    related_information = n.related_information, resolved_note = n.resolved_note,
    related_info_link = n.related_info_link
FROM new_records n
WHERE n.presentation = s.presentation
  AND n.status = s.status
  AND n.initial_posting_date = s.initial_posting_date
  AND (s.drug_id, s.company_id, s.reason_id, s.availability, s.availability_raw,
       s.update_type, s.date_of_update, s.change_date, s.date_discontinued,
       s.related_information, s.resolved_note, s.related_info_link)
      IS DISTINCT FROM
      (n.drug_id, n.company_id, n.reason_id, n.availability, n.availability_raw,
       n.update_type, n.date_of_update, n.change_date, n.date_discontinued,
       n.related_information, n.resolved_note, n.related_info_link);

-- 8. Insert records that are new on the list.
INSERT INTO shortage_record (
    drug_id, company_id, reason_id, presentation, status, availability, availability_raw,
    update_type, date_of_update, initial_posting_date, change_date, date_discontinued,
    related_information, resolved_note, related_info_link)
SELECT n.drug_id, n.company_id, n.reason_id, n.presentation, n.status, n.availability,
       n.availability_raw, n.update_type, n.date_of_update, n.initial_posting_date,
       n.change_date, n.date_discontinued, n.related_information, n.resolved_note,
       n.related_info_link
FROM new_records n
WHERE NOT EXISTS (
    SELECT 1 FROM shortage_record s
    WHERE s.presentation = n.presentation
      AND s.status = n.status
      AND s.initial_posting_date = n.initial_posting_date);

-- 9. Bring the record-to-area links in line with the new file.
CREATE TEMP TABLE new_links ON COMMIT DROP AS
SELECT DISTINCT s.record_id, ta.area_id
FROM new_records n
JOIN shortage_record s
  ON  s.presentation = n.presentation
  AND s.status = n.status
  AND s.initial_posting_date = n.initial_posting_date
CROSS JOIN LATERAL unnest(string_to_array(n.therapeutic_category, ';')) AS area
JOIN therapeutic_area ta ON ta.area_name = trim(area);

DELETE FROM record_therapeutic_area r
WHERE NOT EXISTS (SELECT 1 FROM new_links l WHERE l.record_id = r.record_id AND l.area_id = r.area_id);
INSERT INTO record_therapeutic_area (record_id, area_id)
SELECT record_id, area_id FROM new_links
ON CONFLICT DO NOTHING;

-- 10. Record the counts for this refresh, taken from the audit trail.
UPDATE refresh_log
SET records_in_file  = (SELECT count(*) FROM new_records),
    records_inserted = (SELECT count(*) FROM shortage_record_audit WHERE refresh_id = :refresh_id AND operation = 'INSERT'),
    records_updated  = (SELECT count(*) FROM shortage_record_audit WHERE refresh_id = :refresh_id AND operation = 'UPDATE'),
    records_deleted  = (SELECT count(*) FROM shortage_record_audit WHERE refresh_id = :refresh_id AND operation = 'DELETE')
WHERE refresh_id = :refresh_id;

COMMIT;

-- Summary ----------------------------------------------------------------------
SELECT refresh_id, source_file, records_before, records_in_file, records_inserted, records_updated, records_deleted
FROM refresh_log WHERE refresh_id = :refresh_id;

\echo 'Which columns changed, and how often'
SELECT col AS column_changed, count(*) AS records
FROM shortage_record_audit, unnest(changed_columns) AS col
WHERE refresh_id = :refresh_id AND operation = 'UPDATE'
GROUP BY col ORDER BY records DESC, col;

\echo 'Availability and reason changes'
SELECT new_row ->> 'presentation'  AS presentation,
       old_row ->> 'availability'  AS old_availability,
       new_row ->> 'availability'  AS new_availability,
       (SELECT reason_text FROM shortage_reason WHERE reason_id = (old_row ->> 'reason_id')::int) AS old_reason,
       (SELECT reason_text FROM shortage_reason WHERE reason_id = (new_row ->> 'reason_id')::int) AS new_reason
FROM shortage_record_audit
WHERE refresh_id = :refresh_id AND operation = 'UPDATE'
  AND changed_columns && ARRAY['availability', 'reason_id']
ORDER BY 1;

\echo 'Deleted records'
SELECT old_row ->> 'presentation' AS presentation, old_row ->> 'status' AS status,
       old_row ->> 'initial_posting_date' AS initial_posting_date
FROM shortage_record_audit
WHERE refresh_id = :refresh_id AND operation = 'DELETE'
ORDER BY 1;
