BEGIN;

DROP INDEX ix_event_at_signal_id_not_null;

CREATE INDEX ix_event_signal_ref ON event ("at")
    WHERE signal_id IS NOT NULL;

CREATE INDEX ix_event_signal_ref_actions ON event ("at")
    WHERE action IN ('signal','edit_save') AND signal_id IS NOT NULL;

CREATE FUNCTION is_ignorable_action("event_class" text, "action" text) RETURNS boolean
    AS $$
BEGIN
    IF event_class = 'page' THEN
        RETURN action IN ('view', 'edit_start', 'edit_cancel', 'edit_contention', 'watch_add', 'watch_delete');

    ELSIF event_class = 'person' THEN
        RETURN action IN ('view', 'watch_add', 'watch_delete');

    ELSIF event_class = 'signal' THEN
        RETURN false;

    ELSIF event_class = 'widget' THEN
        RETURN action NOT IN ('add');

    END IF;

    -- ignore all other event classes:
    RETURN true;
END;
$$
    LANGUAGE plpgsql IMMUTABLE;

CREATE INDEX ix_event_activity_ignore ON event ("at")
    WHERE NOT is_ignorable_action(event_class, action);


-- remove duplicated index
DROP INDEX ix_gadget__src;

-- Turns out we store the parameters to /data/events as a widget user pref.
-- Update prefs to use the optimized default if the old default was saved (new
-- query targets the index created above).

UPDATE gadget_instance_user_pref
   SET value = 'activity=all-combined;with_my_signals=1'
 WHERE user_pref_id = (
        SELECT user_pref_id
          FROM gadget JOIN gadget_user_pref USING (gadget_id)
         WHERE gadget.src = 'local:widgets:activities'
           AND gadget_user_pref.name = 'action'
 ) AND value = 'action!=view,edit_start,edit_cancel,watch_add,watch_delete;with_my_signals=1';


UPDATE "System"
   SET value = '82'
 WHERE field = 'socialtext-schema-version';

COMMIT;
