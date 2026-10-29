-- 09_audit_setup.sql
-- Change tracking for shortage_record. Run once, before the first refresh.
--   refresh_log           : one row per refresh (file name, time, counts)
--   shortage_record_audit : one row per inserted, updated or deleted record, with the
--                           old and new values and the list of columns that changed
-- A trigger fills the audit table automatically, whoever makes the change.
-- Note: after this, re-running 03_transform.sql would log every reload as inserts.
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/09_audit_setup.sql'

\set ON_ERROR_STOP on
SET search_path TO fda;

CREATE TABLE IF NOT EXISTS refresh_log (
    refresh_id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_file      text        NOT NULL,
    run_at           timestamptz NOT NULL DEFAULT now(),
    run_by           text        NOT NULL DEFAULT current_user,
    records_before   integer,
    records_in_file  integer,
    records_inserted integer,
    records_updated  integer,
    records_deleted  integer
);

CREATE TABLE IF NOT EXISTS shortage_record_audit (
    audit_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    refresh_id      integer REFERENCES refresh_log (refresh_id),   -- NULL = change made outside a refresh
    changed_at      timestamptz NOT NULL DEFAULT now(),
    changed_by      text        NOT NULL DEFAULT current_user,
    operation       text        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    record_id       integer     NOT NULL,
    changed_columns text[],
    old_row         jsonb,
    new_row         jsonb
);

CREATE OR REPLACE FUNCTION trg_audit_shortage_record() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_refresh integer := NULLIF(current_setting('fda.refresh_id', true), '')::integer;
    v_columns text[];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- Compare old and new values column by column.
        SELECT array_agg(n.key ORDER BY n.key) INTO v_columns
        FROM jsonb_each(to_jsonb(NEW)) AS n
        JOIN jsonb_each(to_jsonb(OLD)) AS o ON o.key = n.key
        WHERE n.value IS DISTINCT FROM o.value;

        IF v_columns IS NOT NULL THEN
            INSERT INTO shortage_record_audit (refresh_id, operation, record_id, changed_columns, old_row, new_row)
            VALUES (v_refresh, 'UPDATE', NEW.record_id, v_columns, to_jsonb(OLD), to_jsonb(NEW));
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO shortage_record_audit (refresh_id, operation, record_id, new_row)
        VALUES (v_refresh, 'INSERT', NEW.record_id, to_jsonb(NEW));
        RETURN NEW;
    ELSE
        INSERT INTO shortage_record_audit (refresh_id, operation, record_id, old_row)
        VALUES (v_refresh, 'DELETE', OLD.record_id, to_jsonb(OLD));
        RETURN OLD;
    END IF;
END
$$;

DROP TRIGGER IF EXISTS audit_shortage_record ON shortage_record;
CREATE TRIGGER audit_shortage_record
AFTER INSERT OR UPDATE OR DELETE ON shortage_record
FOR EACH ROW EXECUTE FUNCTION trg_audit_shortage_record();

-- The admin role can read the audit trail and add to it (through the trigger),
-- but cannot edit or delete audit rows.
GRANT SELECT, INSERT ON shortage_record_audit TO fda_admin;
GRANT SELECT, INSERT, UPDATE ON refresh_log TO fda_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA fda TO fda_admin;
REVOKE UPDATE, DELETE, TRUNCATE ON shortage_record_audit FROM fda_admin;

\echo 'Audit trigger installed. Test: change one record inside a transaction, read the audit row, roll back.'
BEGIN;
UPDATE shortage_record SET related_information = related_information || ' [test]'
WHERE record_id = (SELECT min(record_id) FROM shortage_record WHERE related_information IS NOT NULL);
SELECT operation, record_id, changed_columns FROM shortage_record_audit ORDER BY audit_id DESC LIMIT 1;
ROLLBACK;
SELECT count(*) AS audit_rows_after_rollback FROM shortage_record_audit;   -- expected: 0
