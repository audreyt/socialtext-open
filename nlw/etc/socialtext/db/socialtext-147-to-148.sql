BEGIN;

CREATE TABLE theme (
    theme_id integer NOT NULL,
    name text NOT NULL,
    header_color text NOT NULL,
    header_image_id bigint NOT NULL,
    header_image_tiling text NOT NULL,
    header_image_position text NOT NULL,
    background_color text NOT NULL,
    background_image_id bigint NOT NULL,
    background_image_tiling text NOT NULL,
    background_image_position text NOT NULL,
    primary_color text NOT NULL,
    secondary_color text NOT NULL,
    tertiary_color text NOT NULL,
    header_font text NOT NULL,
    body_font text NOT NULL,
    is_default boolean NOT NULL
);

CREATE SEQUENCE theme_theme_id
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_pkey
            PRIMARY KEY (theme_id);

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_name_key
            UNIQUE (name);

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_header_image_fk
            FOREIGN KEY (header_image_id)
            REFERENCES attachment(attachment_id) ON DELETE RESTRICT;

ALTER TABLE ONLY theme
    ADD CONSTRAINT theme_background_image_fk
            FOREIGN KEY (background_image_id)
            REFERENCES attachment(attachment_id) ON DELETE RESTRICT;

UPDATE "System"
   SET value = '148'
 WHERE field = 'socialtext-schema-version';

COMMIT;
