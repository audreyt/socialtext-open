BEGIN;

-- Temporary function for initial population of the display name
CREATE OR REPLACE FUNCTION make_display_name (first_name text, last_name text, email_address text) RETURNS text
    AS $$
BEGIN
    IF length(first_name) > 0 THEN
        IF length(last_name) > 0 THEN
            RETURN first_name || ' ' || last_name;
        END IF;
        RETURN first_name;
    ELSE
        IF length(last_name) > 0 THEN
            RETURN last_name;
        END IF;
    END IF;
    RETURN substring(email_address from 0 for position('@' in email_address));
END;
$$ LANGUAGE plpgsql;

-- Add the column and populate it
ALTER TABLE users ADD COLUMN display_name text;
UPDATE users 
    SET display_name = make_display_name(first_name, last_name, email_address);
ALTER TABLE users ALTER COLUMN display_name SET NOT NULL;

-- Cleanup
DROP FUNCTION make_display_name(text, text, text);

-- update the schema-version
UPDATE "System"
   SET value = '87'
 WHERE field = 'socialtext-schema-version';

COMMIT;
