BEGIN;

-- Rename the "account_id" column in the Groups table, so its obvious that
-- this is the *primary* account for the Group (not necessarily the _only_
-- account to which the Group members have access)

ALTER TABLE ONLY groups
    DROP CONSTRAINT groups_account_id_fk;

ALTER TABLE groups RENAME COLUMN account_id TO primary_account_id;

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_primary_account_id_fk
        FOREIGN KEY (primary_account_id)
            REFERENCES "Account" (account_id) ON DELETE CASCADE;

-- Add some missing indices

CREATE INDEX user_group_role_group_id
    ON user_group_role (group_id);

CREATE INDEX watchlist_workspace_page
    ON "Watchlist" (workspace_id, page_text_id);

UPDATE "System"
   SET value = '70'
 WHERE field = 'socialtext-schema-version';

COMMIT;
