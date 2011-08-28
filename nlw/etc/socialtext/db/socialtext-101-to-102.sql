BEGIN;

-- The point of this schema update is to make /data/events/conversations
-- actually scale.  The event table is so fragmented that we incur far too
-- much overhead in scanning for "page contrib" rows; placing all of the page
-- contrib events into a single table drastically reduces this overhead.

CREATE TABLE event_page_contrib (
    "at" timestamptz NOT NULL,
    "action" text NOT NULL,
    actor_id integer NOT NULL,
    context text,
    page_id text NOT NULL,
    page_workspace_id bigint NOT NULL,
    tag_name text
);

INSERT INTO event_page_contrib
SELECT at, action, actor_id, context, page_id, page_workspace_id, tag_name
  FROM event
 WHERE event_class = 'page' AND is_page_contribution(action);

CREATE INDEX ix_epc_actor_page_at
	    ON event_page_contrib (actor_id, page_workspace_id, page_id, "at");
CREATE INDEX ix_epc_actor_at
	    ON event_page_contrib (actor_id, "at");
CREATE INDEX ix_epc_at
	    ON event_page_contrib ("at");
CREATE INDEX ix_epc_action_at
	    ON event_page_contrib (action, "at");
CREATE INDEX ix_epc_workspace_at
	    ON event_page_contrib (page_workspace_id, "at");
CREATE INDEX ix_epc_workspace_page
	    ON event_page_contrib (page_workspace_id, page_id);
CREATE INDEX ix_epc_workspace_page_at
	    ON event_page_contrib (page_workspace_id, page_id,"at");

-- use a trigger to synchronize the event_page_contrib table

CREATE FUNCTION materialize_event_view () RETURNS "trigger"
AS $$
BEGIN
    IF NEW.event_class = 'page' AND is_page_contribution(NEW.action) THEN
        INSERT INTO event_page_contrib
        (at,action,actor_id,context,page_id,page_workspace_id,tag_name)
        VALUES
        (NEW.at,NEW.action,NEW.actor_id,NEW.context,
         NEW.page_id,NEW.page_workspace_id,NEW.tag_name);
    END IF;
    RETURN NEW;
END
$$
LANGUAGE plpgsql;

CREATE TRIGGER materialize_event_view_on_insert
    AFTER INSERT ON event
    FOR EACH ROW
    EXECUTE PROCEDURE materialize_event_view();

UPDATE "System"
   SET value = '102'
 WHERE field = 'socialtext-schema-version';

COMMIT;
