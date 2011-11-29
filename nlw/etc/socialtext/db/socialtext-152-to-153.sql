BEGIN;

ALTER TABLE ONLY theme
    ADD COLUMN header_link_color TEXT NOT NULL DEFAULT '';

ALTER TABLE ONLY theme
    ADD COLUMN background_link_color TEXT NOT NULL DEFAULT '';

UPDATE "System"
   SET value = '153'
 WHERE field = 'socialtext-schema-version';

COMMIT;
