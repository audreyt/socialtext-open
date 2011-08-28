BEGIN;

-- indexes and functions for event refactoring

CREATE FUNCTION is_direct_signal(actor_id bigint, person_id bigint)
RETURNS bool AS $$
BEGIN
    RETURN (actor_id IS NOT NULL AND person_id IS NOT NULL);
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE INDEX ix_event_signal_direct ON event (at)
  WHERE event_class = 'signal' AND is_direct_signal(actor_id,person_id);
CREATE INDEX ix_event_signal_indirect ON event (at)
  WHERE event_class = 'signal' AND NOT is_direct_signal(actor_id,person_id);

-- speeds up bare /data/events queries
CREATE INDEX ix_event_workspace ON event (page_workspace_id, at)
  WHERE event_class = 'page';

UPDATE "System"
   SET value = '75'
 WHERE field = 'socialtext-schema-version';

COMMIT;
