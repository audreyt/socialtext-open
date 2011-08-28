BEGIN;

ALTER TABLE page
    ADD COLUMN locked BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE "Workspace"
    ADD COLUMN allows_page_locking BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE "System"
   SET value = '59'
 WHERE field = 'socialtext-schema-version';

COMMIT;
