BEGIN;

-- Get rid of the container_type table, which is now handled in perl

ALTER TABLE container
    DROP CONSTRAINT container_type_fk;

DROP TABLE container_type;

-- Remove containers that violate the unique constraint we are about to add on
-- (container_type, user_set_id, name)
-- This will leave ONLY the most recent versions of all containers.
DELETE
  FROM container
 WHERE container_id NOT IN (
    SELECT MAX(container_id)
      FROM container
  GROUP BY container_type, name, user_id, group_id, account_id
 );

-- Replace user_id, account_id, group_id, page_id, workspace_id with
-- user_set_id

ALTER TABLE container
    ADD COLUMN user_set_id integer;

UPDATE container
   SET user_set_id = group_id + x'10000000'::int
 WHERE group_id IS NOT NULL;

UPDATE container
   SET user_set_id = account_id + x'30000000'::int
 WHERE account_id IS NOT NULL;

UPDATE container
   SET user_set_id = user_id
 WHERE user_id IS NOT NULL;

ALTER TABLE container
    DROP CONSTRAINT container_scope_ptr,
    DROP COLUMN user_id,
    DROP COLUMN group_id,
    DROP COLUMN page_id,
    DROP COLUMN workspace_id,
    DROP COLUMN account_id,
    ALTER COLUMN user_set_id SET NOT NULL;

CREATE UNIQUE INDEX container__type_name_set
    ON container(container_type, name, user_set_id);

UPDATE gadget
   SET plugin = 'widgets'
 WHERE plugin IS NULL;

ALTER TABLE gadget
ALTER COLUMN plugin SET DEFAULT 'widgets';

-- Done

UPDATE "System"
   SET value = '101'
 WHERE field = 'socialtext-schema-version';

COMMIT;
