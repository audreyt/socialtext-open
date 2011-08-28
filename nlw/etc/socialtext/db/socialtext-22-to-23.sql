BEGIN;

-- Create a new index to speed up deletes from the page table.
CREATE INDEX ix_event_workspace_page ON event (page_workspace_id, page_id);

-- Finish up
UPDATE "System"
   SET value = 23
 WHERE field = 'socialtext-schema-version';

COMMIT;
