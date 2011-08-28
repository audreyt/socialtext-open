BEGIN;

-- [Story: Implement Container Inheritance]

ALTER TABLE gadget_instance
    ADD COLUMN parent_instance_id bigint;

-- NB: ON DELETE RESTRICT
ALTER TABLE ONLY gadget_instance
    ADD CONSTRAINT gadget_instance_parent_fk
            FOREIGN KEY (parent_instance_id)
            REFERENCES gadget_instance(gadget_instance_id) 
            ON DELETE RESTRICT;

CREATE INDEX ix_gadget_instance__parent_id
    ON gadget_instance (parent_instance_id);


ALTER TABLE ONLY container
    ADD COLUMN layout_template text,
    DROP CONSTRAINT container_scope_ptr,
    ADD CONSTRAINT container_scope_ptr
        CHECK (
              (user_id IS NOT NULL AND account_id IS     NULL AND workspace_id IS     NULL AND page_id IS     NULL)
           OR (user_id IS     NULL AND account_id IS NOT NULL AND workspace_id IS     NULL AND page_id IS     NULL)
           OR (user_id IS     NULL AND account_id IS     NULL AND workspace_id IS NOT NULL )
        ),
    ADD CONSTRAINT container_page_id_fk 
        FOREIGN KEY (workspace_id, page_id)
        REFERENCES page(workspace_id, page_id)
        ON DELETE CASCADE;

-- This table is no longer used. We just go directly to the YAML file when
-- adding default gadgets
DROP TABLE default_gadget;

UPDATE "System"
   SET value = '42'
 WHERE field = 'socialtext-schema-version';

COMMIT;
