BEGIN;

-- When a User is deleted, *DON'T* cascade the delete through to any
-- Workspaces that the User may have created.  Prevent the delete from
-- happening, and require that someone re-assign as necessary *first* and
-- then attempt the delete.
ALTER TABLE "Workspace"
    DROP CONSTRAINT fk_251eb1be4c68e78c9e4b7799c9eed357;

ALTER TABLE "Workspace"
    ADD CONSTRAINT workspace_created_by_user_id_fk
        FOREIGN KEY (created_by_user_id)
        REFERENCES users(user_id) ON DELETE RESTRICT;

-- When a User is deleted, *DON'T* cascade the delete through to any Pages
-- that the User may have created.  Prevent the delete from happening, and
-- require that someone re-assign as necessary *first* and then attempt the
-- delete.
ALTER TABLE page
    DROP CONSTRAINT page_creator_id_fk;

ALTER TABLE page
    ADD CONSTRAINT page_creator_id_fk
        FOREIGN KEY (creator_id)
        REFERENCES users(user_id) ON DELETE RESTRICT;

-- When a User is deleted, *DON'T* cascade the delete through to any Pages
-- that the User may have been the last person to edit.  Prevent the delete
-- from happening, and require that someone re-assign as necessary *first*
-- and then attempt the delete.
ALTER TABLE page
    DROP CONSTRAINT page_last_editor_id_fk;

ALTER TABLE page
    ADD CONSTRAINT page_last_editor_id_fk
        FOREIGN KEY (last_editor_id)
        REFERENCES users(user_id) ON DELETE RESTRICT;

-- Update schema version
UPDATE "System"
   SET value = '25'
 WHERE field = 'socialtext-schema-version';

COMMIT;
