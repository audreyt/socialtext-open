BEGIN;

-- For the first revision of migration 134, constraint and index would have
-- been added.  But, due to large links added by the BMT, I assume we needed
-- to remove that index so it never gets created.
-- Thankfully, Pg 9.0 has a 'DROP INDEX IF EXISTS' command :)
ALTER TABLE ONLY page_link
    DROP CONSTRAINT IF EXISTS page_link_unique;

DROP INDEX IF EXISTS page_link__to_page;

ALTER TABLE page_link ADD COLUMN from_page_md5 text;
UPDATE page_link SET from_page_md5 = md5(from_page_id);
ALTER TABLE page_link ALTER COLUMN from_page_md5 SET NOT NULL;
CREATE INDEX page_link__from_page_md5 ON page_link (from_workspace_id, from_page_md5);

ALTER TABLE page_link ADD COLUMN to_page_md5 text;
UPDATE page_link SET to_page_md5 = md5(to_page_id);
ALTER TABLE page_link ALTER COLUMN to_page_md5 SET NOT NULL;
CREATE INDEX page_link__to_page_md5 ON page_link (to_workspace_id,   to_page_md5);

ALTER TABLE ONLY page_link
    ADD CONSTRAINT page_link_unique
            UNIQUE (from_workspace_id, from_page_md5, to_workspace_id, to_page_md5);

UPDATE "System"
   SET value = '136'
 WHERE field = 'socialtext-schema-version';

COMMIT;
