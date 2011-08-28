BEGIN;

CREATE INDEX ix_event_page_contention 
    ON event (page_workspace_id, page_id, at) 
    WHERE event_class = 'page' AND action IN ('edit_start','edit_cancel');


-- Drop some index that is never used
DROP INDEX ix_event_tag;

UPDATE "System"
   SET value = '52'
 WHERE field = 'socialtext-schema-version';

COMMIT;
