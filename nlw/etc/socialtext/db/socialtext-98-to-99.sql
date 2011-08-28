BEGIN;

DROP TABLE user_account_role CASCADE;
DROP TABLE group_account_role;
DROP TABLE group_workspace_role CASCADE;
DROP TABLE user_group_role;
DROP TABLE user_workspace_role CASCADE;

-- user_set_id indexes for groups/workspaces/accounts

CREATE UNIQUE INDEX groups_user_set_id ON groups (user_set_id);
CREATE UNIQUE INDEX workspace_user_set_id ON "Workspace" (user_set_id);
CREATE UNIQUE INDEX account_user_set_id ON "Account" (user_set_id);

-- indexes for user_set_include

-- the "user_set_include_tc" view will use this index:
CREATE UNIQUE INDEX idx_user_set_include_pkey_and_role
    ON user_set_include (from_set_id,into_set_id,role_id);
CREATE UNIQUE INDEX idx_user_set_include_rev_and_role
    ON user_set_include (into_set_id,from_set_id,role_id);

-- indexes for user_set_path

CREATE INDEX idx_user_set_path_wholepath_and_role
    ON user_set_path (from_set_id,into_set_id,role_id);
CREATE INDEX idx_user_set_path_rev_and_role
    ON user_set_path (into_set_id,from_set_id,role_id);

-- indexes for user_set_path_component

ALTER TABLE ONLY user_set_path_component
    ADD CONSTRAINT "user_set_path_component_pkey"
    PRIMARY KEY (user_set_path_id, user_set_id);
CREATE UNIQUE INDEX idx_uspc_set_and_id
    ON user_set_path_component (user_set_id, user_set_path_id);

-- constraints

ALTER TABLE ONLY user_set_include
    ADD CONSTRAINT user_set_include_role
            FOREIGN KEY (role_id)
            REFERENCES "Role"(role_id) ON DELETE RESTRICT;
ALTER TABLE ONLY user_set_path
    ADD CONSTRAINT user_set_path_role
            FOREIGN KEY (role_id)
            REFERENCES "Role"(role_id) ON DELETE RESTRICT;

ALTER TABLE ONLY user_set_path_component
    ADD CONSTRAINT user_set_path_component_part
            FOREIGN KEY (user_set_path_id)
            REFERENCES user_set_path(user_set_path_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '99'
 WHERE field = 'socialtext-schema-version';

COMMIT;
