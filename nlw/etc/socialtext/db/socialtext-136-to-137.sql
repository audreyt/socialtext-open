BEGIN;

--
-- Create a separate gadget_content table for different views
--
CREATE TABLE gadget_content (
    gadget_id bigint NOT NULL,
    view_name text NOT NULL DEFAULT 'default',
    content_type text DEFAULT 'html',
    content text,
    href text,
    position integer
);

ALTER TABLE ONLY gadget_content
    ADD CONSTRAINT gadget_content_gadget_fk
        FOREIGN KEY (gadget_id)
        REFERENCES gadget(gadget_id) ON DELETE CASCADE,
    ADD CONSTRAINT gadget_content__gadget_id_position
        UNIQUE(gadget_id, position);

CREATE INDEX gadget_content__gadget_id
    ON gadget_content (gadget_id);

-- Update the new table with values (all should be default)
INSERT INTO gadget_content (gadget_id, content_type, content, href)
    SELECT gadget_id, COALESCE(content_type,'html'), content, href
      FROM gadget;

/* Drop all our old columns */
ALTER TABLE ONLY gadget
    DROP COLUMN content,
    DROP COLUMN content_type,
    DROP COLUMN href;

/* Add a column in the gallery_gadget table for available target containers */
ALTER TABLE ONLY gallery_gadget
    ADD COLUMN container_types text[];

UPDATE gadget
   SET src = 'local:people:all_tags.xml'
 WHERE src = 'local:people:all_tags';

UPDATE "System"
   SET value = '137'
 WHERE field = 'socialtext-schema-version';

COMMIT;
