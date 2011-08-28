BEGIN;

CREATE OR REPLACE FUNCTION signal_hide() RETURNS trigger AS $signal_hide$
BEGIN
  IF NEW.hidden = TRUE and OLD.hidden = FALSE THEN
    DELETE FROM signal_asset WHERE signal_asset.signal_id = NEW.signal_id;
    UPDATE event
       SET hidden = TRUE
     WHERE event.signal_id = NEW.signal_id;

    DELETE FROM signal_thread_tag WHERE signal_id = NEW.signal_id;

    IF NEW.in_reply_to_id IS NOT NULL then
      DELETE FROM signal_thread_tag where signal_id = NEW.in_reply_to_id;

      INSERT INTO signal_thread_tag (signal_id, tag, user_id)
        SELECT DISTINCT NEW.in_reply_to_id, lower(tag), user_id
          FROM signal_tag tag JOIN signal USING (signal_id)
          WHERE signal.signal_id = NEW.in_reply_to_id AND NOT signal.hidden
        UNION
        SELECT DISTINCT NEW.in_reply_to_id, lower(tag), user_id
          FROM signal_tag tag JOIN signal USING (signal_id)
          WHERE
            signal.in_reply_to_id = NEW.in_reply_to_id
            AND NOT signal.hidden;
    END IF;
  END IF;
  RETURN NEW;
END;
$signal_hide$ LANGUAGE plpgsql;

CREATE TRIGGER signal_hide AFTER UPDATE ON signal FOR EACH ROW EXECUTE PROCEDURE signal_hide();


UPDATE "System"
   SET value = '132'
 WHERE field = 'socialtext-schema-version';

COMMIT;
