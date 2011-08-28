BEGIN;

-- Add an optional reference to a workspace in a confirmation email
-- If present, indicates the user should be added to the workspace
-- after confirming

ALTER TABLE "UserEmailConfirmation"  
    ADD COLUMN workspace_id bigint;

ALTER TABLE "UserEmailConfirmation"  
    ADD CONSTRAINT useremailconfirmation_workpace_id_fk
        FOREIGN KEY (workspace_id)
        REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

UPDATE "System"
    SET value = '66'
  WHERE field = 'socialtext-schema-version';

COMMIT;
