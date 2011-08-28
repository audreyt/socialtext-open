BEGIN;

-- Add a "annotations" field for [Story: Signals Annotations].
ALTER TABLE signal ADD COLUMN anno_blob TEXT;
ALTER TABLE recent_signal ADD COLUMN anno_blob TEXT;

CREATE OR REPLACE FUNCTION insert_recent_signal() RETURNS "trigger"
    AS $$
    BEGIN
        INSERT INTO recent_signal (
            signal_id, "at", user_id, body,
            in_reply_to_id, recipient_id, hidden, hash, anno_blob
        )
        VALUES (
            NEW.signal_id, NEW."at", NEW.user_id, NEW.body,
            NEW.in_reply_to_id, NEW.recipient_id, NEW.hidden, NEW.hash, 
            NEW.anno_blob
        );
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
    LANGUAGE plpgsql;

UPDATE "System"
   SET value = '116'
 WHERE field = 'socialtext-schema-version';

COMMIT;
