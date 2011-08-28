BEGIN;

ALTER TABLE "Account"
    ADD COLUMN pref_blob TEXT NOT NULL DEFAULT ''::text;

UPDATE "System"
   SET value = '146'
 WHERE field = 'socialtext-schema-version';

COMMIT;
