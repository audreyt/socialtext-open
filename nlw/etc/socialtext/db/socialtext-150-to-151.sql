BEGIN;

CREATE OR REPLACE VIEW group_workspaces AS
  SELECT DISTINCT
    user_set_path.from_set_id user_set_id,
    user_set_path.into_set_id workspace_set_id
  FROM
    user_set_path
  WHERE
    user_set_path.into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
  AND
    user_set_path.from_set_id BETWEEN x'10000001'::int AND x'20000000'::int
  ;

CREATE OR REPLACE VIEW user_workspaces AS
  SELECT DISTINCT
    user_set_path.from_set_id user_set_id,
    user_set_path.into_set_id workspace_set_id
  FROM
    user_set_path
  WHERE
    user_set_path.into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
  AND
    user_set_path.from_set_id <= x'10000000'::int
  ;

UPDATE "System"
   SET value = '151'
 WHERE field = 'socialtext-schema-version';

COMMIT;
