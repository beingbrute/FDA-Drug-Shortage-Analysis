-- 01_create_schema.sql
-- Normalised schema for the FDA drug shortages list (downloaded 26 Oct 2026).
-- Run inside the fda_shortages database:
--   \i 'C:/Users/hp/Desktop/FDA-Drug-Shortage-Analysis/database/sql/01_create_schema.sql'
-- Re-running this file deletes the fda schema and everything in it, then rebuilds it empty.

DROP SCHEMA IF EXISTS fda CASCADE;
CREATE SCHEMA fda;
SET search_path TO fda;

-- Lookup tables -------------------------------------------------------------

CREATE TABLE company (
    company_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name text NOT NULL UNIQUE
);

CREATE TABLE drug (
    drug_id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    generic_name text NOT NULL UNIQUE
);

CREATE TABLE therapeutic_area (
    area_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    area_name text NOT NULL UNIQUE
);

CREATE TABLE shortage_reason (
    reason_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reason_text text NOT NULL UNIQUE
);

-- Main table: one row per product record on the FDA list --------------------

CREATE TABLE shortage_record (
    record_id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    drug_id              integer NOT NULL REFERENCES drug (drug_id),
    company_id           integer NOT NULL REFERENCES company (company_id),
    reason_id            integer REFERENCES shortage_reason (reason_id),   -- NULL = no reason given
    presentation         text    NOT NULL,                                 -- strength, form, pack and NDC
    status               text    NOT NULL,
    availability         text,                                             -- standardised value
    availability_raw     text,                                             -- value exactly as the FDA wrote it
    update_type          text    NOT NULL,
    date_of_update       date    NOT NULL,
    initial_posting_date date    NOT NULL,
    change_date          date,
    date_discontinued    date,
    related_information  text,
    resolved_note        text,
    related_info_link    text,

    CONSTRAINT chk_status
        CHECK (status IN ('Current', 'Resolved', 'To Be Discontinued')),
    CONSTRAINT chk_availability
        CHECK (availability IN ('Available', 'Limited Availability', 'Unavailable')),
    CONSTRAINT chk_update_type
        CHECK (update_type IN ('New', 'Revised', 'Reverified')),
    -- Business rules, each checked against the 26 Oct 2026 file before being added
    CONSTRAINT chk_current_has_availability
        CHECK (status <> 'Current' OR availability IS NOT NULL),
    CONSTRAINT chk_discontinued_date
        CHECK ((status = 'To Be Discontinued') = (date_discontinued IS NOT NULL)),
    CONSTRAINT chk_resolved_has_change_date
        CHECK (status <> 'Resolved' OR change_date IS NOT NULL),
    CONSTRAINT chk_update_not_before_posting
        CHECK (date_of_update >= initial_posting_date),
    -- The same product can be listed twice (e.g. Current and To Be Discontinued,
    -- or posted on two dates), so this combination is the natural key.
    CONSTRAINT uq_record UNIQUE (presentation, status, initial_posting_date)
);

-- Bridge table: a record can belong to several therapeutic areas ------------

CREATE TABLE record_therapeutic_area (
    record_id integer NOT NULL REFERENCES shortage_record (record_id) ON DELETE CASCADE,
    area_id   integer NOT NULL REFERENCES therapeutic_area (area_id),
    PRIMARY KEY (record_id, area_id)
);
