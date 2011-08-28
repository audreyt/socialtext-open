BEGIN;

CREATE TABLE user_workspace_pref (
    user_id bigint NOT NULL,
    workspace_id bigint NOT NULL,
    last_updated timestamptz DEFAULT now() NOT NULL,
    pref_blob text NOT NULL
);

ALTER TABLE ONLY user_workspace_pref
    ADD CONSTRAINT user_workspace_pref_user_fk
        FOREIGN KEY (user_id)
            REFERENCES users (user_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_workspace_pref
    ADD CONSTRAINT user_workspace_pref_workspace_fk
        FOREIGN KEY (workspace_id)
            REFERENCES "Workspace" (workspace_id) ON DELETE CASCADE;

CREATE INDEX user_workspace_pref_idx
    ON user_workspace_pref (user_id, workspace_id);

UPDATE "System"
   SET value = '61'
 WHERE field = 'socialtext-schema-version';

COMMIT;
