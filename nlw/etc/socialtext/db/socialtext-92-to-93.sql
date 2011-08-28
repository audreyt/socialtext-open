BEGIN;

ALTER TABLE event
    ADD COLUMN group_id bigint;

ALTER TABLE event_archive
    ADD COLUMN group_id bigint;

CREATE INDEX ix_event_for_group
    ON event (group_id, "at")
    WHERE (event_class = 'group');

ALTER TABLE container
    ADD COLUMN group_id bigint,
    ADD CONSTRAINT container_group_id_fk
            FOREIGN KEY (group_id)
            REFERENCES groups(group_id) ON DELETE CASCADE,
    DROP CONSTRAINT container_scope_ptr,
    ADD CONSTRAINT container_scope_ptr
        CHECK (
              (user_id IS NOT NULL AND account_id IS     NULL AND group_id IS     NULL AND workspace_id IS     NULL AND page_id IS     NULL)
           OR (user_id IS     NULL AND account_id IS NOT NULL AND group_id IS     NULL AND workspace_id IS     NULL AND page_id IS     NULL)
           OR (user_id IS     NULL AND account_id IS     NULL AND group_id IS NOT NULL AND workspace_id IS     NULL AND page_id IS     NULL)
           OR (user_id IS     NULL AND account_id IS     NULL AND group_id IS     NULL AND workspace_id IS NOT NULL )
        );

CREATE INDEX ix_container_group_id
	    ON container (group_id);

UPDATE "System"
   SET value = '93'
 WHERE field = 'socialtext-schema-version';

COMMIT;
