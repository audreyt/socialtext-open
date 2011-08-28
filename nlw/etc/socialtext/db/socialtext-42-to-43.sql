BEGIN;

CREATE INDEX ix_event_actor_page_contribs
    ON event (actor_id, page_workspace_id, page_id, at)
    WHERE event_class='page' AND is_page_contribution(action); 

UPDATE "System"
   SET value = '43'
 WHERE field = 'socialtext-schema-version';

COMMIT;
