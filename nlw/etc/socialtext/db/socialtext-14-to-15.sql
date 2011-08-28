BEGIN;

-- Add indexes to the storage table

CREATE INDEX storage_class_key_ix 
    ON storage (class, key);

CREATE INDEX storage_key_ix 
    ON storage (key);

-- These two indexes are trying to optimize lookups on two common keys.  They
-- might not get used, and so might need to get pruned later.

CREATE INDEX storage_key_value_type_ix 
    ON storage (key, value)
    WHERE key = 'type';

CREATE INDEX storage_key_value_viewer_ix 
    ON storage (key, value)
    WHERE key = 'viewer';

-- Add indexes to the page_tag table

CREATE INDEX page_tag__page_ix 
    ON page_tag (workspace_id, page_id);

CREATE INDEX page_tag__workspace_ix 
    ON page_tag (workspace_id);

CREATE INDEX page_tag__tag_ix 
    ON page_tag (tag);

-- This index *might* get used when getting an ordered list of tags for a
-- workspace.  We may need to prune it later.

CREATE INDEX page_tag__workspace_tag_ix 
    ON page_tag (workspace_id, tag);


UPDATE "System"
   SET value = 15
 WHERE field = 'socialtext-schema-version';

COMMIT;
