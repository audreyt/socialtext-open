BEGIN;

-- I tried to do this using one sql statement, but using a function is way
-- easier

-- In order to support a lot of 3rd party widgets, widget IDs need to be
-- integers rather than strings. This way we can support things like
-- _IG_prefs(__MODULE_ID__), which is valid javascript if __MODULE_ID__ is
-- expanded to a number, but not if it is expanded to a string.

-- Here, we create a function update_container_ids which changes all IDs from
-- SHA1 strings into the concatination of a timestamp and a random number. We
-- don't change any gadget IDs because there is no point. All new gadgets will
-- use the new container ID, and old style gadget IDs will still work.

-- The update_container_ids function is dropped at the end because we'll never
-- reuse this function.

CREATE OR REPLACE FUNCTION update_container_ids () RETURNS BOOLEAN AS $$
DECLARE
    container RECORD; 
    new_class VARCHAR;
BEGIN
    FOR container IN SELECT DISTINCT class FROM storage WHERE class LIKE 'container:%'
    LOOP
        new_class := 'container:' || ( SELECT (EXTRACT(EPOCH FROM now())::int::real * 10000) + (random()*10000)::int::real);
        UPDATE storage
            SET class = new_class
            WHERE class = container.class;
    END LOOP;
    RETURN(TRUE);
END
$$ LANGUAGE 'plpgsql' VOLATILE;

SELECT update_container_ids();

DROP FUNCTION update_container_ids ();

SELECT DISTINCT class FROM storage;

UPDATE "System"
   SET value = 6
 WHERE field = 'socialtext-schema-version';

COMMIT;
