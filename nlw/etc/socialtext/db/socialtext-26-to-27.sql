BEGIN;

-- add some time-based indexes to the noun table
-- we may want to prune some of these if under-used
CREATE INDEX ix_noun_at ON noun (at);
CREATE INDEX ix_noun_user_at ON noun (user_id, at);
CREATE INDEX ix_noun_at_user ON noun (at, user_id);

-- Update schema version
UPDATE "System"
   SET value = '27'
 WHERE field = 'socialtext-schema-version';

COMMIT;
