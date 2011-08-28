BEGIN;

-- make a temp table that has the map of old field_ids to new field_ids
CREATE TEMPORARY TABLE field_migration AS
    SELECT ap.account_id, 
        pf.profile_field_id AS old_profile_field_id, 
        pf.name, 
        pf.field_class, 
        nextval('profile_field___profile_field_id') AS new_profile_field_id
    FROM account_plugin ap CROSS JOIN profile_field pf 
    WHERE ap.plugin = 'people';

-- add the account_id to profile_field

ALTER TABLE profile_field
    ADD COLUMN account_id bigint;

-- names are no longer globally unique, but unique per account
DROP INDEX profile_field_name;
CREATE UNIQUE INDEX profile_field_name ON profile_field (account_id, name);
-- if the above index sucks for "get all fields for an account", use:
-- CREATE INDEX profile_field_account ON profile_field (account_id);

-- insert into profile_field new entries for each people-enabled account
INSERT INTO profile_field (profile_field_id, account_id, name, field_class) 
    SELECT new_profile_field_id, account_id, name, field_class 
        FROM field_migration;

-- update profile_attribute
UPDATE profile_attribute 
    SET profile_field_id = new_profile_field_id
    FROM field_migration, "UserMetadata" um
    WHERE field_migration.account_id = um.primary_account_id
      AND um.primary_account_id IS NOT NULL
      AND profile_attribute.user_id = um.user_id
      AND profile_field_id = old_profile_field_id;
    
-- update profile_relationship
UPDATE profile_relationship
    SET profile_field_id = new_profile_field_id
    FROM field_migration, "UserMetadata" um
    WHERE field_migration.account_id = um.primary_account_id
      AND um.primary_account_id IS NOT NULL
      AND profile_relationship.user_id = um.user_id
      AND profile_field_id = old_profile_field_id;

-- make account_id NOT NULL (delete old NULL entries)
DELETE FROM profile_field WHERE account_id IS NULL;
ALTER TABLE profile_field ALTER COLUMN account_id SET NOT NULL;

-- make account_id a foreign key in the two attr/reln tables
ALTER TABLE profile_field 
    ADD CONSTRAINT profile_field_account_fk 
    FOREIGN KEY (account_id) 
    REFERENCES "Account" (account_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = 22
 WHERE field = 'socialtext-schema-version';

COMMIT;
