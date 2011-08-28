BEGIN;

ALTER TABLE container_type
    ADD COLUMN last_update timestamptz DEFAULT now() NOT NULL;

-- Update schema version
UPDATE "System"
   SET value = '35'
 WHERE field = 'socialtext-schema-version';

COMMIT;
