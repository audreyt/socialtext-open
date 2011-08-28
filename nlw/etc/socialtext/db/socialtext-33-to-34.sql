BEGIN;

-- create a simple user signal rollup table.  This can be used to work around
-- some degenerate behaviour, as well as providing some fast summaries :)

CREATE TABLE rollup_user_signal (
    user_id bigint NOT NULL,
    sent_latest timestamptz NOT NULL DEFAULT '-infinity'::timestamptz,
    sent_earliest timestamptz NOT NULL DEFAULT 'infinity'::timestamptz,
    sent_count bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_rollup_user_signal_user ON rollup_user_signal (user_id);
ALTER TABLE rollup_user_signal
    ADD CONSTRAINT "rollup_user_signal_user_id_fk"
    FOREIGN KEY (user_id)
    REFERENCES users (user_id)
    ON DELETE CASCADE;

-- first, populate the rollup with users that have sent signals
INSERT INTO rollup_user_signal (user_id, sent_latest, sent_earliest, sent_count)
SELECT user_id, MAX(at) AS sent_latest, MIN(at) AS sent_earliest, COUNT(1) AS sent_count
  FROM signal
GROUP BY user_id;

-- next, bring in everybody that hasn't signalled yet
SET enable_seqscan TO off; -- don't use SeqScans if possible
INSERT INTO rollup_user_signal (user_id)
SELECT user_id
  FROM users
  LEFT JOIN rollup_user_signal r USING (user_id)
 WHERE r.user_id IS NULL; -- anti-join
SET enable_seqscan TO DEFAULT;

-- create a trigger to maintain a rollup entry for each user created after
-- this migration
CREATE FUNCTION auto_vivify_user_rollups() RETURNS "trigger"
AS $$
    BEGIN
        INSERT INTO rollup_user_signal (user_id) VALUES (NEW.user_id);
        RETURN NULL; -- trigger return val is ignored
    END
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_insert
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE PROCEDURE auto_vivify_user_rollups();

-- create a trigger to update the rollup entry for each signal added
CREATE FUNCTION signal_sent() RETURNS "trigger"
AS $$
    BEGIN

        UPDATE rollup_user_signal
           SET sent_count = sent_count + 1,
               sent_latest = GREATEST(NEW."at", sent_latest),
               sent_earliest = LEAST(NEW."at", sent_earliest)
         WHERE user_id = NEW.user_id;

        NOTIFY new_signal; -- not strictly needed yet

        RETURN NULL; -- trigger return val is ignored
    END
$$ LANGUAGE plpgsql;

CREATE TRIGGER signal_insert
    AFTER INSERT ON signal
    FOR EACH ROW
    EXECUTE PROCEDURE signal_sent();

UPDATE "System"
    SET value = 34
    WHERE field = 'socialtext-schema-version';

COMMIT;
