BEGIN;

-- Delete all events that reference groups that have been deleted, then create
-- a foreign key constraint on event.group_id

DELETE FROM event
    WHERE group_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
          FROM groups
         WHERE group_id = event.group_id
      );

ALTER TABLE ONLY event
    ADD CONSTRAINT event_group_id_fk
            FOREIGN KEY (group_id)
            REFERENCES groups(group_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '112'
 WHERE field = 'socialtext-schema-version';

COMMIT;
