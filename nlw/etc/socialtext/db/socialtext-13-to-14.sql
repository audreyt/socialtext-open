BEGIN;

CREATE INDEX "UserMetadata_primary_account_id" 
    ON "UserMetadata" (primary_account_id);

CREATE INDEX "Workspace_account_id" 
    ON "Workspace" (account_id);

CREATE INDEX "UserWorkspaceRole_workspace_id" 
    ON "UserWorkspaceRole" (workspace_id);

UPDATE "System"
   SET value = 14
 WHERE field = 'socialtext-schema-version';

COMMIT;
