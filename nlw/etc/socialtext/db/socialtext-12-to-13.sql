BEGIN;

ALTER TABLE "Account"
    ADD COLUMN email_addresses_are_hidden BOOLEAN;

UPDATE "System"
   SET value = 13
 WHERE field = 'socialtext-schema-version';

COMMIT;
