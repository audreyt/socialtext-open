BEGIN;

--
-- Table to define profile fields
--
CREATE TABLE profile_field (
    profile_field_id bigint NOT NULL,
    name text NOT NULL,
    field_class text NOT NULL,
    CONSTRAINT profile_field_class_check
            CHECK (field_class IN ('attribute', 'contact', 'relationship'))
);
CREATE SEQUENCE profile_field___profile_field_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;
ALTER TABLE ONLY profile_field
    ADD CONSTRAINT profile_field_pkey
            PRIMARY KEY (profile_field_id);
CREATE UNIQUE INDEX profile_field_name ON profile_field (name);

--
-- Table to associate profiles with profile attributes
--
CREATE TABLE profile_attribute (
    user_id bigint NOT NULL,
    profile_field_id bigint NOT NULL,
    value text NOT NULL
);
ALTER TABLE ONLY profile_attribute
    ADD CONSTRAINT profile_attribute_pkey
            PRIMARY KEY (user_id, profile_field_id);
ALTER TABLE profile_attribute
    ADD CONSTRAINT profile_attribute_user_fk
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE profile_attribute
    ADD CONSTRAINT profile_attribute_field_fk
            FOREIGN KEY (profile_field_id)
            REFERENCES profile_field(profile_field_id) ON DELETE CASCADE;

--
-- Table to associate profiles with each other
--
CREATE TABLE profile_relationship (
    user_id bigint NOT NULL,
    profile_field_id bigint NOT NULL,
    other_user_id bigint NOT NULL
);
ALTER TABLE ONLY profile_relationship
    ADD CONSTRAINT profile_relationship_pkey
            PRIMARY KEY (user_id, profile_field_id);
ALTER TABLE profile_relationship
    ADD CONSTRAINT profile_relationship_user_fk
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE profile_relationship
    ADD CONSTRAINT profile_relationship_field_fk
            FOREIGN KEY (profile_field_id)
            REFERENCES profile_field(profile_field_id) ON DELETE CASCADE;
ALTER TABLE profile_relationship
    ADD CONSTRAINT profile_relationship_other_user_fk
            FOREIGN KEY (other_user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;
CREATE INDEX profile_relationship_other_user_id
    ON profile_relationship (other_user_id);

--
-- Migrate data out of person, into these new tables
-- First, create the profile fields
--
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'position', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'location', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'work_phone', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'mobile_phone', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'home_phone', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'aol_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'yahoo_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'gtalk_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'skype_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'sametime_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'twitter_sn', 'contact');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'blog', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'personal_url', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'linkedin_url', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'facebook_url', 'attribute');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'company', 'attribute');

INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'supervisor', 'relationship');
INSERT INTO profile_field (profile_field_id, name, field_class) VALUES (nextval('profile_field___profile_field_id'), 'assistant', 'relationship');

--
-- Next: Copy profile attributes in from person table
--
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.position 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'position' 
          AND person.position != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.location 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'location' 
          AND person.location != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.work_phone 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'work_phone' 
          AND person.work_phone != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.mobile_phone 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'mobile_phone' 
          AND person.mobile_phone != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.home_phone 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'home_phone' 
          AND person.home_phone != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.aol_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'aol_sn' 
          AND person.aol_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.yahoo_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'yahoo_sn' 
          AND person.yahoo_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.gtalk_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'gtalk_sn' 
          AND person.gtalk_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.skype_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'skype_sn' 
          AND person.skype_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.sametime_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'sametime_sn' 
          AND person.sametime_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.twitter_sn 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'twitter_sn' 
          AND person.twitter_sn != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.blog 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'blog' 
          AND person.blog != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.personal_url 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'personal_url' 
          AND person.personal_url != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.linkedin_url 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'linkedin_url' 
          AND person.linkedin_url != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.facebook_url 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'facebook_url' 
          AND person.facebook_url != ''
);
INSERT INTO profile_attribute (
    SELECT person.id, profile_field_id, person.company 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'company' 
          AND person.company != ''
);

--
-- Import the profile relationships into the new table
--
INSERT INTO profile_relationship (
    SELECT person.id, profile_field_id, person.supervisor_id 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'supervisor' 
          AND person.supervisor_id IS NOT NULL
);
INSERT INTO profile_relationship (
    SELECT person.id, profile_field_id, person.assistant_id 
        FROM profile_field CROSS JOIN person 
        WHERE name = 'assistant' 
          AND person.assistant_id IS NOT NULL
);

--
-- Move the last_update and is_hidden flags to users table
--
ALTER TABLE users ADD COLUMN last_profile_update timestamptz DEFAULT '-infinity'::timestamptz NOT NULL;
UPDATE users SET last_profile_update = person.last_update
    FROM person
    WHERE users.user_id = person.id;

ALTER TABLE users ADD COLUMN is_profile_hidden boolean DEFAULT FALSE NOT NULL;
UPDATE users SET is_profile_hidden = person.is_hidden
    FROM person
    WHERE users.user_id = person.id;

--
-- Now that person data is all migrated, trim it down to just photos
-- 
DROP INDEX ix_person_assistant_id;
DROP INDEX ix_person_supervisor_id;
ALTER TABLE person DROP CONSTRAINT person_pkey;
ALTER TABLE person DROP CONSTRAINT person_id_fk;

ALTER TABLE person RENAME TO profile_photo;
ALTER TABLE profile_photo 
    DROP COLUMN "position",
    DROP COLUMN "location",
    DROP COLUMN work_phone,
    DROP COLUMN mobile_phone,
    DROP COLUMN home_phone,
    DROP COLUMN aol_sn,
    DROP COLUMN yahoo_sn,
    DROP COLUMN gtalk_sn,
    DROP COLUMN skype_sn,
    DROP COLUMN sametime_sn,
    DROP COLUMN twitter_sn,
    DROP COLUMN blog,
    DROP COLUMN personal_url,
    DROP COLUMN linkedin_url,
    DROP COLUMN facebook_url,
    DROP COLUMN company,
    DROP COLUMN supervisor_id,
    DROP COLUMN assistant_id,
    DROP COLUMN last_update,
    DROP COLUMN is_hidden;

ALTER TABLE profile_photo RENAME COLUMN id TO user_id;
ALTER TABLE profile_photo
    ADD CONSTRAINT profile_photo_pkey
        PRIMARY KEY (user_id);
ALTER TABLE profile_photo
    ADD CONSTRAINT profile_photo_user_id_fk
       FOREIGN KEY (user_id)
       REFERENCES users(user_id) ON DELETE CASCADE;

-- Since there's no person table to keep in sync with the users table, we can
-- drop auto_vivify_person and its trigger.
--
-- Goodbye, auto_vivify_person: you've caused us so much pain, but we've
-- learned so much from you in the process.
DROP TRIGGER person_ins ON users;
DROP FUNCTION auto_vivify_person();

-- Update this view to include the "is_profile_hidden" flag
-- (added after the secondary_account_id so as not to disturb things that
-- depend on the order)
DROP VIEW user_account;
CREATE VIEW user_account AS
    SELECT DISTINCT 
        u.user_id, 
        u.driver_key, 
        u.driver_unique_id, 
        u.driver_username, 
        um.created_by_user_id AS creator_id, 
        um.creation_datetime, 
        um.primary_account_id, 
        w.account_id AS secondary_account_id, 
        u.is_profile_hidden
    FROM users u
    JOIN "UserMetadata" um USING (user_id)
    LEFT JOIN "UserWorkspaceRole" uwr USING (user_id)
    LEFT JOIN "Workspace" w USING (workspace_id);

-- finish up

UPDATE "System"
   SET value = 20
 WHERE field = 'socialtext-schema-version';

COMMIT;
