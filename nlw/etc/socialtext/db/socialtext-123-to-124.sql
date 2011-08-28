BEGIN;

-- [Story: Signals workspace links follow privacy rules]:
-- Relax the topical constraint on signal's pages; it's now okay
-- to talk about non-existent pages or already-deleted pages.

ALTER TABLE ONLY topic_signal_page
    DROP CONSTRAINT topic_signal_page_forward;

ALTER TABLE ONLY topic_signal_page
    ADD CONSTRAINT topic_signal_page_workspace_fk
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '124'
 WHERE field = 'socialtext-schema-version';

COMMIT;
