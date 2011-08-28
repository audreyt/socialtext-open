BEGIN;

-- Foreign keys
ALTER TABLE ONLY user_like
    -- liker_user_id
    ADD CONSTRAINT user_like_liker_fk
        FOREIGN KEY (liker_user_id)
        REFERENCES all_users(user_id)
        ON DELETE CASCADE,
    -- workspace_id
    ADD CONSTRAINT user_like_workspace_id_fk
        FOREIGN KEY (workspace_id)
        REFERENCES "Workspace"(workspace_id)
        ON DELETE CASCADE,
    -- page_id, workspace_id
    ADD CONSTRAINT user_like_page_id_fk
        FOREIGN KEY (workspace_id, page_id)
        REFERENCES page(workspace_id, page_id)
        ON DELETE CASCADE,
    -- revision_id, page_id, workspace_id
    ADD CONSTRAINT user_like_revision_id_fk
        FOREIGN KEY (workspace_id, page_id, revision_id)
        REFERENCES page_revision(workspace_id, page_id, revision_id)
        ON DELETE CASCADE,
    -- signal_id
    ADD CONSTRAINT user_like_signal_id_fk
        FOREIGN KEY (signal_id)
        REFERENCES signal(signal_id)
        ON DELETE CASCADE;

-- Indexes

-- Socialtext::Pluggable::Plugin->export_workspace
CREATE INDEX user_like_workspace_id_idx
    ON user_like (workspace_id);

-- Socialtext::Liked->likers
CREATE INDEX user_like_likers_idx
    ON user_like ( workspace_id, page_id, revision_id, signal_id );

-- Socialtext::Liker->like, Socialtext::Liker->unlike
CREATE INDEX user_like_unlike_idx
    ON user_like (liker_user_id, workspace_id, page_id, revision_id, signal_id);

-- Socialtext::Liker->likes
CREATE INDEX user_like_likes_idx
    ON user_like (liker_user_id);

UPDATE "System"
   SET value = '144'
 WHERE field = 'socialtext-schema-version';

COMMIT;
