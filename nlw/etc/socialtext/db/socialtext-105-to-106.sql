BEGIN;

-- perf optimzations for {link: dev-tasks [Perf: Improve prod perf 2010-02]}

CREATE INDEX users_that_are_hidden ON users (user_id) WHERE (is_profile_hidden);

UPDATE "System"
   SET value = '106'
 WHERE field = 'socialtext-schema-version';

COMMIT;
