BEGIN;

CREATE TABLE group_workspace_role (
    group_id     bigint  NOT NULL,
    workspace_id bigint  NOT NULL,
    role_id      integer NOT NULL
);

ALTER TABLE group_workspace_role
    ADD CONSTRAINT group_workspace_role_group_fk
    FOREIGN KEY (group_id)
    REFERENCES groups(group_id) ON DELETE CASCADE;

ALTER TABLE group_workspace_role
    ADD CONSTRAINT group_workspace_role_workspace_fk
    FOREIGN KEY (workspace_id)
    REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE group_workspace_role
    ADD CONSTRAINT group_workspace_role_role_fk
    FOREIGN KEY (role_id)
    REFERENCES "Role"(role_id) ON DELETE CASCADE;

ALTER TABLE ONLY group_workspace_role
    ADD CONSTRAINT group_workspace_role_pk
    PRIMARY KEY (group_id, workspace_id);

CREATE INDEX group_workspace_role_workspace_id
    ON group_workspace_role (workspace_id);

UPDATE "System"
   SET value = '69'
 WHERE field = 'socialtext-schema-version';

COMMIT;
