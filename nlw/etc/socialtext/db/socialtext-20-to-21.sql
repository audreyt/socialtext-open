BEGIN;

-- Make a table to store workspace-plugin associations.
-- Presence of a plugin in this table indicates it's enabled.
CREATE TABLE workspace_plugin (
    workspace_id bigint NOT NULL,
    plugin text NOT NULL
);

ALTER TABLE workspace_plugin
    ADD CONSTRAINT workspace_plugin_workspace_fk
        FOREIGN KEY (workspace_id)
        REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE workspace_plugin ADD PRIMARY KEY(workspace_id,plugin);
ALTER TABLE workspace_plugin ADD CONSTRAINT workspace_plugin_ukey UNIQUE (plugin, workspace_id);

UPDATE "System"
   SET value = 21
 WHERE field = 'socialtext-schema-version';

COMMIT;
