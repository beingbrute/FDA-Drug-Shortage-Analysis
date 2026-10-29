-- 07_indexing.sql
-- Part A: indexes on the real tables, and what the query planner does with them.
-- Part B: the same idea on a generated 1,000,000-row load-test table, where an index
--         makes a measurable difference. The load-test data is random and is NOT FDA data.
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/07_indexing.sql'

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO fda;

-- ============================================================================
-- Part A: real FDA tables (1,605 records)
-- ============================================================================
-- PostgreSQL indexes primary keys and UNIQUE columns automatically, but not
-- foreign key columns. These columns are used in every join and filter.

DROP INDEX IF EXISTS idx_record_company, idx_record_drug, idx_record_status, idx_rta_area;

\echo '--- A1. Before indexes: records for one company (a few of 1,605 rows)'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM shortage_record WHERE company_id = 1;

CREATE INDEX idx_record_company ON shortage_record (company_id);
CREATE INDEX idx_record_drug    ON shortage_record (drug_id);
CREATE INDEX idx_rta_area       ON record_therapeutic_area (area_id);
ANALYZE shortage_record;
ANALYZE record_therapeutic_area;

\echo '--- A2. After indexes: same query. The planner now uses idx_record_company.'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM shortage_record WHERE company_id = 1;

\echo '--- A3. An index on status is NOT used: Current is 71% of rows, so reading the whole table is cheaper'
CREATE INDEX idx_record_status ON shortage_record (status);
ANALYZE shortage_record;
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM shortage_record WHERE status = 'Current';
DROP INDEX idx_record_status;   -- an unused index only slows down writes, so it is removed

\echo '--- A4. Table size: the whole table is a few 8 kB pages, so any gain here is tiny'
SELECT pg_size_pretty(pg_relation_size('shortage_record')) AS table_size,
       pg_relation_size('shortage_record') / 8192           AS pages;

-- ============================================================================
-- Part B: load test on 1,000,000 generated rows
-- ============================================================================
DROP SCHEMA IF EXISTS loadtest CASCADE;
CREATE SCHEMA loadtest;

SELECT setseed(0.42);   -- same random data on every run

CREATE TABLE loadtest.shortage_record_lt AS
SELECT g                                        AS record_id,
       1 + floor(random() * 234)::int           AS drug_id,
       1 + floor(random() * 128)::int           AS company_id,
       CASE WHEN random() < 0.71 THEN 'Current'
            WHEN random() < 0.95 THEN 'To Be Discontinued'
            ELSE 'Resolved' END                 AS status,
       date '2012-01-01' + floor(random() * 5400)::int AS initial_posting_date
FROM generate_series(1, 1000000) AS g;
ANALYZE loadtest.shortage_record_lt;

\echo '--- B1. Before index: one drug from one company (about 30 of 1,000,000 rows)'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM loadtest.shortage_record_lt WHERE company_id = 42 AND drug_id = 7;

CREATE INDEX idx_lt_company_drug ON loadtest.shortage_record_lt (company_id, drug_id);
ANALYZE loadtest.shortage_record_lt;

\echo '--- B2. After index: same query'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM loadtest.shortage_record_lt WHERE company_id = 42 AND drug_id = 7;

\echo '--- B3. Sizes'
SELECT pg_size_pretty(pg_relation_size('loadtest.shortage_record_lt'))    AS table_size,
       pg_size_pretty(pg_relation_size('loadtest.idx_lt_company_drug')) AS index_size;

-- The load-test schema is removed so it does not end up in the backup.
DROP SCHEMA loadtest CASCADE;
