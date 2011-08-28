BEGIN;

-- We are explicitly not adding indexes to this table
-- because we are not currently running queries on it.
-- If we want to query this table in the future, we will
-- need to add indexes at that time

CREATE TABLE event_archive (
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
    hidden boolean DEFAULT false
);

UPDATE "System"
   SET value = '83'
 WHERE field = 'socialtext-schema-version';

COMMIT;
