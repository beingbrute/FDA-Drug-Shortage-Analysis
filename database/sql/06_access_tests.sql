-- 06_access_tests.sql
-- Tests that each role can do what it should, and nothing more.
-- Run as postgres. SET ROLE switches to a user without logging in again.
-- Tests marked "should fail" are expected to give: ERROR: permission denied
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/06_access_tests.sql'

\set ON_ERROR_STOP off
SET search_path TO fda;

\echo '=== analyst_user ==='
SET ROLE analyst_user;

\echo 'Test 1 (should work): read a reporting view'
SELECT count(*) AS current_records FROM v_current_shortages;

\echo 'Test 2 (should fail): read a base table directly'
SELECT count(*) FROM shortage_record;

\echo 'Test 3 (should fail): change data'
UPDATE shortage_record SET availability = 'Available' WHERE record_id = 1;

\echo 'Test 4 (should fail): delete data'
DELETE FROM company WHERE company_id = 1;

RESET ROLE;

\echo '=== admin_user ==='
SET ROLE admin_user;

\echo 'Test 5 (should work): read a base table'
SELECT count(*) AS records FROM shortage_record;

\echo 'Test 6 (should work): change data, inside a transaction that is rolled back'
BEGIN;
UPDATE shortage_record SET availability = 'Available' WHERE record_id = 1;
ROLLBACK;

RESET ROLE;
\set ON_ERROR_STOP on
