BEGIN;

-- Definition of the page table.

CREATE TABLE page (
    workspace_id bigint NOT NULL,
    page_id text NOT NULL,
    name text,
    last_editor_id bigint NOT NULL,
    last_edit_time timestamptz NOT NULL,
    creator_id bigint NOT NULL,
    create_time timestamptz NOT NULL,
    current_revision_id text  NOT NULL,
    current_revision_num integer NOT NULL,
    revision_count int NOT NULL,
    page_type text NOT NULL,
    deleted boolean NOT NULL,
    summary text
);

ALTER TABLE ONLY page
    ADD CONSTRAINT "page_pkey"
        PRIMARY KEY (workspace_id, page_id);

ALTER TABLE ONLY page
    ADD CONSTRAINT page_workspace_id_fk
        FOREIGN KEY (workspace_id)
        REFERENCES "Workspace" (workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY page
    ADD CONSTRAINT page_last_editor_id_fk
    FOREIGN KEY (last_editor_id)
    REFERENCES "UserId" (system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY page
    ADD CONSTRAINT page_creator_id_fk
    FOREIGN KEY (creator_id)
    REFERENCES "UserId" (system_unique_id) ON DELETE CASCADE;

-- Definition of the page_tag table

CREATE TABLE page_tag (
    workspace_id bigint NOT NULL,
    page_id text NOT NULL,
    tag text NOT NULL
);

ALTER TABLE ONLY page_tag
    ADD CONSTRAINT page_tag_workspace_id_page_id_fkey
        FOREIGN KEY ( workspace_id, page_id )
        REFERENCES page ( workspace_id, page_id ) ON DELETE CASCADE;

UPDATE "System"
    SET value = 5
    WHERE field = 'socialtext-schema-version';

COMMIT;
