BEGIN;

-- Create tables for per-user global plugin prefs
CREATE TABLE page_plugin_pref (
    workspace_id bigint NOT NULL,
    page_name text NOT NULL,
    plugin text NOT NULL,
    key text NOT NULL,
    value text NOT NULL
);

CREATE INDEX page_plugin_pref_key_idx
    ON page_plugin_pref (workspace_id, page_name, plugin, key);

UPDATE "System"
   SET value = '138'
 WHERE field = 'socialtext-schema-version';

COMMIT;
