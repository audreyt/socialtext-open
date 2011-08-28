BEGIN;

CREATE INDEX "ix_event_workspace_contrib"
    ON event (page_workspace_id, "at")
    WHERE event_class = 'page'::text AND is_page_contribution("action");

UPDATE "System"
    SET value = '68'
  WHERE field = 'socialtext-schema-version';

COMMIT;
