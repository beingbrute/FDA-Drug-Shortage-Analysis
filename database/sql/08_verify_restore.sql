-- 08_verify_restore.sql
-- Compares the original database with the restored copy: row counts per table,
-- a checksum of every shortage record, and the number of views, indexes and grants.
-- Run from SQL Shell (any database):
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/08_verify_restore.sql'

\set ON_ERROR_STOP on
\pset pager off

-- The same snapshot query is run on both databases; \gset stores each column in a variable.
\set snapshot 'SELECT (SELECT count(*) FROM fda.company) AS company, (SELECT count(*) FROM fda.drug) AS drug, (SELECT count(*) FROM fda.therapeutic_area) AS therapeutic_area, (SELECT count(*) FROM fda.shortage_reason) AS shortage_reason, (SELECT count(*) FROM fda.shortage_record) AS shortage_record, (SELECT count(*) FROM fda.record_therapeutic_area) AS record_therapeutic_area, (SELECT count(*) FROM fda.stg_raw) AS stg_raw, (SELECT count(*) FROM fda.dq_check_log) AS dq_check_log, (SELECT md5(string_agg(s::text, ''|'' ORDER BY s.record_id)) FROM fda.shortage_record s) AS record_checksum, (SELECT count(*) FROM pg_views WHERE schemaname = ''fda'') AS views, (SELECT count(*) FROM pg_indexes WHERE schemaname = ''fda'') AS indexes, (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = ''fda'' AND grantee IN (''fda_analyst'', ''fda_admin'')) AS grants'

\c fda_shortages
:snapshot \gset orig_

\c fda_restore_test
:snapshot \gset rest_

SELECT item, original, restored,
       CASE WHEN original = restored THEN 'Match' ELSE 'DIFFERENT' END AS result
FROM (VALUES
    ('company',                 :'orig_company',                 :'rest_company'),
    ('drug',                    :'orig_drug',                    :'rest_drug'),
    ('therapeutic_area',        :'orig_therapeutic_area',        :'rest_therapeutic_area'),
    ('shortage_reason',         :'orig_shortage_reason',         :'rest_shortage_reason'),
    ('shortage_record',         :'orig_shortage_record',         :'rest_shortage_record'),
    ('record_therapeutic_area', :'orig_record_therapeutic_area', :'rest_record_therapeutic_area'),
    ('stg_raw',                 :'orig_stg_raw',                 :'rest_stg_raw'),
    ('dq_check_log',            :'orig_dq_check_log',            :'rest_dq_check_log'),
    ('shortage_record checksum',:'orig_record_checksum',         :'rest_record_checksum'),
    ('views',                   :'orig_views',                   :'rest_views'),
    ('indexes',                 :'orig_indexes',                 :'rest_indexes'),
    ('grants to fda roles',     :'orig_grants',                  :'rest_grants')
) AS t (item, original, restored);

\c fda_shortages
