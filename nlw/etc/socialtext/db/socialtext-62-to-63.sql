BEGIN;

-- unlimit the length of error messages
ALTER TABLE error ALTER COLUMN message TYPE TEXT;

UPDATE "System"
   SET value = '63'
 WHERE field = 'socialtext-schema-version';

COMMIT;
