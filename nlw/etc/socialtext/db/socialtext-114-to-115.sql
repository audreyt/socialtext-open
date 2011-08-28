BEGIN;

ALTER TABLE "groups"
    ADD COLUMN "permission_set" text NOT NULL DEFAULT 'private';

CREATE INDEX "groups_permission_set" ON "groups" (permission_set);
CREATE INDEX "groups_permission_set_non_priv" ON "groups" (permission_set) WHERE permission_set <> 'private';

UPDATE "System"
   SET value = '115'
 WHERE field = 'socialtext-schema-version';
COMMIT;
