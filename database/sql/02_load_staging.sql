-- 02_load_staging.sql
-- Load the FDA file into a staging table exactly as it is: every column as text,
-- no cleaning. Cleaning happens in 03_transform.sql, so the raw values stay available.
-- Run first: python database/scripts/prepare_load_file.py
-- Then, inside the fda_shortages database:
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/02_load_staging.sql'

\set ON_ERROR_STOP on
SET search_path TO fda;

DROP TABLE IF EXISTS stg_raw;

CREATE TABLE stg_raw (
    generic_name             text,
    company_name             text,
    contact_info             text,
    presentation             text,
    type_of_update           text,
    date_of_update           text,
    availability_information text,
    related_information      text,
    resolved_note            text,
    reason_for_shortage      text,
    therapeutic_category     text,
    status                   text,
    change_date              text,
    date_discontinued        text,
    initial_posting_date     text,
    generic_name_note        text,
    generic_name_link        text,
    company_info_link        text,
    availability_link        text,
    related_info_link        text,
    resolved_note_link       text,
    discontinued_note_link   text
);

-- ENCODING 'UTF8' is needed because the file contains ®, ™ and – characters and the
-- Windows console uses a different code page.
\copy stg_raw FROM 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/data/fda_load_ready.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

SELECT count(*) AS rows_loaded FROM stg_raw;   -- expected: 1606
