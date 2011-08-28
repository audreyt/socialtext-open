BEGIN;

-- Create tables for per-user global plugin prefs
CREATE TABLE user_plugin_pref (
    user_id bigint NOT NULL,
    plugin text NOT NULL,
    key text NOT NULL,
    value text NOT NULL
);

ALTER TABLE ONLY user_plugin_pref
    ADD CONSTRAINT user_plugin_pref_user_fk
        FOREIGN KEY (user_id)
            REFERENCES users (user_id) ON DELETE CASCADE;

CREATE INDEX user_plugin_pref_idx
    ON user_plugin_pref (user_id, plugin);

CREATE INDEX user_plugin_pref_key_idx
    ON user_plugin_pref (user_id, plugin, key);


UPDATE "System"
   SET value = '54'
 WHERE field = 'socialtext-schema-version';

COMMIT;
