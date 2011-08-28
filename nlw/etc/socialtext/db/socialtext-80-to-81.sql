BEGIN;

CREATE INDEX ix_event_at_signal_id_not_null ON event ("at") WHERE COALESCE(signal_id, 0)<>0;

UPDATE "System"
   SET value = '81'
 WHERE field = 'socialtext-schema-version';

COMMIT;
