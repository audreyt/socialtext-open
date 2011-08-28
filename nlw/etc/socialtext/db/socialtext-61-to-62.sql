BEGIN;

CREATE SEQUENCE groups___group_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

-- "groups" because "group" is a reserved keyword like "user" (and we have a
-- "users" table)
CREATE TABLE groups (
    -- internal unique Group Identifier
    group_id            BIGINT      NOT NULL,
    -- driver/factory key (name:id)
    driver_key          TEXT        NOT NULL,
    -- unique key identifying this Group within its driver
    driver_unique_id    TEXT        NOT NULL,
    -- name of Group, as defined in its driver
    driver_group_name   TEXT        NOT NULL,
    -- the Account in which the Group resides
    account_id          BIGINT      NOT NULL,
    -- when the Group was created, and by whom
    creation_datetime   TIMESTAMPTZ DEFAULT now() NOT NULL,
    created_by_user_id  BIGINT      NOT NULL,
    -- date/time the Group was last cached (e.g. externally sourced groups)
    cached_at           TIMESTAMPTZ DEFAULT '-infinity'::TIMESTAMPTZ NOT NULL
);

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_group_id_pk
        PRIMARY KEY (group_id);

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_account_id_fk
        FOREIGN KEY (account_id)
            REFERENCES "Account" (account_id) ON DELETE CASCADE;

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_created_by_user_id_fk
        FOREIGN KEY (created_by_user_id)
            REFERENCES users (user_id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX groups_driver_unique_id
    ON groups (driver_key, driver_unique_id);

UPDATE "System"
    SET value = '62'
  WHERE field = 'socialtext-schema-version';

COMMIT;
