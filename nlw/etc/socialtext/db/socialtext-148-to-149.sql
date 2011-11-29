BEGIN;

CREATE OR REPLACE VIEW user_set_user_count AS
  SELECT
    user_set_include.into_set_id user_set_id,
    COUNT(DISTINCT(user_set_include.from_set_id)) AS user_count
  FROM
    user_set_include
    JOIN ALL_USERS ON ALL_USERS.USER_ID = USER_SET_INCLUDE.FROM_SET_ID
  WHERE
    user_set_include.from_set_id <= x'10000000'::int
  AND
    all_users.is_deleted = false
  GROUP BY
    user_set_include.into_set_id;

CREATE OR REPLACE VIEW user_set_group_count AS
  SELECT
    user_set_include.into_set_id user_set_id,
    COUNT(DISTINCT(user_set_include.from_set_id)) AS group_count
  FROM
    user_set_include
  WHERE
    user_set_include.from_set_id BETWEEN x'10000001'::int AND x'20000000'::int
  GROUP BY
    user_set_include.into_set_id;

CREATE OR REPLACE VIEW group_workspaces AS
  SELECT DISTINCT
    user_set_include.from_set_id user_set_id,
    user_set_include.into_set_id workspace_set_id
  FROM
    user_set_include
  WHERE
    user_set_include.into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
  AND
    user_set_include.from_set_id BETWEEN x'10000001'::int AND x'20000000'::int
  ;

CREATE OR REPLACE VIEW user_workspaces AS
  SELECT DISTINCT
    user_set_include.from_set_id user_set_id,
    user_set_include.into_set_id workspace_set_id
  FROM
    user_set_include
  WHERE
    user_set_include.into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
  AND
    user_set_include.from_set_id <= x'10000000'::int
  ;

UPDATE "System"
   SET value = '149'
 WHERE field = 'socialtext-schema-version';

COMMIT;
