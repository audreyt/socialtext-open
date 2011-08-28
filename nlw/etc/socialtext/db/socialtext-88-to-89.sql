BEGIN;

CREATE TABLE page_link (
    from_workspace_id BIGINT NOT NULL,
    from_page_id      TEXT NOT NULL,
    to_workspace_id   BIGINT NOT NULL,
    to_page_id        TEXT NOT NULL
);

ALTER TABLE ONLY page_link
    ADD CONSTRAINT page_link__from_page_id_fk
        FOREIGN KEY (from_workspace_id, from_page_id)
        REFERENCES page(workspace_id, page_id) ON DELETE CASCADE,
    ADD CONSTRAINT page_link_unique
        UNIQUE (from_workspace_id, from_page_id, to_workspace_id, to_page_id);

CREATE INDEX page_link__to_page
    ON page_link (to_workspace_id, to_page_id);

-- update the schema-version
UPDATE "System"
   SET value = '89'
 WHERE field = 'socialtext-schema-version';

COMMIT;
