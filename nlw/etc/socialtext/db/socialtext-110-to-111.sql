BEGIN;

CREATE OR REPLACE FUNCTION is_ignorable_action(event_class text, "action" text) RETURNS boolean
    AS $$
BEGIN
    RETURN (event_class = 'page' AND action IN ('edit_start', 'edit_cancel', 'edit_contention'))
        OR (event_class = 'widget' AND action <> 'add');
END;
$$
    LANGUAGE plpgsql IMMUTABLE;

-- rebuild this index (based on the above updated function)
REINDEX INDEX ix_event_activity_ignore;

--- DB migration done
UPDATE "System"
   SET value = '111'
 WHERE field = 'socialtext-schema-version';

COMMIT;
