BEGIN;

ALTER TABLE page_revision ADD COLUMN anno_blob TEXT;

UPDATE "System"
   SET value = '147'
 WHERE field = 'socialtext-schema-version';

COMMIT;
