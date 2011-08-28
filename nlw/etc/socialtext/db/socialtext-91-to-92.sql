BEGIN;

-- Create tables for per-user global plugin prefs
CREATE TABLE plugin_pref (
    plugin text NOT NULL,
    key text NOT NULL,
    value text NOT NULL
);

CREATE INDEX plugin_pref_key_idx
    ON plugin_pref (plugin, key);

UPDATE "System"
   SET value = '92'
 WHERE field = 'socialtext-schema-version';

COMMIT;
