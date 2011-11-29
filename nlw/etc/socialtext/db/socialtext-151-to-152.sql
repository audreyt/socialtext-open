BEGIN;

ALTER TABLE ONLY theme
    ALTER COLUMN background_image_id DROP NOT NULL;

ALTER TABLE ONLY theme
    ALTER COLUMN header_image_id DROP NOT NULL;

ALTER TABLE ONLY theme
    ADD COLUMN foreground_shade TEXT NOT NULL DEFAULT '';

ALTER TABLE ONLY theme
    ADD COLUMN logo_image_id bigint;

ALTER TABLE ONLY theme
    ADD COLUMN favicon_image_id bigint;

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_logo_image_fk
             FOREIGN KEY (logo_image_id)
             REFERENCES attachment(attachment_id) ON DELETE RESTRICT;

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_favicon_image_fk
             FOREIGN KEY (favicon_image_id)
             REFERENCES attachment(attachment_id) ON DELETE RESTRICT;

UPDATE "System"
   SET value = '152'
 WHERE field = 'socialtext-schema-version';

COMMIT;
