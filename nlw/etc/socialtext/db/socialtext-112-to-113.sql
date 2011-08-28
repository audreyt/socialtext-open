BEGIN;

-- Store data for opensocial URLs like this:
-- /appdata/@viewer/@self/@app?networkDistance=&fields=feed,network,action

CREATE TABLE opensocial_appdata (
    app_id bigint NOT NULL,
    user_id bigint NOT NULL,
    field text NOT NULL,
    value text
);

ALTER TABLE ONLY opensocial_appdata
    ADD CONSTRAINT opensocial_app_data_app_id
            FOREIGN KEY (app_id)
            REFERENCES gadget_instance(gadget_instance_id) ON DELETE CASCADE;

ALTER TABLE ONLY opensocial_appdata
    ADD CONSTRAINT opensocial_app_data_user_id
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;

CREATE UNIQUE INDEX idx_opensocial_appdata_app_user_field
	    ON opensocial_appdata (app_id, user_id, field);

CREATE INDEX idx_opensocial_appdata_app_user
	    ON opensocial_appdata (app_id, user_id);

UPDATE "System"
   SET value = '113'
 WHERE field = 'socialtext-schema-version';

COMMIT;
