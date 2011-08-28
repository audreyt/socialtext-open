BEGIN;

ALTER TABLE signal
    ADD COLUMN hidden BOOLEAN DEFAULT FALSE;

CREATE INDEX signal_hidden
    ON signal (hidden);

ALTER TABLE event
    ADD COLUMN hidden BOOLEAN DEFAULT FALSE;

CREATE INDEX event_hidden
    ON event (hidden);

UPDATE "System"
   SET value = '78'
 WHERE field = 'socialtext-schema-version';

COMMIT;
