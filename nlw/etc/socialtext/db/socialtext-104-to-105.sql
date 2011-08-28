BEGIN;

DROP TABLE storage;

--- DB migration done
UPDATE "System"
   SET value = '105'
 WHERE field = 'socialtext-schema-version';

COMMIT;
