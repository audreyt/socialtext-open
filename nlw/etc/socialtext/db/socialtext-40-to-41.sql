BEGIN;

-- partition page view events.  We have another on (actor_id,at), but having a
-- general one is handy too.

CREATE INDEX ix_event_page_contribs ON event (at)
    WHERE event_class = 'page' AND is_page_contribution(action);

-- partition profile contrib events

CREATE FUNCTION is_profile_contribution("action" text) RETURNS boolean
    AS $$
BEGIN
    IF action IN ('edit_save', 'tag_add', 'tag_delete')
    THEN
        RETURN true;
    END IF;
    RETURN false;
END;
$$
    LANGUAGE plpgsql IMMUTABLE;

CREATE INDEX ix_event_person_contribs_actor ON event (actor_id,at)
    WHERE event_class = 'person' AND is_profile_contribution(action);
CREATE INDEX ix_event_person_contribs_person ON event (person_id,at)
    WHERE event_class = 'person' AND is_profile_contribution(action);
CREATE INDEX ix_event_person_contribs ON event (at)
    WHERE event_class = 'person' AND is_profile_contribution(action);

-- predict some useful signal indexes

CREATE INDEX ix_event_signal_at ON event (at)
    WHERE event_class = 'signal';
CREATE INDEX ix_event_signal_actor_at ON event (actor_id,at)
    WHERE event_class = 'signal';

-- partition-away view events

CREATE INDEX ix_event_noview_at ON event (at)
    WHERE action <> 'view';
CREATE INDEX ix_event_noview_class_at ON event (event_class,at)
    WHERE action <> 'view';
CREATE INDEX ix_event_noview_at_page ON event (at)
    WHERE action <> 'view' AND event_class = 'page';

-- if we start logging profile view events, this will be important:
CREATE INDEX ix_event_noview_at_person ON event (at)
    WHERE action <> 'view' AND event_class = 'person';

UPDATE "System"
   SET value = '41'
 WHERE field = 'socialtext-schema-version';

COMMIT;
