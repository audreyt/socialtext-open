BEGIN;

CREATE TABLE user_group_role (
    user_id bigint NOT NULL,
    role_id integer NOT NULL,
    group_id bigint NOT NULL

);

ALTER TABLE user_group_role
    ADD CONSTRAINT user_group_role_user_fk
    FOREIGN KEY ( user_id )
    REFERENCES users( user_id ) ON DELETE CASCADE;

ALTER TABLE user_group_role
    ADD CONSTRAINT user_group_role_group_fk
    FOREIGN KEY ( group_id )
    REFERENCES groups( group_id ) ON DELETE CASCADE;

ALTER TABLE user_group_role
    ADD CONSTRAINT user_group_role_role_fk
    FOREIGN KEY ( role_id )
    REFERENCES "Role"( role_id ) ON DELETE CASCADE;

ALTER TABLE ONLY user_group_role
    ADD CONSTRAINT user_group_role_pk
            PRIMARY KEY ( user_id, group_id );

UPDATE "System"
    SET value = '65'
  WHERE field = 'socialtext-schema-version';

COMMIT;
