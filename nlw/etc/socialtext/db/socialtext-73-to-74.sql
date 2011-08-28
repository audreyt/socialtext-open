BEGIN;

-- In a given Account, a User can *only* have one "Golfing Buddies" Group
CREATE UNIQUE INDEX groups_account_user_group_name
    ON groups (primary_account_id, created_by_user_id, driver_group_name);

UPDATE "System"
   SET value = '74'
 WHERE field = 'socialtext-schema-version';

COMMIT;
