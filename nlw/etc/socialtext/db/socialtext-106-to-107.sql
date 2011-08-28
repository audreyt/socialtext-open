BEGIN;

CREATE OR REPLACE FUNCTION is_ignorable_action(event_class text, "action" text) RETURNS boolean
    AS $$
BEGIN
    IF event_class = 'page' THEN
        RETURN action IN ('view', 'edit_start', 'edit_cancel', 'edit_contention');

    ELSIF event_class = 'person' THEN
        RETURN action = 'view';

    ELSIF event_class = 'signal' THEN
        RETURN false;

    ELSIF event_class = 'widget' THEN
        RETURN action != 'add';

    END IF;

    -- ignore all other event classes:
    RETURN true;
END;
$$
    LANGUAGE plpgsql IMMUTABLE;

-- rebuild this index (based on the above updated function)
REINDEX INDEX ix_event_activity_ignore;

--- DB migration done
UPDATE "System"
   SET value = '107'
 WHERE field = 'socialtext-schema-version';

COMMIT;
