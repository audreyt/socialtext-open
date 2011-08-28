BEGIN;

-- Create tables for per-workspace plugin prefs
CREATE TABLE workspace_plugin_pref (
    workspace_id bigint NOT NULL,
    plugin text NOT NULL,
    key text NOT NULL,
    value text NOT NULL
);

ALTER TABLE ONLY workspace_plugin_pref
    ADD CONSTRAINT workspace_plugin_pref_fk
        FOREIGN KEY (workspace_id, plugin)
            REFERENCES workspace_plugin (workspace_id, plugin) ON DELETE CASCADE;

CREATE INDEX workspace_plugin_pref_idx
    ON workspace_plugin_pref (workspace_id, plugin);

CREATE INDEX workspace_plugin_pref_key_idx
    ON workspace_plugin_pref (workspace_id, plugin, key);

UPDATE "System"
   SET value = '53'
 WHERE field = 'socialtext-schema-version';

COMMIT;
