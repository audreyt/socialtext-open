BEGIN;

CREATE TABLE group_photo (
    group_id INTEGER NOT NULL,
    large BYTEA,
    small BYTEA
);

ALTER TABLE group_photo
    ADD CONSTRAINT group_photo_pkey
        PRIMARY KEY (group_id);

ALTER TABLE group_photo
    ADD CONSTRAINT group_photo_group_id_fk
       FOREIGN KEY (group_id)
       REFERENCES groups(group_id) ON DELETE CASCADE;

ALTER TABLE profile_photo
    RENAME COLUMN photo_image TO large;

ALTER TABLE profile_photo
    RENAME COLUMN small_photo_image TO small;

UPDATE "System"
   SET value = '98'
 WHERE field = 'socialtext-schema-version';

COMMIT;
