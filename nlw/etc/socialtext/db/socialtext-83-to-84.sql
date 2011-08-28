BEGIN;

-- populate the user_account_role table from `account_user`
-- -- user_account_role is a link table composed of FK's.
-- -- Restrict it so that one User can have only one Role in an Account.
SELECT DISTINCT user_id, 
       account_id, 
       ( SELECT role_id FROM "Role" WHERE name = 'affiliate' ) AS role_id
  INTO user_account_role
  FROM account_user;

ALTER TABLE ONLY user_account_role
    ADD CONSTRAINT user_account_role_pkey
            PRIMARY KEY (user_id, account_id);

CREATE INDEX user_account_role__account_id_ix
            ON user_account_role (account_id);

ALTER TABLE ONLY user_account_role
    ADD CONSTRAINT user_account_role__user_fk
            FOREIGN KEY (user_id)
            REFERENCES users (user_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_account_role
    ADD CONSTRAINT user_account_role__account_fk
            FOREIGN KEY (account_id)
            REFERENCES "Account" (account_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_account_role
    ADD CONSTRAINT user_account_role__role_fk
            FOREIGN KEY (role_id)
            REFERENCES "Role" (role_id) ON DELETE CASCADE;

-- for the new GroupAccountRole object
-- -- group_account_role is a link table composed of FK's.
-- -- Restrict it so that one Group can have only one Role in an Account.
CREATE TABLE group_account_role (
    group_id bigint NOT NULL,
    account_id bigint NOT NULL,
    role_id bigint NOT NULL
);

ALTER TABLE ONLY group_account_role
    ADD CONSTRAINT group_account_role_pkey
            PRIMARY KEY (group_id, account_id);

CREATE INDEX group_account_role__account_id_ix
            ON group_account_role (account_id);

ALTER TABLE ONLY group_account_role
    ADD CONSTRAINT group_account_role__group_fk
            FOREIGN KEY (group_id)
            REFERENCES groups (group_id) ON DELETE CASCADE;

ALTER TABLE ONLY group_account_role
    ADD CONSTRAINT group_account_role__account_fk
            FOREIGN KEY (account_id)
            REFERENCES "Account" (account_id) ON DELETE CASCADE;

ALTER TABLE ONLY group_account_role
    ADD CONSTRAINT group_account_role__role_fk
            FOREIGN KEY (role_id)
            REFERENCES "Role" (role_id) ON DELETE CASCADE;

-- recreate account_user
DROP VIEW account_user;

CREATE VIEW account_user AS
  SELECT explicit.user_id, explicit.account_id
    FROM ( SELECT user_account_role.user_id AS user_id,
                  user_account_role.account_id AS account_id
             FROM user_account_role
           UNION ALL
           SELECT ugr.user_id, gar.account_id
             FROM user_group_role ugr
             JOIN group_account_role gar USING (group_id)
          ) explicit;

-- recreate user_account
DROP VIEW user_account;

CREATE VIEW user_account AS
  SELECT user_id,
         primary_account_id AS account_id,
         true AS is_primary
    FROM "UserMetadata" um
  UNION ALL
  SELECT user_id,
         account_id,
         false AS is_primary
    FROM account_user;

--- drop views; they're no longer needed!
DROP VIEW user_account_implicit;
DROP VIEW user_account_explicit;
DROP VIEW user_account_implicit_gwr;
DROP VIEW user_account_implicit_uwr;
DROP VIEW account_user_no_groups;

-- update the schema-version
UPDATE "System"
   SET value = '84'
 WHERE field = 'socialtext-schema-version';

COMMIT;
