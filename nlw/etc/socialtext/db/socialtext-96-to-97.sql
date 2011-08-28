BEGIN;

ALTER TABLE groups
    ADD COLUMN description TEXT NOT NULL DEFAULT '';

ALTER TABLE container_type
    ADD COLUMN footer_template TEXT;

UPDATE "Role"
    SET name = 'admin'
  WHERE name = 'workspace_admin';

UPDATE "System"
   SET value = '97'
 WHERE field = 'socialtext-schema-version';

COMMIT;
