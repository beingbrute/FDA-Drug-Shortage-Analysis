-- 11_post_refresh_checks.sql
-- Checks after a refresh: the database must now match the new FDA file exactly,
-- the audit trail must account for every change, and the integrity rules must still hold.
-- Results are saved to dq_check_log with category 'Refresh'.
-- (04_data_quality_checks.sql reconciles the first load with the Google Sheet; its
--  expected numbers are for the 26 Oct file, so it is not re-run after a refresh.)
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/11_post_refresh_checks.sql'

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO fda;

SELECT max(refresh_id) AS last_refresh FROM refresh_log \gset

WITH file_records AS (      -- the new file, cleaned the same way as in 10_refresh.sql
    SELECT DISTINCT
        NULLIF(trim(presentation), '') AS presentation,
        NULLIF(trim(status), '')       AS status,
        to_date(NULLIF(trim(initial_posting_date), ''), 'MM/DD/YYYY') AS initial_posting_date,
        to_date(NULLIF(trim(date_of_update), ''), 'MM/DD/YYYY')       AS date_of_update,
        NULLIF(trim(availability_information), '') AS availability_raw,
        NULLIF(trim(reason_for_shortage), '')      AS reason_text,
        NULLIF(trim(related_information), '')      AS related_information
    FROM stg_refresh
),
db_records AS (
    SELECT s.presentation, s.status, s.initial_posting_date, s.date_of_update,
           s.availability_raw, r.reason_text, s.related_information
    FROM shortage_record s LEFT JOIN shortage_reason r USING (reason_id)
),
log AS (SELECT * FROM refresh_log WHERE refresh_id = :last_refresh),
checks (check_no, category, check_name, expected, actual) AS (
    SELECT 101, 'Refresh', 'Records in the database = distinct records in the new file',
           (SELECT count(*) FROM file_records), (SELECT count(*) FROM shortage_record)
    UNION ALL SELECT 102, 'Refresh', 'Records in the file but missing from the database', 0,
           (SELECT count(*) FROM (SELECT presentation, status, initial_posting_date FROM file_records
                                  EXCEPT
                                  SELECT presentation, status, initial_posting_date FROM db_records) t)
    UNION ALL SELECT 103, 'Refresh', 'Records in the database but not in the file', 0,
           (SELECT count(*) FROM (SELECT presentation, status, initial_posting_date FROM db_records
                                  EXCEPT
                                  SELECT presentation, status, initial_posting_date FROM file_records) t)
    UNION ALL SELECT 104, 'Refresh', 'Records whose values differ from the file (date, availability, reason, notes)', 0,
           (SELECT count(*) FROM (SELECT * FROM db_records EXCEPT SELECT * FROM file_records) t)
    UNION ALL SELECT 105, 'Refresh', 'Records before + inserted - deleted = records now',
           (SELECT records_before + records_inserted - records_deleted FROM log),
           (SELECT count(*) FROM shortage_record)
    UNION ALL SELECT 106, 'Refresh', 'Audit rows for this refresh = inserted + updated + deleted',
           (SELECT records_inserted + records_updated + records_deleted FROM log),
           (SELECT count(*) FROM shortage_record_audit WHERE refresh_id = :last_refresh)
    UNION ALL SELECT 107, 'Integrity', 'Records with no therapeutic area', 0,
           (SELECT count(*) FROM shortage_record s
             WHERE NOT EXISTS (SELECT 1 FROM record_therapeutic_area r WHERE r.record_id = s.record_id))
    UNION ALL SELECT 108, 'Integrity', 'Current records without availability', 0,
           (SELECT count(*) FROM shortage_record WHERE status = 'Current' AND availability IS NULL)
    UNION ALL SELECT 109, 'Integrity', 'Dates later than today', 0,
           (SELECT count(*) FROM shortage_record
             WHERE greatest(date_of_update, initial_posting_date, change_date, date_discontinued) > current_date)
    UNION ALL SELECT 110, 'Review', 'Drugs and companies no longer on the list (kept for audit history)', NULL,
           (SELECT count(*) FROM drug d WHERE NOT EXISTS (SELECT 1 FROM shortage_record s WHERE s.drug_id = d.drug_id))
         + (SELECT count(*) FROM company c WHERE NOT EXISTS (SELECT 1 FROM shortage_record s WHERE s.company_id = c.company_id))
)
INSERT INTO dq_check_log (check_no, category, check_name, expected, actual, result)
SELECT check_no, category, check_name, expected, actual,
       CASE WHEN category = 'Review' THEN 'Review'
            WHEN actual = expected   THEN 'Pass'
            ELSE 'FAIL' END
FROM checks;

SELECT check_no AS no, category, check_name, expected, actual, result
FROM dq_check_log
WHERE run_at = (SELECT max(run_at) FROM dq_check_log)
ORDER BY check_no;
