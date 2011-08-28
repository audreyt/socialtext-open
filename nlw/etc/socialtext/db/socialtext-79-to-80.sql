BEGIN;

CREATE VIEW account_user_no_groups (account_id, user_id) AS
    SELECT account_id, user_id
    FROM "UserWorkspaceRole" JOIN "Workspace" USING (workspace_id)
    UNION ALL
    SELECT primary_account_id AS account_id, user_id 
    FROM "UserMetadata";

UPDATE "System"
   SET value = '80'
 WHERE field = 'socialtext-schema-version';

COMMIT;
