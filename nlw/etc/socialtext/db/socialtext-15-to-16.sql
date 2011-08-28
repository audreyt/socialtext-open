BEGIN;

-- Add a function to define page actions that connote a "contribution".
-- The IMMUTABLE keyword indicates that this is a "constant" function; with
-- the same args, it always produces the same return value.  This allows
-- caching and use in indexes.
CREATE FUNCTION is_page_contribution (action text) RETURNS bool AS $$
BEGIN
    IF action IN ('edit_save', 'tag_add', 'tag_delete', 'comment', 'rename', 'duplicate', 'delete')
    THEN
        RETURN true;
    END IF;
    RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- index page contributions by actor
CREATE INDEX ix_page_events_contribs_actor_time 
    ON event (actor_id, at) 
    WHERE event_class = 'page' 
      AND is_page_contribution(action);

-- The following indexes greatly speed up the "My Conversations" query

CREATE INDEX watchlist_user_workspace 
    ON "Watchlist" (user_id, workspace_id);

CREATE INDEX page_creator_time 
    ON page (creator_id, create_time);

UPDATE "System"
   SET value = 16
 WHERE field = 'socialtext-schema-version';

COMMIT;
