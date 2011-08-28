BEGIN;

-- Create a new table for all view events, move all view events
-- into that table.
CREATE TABLE view_event (
    "at" timestamptz NOT NULL,
    "action" text NOT NULL,
    actor_id integer NOT NULL,
    event_class text NOT NULL,
    context text,
    page_id text,
    page_workspace_id bigint,
    person_id integer,
    tag_name text,
    signal_id bigint,
    hidden boolean DEFAULT false,
    group_id bigint
);

-- No longer need these indexes
DROP INDEX ix_event_noview_at;
DROP INDEX ix_event_noview_at_page;
DROP INDEX ix_event_noview_at_person;
DROP INDEX ix_event_noview_class_at;

-- Move data into this new table
INSERT INTO view_event ( SELECT * FROM event_archive WHERE action = 'view');
INSERT INTO view_event ( SELECT * FROM event         WHERE action = 'view');
DELETE FROM event_archive WHERE action = 'view';
DELETE FROM event         WHERE action = 'view';

--- DB migration done
UPDATE "System"
   SET value = '110'
 WHERE field = 'socialtext-schema-version';

COMMIT;
