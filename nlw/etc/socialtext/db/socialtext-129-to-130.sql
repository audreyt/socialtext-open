BEGIN;

ALTER TABLE users
    ADD COLUMN private_external_id TEXT;

CREATE UNIQUE INDEX users_private_external_id
    ON users(private_external_id);

UPDATE "System"
   SET value = '130'
 WHERE field = 'socialtext-schema-version';

COMMIT;
