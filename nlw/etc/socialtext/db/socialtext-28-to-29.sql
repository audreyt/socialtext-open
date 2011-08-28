BEGIN;

-- page_tag lookups by tag are usually lower()'d
CREATE INDEX page_tag__workspace_lower_tag_ix 
    ON page_tag (workspace_id, lower(tag));

ALTER TABLE profile_field
    ADD COLUMN is_hidden boolean NOT NULL DEFAULT false;

-- add an edit summary field to page table
ALTER TABLE page
    ADD COLUMN edit_summary text;

-- Update schema version
UPDATE "System"
   SET value = '29'
 WHERE field = 'socialtext-schema-version';

COMMIT;
