BEGIN;

-- Update all Accounts to use the s3 as the new default.
UPDATE "Account"
   SET skin_name = 's3';

-- Update all workspaces to use the default skin for it's
-- account ( and hence, s3 ) if it's currently using s2.
UPDATE "Workspace"
   SET skin_name = ''
 WHERE skin_name = 's2';

-- Enable the widgets plugin for all accounts where it's not
-- already enabled.
INSERT INTO account_plugin
SELECT "Account".account_id,
       'widgets'
  FROM "Account"
 WHERE account_id NOT IN (
    SELECT account_id
      FROM account_plugin
     WHERE plugin = 'widgets'
);

-- Enable the dashboard plugin for all accounts where it's not
-- already enabled.
INSERT INTO account_plugin
SELECT "Account".account_id,
       'dashboard'
  FROM "Account"
 WHERE account_id NOT IN (
    SELECT account_id
      FROM account_plugin
     WHERE plugin = 'dashboard'
);

COMMIT;
