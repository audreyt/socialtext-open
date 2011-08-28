BEGIN;

-- To accommodate workspace tags, we must permit page_id to be NULL
ALTER TABLE page_tag ALTER COLUMN page_id DROP NOT NULL;

-- Make some profile fields user editable
ALTER TABLE profile_field
    ADD COLUMN is_user_editable boolean DEFAULT true NOT NULL;

-- Update schema version
UPDATE "System"
   SET value = '26'
 WHERE field = 'socialtext-schema-version';

COMMIT;
