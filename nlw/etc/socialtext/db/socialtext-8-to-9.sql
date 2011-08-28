BEGIN;

-- update the User table with profile-selected names

UPDATE "User"
SET first_name = person.first_name,
    last_name = person.last_name
FROM person
WHERE "User".first_name ~ '^\\s*$' AND "User".last_name ~ '^\\s*$'
  AND "User".user_id = person.id
  AND person.first_name IS NOT NULL AND person.last_name IS NOT NULL;

-- Auto-vivify shouldn't set the username anymore; just a blank profile

DROP FUNCTION auto_vivify_person() CASCADE;

CREATE FUNCTION auto_vivify_person() RETURNS "trigger"
    AS $$
BEGIN
    INSERT INTO person (id) 
        VALUES (NEW.system_unique_id);
    RETURN NEW;
END
$$
    LANGUAGE plpgsql;

CREATE TRIGGER person_ins
    AFTER INSERT ON "UserId"
    FOR EACH ROW
    EXECUTE PROCEDURE auto_vivify_person();

-- Remove the name, first_name, middle_name, last_name and email fields from the person table

ALTER TABLE person
    DROP COLUMN name;

ALTER TABLE person
    DROP COLUMN first_name;

ALTER TABLE person
    DROP COLUMN middle_name;

ALTER TABLE person
    DROP COLUMN last_name;

ALTER TABLE person
    DROP COLUMN email;

-- add a workspace config value for allowing skin upload

ALTER TABLE "Workspace"
    ADD COLUMN
        allows_skin_upload boolean DEFAULT false NOT NULL;

UPDATE "System"
   SET value = 9
 WHERE field = 'socialtext-schema-version';

COMMIT;
