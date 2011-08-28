BEGIN;

ALTER TABLE users RENAME TO all_users;

CREATE OR REPLACE FUNCTION on_user_set_delete() RETURNS "trigger"
AS $$
BEGIN
    IF (TG_RELNAME = 'all_users') THEN
        PERFORM purge_user_set(OLD.user_id::integer);
    ELSE
        PERFORM purge_user_set(OLD.user_set_id);
    END IF;

    RETURN NEW; -- proceed with the delete
END;
$$ LANGUAGE plpgsql;

ALTER TABLE all_users
    ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE NOT NULL;

UPDATE all_users
   SET is_deleted = false;

CREATE VIEW users
    AS SELECT user_id,
              driver_key,
              driver_unique_id,
              driver_username,
              email_address,
              password,
              first_name,
              middle_name,
              last_name,
              cached_at,
              last_profile_update,
              is_profile_hidden,
              display_name,
              missing,
              private_external_id
         FROM all_users
        WHERE is_deleted = false;

CREATE RULE users_insert
    AS ON INSERT TO users DO INSTEAD
    INSERT INTO all_users
           (
             user_id,
             driver_key,
             driver_unique_id,
             driver_username,
             email_address,
             password,
             first_name,
             middle_name,
             last_name,
             cached_at,
             last_profile_update,
             is_profile_hidden,
             display_name,
             missing,
             private_external_id,
             is_deleted
           )
    VALUES (
             NEW.user_id,
             NEW.driver_key,
             NEW.driver_unique_id,
             NEW.driver_username,
             NEW.email_address,
             NEW.password,
             NEW.first_name,
             NEW.middle_name,
             NEW.last_name,
             CASE WHEN NEW.cached_at IS NOT NULL 
                 THEN NEW.cached_at
                 ELSE '-infinity'::timestamptz
             END,
             CASE WHEN NEW.last_profile_update IS NOT NULL
                 THEN NEW.last_profile_update
                 ELSE '-infinity'::timestamptz
             END,
             CASE WHEN NEW.is_profile_hidden IS NOT NULL
                 THEN NEW.is_profile_hidden
                 ELSE false
             END,
             NEW.display_name,
             CASE WHEN NEW.missing IS NOT NULL
                 THEN NEW.missing
                 ELSE false
             END,
             NEW.private_external_id,
             false 
           );

CREATE RULE users_update
    AS ON UPDATE TO users DO INSTEAD
    UPDATE all_users
       SET driver_key = NEW.driver_key,
           driver_unique_id = NEW.driver_unique_id,
           driver_username = NEW.driver_username,
           email_address = NEW.email_address,
           password = NEW.password,
           first_name = NEW.first_name,
           middle_name = NEW.middle_name,
           last_name = NEW.last_name,
           cached_at = NEW.cached_at,
           last_profile_update = NEW.last_profile_update,
           is_profile_hidden = NEW.is_profile_hidden,
           display_name = NEW.display_name,
           missing = NEW.missing,
           private_external_id = NEW.private_external_id
     WHERE user_id = OLD.user_id;

CREATE RULE users_delete
    AS ON DELETE TO users DO INSTEAD
    DELETE FROM all_users
     WHERE user_id = OLD.user_id;

CREATE SEQUENCE user_mapping_id_seq
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE user_mapping (
    user_mapping_id bigint NOT NULL,
    at timestamptz DEFAULT now() NOT NULL,
    actor_id bigint NOT NULL,
    current_user_id bigint NOT NULL,
    original_user_id bigint NOT NULL
);


ALTER TABLE ONLY user_mapping
    ADD CONSTRAINT user_mapping_pkey
            PRIMARY KEY (user_mapping_id);

ALTER TABLE ONLY user_mapping
    ADD CONSTRAINT user_mapping_original_user_id_fk
            FOREIGN KEY (original_user_id)
            REFERENCES all_users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_mapping
    ADD CONSTRAINT user_mapping_actor_id_fk
            FOREIGN KEY (original_user_id)
            REFERENCES all_users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY user_mapping
    ADD CONSTRAINT user_mapping_current_user_id_fk
            FOREIGN KEY (current_user_id)
            REFERENCES all_users(user_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '141'
 WHERE field = 'socialtext-schema-version';

COMMIT;
