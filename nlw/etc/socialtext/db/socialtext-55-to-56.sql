BEGIN;

ALTER TABLE container_type
    ADD COLUMN global BOOLEAN DEFAULT FALSE,
    DROP COLUMN layout_template,
    ADD COLUMN columns INTEGER DEFAULT 3,
    ADD COLUMN title TEXT;

UPDATE container_type
    SET global = true
    WHERE container_type IN ('profile', 'edit_profile');

ALTER TABLE gadget
    DROP COLUMN extra_files;

UPDATE "System"
   SET value = '56'
 WHERE field = 'socialtext-schema-version';

COMMIT;
