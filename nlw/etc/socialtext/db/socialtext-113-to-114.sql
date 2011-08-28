BEGIN;

-- Add a "hash" field for [Story: Signals have Permalinks].
ALTER TABLE signal ADD COLUMN hash character(32);
ALTER TABLE recent_signal ADD COLUMN hash character(32);

UPDATE signal 
    SET hash = md5(at AT TIME ZONE 'UTC' || 'Z' || body);
UPDATE recent_signal 
    SET hash = md5(at AT TIME ZONE 'UTC' || 'Z' || body);

ALTER TABLE signal ALTER COLUMN hash SET NOT NULL;
ALTER TABLE recent_signal ALTER COLUMN hash SET NOT NULL;

-- Remove duplicate signals that will cause problems with the unique index
DELETE FROM signal 
  WHERE signal_id IN (
    SELECT A.signal_id 
      FROM signal A 
      JOIN signal B ON (A.at = B.at AND a.body = B.body)
     WHERE a.signal_id > b.signal_id
  );

CREATE UNIQUE INDEX ix_signal_hash ON signal (hash);
CREATE UNIQUE INDEX ix_recent_signal_hash ON recent_signal (hash);

CREATE OR REPLACE FUNCTION auto_hash_signal() RETURNS "trigger"
    AS $$
    BEGIN
        NEW.hash = md5(NEW.at AT TIME ZONE 'UTC' || 'Z' || NEW.body);
        return NEW;
    END
$$
    LANGUAGE plpgsql;

CREATE TRIGGER signal_before_insert
    BEFORE INSERT ON signal
    FOR EACH ROW
    EXECUTE PROCEDURE auto_hash_signal();

CREATE OR REPLACE FUNCTION insert_recent_signal() RETURNS "trigger"
    AS $$
    BEGIN
        INSERT INTO recent_signal (
            signal_id, "at", user_id, body,
            in_reply_to_id, recipient_id, hidden, hash
        )
        VALUES (
            NEW.signal_id, NEW."at", NEW.user_id, NEW.body,
            NEW.in_reply_to_id, NEW.recipient_id, NEW.hidden, NEW.hash
        );
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
    LANGUAGE plpgsql;

UPDATE "System"
   SET value = '114'
 WHERE field = 'socialtext-schema-version';

COMMIT;
