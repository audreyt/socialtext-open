BEGIN;

-- Nice and simple, let's just add a couple of additional fields. Once they
-- are populated, we'll delete the old fields and move these over.

ALTER TABLE person
    ADD COLUMN photo_image bytea;

ALTER TABLE person
    ADD COLUMN small_photo_image bytea;

-- Table was renamed, so we should re-name the pkey index to be consistent
-- Dropping the constraint cascades, so we need to re-create tag_people_fk
-- too.
ALTER TABLE ONLY person_tag DROP CONSTRAINT tag_pkey CASCADE;
ALTER TABLE ONLY person_tag ADD CONSTRAINT person_tag_pkey PRIMARY KEY (id);
ALTER TABLE ONLY tag_people__person_tags
    ADD CONSTRAINT tag_people_fk
            FOREIGN KEY (tag_id)
            REFERENCES person_tag(id) ON DELETE CASCADE;


-- Remove the execute_(unless|if)_table_exists - these shouldn't be left
-- in the core schema.  Make sure they exist before we delete them.

CREATE OR REPLACE FUNCTION execute_if_table_exists (table_name TEXT, sql TEXT) RETURNS BOOLEAN AS $$
BEGIN
    RETURN(FALSE);
END
$$ LANGUAGE 'plpgsql' VOLATILE;

CREATE OR REPLACE FUNCTION execute_unless_table_exists (table_name TEXT, sql TEXT) RETURNS BOOLEAN AS $$
BEGIN
    RETURN(FALSE);
END
$$ LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION execute_if_table_exists(text,text);
DROP FUNCTION execute_unless_table_exists(text,text);


UPDATE "System"
   SET value = 8
 WHERE field = 'socialtext-schema-version';

COMMIT;
