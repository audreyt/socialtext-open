BEGIN;

-- Migrate event data from the old format to the new.
-- To accomplish this, we will create a temp table that is a clone
-- of the old event table and recreate the event table with munged data.

CREATE TABLE event_old AS
    SELECT * FROM event;

DROP SEQUENCE event_id_seq;

DROP TABLE event;

CREATE TABLE event AS
SELECT e.timestamp AS at,
       CASE WHEN e.action = 'follow' THEN 'watch_add'::text
            WHEN e.action = 'profile edit' THEN 'edit_save'::text
            WHEN e.action = 'tag' THEN 'tag_add'::text
       END AS action,
       e.actor_id,
       'person'::text AS event_class,
       CASE WHEN e.action = 'profile edit' THEN '{"change_set":' || e.context || '}'::text
            ELSE NULL::text
       END AS context,
       NULL::text AS page_id,
       NULL::bigint AS page_workspace_id,
       id.system_unique_id::integer AS person_id,
       CASE WHEN e.action = 'tag' THEN SUBSTR(context, 10, (LENGTH(context) - 11))::text
            ELSE NULL::text 
       END AS tag_name
  FROM event_old e
  LEFT OUTER JOIN "UserId" id ON e.object = id.driver_username
 WHERE e.action IN ('follow', 'profile edit', 'tag')
   AND e.actor_id IS NOT NULL;
 
ALTER TABLE event
    ALTER COLUMN actor_id SET NOT NULL;

ALTER TABLE event
    ALTER COLUMN at SET NOT NULL;

ALTER TABLE event
    ALTER COLUMN action SET NOT NULL;

ALTER TABLE event
    ALTER COLUMN event_class SET NOT NULL;

CREATE INDEX ix_event_at
	    ON event (at);

CREATE INDEX ix_event_event_class_at
	    ON event (event_class, at);

CREATE INDEX ix_event_event_class_action_at
	    ON event (event_class, action, at);

CREATE INDEX ix_event_person_time
	    ON event (person_id, at)
            WHERE (event_class = 'person');

CREATE INDEX ix_event_actor_time
	    ON event (actor_id, at);

CREATE INDEX ix_event_for_page
	    ON event (page_workspace_id, page_id, at)
            WHERE (event_class = 'page');

CREATE INDEX ix_event_tag
	    ON event (tag_name, at)
            WHERE (event_class = 'page' OR event_class = 'person');

ALTER TABLE ONLY event
    ADD CONSTRAINT event_actor_id_fk
            FOREIGN KEY (actor_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_page_fk
            FOREIGN KEY (page_workspace_id, page_id)
            REFERENCES page(workspace_id, page_id) ON DELETE CASCADE;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_person_id_fk
            FOREIGN KEY (person_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE tag_people__person_tags 
    DROP CONSTRAINT tag_people_fk;

ALTER TABLE tag RENAME TO person_tag;

CREATE UNIQUE INDEX person_tag__name
        ON person_tag (name);

ALTER TABLE ONLY tag_people__person_tags
    ADD CONSTRAINT tag_people_fk
            FOREIGN KEY (tag_id)
            REFERENCES person_tag(id) ON DELETE CASCADE;

DROP TABLE event_old;

UPDATE "System"
    SET value = 7
    WHERE field = 'socialtext-schema-version';

COMMIT;
