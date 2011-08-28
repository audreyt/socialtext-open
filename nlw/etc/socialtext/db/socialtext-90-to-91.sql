BEGIN;

DROP VIEW user_account;
DROP VIEW account_user;

CREATE VIEW account_user AS
   SELECT user_account_role.user_id,
          user_account_role.account_id,
          true AS is_direct
     FROM user_account_role
     UNION ALL 
     SELECT ugr.user_id,
            gar.account_id,
            false AS is_direct
       FROM user_group_role ugr
       JOIN group_account_role gar USING (group_id);

CREATE VIEW user_account AS
  SELECT um.user_id,
         um.primary_account_id AS account_id,
         true AS is_direct,
         true AS is_primary
   FROM "UserMetadata" um
  UNION ALL 
 SELECT account_user.user_id,
        account_user.account_id,
        account_user.is_direct,
        false AS is_primary
   FROM account_user;

-- update the schema-version
UPDATE "System"
   SET value = '91'
 WHERE field = 'socialtext-schema-version';

COMMIT;
