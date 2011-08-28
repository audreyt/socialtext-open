BEGIN;

ALTER TABLE opensocial_appdata DROP CONSTRAINT opensocial_app_data_user_id;

ALTER TABLE opensocial_appdata RENAME COLUMN user_id TO user_set_id;

ALTER TABLE opensocial_appdata 
    ADD CONSTRAINT opensocial_appdata_pk
            PRIMARY KEY (app_id, user_set_id, field);

UPDATE "System"
   SET value = '131'
 WHERE field = 'socialtext-schema-version';

COMMIT;
