BEGIN;

-- Satisfies the requirements of
-- https://www2.socialtext.net/dev-tasks/index.cgi?story_periodically_pull_user_list
-- where we make account user data available for download so we can notify
-- select customers of changes.

ALTER TABLE "Account"
    ADD COLUMN is_exportable bool NOT NULL DEFAULT false;

UPDATE "System"
    SET value = '39'
    WHERE field = 'socialtext-schema-version';

COMMIT;
