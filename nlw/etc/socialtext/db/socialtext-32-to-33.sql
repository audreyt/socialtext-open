BEGIN;

-- Scrub the table one time (sequential scan, but that's ok)
DELETE FROM sessions
    WHERE last_updated < 'now'::timestamptz - '28 days'::interval;

-- make it so the trigger can run quickly
CREATE INDEX ix_session_last_updated ON sessions (last_updated);

CREATE FUNCTION cleanup_sessions() RETURNS "trigger"
AS $$
    BEGIN
        -- if this is too slow, randomize running the delete
        -- e.g. IF (RANDOM() * 5)::integer = 0 THEN ...
        DELETE FROM sessions
        WHERE last_updated < 'now'::timestamptz - '28 days'::interval;
        RETURN NULL; -- after trigger
    END
$$
LANGUAGE plpgsql;

-- every time we grow the sessions table, we want to try and shrink it
CREATE TRIGGER sessions_insert
    AFTER INSERT ON sessions
    FOR EACH STATEMENT
    EXECUTE PROCEDURE cleanup_sessions();

UPDATE "System"
    SET value = '33'
    WHERE field = 'socialtext-schema-version';

COMMIT;
