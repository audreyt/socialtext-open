BEGIN;

ALTER TABLE ONLY "UserWorkspaceRole"
    RENAME TO user_workspace_role;

-- Rename our constraints
ALTER TABLE ONLY user_workspace_role
    DROP CONSTRAINT "UserWorkspaceRole_pkey";

ALTER TABLE ONLY user_workspace_role
    ADD CONSTRAINT user_workspace_role_pkey
            PRIMARY KEY (user_id, workspace_id);

ALTER TABLE ONLY user_workspace_role
    DROP CONSTRAINT fk_2d35adae0767c6ef9bd03ed923bd2380;

ALTER TABLE ONLY user_workspace_role
    ADD CONSTRAINT user_workspace_role_user_id_fk
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_workspace_role
    DROP CONSTRAINT fk_c00a18f1daca90d376037f946a0b3894;

ALTER TABLE ONLY user_workspace_role
    ADD CONSTRAINT user_workspace_role_workspace_id_fk
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_workspace_role
    DROP CONSTRAINT userworkspacerole___role___role_id___role_id___n___1___1___0;

ALTER TABLE ONLY user_workspace_role
    ADD CONSTRAINT user_workspace_role_role_id_fk
            FOREIGN KEY (role_id)
            REFERENCES "Role"(role_id) ON DELETE CASCADE;

-- Rename our indexes
DROP INDEX "UserWorkspaceRole_workspace_id";

CREATE INDEX user_workspace_role__workspace_id
	    ON user_workspace_role (workspace_id);

-- Drop and recreate views
DROP VIEW distinct_user_workspace;
DROP VIEW distinct_user_workspace_role;
DROP VIEW all_user_workspace;
DROP VIEW all_user_workspace_role;

CREATE VIEW all_user_workspace AS
  SELECT my_workspaces.user_id, my_workspaces.workspace_id
   FROM ( SELECT user_id, workspace_id
           FROM user_workspace_role
UNION ALL 
         SELECT ugr.user_id, gwr.workspace_id
           FROM user_group_role ugr
      JOIN group_workspace_role gwr USING (group_id)) my_workspaces;

CREATE VIEW all_user_workspace_role AS
  SELECT my_workspace_roles.user_id, my_workspace_roles.workspace_id, my_workspace_roles.role_id
   FROM ( SELECT user_id, workspace_id, role_id
           FROM user_workspace_role
UNION ALL 
         SELECT ugr.user_id, gwr.workspace_id, gwr.role_id
           FROM user_group_role ugr
      JOIN group_workspace_role gwr USING (group_id)) my_workspace_roles;

CREATE VIEW distinct_user_workspace AS
  SELECT DISTINCT all_user_workspace.user_id, all_user_workspace.workspace_id
   FROM all_user_workspace
  ORDER BY all_user_workspace.user_id, all_user_workspace.workspace_id;

CREATE VIEW distinct_user_workspace_role AS
  SELECT DISTINCT all_user_workspace_role.user_id, all_user_workspace_role.workspace_id, all_user_workspace_role.role_id
   FROM all_user_workspace_role
  ORDER BY all_user_workspace_role.user_id, all_user_workspace_role.workspace_id, all_user_workspace_role.role_id;

-- update the schema-version
UPDATE "System"
   SET value = '86'
 WHERE field = 'socialtext-schema-version';

COMMIT;
