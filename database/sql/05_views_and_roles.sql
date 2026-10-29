-- 05_views_and_roles.sql
-- Reporting views, and two access levels:
--   fda_analyst : read-only, and only through the reporting views
--   fda_admin   : full read and write on the fda schema
-- Login users are members of these roles, so permissions are managed in one place.
-- No passwords are stored in this file: set them with \password (see the end).
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/05_views_and_roles.sql'

\set ON_ERROR_STOP on
SET search_path TO fda;

-- Reporting views -------------------------------------------------------------

-- One row per current product record, with names instead of IDs.
CREATE OR REPLACE VIEW v_current_shortages AS
SELECT s.record_id,
       d.generic_name,
       c.company_name,
       s.presentation,
       s.availability,
       r.reason_text                          AS reason,
       s.initial_posting_date,
       current_date - s.initial_posting_date  AS days_listed,
       s.date_of_update
FROM shortage_record s
JOIN drug d                 USING (drug_id)
JOIN company c              USING (company_id)
LEFT JOIN shortage_reason r USING (reason_id)
WHERE s.status = 'Current';

-- One row per drug in current shortage.
CREATE OR REPLACE VIEW v_drug_summary AS
SELECT d.generic_name,
       count(*)                                               AS current_records,
       count(DISTINCT s.company_id)                           AS companies,
       count(*) FILTER (WHERE s.availability = 'Unavailable') AS unavailable_records,
       min(s.initial_posting_date)                            AS earliest_posting,
       (SELECT string_agg(DISTINCT ta.area_name, '; ' ORDER BY ta.area_name)
          FROM shortage_record s2
          JOIN record_therapeutic_area rta ON rta.record_id = s2.record_id
          JOIN therapeutic_area ta         ON ta.area_id = rta.area_id
         WHERE s2.drug_id = d.drug_id AND s2.status = 'Current') AS therapeutic_areas
FROM shortage_record s
JOIN drug d USING (drug_id)
WHERE s.status = 'Current'
GROUP BY d.drug_id, d.generic_name;

-- One row per company with products in current shortage.
CREATE OR REPLACE VIEW v_company_summary AS
SELECT c.company_name,
       count(*)                                                AS current_records,
       count(DISTINCT s.drug_id)                               AS drugs,
       round(100.0 * count(*) FILTER (WHERE s.availability = 'Unavailable') / count(*), 1)
                                                               AS pct_unavailable
FROM shortage_record s
JOIN company c USING (company_id)
WHERE s.status = 'Current'
GROUP BY c.company_name;

-- One row per therapeutic area. A record with two areas counts in both.
CREATE OR REPLACE VIEW v_area_summary AS
SELECT ta.area_name,
       count(DISTINCT s.drug_id) AS drugs,
       count(*)                  AS current_records
FROM shortage_record s
JOIN record_therapeutic_area rta USING (record_id)
JOIN therapeutic_area ta         USING (area_id)
WHERE s.status = 'Current'
GROUP BY ta.area_name;

-- Roles (created only if they do not exist yet; roles belong to the whole server) --

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fda_analyst') THEN
        CREATE ROLE fda_analyst NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fda_admin') THEN
        CREATE ROLE fda_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'analyst_user') THEN
        CREATE ROLE analyst_user LOGIN IN ROLE fda_analyst;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'admin_user') THEN
        CREATE ROLE admin_user LOGIN IN ROLE fda_admin;
    END IF;
END
$$;

-- Nobody else can connect to this database.
REVOKE ALL ON DATABASE fda_shortages FROM PUBLIC;
GRANT CONNECT ON DATABASE fda_shortages TO fda_analyst, fda_admin;

-- Analyst: can see the schema, but can read only the four views.
REVOKE ALL ON ALL TABLES IN SCHEMA fda FROM fda_analyst;
GRANT USAGE ON SCHEMA fda TO fda_analyst;
GRANT SELECT ON v_current_shortages, v_drug_summary, v_company_summary, v_area_summary
    TO fda_analyst;

-- Admin: full access to everything in the schema.
GRANT USAGE, CREATE ON SCHEMA fda TO fda_admin;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA fda TO fda_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA fda TO fda_admin;

-- Who can do what: one row per role and table or view.
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'fda' AND grantee IN ('fda_analyst', 'fda_admin')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

-- Next, set a password for each login user yourself (psql asks for it twice):
--   \password analyst_user
--   \password admin_user
