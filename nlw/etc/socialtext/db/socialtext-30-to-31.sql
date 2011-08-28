BEGIN;

ALTER TABLE container
  ADD COLUMN name text NOT NULL DEFAULT '',
  ADD COLUMN page_id text,
 DROP CONSTRAINT container_scope_ptr,
  ADD CONSTRAINT container_scope_ptr
        CHECK ((((user_id IS NOT NULL) <> (workspace_id IS NOT NULL)) <> (account_id IS NOT NULL)) <> (page_id IS NOT NULL));

UPDATE "System"
    SET value = 31
    WHERE field = 'socialtext-schema-version';

COMMIT;
