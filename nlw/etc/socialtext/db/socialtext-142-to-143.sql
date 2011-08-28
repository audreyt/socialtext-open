BEGIN;
-- add a user_pref table for [Story: Global user settings for timezone]

CREATE TABLE user_pref (
    user_id bigint NOT NULL,
    last_updated timestamptz DEFAULT now() NOT NULL,
    pref_blob text
);

ALTER TABLE ONLY user_pref
    ADD CONSTRAINT user_pref_pkey
            PRIMARY KEY (user_id);

ALTER TABLE ONLY user_pref
    ADD CONSTRAINT user_pref_fk
            FOREIGN KEY (user_id)
            REFERENCES all_users(user_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '143'
 WHERE field = 'socialtext-schema-version';

COMMIT;
