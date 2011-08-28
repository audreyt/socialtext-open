BEGIN;

ALTER TABLE gadget_instance
    ADD COLUMN fixed boolean DEFAULT false;

-- Update schema version
UPDATE "System"
   SET value = '37'
 WHERE field = 'socialtext-schema-version';

COMMIT;
