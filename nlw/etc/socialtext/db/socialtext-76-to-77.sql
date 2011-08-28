BEGIN;

CREATE VIEW all_user_workspace AS
    SELECT user_id, workspace_id
    FROM 
    (   SELECT user_id, workspace_id
          FROM "UserWorkspaceRole"
    UNION ALL
       SELECT user_id, workspace_id
          FROM user_group_role ugr
          JOIN group_workspace_role gwr USING (group_id)
    ) my_workspaces;

CREATE VIEW distinct_user_workspace AS
    SELECT DISTINCT * FROM all_user_workspace;

CREATE VIEW all_user_workspace_role AS
    SELECT user_id, workspace_id, role_id
    FROM 
    (   SELECT user_id, workspace_id, role_id
          FROM "UserWorkspaceRole"
    UNION ALL
       SELECT user_id, workspace_id, gwr.role_id AS role_id
          FROM user_group_role ugr
          JOIN group_workspace_role gwr USING (group_id)
    ) my_workspace_roles;

CREATE VIEW distinct_user_workspace_role AS
    SELECT DISTINCT * FROM all_user_workspace_role;

-- Create a series of smaller VIEWs that give us bits+pieces of the
-- User/Account relationship puzzle
CREATE VIEW user_account_explicit AS
    SELECT um.user_id, um.primary_account_id AS account_id
      FROM "UserMetadata" um;

CREATE VIEW user_account_implicit_uwr AS
    SELECT uwr.user_id, w.account_id
      FROM "UserWorkspaceRole" uwr
      JOIN "Workspace" w USING (workspace_id);

CREATE VIEW user_account_implicit_gwr AS
    SELECT ugr.user_id, w.account_id
      FROM user_group_role ugr
      JOIN group_workspace_role gwr USING (group_id)
      JOIN "Workspace" w USING (workspace_id);

CREATE VIEW user_account_implicit AS
    SELECT user_id, account_id
      FROM (    (SELECT user_id, account_id FROM user_account_implicit_uwr)
                UNION ALL
                (SELECT user_id, account_id FROM user_account_implicit_gwr)
           ) AS implicit_user_account_relationships;

-- Drop and recreate existing VIEWs, but based on the smaller pieces this time
DROP VIEW user_account;
CREATE VIEW user_account AS
    SELECT user_id, account_id, is_primary
      FROM (    (SELECT user_id, account_id, TRUE  AS is_primary FROM user_account_explicit)
                UNION ALL
                (SELECT user_id, account_id, FALSE AS is_primary FROM user_account_implicit_uwr)
                UNION ALL
                (SELECT user_id, account_id, FALSE AS is_primary FROM user_account_implicit_gwr)
           ) AS user_account_relationships;

DROP VIEW account_user;
CREATE VIEW account_user AS
    SELECT account_id, user_id
      FROM (    (SELECT account_id, user_id FROM user_account_explicit)
                UNION ALL
                (SELECT account_id, user_id FROM user_account_implicit_uwr)
                UNION ALL
                (SELECT account_id, user_id FROM user_account_implicit_gwr)
           ) AS account_user_relationships;

-- --------------------------------------------------------------------------------------------------------------------------------
UPDATE "System"
   SET value = '77'
 WHERE field = 'socialtext-schema-version';

COMMIT;
