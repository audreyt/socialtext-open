BEGIN;

ALTER TABLE container_type
    ADD COLUMN plugin text DEFAULT 'widgets';

UPDATE container_type
    SET plugin = (
        CASE
            WHEN container_type = 'dashboard' THEN 'dashboard'
            WHEN container_type = 'group' THEN 'groups'
            WHEN container_type = 'profile' THEN 'people'
            WHEN container_type = 'edit_profile' THEN 'people'
            WHEN container_type = 'signals' THEN 'signals'
            ELSE 'widgets'
        END
    );

UPDATE "System"
   SET value = '96'
 WHERE field = 'socialtext-schema-version';

COMMIT;
