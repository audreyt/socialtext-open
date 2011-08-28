BEGIN;

-- Allow nulls since that's going to be the case 95% of the time.
ALTER TABLE "Account"
    ADD COLUMN all_users_workspace BIGINT;

ALTER TABLE ONLY "Account"
    ADD CONSTRAINT account_all_users_workspace_fk
            FOREIGN KEY (all_users_workspace)
            REFERENCES "Workspace"(workspace_id) ON DELETE RESTRICT;

UPDATE "System"
   SET value = '71'
 WHERE field = 'socialtext-schema-version';

COMMIT;
