BEGIN;

-- Add an xml column for storing actual XML data for widgets

ALTER TABLE gadget
   ADD COLUMN xml text;

ALTER TABLE gallery_gadget
    -- add a temporary account_id column so we don't lose the track of what
    -- account this gadget is in
    ADD COLUMN account_id BIGINT,

    -- we're about to break this constraint, so remove it.... uh, it has the 
    -- wrong name anyway, really this should be gallery_gadget_gallery_id_fk
    DROP CONSTRAINT gallery_gadget_account_fk;

-- We are about to break this constraint, but we will add it back right
-- after the migration runs
ALTER TABLE gallery DROP CONSTRAINT gallery_pk;

-- fill in the account_ids of all gallery gadgets so we can change gallery ids
UPDATE gallery_gadget
    SET account_id = (
        SELECT account_id
          FROM gallery
         WHERE gallery.gallery_id = gallery_gadget.gallery_id
    );

-- now change gallery_id to be 0 OR the account_id
UPDATE gallery_gadget SET gallery_id = account_id WHERE account_id IS NOT NULL;
UPDATE gallery SET gallery_id = account_id WHERE account_id IS NOT NULL;

-- And create a constraint that requires the gallery_id to be 0 or equal the
-- account_id
ALTER TABLE gallery
    ADD CONSTRAINT gallery_id_zero_or_account_id
        CHECK(gallery_id = 0 OR gallery_id = account_id),
    ADD PRIMARY KEY(gallery_id); -- add this back

-- Add back the constraints, and get rid of our temporary account_id column
ALTER TABLE gallery_gadget
    DROP COLUMN account_id,
    ADD CONSTRAINT gallery_gadget_gallery_id_fk
        FOREIGN KEY (gallery_id)
        REFERENCES gallery(gallery_id) ON DELETE CASCADE;

-- this sequence is useless now that gallery_id is just account_id or 0
DROP SEQUENCE gallery_id;

UPDATE "System"
   SET value = '129'
 WHERE field = 'socialtext-schema-version';
COMMIT;
