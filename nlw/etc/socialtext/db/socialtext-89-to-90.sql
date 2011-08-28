BEGIN;

-- create new VIEWs for querying the Role a User has in an Account
CREATE VIEW all_user_account_role AS
    SELECT my_acct_roles.user_id, my_acct_roles.account_id, my_acct_roles.role_id
      FROM (
            SELECT user_id, account_id, role_id
              FROM user_account_role

            UNION ALL

            SELECT ugr.user_id, gar.account_id, gar.role_id
              FROM user_group_role ugr
              JOIN group_account_role gar USING (group_id)
           ) my_acct_roles;

CREATE VIEW distinct_user_account_role AS
    SELECT DISTINCT all_user_account_role.user_id, all_user_account_role.account_id, all_user_account_role.role_id
      FROM all_user_account_role 
     ORDER BY all_user_account_role.user_id, all_user_account_role.account_id, all_user_account_role.role_id;

-- update the schema-version
UPDATE "System"
   SET value = '90'
 WHERE field = 'socialtext-schema-version';

COMMIT;
