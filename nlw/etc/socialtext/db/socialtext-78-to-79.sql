BEGIN;

CREATE INDEX ix_event_action_at ON event (action,at);

UPDATE "System"
   SET value = '79'
 WHERE field = 'socialtext-schema-version';

COMMIT;
