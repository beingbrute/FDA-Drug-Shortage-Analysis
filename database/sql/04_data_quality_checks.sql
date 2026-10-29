-- 04_data_quality_checks.sql
-- Data-quality checks on the loaded database. Each run is saved to dq_check_log,
-- so results can be compared after every refresh.
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/04_data_quality_checks.sql'
--
-- Three kinds of check:
--   Reconciliation : the database must give the same numbers as the Google Sheet
--                    analysis of the same file (26 Oct 2026 download).
--   Integrity      : rules that must hold for any download (expected 0 problems).
--   Review         : issues in the FDA data itself. Counted and listed, not changed.

\set ON_ERROR_STOP on
SET search_path TO fda;

CREATE TABLE IF NOT EXISTS dq_check_log (
    run_at     timestamptz NOT NULL DEFAULT now(),
    check_no   integer     NOT NULL,
    category   text        NOT NULL,
    check_name text        NOT NULL,
    expected   numeric,
    actual     numeric,
    result     text        NOT NULL,
    PRIMARY KEY (run_at, check_no)
);

-- Download date of the file, used for "days on the list".
\set as_of '''2026-10-26'''

WITH cur AS (
    SELECT * FROM shortage_record WHERE status = 'Current'
),
checks (check_no, category, check_name, expected, actual) AS (
    -- Reconciliation with the Google Sheet ------------------------------------
    SELECT 1, 'Reconciliation', 'Rows loaded into staging', 1606,
           (SELECT count(*) FROM stg_raw)
    UNION ALL SELECT 2, 'Reconciliation', 'Exact duplicate rows removed', 1,
           (SELECT count(*) FROM stg_raw) - (SELECT count(*) FROM shortage_record)
    UNION ALL SELECT 3, 'Reconciliation', 'Records after cleaning', 1605,
           (SELECT count(*) FROM shortage_record)
    UNION ALL SELECT 4, 'Reconciliation', 'Current product records', 1141,
           (SELECT count(*) FROM cur)
    UNION ALL SELECT 5, 'Reconciliation', 'Drugs in current shortage', 69,
           (SELECT count(DISTINCT drug_id) FROM cur)
    UNION ALL SELECT 6, 'Reconciliation', 'Current records: Available', 738,
           (SELECT count(*) FROM cur WHERE availability = 'Available')
    UNION ALL SELECT 7, 'Reconciliation', 'Current records: Limited Availability', 140,
           (SELECT count(*) FROM cur WHERE availability = 'Limited Availability')
    UNION ALL SELECT 8, 'Reconciliation', 'Current records: Unavailable', 263,
           (SELECT count(*) FROM cur WHERE availability = 'Unavailable')
    UNION ALL SELECT 9, 'Reconciliation', 'Records with no reason given', 1199,
           (SELECT count(*) FROM shortage_record WHERE reason_id IS NULL)
    UNION ALL SELECT 10, 'Reconciliation', 'Median days a current record has been listed', 1776,
           (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY :as_of::date - initial_posting_date) FROM cur)
    UNION ALL SELECT 11, 'Reconciliation', 'Current records from the top 3 companies', 410,
           (SELECT sum(n) FROM (SELECT count(*) AS n FROM cur GROUP BY company_id ORDER BY n DESC LIMIT 3) t)
    UNION ALL SELECT 12, 'Reconciliation', 'Companies with products in current shortage', 92,
           (SELECT count(DISTINCT company_id) FROM cur)
    UNION ALL SELECT 13, 'Reconciliation', 'Current drugs with Pediatric as an area', 17,
           (SELECT count(DISTINCT c.drug_id)
              FROM cur c
              JOIN record_therapeutic_area rta USING (record_id)
              JOIN therapeutic_area ta USING (area_id)
             WHERE ta.area_name = 'Pediatric')
    UNION ALL SELECT 14, 'Reconciliation', 'Current drugs with records first posted in 2023', 20,
           (SELECT count(DISTINCT drug_id) FROM cur WHERE extract(year FROM initial_posting_date) = 2023)
    UNION ALL SELECT 15, 'Reconciliation', 'Products listed more than once', 19,
           (SELECT count(*) FROM (SELECT presentation FROM shortage_record
                                  GROUP BY presentation HAVING count(*) > 1) t)

    -- Integrity rules (expected 0) --------------------------------------------
    UNION ALL SELECT 16, 'Integrity', 'Records with no therapeutic area', 0,
           (SELECT count(*) FROM shortage_record s
             WHERE NOT EXISTS (SELECT 1 FROM record_therapeutic_area r WHERE r.record_id = s.record_id))
    UNION ALL SELECT 17, 'Integrity', 'Records pointing to a missing drug or company', 0,
           (SELECT count(*) FROM shortage_record s
              LEFT JOIN drug d    ON d.drug_id = s.drug_id
              LEFT JOIN company c ON c.company_id = s.company_id
             WHERE d.drug_id IS NULL OR c.company_id IS NULL)
    UNION ALL SELECT 18, 'Integrity', 'Drugs or companies with no records', 0,
           (SELECT count(*) FROM drug d WHERE NOT EXISTS (SELECT 1 FROM shortage_record s WHERE s.drug_id = d.drug_id))
         + (SELECT count(*) FROM company c WHERE NOT EXISTS (SELECT 1 FROM shortage_record s WHERE s.company_id = c.company_id))
    UNION ALL SELECT 19, 'Integrity', 'Current records without availability', 0,
           (SELECT count(*) FROM cur WHERE availability IS NULL)
    UNION ALL SELECT 20, 'Integrity', 'Dates later than the download date', 0,
           (SELECT count(*) FROM shortage_record
             WHERE greatest(date_of_update, initial_posting_date, change_date, date_discontinued) > :as_of::date)
    UNION ALL SELECT 21, 'Integrity', 'Availability values standardised (2 misspellings, 1 free text)', 3,
           (SELECT count(*) FROM shortage_record WHERE availability_raw IS DISTINCT FROM availability)

    -- Review: issues in the FDA data, kept as published ----------------------
    UNION ALL SELECT 22, 'Review', 'Discontinued date earlier than initial posting date', NULL,
           (SELECT count(*) FROM shortage_record WHERE date_discontinued < initial_posting_date)
    UNION ALL SELECT 23, 'Review', 'Current drugs whose earliest record was posted in 2023', NULL,
           (SELECT count(*) FROM (SELECT drug_id FROM cur GROUP BY drug_id
                                  HAVING extract(year FROM min(initial_posting_date)) = 2023) t)
)
INSERT INTO dq_check_log (check_no, category, check_name, expected, actual, result)
SELECT check_no, category, check_name, expected, actual,
       CASE WHEN category = 'Review'  THEN 'Review'
            WHEN actual = expected    THEN 'Pass'
            ELSE 'FAIL' END
FROM checks;

-- Results of this run
SELECT check_no AS no, category, check_name, expected, actual, result
FROM dq_check_log
WHERE run_at = (SELECT max(run_at) FROM dq_check_log)
ORDER BY check_no;

-- Records behind check 22, for review
SELECT d.generic_name, s.status, s.initial_posting_date, s.date_discontinued
FROM shortage_record s
JOIN drug d USING (drug_id)
WHERE s.date_discontinued < s.initial_posting_date
ORDER BY d.generic_name;
